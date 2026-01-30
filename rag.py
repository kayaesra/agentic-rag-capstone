import os
import pandas as pd
from typing import List, Dict, Optional
import numpy as np
from langchain_openai import ChatOpenAI, OpenAIEmbeddings
import faiss
from langchain.agents import Tool, AgentExecutor, create_react_agent
from langchain.prompts import PromptTemplate
from langchain.tools import BaseTool
from langchain_community.document_loaders import PyPDFLoader
import requests
import urllib.parse
from typing import ClassVar
from dotenv import load_dotenv
import json
from datetime import datetime, date
from pathlib import Path


load_dotenv()

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
if not OPENAI_API_KEY:
    raise ValueError("OPENAI_API_KEY environment variable is not set. Please add it to your .env file.")

os.environ["OPENAI_API_KEY"] = OPENAI_API_KEY


_database_session = None

def set_database_session(db_session):
    """Set the database session for tools to use"""
    global _database_session
    _database_session = db_session

def get_database_session():
    """Get the current database session"""
    return _database_session

class DocumentRAG:
    def __init__(self, data_dir: str):
        self.data_dir = data_dir
        self.documents = []
        self.index = None
        self.embeddings = None
        self.model = None
        self.index_path = os.path.join(data_dir, "faiss_index")
        self.documents_path = os.path.join(data_dir, "documents.json")
        
       
        self._init_models()
        
        
        if self._load_existing_index():
            print("Mevcut embedding'ler yüklendi.")
            
            self.check_and_add_new_files()
        else:
            print("Yeni embedding'ler oluşturuluyor...")
            new_files_found = self._load_documents()
            if new_files_found or len(self.documents) > 0:
                self._create_embeddings()
                self._save_index()
            else:
                print("İşlenecek dosya bulunamadı!")
    
    def _init_models(self):
        """Initialize OpenAI models for LLM and embeddings"""
        self.model = ChatOpenAI(
            model="gpt-4o-mini",
            temperature=0.1,
            api_key=OPENAI_API_KEY
        )
        self.embeddings = OpenAIEmbeddings(
            model="text-embedding-3-small",
            api_key=OPENAI_API_KEY
        )
    
    def _save_index(self):
        """Save FAISS index and documents to disk"""
        if self.index is not None:
            
            faiss.write_index(self.index, self.index_path)
           
            with open(self.documents_path, 'w', encoding='utf-8') as f:
                json.dump(self.documents, f, ensure_ascii=False, indent=2)
            print(f"Embedding'ler kaydedildi: {self.index_path}")
    
    def _load_existing_index(self) -> bool:
        """Load existing FAISS index and documents if available"""
        try:
            if os.path.exists(self.index_path) and os.path.exists(self.documents_path):
               
                self.index = faiss.read_index(self.index_path)
                
                with open(self.documents_path, 'r', encoding='utf-8') as f:
                    self.documents = json.load(f)
                return True
        except Exception as e:
            print(f"Embedding'ler yüklenirken hata: {str(e)}")
        return False
    
    def _load_documents(self):
        """Load and process all CSV and PDF files in the directory"""
        print("\nDosya yükleme işlemi başladı...")
        
       
        existing_files = set()
        if os.path.exists(self.documents_path):
            with open(self.documents_path, 'r', encoding='utf-8') as f:
                existing_docs = json.load(f)
                existing_files = {doc['source'] for doc in existing_docs}
               
                self.documents = existing_docs
        
        new_files_found = False
        
        for filename in os.listdir(self.data_dir):
            
            if filename.startswith('.') or filename in ['faiss_index', 'documents.json']:
                continue
                
          
            if filename in existing_files:
                print(f"\nDosya zaten işlenmiş: {filename}")
                continue
                
            file_path = os.path.join(self.data_dir, filename)
            print(f"\n YENİ DOSYA İŞLENİYOR: {filename}")
            new_files_found = True
            
            if filename.endswith('.csv'):
                # Process CSV files
                df = pd.read_csv(file_path)
                print(f"CSV dosyası yüklendi: {len(df)} satır")
                for _, row in df.iterrows():
                    text = " | ".join([f"{col}: {val}" for col, val in row.items()])
                    self.documents.append({
                        'text': text,
                        'source': filename
                    })
            
            elif filename.endswith('.pdf'):
                # Process PDF files
                try:
                    print(f"PDF dosyası işleniyor: {filename}")
                    loader = PyPDFLoader(file_path)
                    pages = loader.load()
                    print(f"PDF sayfa sayısı: {len(pages)}")
                    
                    for i, page in enumerate(pages):
                        chunks = self._split_text(page.page_content)
                        print(f"Sayfa {i+1} için oluşturulan chunk sayısı: {len(chunks)}")
                        
                        for chunk in chunks:
                            if chunk.strip():
                                self.documents.append({
                                    'text': chunk,
                                    'source': filename
                                })
                except Exception as e:
                    print(f"PDF işleme hatası {filename}: {str(e)}")
        
        if new_files_found:
            print(f"\n YENİ DOSYALAR BULUNDU VE İŞLENDİ!")
        else:
            print(f"\nYeni dosya bulunamadı, mevcut embeddings kullanılıyor")
            
        print(f"\nToplam yüklenen doküman sayısı: {len(self.documents)}")
        print(f"PDF kaynaklı doküman sayısı: {len([d for d in self.documents if d['source'].endswith('.pdf')])}")
        print(f"CSV kaynaklı doküman sayısı: {len([d for d in self.documents if d['source'].endswith('.csv')])}")
        
        return new_files_found
    
    def _split_text(self, text: str, chunk_size: int = 1000) -> List[str]:
        """Split text into smaller chunks"""
        words = text.split()
        chunks = []
        current_chunk = []
        current_size = 0
        
        for word in words:
            current_chunk.append(word)
            current_size += len(word) + 1
            
            if current_size >= chunk_size:
                chunks.append(" ".join(current_chunk))
                current_chunk = []
                current_size = 0
        
        if current_chunk:
            chunks.append(" ".join(current_chunk))
        
        return chunks
    
    def _create_embeddings(self):
        """Create embeddings for all documents"""
        texts = [doc['text'] for doc in self.documents]
        embeddings = self.embeddings.embed_documents(texts)
        
        embeddings_array = np.array(embeddings, dtype=np.float32)
        self.dimension = embeddings_array.shape[1]
        self.index = faiss.IndexFlatIP(self.dimension)
        self.index.add(embeddings_array)
    
    def _add_new_documents_to_existing_index(self, new_documents):
        """Add new documents to existing FAISS index incrementally"""
        if not new_documents:
            return
            
        print(f"\n Mevcut embedding'lere {len(new_documents)} yeni doküman ekleniyor...")
        
      
        new_texts = [doc['text'] for doc in new_documents]
     
        batch_size = 100  
        all_embeddings = []
        
        for i in range(0, len(new_texts), batch_size):
            batch_texts = new_texts[i:i+batch_size]
            print(f" Batch {i//batch_size + 1}/{(len(new_texts)-1)//batch_size + 1} işleniyor... ({len(batch_texts)} doküman)")
            
            try:
                batch_embeddings = self.embeddings.embed_documents(batch_texts)
                all_embeddings.extend(batch_embeddings)
            except Exception as e:
                print(f"Batch {i//batch_size + 1} işlenirken hata: {str(e)}")
             
                continue
        
        if all_embeddings:
            new_embeddings_array = np.array(all_embeddings, dtype=np.float32)
            
           
            self.index.add(new_embeddings_array)
            
            successful_docs = new_documents[:len(all_embeddings)]
            self.documents.extend(successful_docs)
            
            print(f"{len(all_embeddings)} embedding başarıyla eklendi!")
        else:
            print(" Hiçbir embedding oluşturulamadı!")

    def check_and_add_new_files(self):
        """Check for new files and add them incrementally"""
        print("\n Yeni dosyalar kontrol ediliyor...")
        

        existing_files = set()
        if os.path.exists(self.documents_path):
            existing_files = {doc['source'] for doc in self.documents}
        
        new_documents = []
        new_files_found = False
        
        for filename in os.listdir(self.data_dir):
            
            if filename.startswith('.') or filename in ['faiss_index', 'documents.json']:
                continue
                
            if filename not in existing_files:
                print(f"\n🆕 YENİ DOSYA BULUNDU: {filename}")
                new_files_found = True
                file_path = os.path.join(self.data_dir, filename)
                
                if filename.endswith('.csv'):
                    df = pd.read_csv(file_path)
                    print(f"CSV dosyası işleniyor: {len(df)} satır")
                    for _, row in df.iterrows():
                        text = " | ".join([f"{col}: {val}" for col, val in row.items()])
                        new_documents.append({
                            'text': text,
                            'source': filename
                        })
                
                elif filename.endswith('.pdf'):
                    try:
                        print(f"PDF dosyası işleniyor: {filename}")
                        loader = PyPDFLoader(file_path)
                        pages = loader.load()
                        print(f"PDF sayfa sayısı: {len(pages)}")
                        
                        for i, page in enumerate(pages):
                            chunks = self._split_text(page.page_content)
                            print(f"Sayfa {i+1}: {len(chunks)} chunk")
                            
                            for chunk in chunks:
                                if chunk.strip():
                                    new_documents.append({
                                        'text': chunk,
                                        'source': filename
                                    })
                    except Exception as e:
                        print(f"PDF işleme hatası {filename}: {str(e)}")
        
        if new_files_found and new_documents:
           
            self._add_new_documents_to_existing_index(new_documents)
            
            self._save_index()
            print(f"\n {len(new_documents)} yeni doküman başarıyla eklendi!")
            return True
        elif new_files_found:
            print("\n Yeni dosyalar bulundu ama işlenebilir içerik yok")
            return False
        else:
            print("\n Yeni dosya bulunamadı")
            return False
    
    def retrieve(self, query: str, top_k: int = 3) -> List[Dict]:
        """Retrieve most relevant documents for a query"""
        query_embedding = self.embeddings.embed_query(query)
        query_vector = np.array([query_embedding], dtype=np.float32)
        
        scores, indices = self.index.search(query_vector, top_k)
        results = [self.documents[idx] for idx in indices[0]]
        
        print("\nRetrieved Documents Summary:")
        print("-" * 50)
        pdf_count = len([r for r in results if r['source'].endswith('.pdf')])
        csv_count = len([r for r in results if r['source'].endswith('.csv')])
        print(f"PDF kaynaklı doküman sayısı: {pdf_count}")
        print(f"CSV kaynaklı doküman sayısı: {csv_count}")
        print("-" * 50)
        
        return results
    
    def generate_response(self, query: str, top_k: int = 3) -> str:
        """Generate response using retrieved context"""
        relevant_docs = self.retrieve(query, top_k)
        
        print("\nRetrieved Documents:")
        print("-" * 50)
        for i, doc in enumerate(relevant_docs, 1):
            print(f"\nDocument {i} (Source: {doc['source']}):")
            print(doc['text'])
        print("-" * 50 + "\n")
        
        if not relevant_docs or not any(doc['text'].strip() for doc in relevant_docs):
            return "Bu konuda veritabanımda herhangi bir bilgi bulunamadı."
        
        context = "\n".join([doc['text'] for doc in relevant_docs])
        
        prompt = f"""Aşağıdaki veri tabanı bilgilerini kullanarak soruyu yanıtla:

VERİTABANI BİLGİSİ:
{context}

SORU: {query}

KURALLAR:
- SADECE yukarıdaki veritabanı bilgilerini kullan
- Kendi genel bilgini EKLEME  
- Veri yetersizse "mevcut veritabanımda daha fazla bilgi yok" de
- Yanıtı TÜRKÇE ver
- İngilizce verileri Türkçeye çevir

YANIT:"""
        
        response = self.model.invoke(prompt)
        return response.content


class BMICalculator(BaseTool):
    name: str = "bmi_calculator"
    description: str = "Calculate Body Mass Index (BMI) and provide health category. Input should be in format: weight_kg=70, height_m=1.75"
    
    def _run(self, query: str) -> str:
       
        try:
           
            params = {}
            for param in query.split(','):
                if '=' in param:
                    key, value = param.strip().split('=')
                    params[key.strip()] = value.strip()
            
            weight_kg = float(params['weight_kg'])
            height_m = float(params['height_m'])
            
            bmi = weight_kg / (height_m ** 2)
            
            if bmi < 18.5:
                category = "Underweight"
            elif 18.5 <= bmi < 25:
                category = "Normal weight"
            elif 25 <= bmi < 30:
                category = "Overweight"
            else:
                category = "Obese"
                
            return f"BMI: {bmi:.1f}\nCategory: {category}"
        except Exception as e:
            return f"Error calculating BMI: {str(e)}. Please provide input in format: weight_kg=70, height_m=1.75"

class DietRAGTool(BaseTool):
    name: str = "diet_rag"
    description: str = "Search for diet and nutrition information using RAG"
    rag: Optional[DocumentRAG] = None
    
    def __init__(self, data_dir: str):
        super().__init__()
        self.rag = DocumentRAG(data_dir)
    
    def _run(self, query: str) -> str:
        if self.rag is None:
            raise ValueError("RAG system not initialized")
        return self.rag.generate_response(query)
    

class MacroCalculator(BaseTool):
    name: str = "macro_calculator"
    description: str = "Calculate daily macronutrient needs based on weight and goals. Input format: weight_kg=70, goal=weight_loss"
    
    def _run(self, query: str) -> str:
        try:
           
            params = {}
            for param in query.split(','):
                if '=' in param:
                    key, value = param.strip().split('=')
                    params[key.strip()] = value.strip()
            
            weight_kg = float(params['weight_kg'])
            goal = params['goal'].lower()
            
           
            protein = weight_kg * 2.0
            
           
            fat = weight_kg * 0.8
            
            
            if goal == 'weight_loss':
                carbs = weight_kg * 2.0
            elif goal == 'muscle_gain':
                carbs = weight_kg * 4.0
            else:  
                carbs = weight_kg * 3.0
            
            return f"""Daily Macronutrient Needs:
            - Protein: {protein:.0f}g
            - Fat: {fat:.0f}g
            - Carbs: {carbs:.0f}g"""
            
        except Exception as e:
            return f"Error calculating macros: {str(e)}. Please provide input in correct format."


class CalorieCalculator(BaseTool):
    name: str = "calorie_calculator"
    description: str = "Calculate daily calorie needs based on age, gender, weight, height, and activity level. Input format: age=30, gender=male, weight_kg=70, height_cm=175, activity_level=moderate"
    
    def _run(self, query: str) -> str:
        try:
            
            params = {}
            for param in query.split(','):
                if '=' in param:
                    key, value = param.strip().split('=')
                    params[key.strip()] = value.strip()
            
           
            age = int(params['age'])
            gender = params['gender'].lower()
            weight_kg = float(params['weight_kg'])
            height_cm = float(params['height_cm'])
            activity_level = params['activity_level'].lower()
            
           
            if gender == 'male':
                bmr = 10 * weight_kg + 6.25 * height_cm - 5 * age + 5
            else:
                bmr = 10 * weight_kg + 6.25 * height_cm - 5 * age - 161
            
            
            activity_multipliers = {
                'sedentary': 1.2,
                'light': 1.375,
                'moderate': 1.55,
                'active': 1.725,
                'very_active': 1.9
            }
            
            tdee = bmr * activity_multipliers.get(activity_level, 1.55)
            
            return f"""Daily Calorie Needs:
            - Maintenance: {tdee:.0f} calories
            - Weight Loss: {tdee - 500:.0f} calories
            - Weight Gain: {tdee + 500:.0f} calories"""
            
        except Exception as e:
            return f"Error calculating calories: {str(e)}. Please provide input in format: age=30, gender=male, weight_kg=70, height_cm=175, activity_level=moderate"


class WaterIntakeCalculator(BaseTool):
    name: str = "water_calculator"
    description: str = "Calculate daily water intake needs based on weight. Input format: weight_kg=70"
    
    def _run(self, query: str) -> str:
        try:
      
            params = {}
            for param in query.split(','):
                if '=' in param:
                    key, value = param.strip().split('=')
                    params[key.strip()] = value.strip()
            
            weight_kg = float(params['weight_kg'])
            
           
            water_ml = weight_kg * 33
            water_liters = water_ml / 1000
            
            return f"""Daily Water Intake Needs:
            - {water_liters:.1f} liters ({water_ml:.0f} ml)
            - Approximately {water_liters/0.25:.0f} glasses (250ml)"""
            
        except Exception as e:
            return f"Error calculating water intake: {str(e)}. Please provide input in correct format."
        
class EdamamMealPlannerTool(BaseTool):
    name: str = "meal_planner"
    description: str = (
        "Generate a weekly meal plan using Edamam API. "
        "Input format: diet=vegetarian, calories=2000, days=7. "
        "If no input is provided, defaults are used: diet=vegetarian, calories=2000, days=7."
    )

    def get_recipe_label(self, recipe_uri, app_id, app_key):
        import requests
        import re

        if recipe_uri.startswith("http"):
            match = re.search(r'recipes/v2/([^/?]+)', recipe_uri)
            if match:
                recipe_id = match.group(1)
                recipe_uri = f"http://www.edamam.com/ontologies/edamam.owl#recipe_{recipe_id}"

        url = "https://api.edamam.com/api/recipes/v2/by-uri"
        params = {
            "uri": recipe_uri,
            "app_id": app_id,
            "app_key": app_key
        }
        headers = {
            "Edamam-Account-User": "testuser1"
        }
        try:
            response = requests.get(url, params=params, headers=headers)
            print(f"Recipe URI: {recipe_uri} | Status: {response.status_code} | Response: {response.text[:200]}")
            if response.status_code == 200:
                data = response.json()
                if data.get("hits") and data["hits"][0].get("recipe"):
                    return data["hits"][0]["recipe"].get("label", "Unknown Recipe")
                else:
                    return "Recipe not found in Edamam database"
            else:
                return f"API Error: {response.status_code}"
        except Exception as e:
            print(f"Error fetching recipe label: {e}")
            return "Unknown Recipe"

    def _run(self, query: str) -> str:
        import requests
        APP_ID = "c67374f6"
        APP_KEY = "7831499c14862d774e2abd6f282c96be"
        USER_ID = "testuser1"
        try:
            
            params = {}
            for param in query.split(','):
                if '=' in param:
                    key, value = param.strip().split('=')
                    params[key.strip()] = value.strip()
            
            days = int(params.get('days', 7))
        except Exception as e:
            return f"Error parsing input: {str(e)}. Please use format: days=7"

        url = f"https://api.edamam.com/api/meal-planner/v1/{APP_ID}/select?app_id={APP_ID}&app_key={APP_KEY}"
        headers = {
            "Edamam-Account-User": USER_ID
        }
        payload = {
            "size": days,
            "plan": {
                "sections": {
                    "Breakfast": {
                        "accept": {
                            "all": [
                                {"dish": ["cereals", "bread", "pancake"]},
                                {"meal": ["breakfast"]}
                            ]
                        }
                    },
                    "Lunch": {
                        "accept": {
                            "all": [
                                {"dish": ["main course", "pasta", "salad", "soup", "sandwiches", "pizza"]},
                                {"meal": ["lunch/dinner"]}
                            ]
                        }
                    },
                    "Dinner": {
                        "accept": {
                            "all": [
                                {"dish": ["main course", "salad", "pizza", "pasta"]},
                                {"meal": ["lunch/dinner"]}
                            ]
                        }
                    }
                }
            }
        }
        try:
            response = requests.post(url, json=payload, headers=headers)
            if response.status_code == 200:
                data = response.json()
                
                output = []
                selection = data.get("selection", [])
                for day_idx, day in enumerate(selection, 1):
                    output.append(f"**Day {day_idx}**")
                    sections = day.get("sections", {})
                    for meal in ["Breakfast", "Lunch", "Dinner"]:
                        meal_info = sections.get(meal)
                        if meal_info and "assigned" in meal_info:
                            recipe_uri = meal_info["assigned"]
                            recipe_link = meal_info.get("_links", {}).get("self", {}).get("href", recipe_uri)
                            recipe_label = self.get_recipe_label(recipe_uri, APP_ID, APP_KEY)
                            output.append(f"- **{meal}**: [{recipe_label}]({recipe_link})")
                    output.append("")
                return "\n".join(output)
            else:
                return f"API Error: {response.status_code} - {response.text}"
        except Exception as e:
            return f"Request failed: {str(e)}"

def wikipedia_search(query: str) -> str:
    """Search Wikipedia for information"""
    import requests
    import urllib.parse
    
   
    encoded_query = urllib.parse.quote(query)
    
   
    search_url = f"https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch={encoded_query}&format=json&utf8=1"
    
    try:
        response = requests.get(search_url, timeout=10)
        if response.status_code == 200:
            data = response.json()
            search_results = data.get("query", {}).get("search", [])
            
            if not search_results:
                return "No relevant information found."
            
            page_id = search_results[0].get("pageid")
            
       
            content_url = f"https://en.wikipedia.org/w/api.php?action=query&prop=extracts&exintro=1&explaintext=1&pageids={page_id}&format=json&utf8=1"
            content_response = requests.get(content_url, timeout=10)
            
            if content_response.status_code == 200:
                content_data = content_response.json()
                pages = content_data.get("query", {}).get("pages", {})
                if str(page_id) in pages:
                    extract = pages[str(page_id)].get("extract", "")
                    if extract:
                        
                        extract = extract.replace("\n", " ").strip()
                        if len(extract) > 500:
                            extract = extract[:497] + "..."
                        return f" {extract}\n\n🔗 https://en.wikipedia.org/?curid={page_id}"
            
            return "Could not retrieve content."
        else:
            return f"Search error: {response.status_code}"
    except Exception as e:
        return f"An error occurred: {str(e)}"

class WebSearchTool(BaseTool):
    name: str = "web_search"
    description: str = "LAST RESORT: Search Wikipedia only if Diet_Information doesn't have the answer. Use only when local database has no relevant information."

    def _run(self, query: str) -> str:
        return wikipedia_search(query)

class USDAFoodTool(BaseTool):
    name: str = "usda_food"
    description: str = (
        "Search for foods and get their nutritional information using USDA FoodData Central API. "
        "IMPORTANT: Always use ENGLISH food names (sosis→sausage, süt→milk, elma→apple, tavuk→chicken, ekmek→bread, etc.). "
        "Input: food name in English. "
        "Returns food name, calories, and key nutrients."
    )
    API_KEY: ClassVar[str] = "YsJskbXYuMwWfyPsykFdGQjv6whHIin6ao3RORA9"

    def _run(self, query: str) -> str:
        try:
           
            nutrient_keywords = {
                'calorie':      ('1008', 'energy'),
                'calories':     ('1008', 'energy'),
                'kcal':         ('1008', 'energy'),
                'energy':       ('1008', 'energy'),
                'magnesium':    ('1090', 'magnesium'),
                'calcium':      ('1087', 'calcium'),
                'protein':      ('1003', 'protein'),
                'fat':          ('1004', 'fat'),
                'carbohydrate': ('1005', 'carbohydrate'),
                'carb':         ('1005', 'carbohydrate'),
                'sugar':        ('2000', 'sugar'),
                'fiber':        ('1079', 'fiber'),
                'vitamin c':    ('1162', 'vitamin c'),
                'iron':         ('1089', 'iron'),
                'potassium':    ('1092', 'potassium'),
                'sodium':       ('1093', 'sodium'),
                'zinc':         ('1095', 'zinc'),
                'b12':          ('1178', 'b12'),
                'b6':           ('1175', 'b6'),
                'k1':           ('1185', 'vitamin k'),
                'vitamin k':    ('1185', 'vitamin k'),
                'niacin':       ('1167', 'niacin'),
                'riboflavin':   ('1166', 'riboflavin'),
                'thiamin':      ('1165', 'thiamin'),
            }

            
            query_lower = query.lower()
            found_key = None
            for key in nutrient_keywords:
                if key in query_lower:
                    found_key = key
                    break

            foods = self._search_food(query)
            if not foods:
                return f"No foods found matching '{query}'"

            
            best_match = foods[0] 
            best_score = 0
            query_lower = query.lower().strip()
            
            for food in foods:
                description = food.get('description', '').lower()
                score = 0
                
                
                if description.startswith(query_lower):
                    score = 100
                
                elif f" {query_lower} " in f" {description} " or f"{query_lower}," in description:
                    score = 50
                
                elif query_lower in description:
                    score = 25
                 # En yüksek skorlu olanı seç
                if score > best_score:
                    best_score = score
                    best_match = food

            nutrients = best_match.get("foodNutrients", [])
            if not nutrients:
                return f"No nutrient information available for {best_match.get('description', 'Unknown')}"

            
            if found_key:
                nutrient_id, nutrient_name_kw = nutrient_keywords[found_key]
                for nutrient in nutrients:
                    nutrient_id_val = str(nutrient.get("nutrientId"))
                    nutrient_name = nutrient.get("nutrientName", "").lower()
                    
                    if nutrient_id_val == nutrient_id or nutrient_name_kw in nutrient_name or "energy" in nutrient_name:
                        value = nutrient.get("value")
                        unit = nutrient.get("unitName", "")
                        return f"{best_match.get('description', 'Unknown')} için {nutrient.get('nutrientName', nutrient_name_kw).capitalize()}: {value} {unit} (100g için)"
                return f"{best_match.get('description', 'Unknown')} için {found_key} bilgisi bulunamadı."

            
            nutrient_map = {
                "1008": "Energy (kcal)",
                "1003": "Protein",
                "1004": "Total Fat",
                "1005": "Total Carbohydrates",
                "2000": "Sugars",
                "1079": "Fiber",
                "1087": "Calcium",
                "1089": "Iron",
                "1090": "Magnesium",
                "1091": "Phosphorus",
                "1092": "Potassium",
                "1093": "Sodium",
                "1095": "Zinc",
                "1162": "Vitamin C",
                "1165": "Thiamin (B1)",
                "1166": "Riboflavin (B2)",
                "1167": "Niacin (B3)",
                "1175": "Vitamin B6",
                "1178": "Vitamin B12",
                "1185": "Vitamin K"
            }
            found_nutrients = {}
            for nutrient in nutrients:
                nutrient_id = str(nutrient.get("nutrientId"))
                nutrient_name = nutrient.get("nutrientName", "").lower()
                value = nutrient.get("value")
                unit = nutrient.get("unitName", "")
                
                if nutrient_id in nutrient_map or "energy" in nutrient_name:
                    if "energy" in nutrient_name and unit.lower() == "kcal":
                        found_nutrients["Energy (kcal)"] = f"{value} {unit}"
                    elif nutrient_id in nutrient_map and not ("energy" in nutrient_name and unit.lower() != "kcal"):
                        found_nutrients[nutrient_map[nutrient_id]] = f"{value} {unit}"

            output = [f"Food: {best_match.get('description', 'Unknown')}"]
            if found_nutrients:
                output.append("\nNutrients (per 100g):")
                
                if "Energy (kcal)" in found_nutrients:
                    output.append(f"- {found_nutrients.pop('Energy (kcal)')}")
                for name, value in found_nutrients.items():
                    output.append(f"- {name}: {value}")
            else:
                output.append("\nNo nutrient information found in selected item.")
            return "\n".join(output)
        except Exception as e:
            print(f"Error in _run: {str(e)}")
            return f"Error accessing USDA API: {str(e)}"

    def _search_food(self, query: str) -> list:
        url = "https://api.nal.usda.gov/fdc/v1/foods/search"
        headers = {"Content-Type": "application/json"}
        payload = {
            "query": query,
            "pageSize": 5,
            "dataType": ["Foundation", "SR Legacy", "Survey (FNDDS)"],
            "sortBy": "dataType.keyword",
            "sortOrder": "asc",
            "queryFields": ["description", "foodCategory", "brandName"],
            "exactMatch": False,
            "includeDataType": True,
            "includeNutrients": True
        }

        try:
            response = requests.post(
                url,
                headers=headers,
                json=payload,
                params={"api_key": self.API_KEY}
            )
            
            if response.status_code == 200:
                data = response.json()
                foods = data.get("foods", [])
                if foods:
                    print(f"Found {len(foods)} foods matching '{query}'")
                    for food in foods:
                        print(f"- {food.get('description')} (ID: {food.get('fdcId')})")
                        if "foodNutrients" in food:
                            print(f"  Nutrients: {food['foodNutrients'][:2]}")
                return foods
            else:
                print(f"Search API Error: {response.status_code} - {response.text}")
                return []
        except Exception as e:
            print(f"Error during food search: {str(e)}")
            return []

class WaterTrackingTool(BaseTool):
    name: str = "water_tracking"
    description: str = (
        "Track water intake and manage daily goals through natural language. "
        "Actions: add (log water), status (check today's progress), goal (set daily target). "
        "Examples: 'action=add, amount_ml=250' or 'action=status' or 'action=goal, target_ml=2500'"
    )
    
    def _run(self, query: str) -> str:
        try:
            
            params = {}
            if 'action=' in query:
                for param in query.split(','):
                    if '=' in param:
                        key, value = param.strip().split('=')
                        params[key.strip()] = value.strip()
            else:
                
                amount_ml = 0
                if 'bardak' in query.lower():
                    
                    words = query.lower().split()
                    for i, word in enumerate(words):
                        if word.isdigit():
                            glasses = int(word)
                            amount_ml = glasses * 200  
                            break
                elif 'ml' in query.lower():
                    
                    words = query.split()
                    for word in words:
                        if word.replace('ml', '').isdigit():
                            amount_ml = int(word.replace('ml', ''))
                            break
                
                if amount_ml > 0:
                    params = {'action': 'add', 'amount_ml': str(amount_ml)}
                else:
                    params = {'action': 'status'}
            
            action = params.get('action', 'status')
            
          
            base_url = "http://localhost:8000/api/v1"
            
            if action == 'add':
                amount_ml = int(params.get('amount_ml', 200))
                
                user_id = self._extract_user_id() or 2  
                
                response = requests.post(
                    f"{base_url}/water/add?user_id={user_id}",
                    headers={'Content-Type': 'application/json'},
                    json={'amount_ml': amount_ml}
                )
                
                if response.status_code == 200:
                    
                    status_response = requests.get(f"{base_url}/water/today/{user_id}")
                    if status_response.status_code == 200:
                        data = status_response.json()
                        current = data.get('amount_ml', 0)
                        goal = data.get('goal_ml', 2000)
                        percentage = (current / goal * 100) if goal > 0 else 0
                        return f" {amount_ml}ml su eklendi! Bugün toplam: {current}ml / {goal}ml (Hedef: %{percentage:.0f})"
                    else:
                        return f" {amount_ml}ml su eklendi!"
                else:
                    return f" Su kaydetme hatası: {response.status_code}"
                    
            elif action == 'status':
                user_id = self._extract_user_id() or 2
                response = requests.get(f"{base_url}/water/today/{user_id}")
                
                if response.status_code == 200:
                    data = response.json()
                    current = data.get('amount_ml', 0)
                    goal = data.get('goal_ml', 2000)
                    percentage = (current / goal * 100) if goal > 0 else 0
                    glasses = current // 200
                    
                    status = "Hedef tamamlandı!" if current >= goal else "💧 Daha fazla su içmelisin"
                    return f"{status}\nBugünkü su alımın: {current}ml / {goal}ml (%{percentage:.0f})\nYaklaşık {glasses} bardak içtin."
                else:
                    return "Su durumu kontrolü başarısız"
                    
            elif action == 'goal':
                target_ml = int(params.get('target_ml', 2000))
                user_id = self._extract_user_id() or 2
                
                response = requests.put(f"{base_url}/water/goal/{user_id}?goal_ml={target_ml}")
                
                if response.status_code == 200:
                    return f"Günlük su hedefin {target_ml}ml olarak güncellendi!"
                else:
                    return "Su hedefi güncelleme hatası"
                    
        except Exception as e:
            return f"Su takibi hatası: {str(e)}"
    
    def _extract_user_id(self):
        """Extract user ID from context if available"""
        
        return getattr(self, '_user_id', None)

class FoodTrackingTool(BaseTool):
    name: str = "food_tracking"
    description: str = (
        "Track food intake and nutrition through natural language. "
        "Actions: add (log food), status (check today's nutrition), goals (see targets). "
        "Examples: 'action=add, food=apple, calories=95' or 'action=status' or 'action=goals'"
    )
    
    def _run(self, query: str) -> str:
        try:
            
            params = {}
            if 'action=' in query:
                for param in query.split(','):
                    if '=' in param:
                        key, value = param.strip().split('=')
                        params[key.strip()] = value.strip()
            else:
                
                params = {'action': 'status'}
            
            action = params.get('action', 'status')
            base_url = "http://localhost:8000/api/v1"
            user_id = self._extract_user_id() or 2
            
            if action == 'add':
                food_name = params.get('food', 'Bilinmeyen')
                calories = float(params.get('calories', 0))
                protein = float(params.get('protein', 0))
                carbs = float(params.get('carbs', 0))
                fat = float(params.get('fat', 0))
                
                food_data = {
                    'food_name': food_name,
                    'calories': calories,
                    'protein_g': protein,
                    'carbs_g': carbs,
                    'fat_g': fat
                }
                
                response = requests.post(
                    f"{base_url}/nutrition/food/add?user_id={user_id}",
                    headers={'Content-Type': 'application/json'},
                    json=food_data
                )
                
                if response.status_code == 200:
                    return f" {food_name} kaydedildi! {calories} kalori, {protein}g protein, {carbs}g karbonhidrat, {fat}g yağ"
                else:
                    return f" Beslenme kaydı hatası: {response.status_code}"
                    
            elif action == 'status':
                response = requests.get(f"{base_url}/nutrition/today/{user_id}")
                
                if response.status_code == 200:
                    data = response.json()
                    daily = data.get('daily_totals', {})
                    goal_info = data.get('goal_info', {})
                    
                    current_cal = daily.get('total_calories', 0)
                    target_cal = goal_info.get('target_calories', 2000)
                    
                    result = f" Bugünkü beslenme durumun:\n"
                    result += f" Kalori: {current_cal:.0f} / {target_cal:.0f} kcal\n"
                    result += f" Protein: {daily.get('total_protein_g', 0):.1f}g\n"
                    result += f"Karbonhidrat: {daily.get('total_carbs_g', 0):.1f}g\n"
                    result += f"Yağ: {daily.get('total_fat_g', 0):.1f}g\n"
                    
                    if current_cal < target_cal * 0.8:
                        result += " Kalori alımın düşük, biraz daha beslenmeye odaklan."
                    elif current_cal > target_cal * 1.2:
                        result += " Kalori alımın hedefin üzerinde."
                    else:
                        result += " Kalori alımın hedef aralığında!"
                        
                    return result
                else:
                    return " Beslenme durumu kontrolü başarısız"
                    
            elif action == 'goals':
                response = requests.get(f"{base_url}/user/{user_id}")
                
                if response.status_code == 200:
                    user_data = response.json()
                    prefs = user_data.get('preferences', {})
                    
                    if prefs:
                        
                        weight = prefs.get('weight', 70)
                        goal = prefs.get('goal', 'maintenance')
                        
                        result = f" Senin beslenme hedeflerin:\n"
                        result += f"Kilo: {weight}kg\n"
                        result += f"Hedef: {goal}\n"
                        
                        
                        if goal == 'weight_loss':
                            cal_target = weight * 24 
                            result += f"Günlük kalori hedefi: ~{cal_target} kcal (kilo verme)\n"
                        elif goal == 'muscle_gain':
                            cal_target = weight * 30
                            result += f"Günlük kalori hedefi: ~{cal_target} kcal (kas kazanma)\n"
                        else:
                            cal_target = weight * 27
                            result += f" Günlük kalori hedefi: ~{cal_target} kcal (koruma)\n"
                            
                        result += f" Protein hedefi: {weight * 1.6:.0f}g\n"
                        return result
                    else:
                        return " Profil bilgilerin eksik, hedef hesaplanamıyor"
                else:
                    return " Hedef bilgileri alınamadı"
                    
        except Exception as e:
            return f" Beslenme takibi hatası: {str(e)}"
    
    def _extract_user_id(self):
        return getattr(self, '_user_id', None)

class ProfileManagementTool(BaseTool):
    name: str = "profile_management"
    description: str = (
        "View and update user profile information through natural language. "
        "Actions: view (show profile), update (modify information). "
        "Examples: 'action=view' or 'action=update, weight=75, goal=weight_loss'"
    )
    
    def _run(self, query: str) -> str:
        try:
            
            params = {}
            if 'action=' in query:
                for param in query.split(','):
                    if '=' in param:
                        key, value = param.strip().split('=')
                        params[key.strip()] = value.strip()
            else:
                params = {'action': 'view'}
            
            action = params.get('action', 'view')
            base_url = "http://localhost:8000/api/v1"
            user_id = self._extract_user_id() or 2
            
            if action == 'view':
                response = requests.get(f"{base_url}/user/{user_id}")
                
                if response.status_code == 200:
                    data = response.json()
                    user = data.get('user', {})
                    prefs = data.get('preferences', {})
                    
                    result = f" Profil Bilgilerin:\n"
                    result += f"Ad: {user.get('name', 'Belirtilmemiş')}\n"
                    
                    if prefs:
                        result += f" Kilo: {prefs.get('weight', 'Belirtilmemiş')}kg\n"
                        result += f" Boy: {prefs.get('height', 'Belirtilmemiş')}cm\n"
                        result += f" Yaş: {prefs.get('age', 'Belirtilmemiş')}\n"
                        result += f" Cinsiyet: {prefs.get('gender', 'Belirtilmemiş')}\n"
                        result += f" Hedef: {prefs.get('goal', 'Belirtilmemiş')}\n"
                        result += f" Aktivite: {prefs.get('activity_level', 'Belirtilmemiş')}\n"
                        
                        
                        if prefs.get('height') and prefs.get('weight'):
                            height_m = prefs['height'] / 100
                            weight = prefs['weight']
                            bmi = weight / (height_m ** 2)
                            result += f" BMI: {bmi:.1f}\n"
                            
                            if bmi < 18.5:
                                result += " BMI Kategorisi: Zayıf"
                            elif bmi < 25:
                                result += " BMI Kategorisi: Normal"
                            elif bmi < 30:
                                result += " BMI Kategorisi: Fazla Kilolu"
                            else:
                                result += " BMI Kategorisi: Obez"
                    else:
                        result += " Profil bilgilerin henüz tamamlanmamış"
                        
                    return result
                else:
                    return " Profil bilgileri alınamadı"
                    
            elif action == 'update':
                update_data = {}
                
                
                if 'weight' in params:
                    update_data['weight'] = int(params['weight'])
                if 'height' in params:
                    update_data['height'] = int(params['height'])
                if 'age' in params:
                    update_data['age'] = int(params['age'])
                if 'goal' in params:
                    update_data['goal'] = params['goal']
                if 'activity_level' in params:
                    update_data['activity_level'] = params['activity_level']
                if 'gender' in params:
                    update_data['gender'] = params['gender']
                if 'name' in params:
                    update_data['name'] = params['name']
                
                if not update_data:
                    return " Güncellenecek bilgi belirtilmedi"
                
                response = requests.put(
                    f"{base_url}/user/{user_id}/profile",
                    headers={'Content-Type': 'application/json'},
                    json=update_data
                )
                
                if response.status_code == 200:
                    updated_fields = ", ".join(update_data.keys())
                    return f" Profil bilgilerin güncellendi: {updated_fields}"
                else:
                    return f" Profil güncelleme hatası: {response.status_code}"
                    
        except Exception as e:
            return f" Profil yönetimi hatası: {str(e)}"
    
    def _extract_user_id(self):
        return getattr(self, '_user_id', None)

class SmartFoodEntryTool(BaseTool):
    name: str = "smart_food_entry"
    description: str = (
        "Automatically look up food nutrition from USDA database and log it to user's daily intake. "
        "Perfect for natural entries like 'I ate an apple' or 'elma yedim'. "
        "Input: food name in any language (will be translated to English for USDA lookup)"
    )
    
    def _run(self, query: str) -> str:
        try:
            
            food_name = self._extract_food_name(query)
            if not food_name:
                return " Yiyecek adı anlaşılamadı"
            
            
            food_translations = {
                'elma': 'apple',
                'armut': 'pear', 
                'muz': 'banana',
                'portakal': 'orange',
                'çilek': 'strawberry',
                'üzüm': 'grape',
                'domates': 'tomato',
                'salatalık': 'cucumber',
                'havuç': 'carrot',
                'patates': 'potato',
                'soğan': 'onion',
                'sarımsak': 'garlic',
                'ekmek': 'bread',
                'süt': 'milk',
                'yoğurt': 'yogurt',
                'peynir': 'cheese',
                'yumurta': 'egg',
                'tavuk': 'chicken',
                'et': 'meat',
                'balık': 'fish',
                'pirinç': 'rice',
                'makarna': 'pasta',
                'sosis': 'sausage'
            }
            
            english_name = food_translations.get(food_name.lower(), food_name)
            
            
            usda_tool = USDAFoodTool()
            nutrition_info = usda_tool._run(english_name)
            
            if "Error" in nutrition_info:
                return f" {food_name} için beslenme bilgisi bulunamadı: {nutrition_info}"
            
            
            calories = self._extract_calories(nutrition_info)
            protein = self._extract_nutrient(nutrition_info, "Protein")
            carbs = self._extract_nutrient(nutrition_info, "Carbohydrates")
            fat = self._extract_nutrient(nutrition_info, "Fat")
            
            
            food_tool = FoodTrackingTool()
            
            food_tool._user_id = getattr(self, '_user_id', 2)
            
            log_result = food_tool._run(f"action=add, food={food_name}, calories={calories}, protein={protein}, carbs={carbs}, fat={fat}")
            
           
            result = f" {food_name.title()} bilgileri:\n"
            result += f" USDA Veritabanından:\n{nutrition_info}\n\n"
            result += f" Günlük kaydına eklendi:\n{log_result}"
            
            return result
            
        except Exception as e:
            return f" Akıllı yiyecek kaydı hatası: {str(e)}"
    
    def _extract_food_name(self, query: str) -> str:
        """Extract food name from natural language"""
       
        query = query.lower()
        remove_words = ['yedim', 'içtim', 'aldım', 'tükettim', 'ate', 'consumed', 'had', 'drank']
        
        for word in remove_words:
            query = query.replace(word, '').strip()
        
        
        words = query.split()
        if words:
            return words[0] 
        return ""
    
    def _extract_calories(self, nutrition_text: str) -> float:
        """Extract calories from USDA nutrition text"""
        lines = nutrition_text.split('\n')
        for line in lines:
            if 'kcal' in line.lower() or 'energy' in line.lower():
                
                parts = line.split()
                for part in parts:
                    if part.replace('.', '').replace(',', '').isdigit():
                        return float(part.replace(',', ''))
        return 0.0
    
    def _extract_nutrient(self, nutrition_text: str, nutrient_name: str) -> float:
        """Extract specific nutrient value from USDA text"""
        lines = nutrition_text.split('\n')
        for line in lines:
            if nutrient_name.lower() in line.lower():
                parts = line.split()
                for part in parts:
                    if part.replace('.', '').replace(',', '').isdigit():
                        return float(part.replace(',', ''))
        return 0.0
    
    def _extract_user_id(self):
        return getattr(self, '_user_id', None)

class DietAgent:
    def __init__(self, data_dir: str):
       
        self.bmi_calculator = BMICalculator()
        self.diet_rag = DietRAGTool(data_dir)
        self.calorie_calculator = CalorieCalculator()
        self.macro_calculator = MacroCalculator()
        self.water_calculator = WaterIntakeCalculator()
        self.meal_planner = EdamamMealPlannerTool()
        self.web_search = WebSearchTool()
        self.usda_food = USDAFoodTool()
        self.water_tracking = WaterTrackingTool()
        self.food_tracking = FoodTrackingTool()
        self.profile_management = ProfileManagementTool()
        self.smart_food_entry = SmartFoodEntryTool()
        
      
        self.llm = ChatOpenAI(
            model="gpt-4o-mini",
            temperature=0.1,
            api_key=OPENAI_API_KEY
        )
        
       
        self.tools = [
            Tool(
                name="BMI_Calculator",
                func=self.bmi_calculator._run,
                description="PRIMARY for BMI calculations: Calculate BMI and health category from weight and height. Input format: weight_kg=70, height_m=1.75"
            ),
            Tool(
                name="Diet_Information",
                func=self.diet_rag._run,
                description="GENERAL KNOWLEDGE: Search local database for cooking techniques, recipes, workout routines, diet advice, and general nutrition knowledge. Use for non-calculation questions."
            ),
            Tool(
                name="Calorie_Calculator",
                func=self.calorie_calculator._run,
                description="PRIMARY for daily calorie needs: Calculate maintenance/weight loss/gain calories based on personal status. Input format: age=30, gender=male, weight_kg=70, height_cm=175, activity_level=moderate"
            ),
            Tool(
                name="Macro_Calculator",
                func=self.macro_calculator._run,
                description="PRIMARY for macronutrient calculations: Calculate daily protein/fat/carb needs based on weight and goals. Input format: weight_kg=70, goal=weight_loss"
            ),
            Tool(
                name="Water_Calculator",
                func=self.water_calculator._run,
                description="PRIMARY for water intake: Calculate daily water needs based on body weight. Input format: weight_kg=70"
            ),
            Tool(
                name="Meal_Planner",
                func=self.meal_planner._run,
                description="PRIMARY for meal planning: Generate weekly meal plans with recipes. Input format: diet=vegetarian, calories=2000, days=7"
            ),
            Tool(
                name="Web_Search",
                func=self.web_search._run,
                description="LAST RESORT: Search Wikipedia only when no other tool provides the needed information."
            ),
            Tool(
                name="USDA_Food",
                func=self.usda_food._run,
                description="PRIMARY for food nutrition: Get precise calorie and nutrient data for specific foods from USDA database. IMPORTANT: Always use ENGLISH food names (sosis→sausage, süt→milk, elma→apple, tavuk→chicken, ekmek→bread, etc.). Input: food name in English"
            ),
            Tool(
                name="Water_Tracking",
                func=self.water_tracking._run,
                description="Track water intake and manage daily goals through natural language. Actions: add (log water), status (check today's progress), goal (set daily target). Examples: 'action=add, amount_ml=250' or 'action=status' or 'action=goal, target_ml=2500'"
            ),
            Tool(
                name="Food_Tracking",
                func=self.food_tracking._run,
                description="Track food intake and nutrition through natural language. Actions: add (log food), status (check today's nutrition), goals (see targets). Examples: 'action=add, food=apple, calories=95' or 'action=status' or 'action=goals'"
            ),
            Tool(
                name="Profile_Management",
                func=self.profile_management._run,
                description="View and update user profile information through natural language. Actions: view (show profile), update (modify information). Examples: 'action=view' or 'action=update, weight=75, goal=weight_loss'"
            ),
            Tool(
                name="Smart_Food_Entry",
                func=self.smart_food_entry._run,
                description="Automatically look up food nutrition from USDA database and log it to user's daily intake. Perfect for natural entries like 'I ate an apple' or 'elma yedim'. Input: food name in any language (will be translated to English for USDA lookup)"
            )
        ]
        
       
        template = """Sen kapsamlı bir fitness ve beslenme asistanısın. Aşağıdaki araçlara erişimin var:

{tools}

AKILLI ARAÇ ÖNCELİK KURALLARI - BUNLARI SIKI ŞEKİLDE TAKİP ET:

1. ENTEGRASYONLİ FONKSİYONLAR (Doğal dil ile sistem işlemleri):
   - Su takibi: "2 bardak su içtim", "su durumum nasıl?" → Water_Tracking aracını kullan
   - Yiyecek kaydetme: "elma yedim", "çilek tükettim" → Smart_Food_Entry aracını kullan
   - Beslenme takibi: "bugün ne kadar kalori aldım?", "protein durumum?" → Food_Tracking aracını kullan
   - Profil yönetimi: "profilimi göster", "kilom 75kg oldu" → Profile_Management aracını kullan

2. ÖZEL HESAPLAMALAR (Uzman araçları):
   - Yiyecek kalori/beslenme soruları → USDA_Food aracını İLK kullan (ÖNEMLİ: Türkçe yiyecek isimleri için İngilizce kullan)
   - BMI hesaplamaları → BMI_Calculator aracını İLK kullan  
   - Su ihtiyacı hesaplamaları → Water_Calculator aracını İLK kullan
   - Öğün planlama soruları → Meal_Planner aracını İLK kullan
   - Makro/kalori ihtiyacı hesaplamaları → Macro_Calculator veya Calorie_Calculator'ı İLK kullan

3. GENEL BİLGİ (Diğer her şey için RAG kullan):
   - Yemek pişirme teknikleri, tarifler, egzersiz rutinleri, diyet tavsiyeleri → Diet_Information'ı İLK kullan
   - Genel beslenme bilgisi, yemek hazırlama ipuçları → Diet_Information'ı İLK kullan

4. SON ÇARE:
   - Sadece diğer araçlar gerekli bilgiyi sağlamazsa Web_Search kullan

KİŞİSELLEŞTİRME KURALLARI:
- Kullanıcının profil bilgileri [USER_CONTEXT: ...] formatında verilecek
- Bu bilgileri kullanarak tavsiyeleri KİŞİSELLEŞTİR
- Yaş, cinsiyet, kilo, boy, hedefler ve aktivite seviyesine göre özel tavsiyeler ver
- Kalori hedefleri varsa bunları göz önünde bulundur
- Kullanıcının hedefine göre motivasyon sağla (kilo verme, kas kazanma, sürdürme)

DOĞAL DİL İŞLEME ÖRNEKLERİ:
- "2 bardak su içtim" → Water_Tracking: action=add, amount_ml=400
- "elma yedim" → Smart_Food_Entry: elma
- "bugün ne kadar kalori aldım?" → Food_Tracking: action=status
- "profilimi göster" → Profile_Management: action=view
- "kilom 75kg oldu" → Profile_Management: action=update, weight=75
- "su durumum nasıl?" → Water_Tracking: action=status

ÖNEMLİ SU ÖLÇÜ BİLGİSİ:
- 1 bardak = 200ml (bu sistemde sabit)
- 2 bardak = 400ml, 3 bardak = 600ml, vs.
- Su hesaplamalarında bu standardı kullan

ÖNEMLİ KURALLAR:
- SADECE araçlardan gelen veriyi kullan, kendi genel bilgini EKLEME
- Tüm yanıtları TÜRKÇE ver
- Eğer kullanıcı Türkçe soruyorsa, soruyu önce İngilizceye çevirip araçlara İngilizce olarak gönder
- Araçlardan gelen İngilizce cevabı mutlaka Türkçeye çevir
- Gerekli bilgiyi topladıktan sonra HEMEN Final Answer ver, fazla Action yapma
- Kullanıcının profil bilgilerine göre tavsiyeleri özelleştir

ENTEGRE SİSTEM KULLANIMI:
- Kullanıcı doğal dille yiyecek, su veya profil değişikliği belirtirse, önce entegrasyon tool'larını kullan
- Sonra ihtiyaç halinde hesaplama veya bilgi tool'larını ekle
- Örnekler:
  * "elma yedim" → Smart_Food_Entry kullan, sonra kalori bilgisi ver
  * "2 bardak su içtim" → Water_Tracking kullan, günlük hedef durumu belirt
  * "kilom 70kg oldu, önerilerin neler?" → Profile_Management ile güncelle, sonra kişiselleştirilmiş tavsiye ver

KARAR SÜRECI:
1. Kullanıcı profilini analiz et (USER_CONTEXT'ten)
2. Soru tipini analiz et: Entegrasyon mı? Hesaplama mı? Genel bilgi mi?
3. Uygun araç(lar)ı kullan
4. Cevabı kullanıcının profiline göre özelleştir
5. Cevap için yeterli bilgi toplandıysa HEMEN Final Answer ver
6. Eksik bilgi varsa sadece o zaman ek araç kullan

ÖRNEKLİK KİŞİSELLEŞTİRME:
- Kilo vermek isteyen 30 yaşında kadın → "Günlük kalori açığı için..." 
- Kas kazanmak isteyen 25 yaşında erkek → "Protein alımını artırman önemli..."
- 40 yaşında maintenance → "Mevcut sağlıklı alışkanlıklarını sürdür..."

Şu formatı kullan:

Question: yanıtlaman gereken giriş sorusu
Thought: ne yapacağını düşünmelisin
Action: yapılacak eylem, [{tool_names}] içinden biri olmalı
Action Input: eylem için girdi
Observation: eylemin sonucu
... (gerekirse tekrarla, ama cevap için yeterli bilgin varsa HEMEN Final Answer ver)
Thought: artık son yanıtı biliyorum
Final Answer: orijinal soruya Türkçe final yanıt

Başla!

Question: {input}
Thought:{agent_scratchpad}"""

        prompt = PromptTemplate.from_template(template)
        
        
        self.agent = create_react_agent(self.llm, self.tools, prompt)
        self.agent_executor = AgentExecutor(
            agent=self.agent,
            tools=self.tools,
            verbose=True,
            handle_parsing_errors=True,
            max_iterations=30,
            max_execution_time=300
        )
    
    def run(self, query: str) -> str:
        """Run the agent with a query"""
        return self.agent_executor.invoke({"input": query})["output"]



if __name__ == "__main__":
    
    agent = DietAgent("diyet_dataları")
    
    
    queries = [
    "What is the calorie of bread?"
    ]

    for query in queries:
        print(f"\nQuery: {query}")
        response = agent.run(query)
        print(f"Response: {response}")
