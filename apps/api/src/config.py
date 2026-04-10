from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv
from pydantic_settings import BaseSettings, SettingsConfigDict

# Load all vars from .env into os.environ (e.g. AWS_ACCESS_KEY_ID for boto3)
load_dotenv(Path(__file__).resolve().parent.parent / ".env")


class Settings(BaseSettings):
    alpaca_api_key: str
    alpaca_secret_key: str
    alpaca_paper_mode: bool = True
    aws_region: str = "us-east-1"
    table_name: str = "trading-copilot-prod"
    anthropic_api_key: str = ""

    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parent.parent / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()