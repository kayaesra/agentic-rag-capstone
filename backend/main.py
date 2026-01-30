from fastapi import FastAPI, Depends, HTTPException, status, Body, APIRouter
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session, joinedload
from typing import List
import sys
import os
from pydantic import BaseModel, EmailStr, Field
from passlib.context import CryptContext
from datetime import datetime, date

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from rag import DietAgent

from database import get_db, engine, Base
from models import User, UserPreferences, ChatHistory, WaterLog, ChatSession, ChatMessage, FoodEntry, NutritionLog
from config import settings


Base.metadata.create_all(bind=engine)


app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.BACKEND_CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


diet_agent = DietAgent("diyet_dataları")

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def get_password_hash(password):
    return pwd_context.hash(password)

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

class ChatRequest(BaseModel):
    message: str
    user_id: int

class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    name: str = None
    age: int = None
    gender: str = None
    height: int = None
    weight: int = None
    goal: str = None
    activity_level: str = None

class LoginRequest(BaseModel):
    email: EmailStr
    password: str

class UpdateProfileRequest(BaseModel):
    name: str = None
    age: int = None
    gender: str = None
    height: int = None
    weight: int = None
    goal: str = None
    activity_level: str = None

class ChangePasswordRequest(BaseModel):
    old_password: str
    new_password: str

class WaterLogRequest(BaseModel):
    amount_ml: int = Field(..., gt=0)
    date: date = None
    goal_ml: int = None

class ChatMessageRequest(BaseModel):
    session_id: int
    user_id: int
    message: str

class FoodEntryRequest(BaseModel):
    food_name: str
    protein_g: float = 0
    carbs_g: float = 0  
    fat_g: float = 0
    calories: float = None 

router = APIRouter()

@router.post("/api/v1/chat/session")
def create_chat_session(user_id: int, session_name: str = "Yeni Sohbet", db: Session = Depends(get_db)):
    session = ChatSession(user_id=user_id, session_name=session_name)
    db.add(session)
    db.commit()
    db.refresh(session)
    return {"session_id": session.id, "session_name": session.session_name, "created_at": session.created_at}

@router.get("/api/v1/chat/sessions/{user_id}")
def get_sessions(user_id: int, db: Session = Depends(get_db)):
    sessions = db.query(ChatSession).filter(ChatSession.user_id == user_id).order_by(ChatSession.created_at.desc()).all()
    return [{"session_id": s.id, "session_name": s.session_name, "created_at": s.created_at} for s in sessions]

@router.get("/api/v1/chat/history/{session_id}")
def get_session_history(session_id: int, db: Session = Depends(get_db)):
    messages = db.query(ChatMessage).filter(ChatMessage.session_id == session_id).order_by(ChatMessage.timestamp).all()
    return [{"role": m.role, "text": m.text, "timestamp": m.timestamp} for m in messages]

def get_personalized_context(user_id: int, db: Session):
    """Get user profile information to personalize AI responses"""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        return "Unknown user"
    
    preferences = db.query(UserPreferences).filter(UserPreferences.user_id == user_id).first()
    
    context = f"User Profile: {user.name or 'User'}"
    
    if preferences:
        if preferences.age:
            context += f", Age: {preferences.age}"
        if preferences.gender:
            context += f", Gender: {preferences.gender}"
        if preferences.weight:
            context += f", Weight: {preferences.weight}kg"
        if preferences.height:
            context += f", Height: {preferences.height}cm"
        if preferences.goal:
            context += f", Goal: {preferences.goal}"
        if preferences.activity_level:
            context += f", Activity Level: {preferences.activity_level}"
        
        
        if preferences.weight and preferences.height:
            bmi = preferences.weight / ((preferences.height / 100) ** 2)
            context += f", BMI: {bmi:.1f}"
        
        
        if all([preferences.age, preferences.gender, preferences.weight, preferences.height, preferences.activity_level, preferences.goal]):
            macros = calculate_macros_and_calories(
                preferences.age, preferences.gender, preferences.weight, preferences.height,
                preferences.goal, preferences.activity_level
            )
            context += f", Daily Calorie Target: {macros['calories']}kcal"
            context += f", Protein Target: {macros['protein_g']}g"
            context += f", Carbs Target: {macros['carbs_g']}g"
            context += f", Fat Target: {macros['fat_g']}g"
        
        
        if preferences.goal == "weight_loss":
            context += ". Focus on calorie deficit and portion control."
        elif preferences.goal == "muscle_gain":
            context += ". Focus on protein intake and strength training."
        elif preferences.goal == "maintenance":
            context += ". Focus on balanced nutrition and maintaining current habits."
    
    return context

@router.post("/api/v1/chat")
def chat(request: ChatMessageRequest, db: Session = Depends(get_db)):
    user_msg = ChatMessage(session_id=request.session_id, user_id=request.user_id, role="user", text=request.message)
    db.add(user_msg)
    db.commit()
    
    try:
        
        user_context = get_personalized_context(request.user_id, db)
        
       
        diet_agent.water_tracking._user_id = request.user_id
        diet_agent.food_tracking._user_id = request.user_id  
        diet_agent.profile_management._user_id = request.user_id
        diet_agent.smart_food_entry._user_id = request.user_id
        
        
        personalized_message = f"[USER_CONTEXT: {user_context}] {request.message}"
        
   
        print(f"Sending to agent: {personalized_message}")
        response = str(diet_agent.run(personalized_message))
        print(f"Agent response: {response}")
        
    except Exception as e:
        print(f"Chat error: {type(e).__name__}: {str(e)}")
        import traceback
        traceback.print_exc()
        
        
        try:
            response = str(diet_agent.run(request.message))
        except Exception as e2:
            print(f"Fallback error: {type(e2).__name__}: {str(e2)}")
            response = "Üzgünüm, şu an bir teknik sorun yaşıyorum. Lütfen tekrar deneyin."
    
    bot_msg = ChatMessage(session_id=request.session_id, user_id=request.user_id, role="bot", text=response)
    db.add(bot_msg)
    db.commit()
    return {"response": response}

@router.delete("/api/v1/chat/session/{session_id}")
def delete_chat_session(session_id: int, db: Session = Depends(get_db)):
    session = db.query(ChatSession).filter(ChatSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Sohbet oturumu bulunamadı.")
    
    db.query(ChatMessage).filter(ChatMessage.session_id == session_id).delete()
    
    db.delete(session)
    db.commit()
    return {"message": "Sohbet oturumu silindi."}

app.include_router(router)

@app.get("/")
def read_root():
    return {"message": "Welcome to Diet Assistant API"}

@app.post("/api/v1/chat")
async def chat_endpoint(request: ChatRequest, db: Session = Depends(get_db)):
    try:
        
        user_context = get_personalized_context(request.user_id, db)
        
        personalized_message = f"[USER_CONTEXT: {user_context}] {request.message}"
        
        response = diet_agent.run(personalized_message)
        
        response_str = str(response)
        chat_history = ChatHistory(
            user_id=request.user_id,
            message=request.message,
            response=response_str
        )
        db.add(chat_history)
        db.commit()
        return {"response": response_str}
    except Exception as e:
        import traceback
        print("API error:", traceback.format_exc())
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e)
        )

@app.get("/api/v1/chat/history/{user_id}")
async def get_chat_history(user_id: int, db: Session = Depends(get_db)):
    chat_history = db.query(ChatHistory).filter(ChatHistory.user_id == user_id).all()
    return chat_history

@app.post("/api/v1/register")
def register(request: RegisterRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == request.email).first()
    if user:
        raise HTTPException(status_code=400, detail="E-posta zaten kayıtlı.")
    hashed_password = get_password_hash(request.password)
    new_user = User(email=request.email, hashed_password=hashed_password, name=request.name)
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    if request.age or request.gender or request.height or request.weight or request.goal or request.activity_level:
        prefs = UserPreferences(
            user_id=new_user.id,
            age=request.age,
            gender=request.gender,
            height=request.height,
            weight=request.weight,
            goal=request.goal,
            activity_level=request.activity_level
        )
        db.add(prefs)
        db.commit()
    return {"message": "Kayıt başarılı", "user_id": new_user.id}

@app.post("/api/v1/login")
def login(request: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == request.email).first()
    if not user or not verify_password(request.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="E-posta veya şifre hatalı.")
    return {"message": "Giriş başarılı", "user_id": user.id}

@app.get("/api/v1/user/{user_id}")
def get_user_profile(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")
    prefs = db.query(UserPreferences).filter(UserPreferences.user_id == user_id).first()
    return {
        "email": user.email,
        "name": user.name,
        "age": getattr(prefs, "age", None),
        "gender": getattr(prefs, "gender", None),
        "height": getattr(prefs, "height", None),
        "weight": getattr(prefs, "weight", None),
        "goal": getattr(prefs, "goal", None),
        "activity_level": getattr(prefs, "activity_level", None),
    }

@app.put("/api/v1/user/{user_id}")
def update_user_profile(user_id: int, request: UpdateProfileRequest = Body(...), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")
    if request.name is not None:
        user.name = request.name
    prefs = db.query(UserPreferences).filter(UserPreferences.user_id == user_id).first()
    if not prefs:
        prefs = UserPreferences(user_id=user_id)
        db.add(prefs)
    if request.age is not None:
        prefs.age = request.age
    if request.gender is not None:
        prefs.gender = request.gender
    if request.height is not None:
        prefs.height = request.height
    if request.weight is not None:
        prefs.weight = request.weight
    if request.goal is not None:
        prefs.goal = request.goal
    if request.activity_level is not None:
        prefs.activity_level = request.activity_level
    db.commit()
    return {"message": "Profil güncellendi"}

@app.post("/api/v1/user/{user_id}/change-password")
def change_password(user_id: int, request: ChangePasswordRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")
    if not verify_password(request.old_password, user.hashed_password):
        raise HTTPException(status_code=400, detail="Mevcut şifre yanlış.")
    user.hashed_password = get_password_hash(request.new_password)
    db.commit()
    return {"message": "Şifre başarıyla değiştirildi."}

def calculate_water_goal(user):
    prefs = user.preferences
    if prefs:
        if prefs.custom_water_goal:
            return prefs.custom_water_goal
        if prefs.weight:
            return prefs.weight * 33
    return 2000

@app.get("/api/v1/water/goal/{user_id}")
def get_personal_water_goal(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).options(joinedload(User.preferences)).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")
    return {"goal_ml": calculate_water_goal(user)}

@app.post("/api/v1/water/add-glass")
def add_water_glass(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).options(joinedload(User.preferences)).filter(User.id == user_id).first()
    goal = calculate_water_goal(user)
    log = db.query(WaterLog).filter(WaterLog.user_id == user_id, WaterLog.date == date.today()).first()
    if log:
        log.amount_ml += 200
        log.goal_ml = goal
    else:
        log = WaterLog(user_id=user_id, date=date.today(), amount_ml=200, goal_ml=goal)
        db.add(log)
    db.commit()
    return {"message": "1 bardak (200 ml) su eklendi."}

@app.post("/api/v1/water/add")
def add_water_log(request: WaterLogRequest, user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).options(joinedload(User.preferences)).filter(User.id == user_id).first()
    goal = calculate_water_goal(user)
    log_date = request.date or date.today()
    log = db.query(WaterLog).filter(WaterLog.user_id == user_id, WaterLog.date == log_date).first()
    if log:
        log.amount_ml += request.amount_ml
        log.goal_ml = goal
        if request.goal_ml:
            log.goal_ml = request.goal_ml
    else:
        log = WaterLog(
            user_id=user_id,
            date=log_date,
            amount_ml=request.amount_ml,
            goal_ml=request.goal_ml or goal
        )
        db.add(log)
    db.commit()
    return {"message": "Su kaydı eklendi/güncellendi."}

@app.get("/api/v1/water/today/{user_id}")
def get_today_water_log(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).options(joinedload(User.preferences)).filter(User.id == user_id).first()
    auto_goal = calculate_water_goal(user)
    log = db.query(WaterLog).filter(WaterLog.user_id == user_id, WaterLog.date == date.today()).first()
    if log:
        log.goal_ml = auto_goal
        db.commit()
        glasses = log.amount_ml // 200
        return {"amount_ml": log.amount_ml, "goal_ml": log.goal_ml, "glasses": glasses, "glass_size": 200}
    return {"amount_ml": 0, "goal_ml": auto_goal, "glasses": 0, "glass_size": 200}

@app.get("/api/v1/water/history/{user_id}")
def get_water_history(user_id: int, db: Session = Depends(get_db)):
    logs = db.query(WaterLog).filter(WaterLog.user_id == user_id).order_by(WaterLog.date.desc()).all()
    return [
        {"date": l.date.strftime("%Y-%m-%d"), "amount_ml": l.amount_ml, "goal_ml": l.goal_ml}
        for l in logs
    ]

@app.put("/api/v1/water/goal/{user_id}")
def update_water_goal(user_id: int, goal_ml: int, db: Session = Depends(get_db)):
    prefs = db.query(UserPreferences).filter(UserPreferences.user_id == user_id).first()
    if not prefs:
        prefs = UserPreferences(user_id=user_id)
        db.add(prefs)
    prefs.custom_water_goal = goal_ml
    db.commit()
    
    log = db.query(WaterLog).filter(WaterLog.user_id == user_id, WaterLog.date == date.today()).first()
    if log:
        log.goal_ml = goal_ml
        db.commit()
    return {"message": "Günlük su hedefi güncellendi."}

def calculate_macros_and_calories(age, gender, weight, height, goal, activity_level):
    # Mifflin-St Jeor
    if gender == "male" or gender == "erkek":
        bmr = 10 * weight + 6.25 * height - 5 * age + 5
    else:
        bmr = 10 * weight + 6.25 * height - 5 * age - 161

    activity_multipliers = {
        "sedentary": 1.2,
        "light": 1.375,
        "moderate": 1.55,
        "active": 1.725,
        "very_active": 1.9
    }
    tdee = bmr * activity_multipliers.get(activity_level, 1.55)

    
    if goal == "weight_loss":
        calories = tdee - 500
    elif goal == "muscle_gain":
        calories = tdee + 500
    else:
        calories = tdee

    
    protein = weight * 2  
    fat = weight * 0.8    
    if goal == "weight_loss":
        carbs = weight * 2
    elif goal == "muscle_gain":
        carbs = weight * 4
    else:
        carbs = weight * 3

    return {
        "calories": round(calories),
        "protein_g": round(protein),
        "fat_g": round(fat),
        "carbs_g": round(carbs)
    }

@app.get("/api/v1/user/{user_id}/macros")
def get_user_macros(user_id: int, db: Session = Depends(get_db)):
    prefs = db.query(UserPreferences).filter(UserPreferences.user_id == user_id).first()
    if not prefs or not prefs.weight or not prefs.height or not prefs.age or not prefs.gender or not prefs.goal:
        raise HTTPException(status_code=400, detail="Makro hesaplama için yeterli bilgi yok.")
    activity_level = prefs.activity_level or 'moderate'
    result = calculate_macros_and_calories(
        age=prefs.age,
        gender=prefs.gender.lower(),
        weight=prefs.weight,
        height=prefs.height,
        goal=prefs.goal,
        activity_level=activity_level.lower()
    )
    return result


@app.post("/api/v1/nutrition/add-food")
def add_food_entry(user_id: int, request: FoodEntryRequest, db: Session = Depends(get_db)):
    """Kullanıcının girdiği beslenme kaydını ekler"""
    
    calculated_calories = (request.protein_g * 4) + (request.carbs_g * 4) + (request.fat_g * 9)
    final_calories = request.calories if request.calories is not None else calculated_calories
    
    
    today = date.today()
    
    food_entry = FoodEntry(
        user_id=user_id,
        food_name=request.food_name,
        protein_g=request.protein_g,
        carbs_g=request.carbs_g,
        fat_g=request.fat_g,
        calories=final_calories,
        date=today  
    )
    db.add(food_entry)
    db.commit()
    
    update_daily_nutrition(user_id, db)
    
    return {"message": "Beslenme kaydı eklendi", "calculated_calories": final_calories}

@app.get("/api/v1/nutrition/today/{user_id}")
def get_today_nutrition(user_id: int, db: Session = Depends(get_db)):
    """Kullanıcının bugünkü beslenme verilerini getirir"""
    today = date.today()
    
    food_entries = db.query(FoodEntry).filter(
        FoodEntry.user_id == user_id,
        FoodEntry.date == today
    ).all()
    
    
    nutrition_log = db.query(NutritionLog).filter(
        NutritionLog.user_id == user_id,
        NutritionLog.date == today
    ).first()
    
    return {
        "date": today,
        "food_entries": [{
            "id": entry.id,
            "food_name": entry.food_name,
            "protein_g": entry.protein_g,
            "carbs_g": entry.carbs_g,
            "fat_g": entry.fat_g,
            "calories": entry.calories,
            "created_at": entry.created_at
        } for entry in food_entries],
        "daily_totals": {
            "total_protein_g": nutrition_log.total_protein_g if nutrition_log else 0,
            "total_carbs_g": nutrition_log.total_carbs_g if nutrition_log else 0,
            "total_fat_g": nutrition_log.total_fat_g if nutrition_log else 0,
            "total_calories": nutrition_log.total_calories if nutrition_log else 0
        }
    }

@app.get("/api/v1/nutrition/history/{user_id}")
def get_nutrition_history(user_id: int, days: int = 7, db: Session = Depends(get_db)):
    """Kullanıcının beslenme geçmişini getirir"""
    from datetime import timedelta
    
    end_date = date.today()
    start_date = end_date - timedelta(days=days-1)
    
    nutrition_logs = db.query(NutritionLog).filter(
        NutritionLog.user_id == user_id,
        NutritionLog.date >= start_date,
        NutritionLog.date <= end_date
    ).order_by(NutritionLog.date.desc()).all()
    
    return [{
        "date": log.date,
        "total_protein_g": log.total_protein_g,
        "total_carbs_g": log.total_carbs_g,
        "total_fat_g": log.total_fat_g,
        "total_calories": log.total_calories
    } for log in nutrition_logs]

@app.delete("/api/v1/nutrition/food/{food_id}")
def delete_food_entry(food_id: int, user_id: int, db: Session = Depends(get_db)):
    """Beslenme kaydını siler"""
    food_entry = db.query(FoodEntry).filter(
        FoodEntry.id == food_id,
        FoodEntry.user_id == user_id
    ).first()
    
    if not food_entry:
        raise HTTPException(status_code=404, detail="Beslenme kaydı bulunamadı")
    
    db.delete(food_entry)
    db.commit()
    
    
    update_daily_nutrition(user_id, db)
    
    return {"message": "Beslenme kaydı silindi"}

def update_daily_nutrition(user_id: int, db: Session):
    """Günlük beslenme toplamlarını günceller"""
    today = date.today()
    
    
    food_entries = db.query(FoodEntry).filter(
        FoodEntry.user_id == user_id,
        FoodEntry.date == today
    ).all()
    
    total_protein = sum(entry.protein_g for entry in food_entries)
    total_carbs = sum(entry.carbs_g for entry in food_entries)
    total_fat = sum(entry.fat_g for entry in food_entries)
    total_calories = sum(entry.calories for entry in food_entries)
    
    
    nutrition_log = db.query(NutritionLog).filter(
        NutritionLog.user_id == user_id,
        NutritionLog.date == today
    ).first()
    
    if nutrition_log:
        nutrition_log.total_protein_g = total_protein
        nutrition_log.total_carbs_g = total_carbs
        nutrition_log.total_fat_g = total_fat
        nutrition_log.total_calories = total_calories
    else:
        nutrition_log = NutritionLog(
            user_id=user_id,
            date=today,
            total_protein_g=total_protein,
            total_carbs_g=total_carbs,
            total_fat_g=total_fat,
            total_calories=total_calories
        )
        db.add(nutrition_log)
    
    db.commit()


@app.put("/api/v1/user/{user_id}/profile")
def update_user_profile_for_agent(user_id: int, request: UpdateProfileRequest = Body(...), db: Session = Depends(get_db)):
    """AI agent tarafından kullanılan profil güncelleme endpoint'i"""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")
    
    
    if request.name is not None:
        user.name = request.name
    
    
    prefs = db.query(UserPreferences).filter(UserPreferences.user_id == user_id).first()
    if not prefs:
        prefs = UserPreferences(user_id=user_id)
        db.add(prefs)
    
    
    if request.age is not None:
        prefs.age = request.age
    if request.gender is not None:
        prefs.gender = request.gender
    if request.height is not None:
        prefs.height = request.height
    if request.weight is not None:
        prefs.weight = request.weight
    if request.goal is not None:
        prefs.goal = request.goal
    if request.activity_level is not None:
        prefs.activity_level = request.activity_level
    
    db.commit()
    return {"message": "Profil başarıyla güncellendi"}


@app.post("/api/v1/nutrition/food/add")
def add_food_for_agent(user_id: int, request: FoodEntryRequest, db: Session = Depends(get_db)):
    """AI agent tarafından kullanılan yiyecek ekleme endpoint'i"""
    
    calculated_calories = (request.protein_g * 4) + (request.carbs_g * 4) + (request.fat_g * 9)
    final_calories = request.calories if request.calories is not None else calculated_calories
    
    
    today = date.today()
    
    
    food_entry = FoodEntry(
        user_id=user_id,
        food_name=request.food_name,
        protein_g=request.protein_g,
        carbs_g=request.carbs_g,
        fat_g=request.fat_g,
        calories=final_calories,
        date=today
    )
    db.add(food_entry)
    db.commit()
    
    
    update_daily_nutrition(user_id, db)
    
    return {
        "message": "Yiyecek başarıyla eklendi",
        "total_today": final_calories,
        "calculated_calories": final_calories
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
