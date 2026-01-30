from pydantic_settings import BaseSettings
from functools import lru_cache

class Settings(BaseSettings):
    # Database settings
    DATABASE_URL: str = "postgresql://postgres:postgres@localhost:5432/diet_app"
    
    # API settings
    API_V1_STR: str = "/api/v1"
    PROJECT_NAME: str = "Diet Assistant API"
    
    # CORS settings
    BACKEND_CORS_ORIGINS: list = ["*"]
    
    # Security settings
    SECRET_KEY: str = "your-secret-key-here"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 8  # 8 days
    
    class Config:
        case_sensitive = True
        env_file = ".env"

@lru_cache()
def get_settings():
    return Settings()

settings = get_settings()
