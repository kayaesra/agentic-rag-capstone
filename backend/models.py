from sqlalchemy import Boolean, Column, ForeignKey, Integer, String, DateTime, JSON, Text, Float, Date
from sqlalchemy.orm import relationship
from database import Base
from datetime import datetime, date


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    name = Column(String)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    preferences = relationship("UserPreferences", back_populates="user", uselist=False)
    chat_history = relationship("ChatHistory", back_populates="user")

class UserPreferences(Base):
    __tablename__ = "user_preferences"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    dietary_restrictions = Column(JSON)
    allergies = Column(JSON)
    weight = Column(Integer)  
    height = Column(Integer) 
    age = Column(Integer)
    gender = Column(String)
    activity_level = Column(String, nullable=True)  
    fitness_goals = Column(String)
    custom_water_goal = Column(Integer, nullable=True) 
    goal = Column(String, nullable=True)      
    user = relationship("User", back_populates="preferences")

class ChatHistory(Base):
    __tablename__ = "chat_history"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    message = Column(Text)
    response = Column(Text)
    timestamp = Column(DateTime, default=datetime.utcnow) 
    user = relationship("User", back_populates="chat_history")

class WaterLog(Base):
    __tablename__ = "water_log"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    date = Column(DateTime, default=datetime.utcnow)
    amount_ml = Column(Integer) 
    goal_ml = Column(Integer, default=2000) 
    user = relationship("User") 

class ChatSession(Base):
    __tablename__ = "chat_sessions"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    created_at = Column(DateTime, default=datetime.utcnow)
    session_name = Column(String, default="Yeni Sohbet")
    messages = relationship("ChatMessage", back_populates="session")

class ChatMessage(Base):
    __tablename__ = "chat_messages"
    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(Integer, ForeignKey("chat_sessions.id"))
    user_id = Column(Integer, ForeignKey("users.id"))
    role = Column(String) 
    text = Column(Text)
    timestamp = Column(DateTime, default=datetime.utcnow)
    session = relationship("ChatSession", back_populates="messages") 

class FoodEntry(Base):
    __tablename__ = "food_entries"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    food_name = Column(String)
    protein_g = Column(Float, default=0)
    carbs_g = Column(Float, default=0)
    fat_g = Column(Float, default=0)
    calories = Column(Float, default=0)
    date = Column(Date, default=lambda: date.today())
    created_at = Column(DateTime, default=datetime.utcnow)
    user = relationship("User")

class NutritionLog(Base):
    __tablename__ = "nutrition_logs"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    date = Column(Date, default=lambda: date.today())
    total_protein_g = Column(Float, default=0)
    total_carbs_g = Column(Float, default=0)
    total_fat_g = Column(Float, default=0)
    total_calories = Column(Float, default=0)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    user = relationship("User") 
