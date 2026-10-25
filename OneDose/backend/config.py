# File: backend/config.py
# Owner: Bhavya  (only the owner edits this file)
# Purpose: Load all settings from .env in one place.
# Inputs: .env file (searched from backend/ upwards, so the repo-level .env is found) or real environment variables.
# Outputs: A settings object: database connection, JWT secret, scanner device key, card salt, Gemini key and model, allowed frontend origin.
# Depends on: none
#
# Required: DB_NAME, DB_USER, JWT_SECRET, DEVICE_KEY. Everything else has a default.
# GEMINI_API_KEY is optional: without it every alert explanation uses the fixed template.
# CARD_SALT must equal the salt in the ESP32 firmware (and the seed data) so card hashes match.
import os
from dataclasses import dataclass

from dotenv import load_dotenv

load_dotenv()


def _need(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"{name} is not set. Copy .env.example to .env and fill it in.")
    return value


@dataclass(frozen=True)
class Settings:
    db_host: str
    db_port: int
    db_name: str
    db_user: str
    db_password: str
    jwt_secret: str
    device_key: str
    card_salt: str
    gemini_api_key: str
    gemini_model: str
    allowed_origin: str
    jwt_hours: int = 8


def load_settings() -> Settings:
    return Settings(
        db_host=os.getenv("DB_HOST", "localhost").strip() or "localhost",
        db_port=int(os.getenv("DB_PORT", "").strip() or 5432),
        db_name=_need("DB_NAME"),
        db_user=_need("DB_USER"),
        db_password=os.getenv("DB_PASSWORD", ""),
        jwt_secret=_need("JWT_SECRET"),
        device_key=_need("DEVICE_KEY"),
        card_salt=os.getenv("CARD_SALT", "OneDoseDemoCardSalt2026"),
        gemini_api_key=os.getenv("GEMINI_API_KEY", "").strip(),
        gemini_model=os.getenv("GEMINI_MODEL", "gemini-2.5-flash").strip(),
        allowed_origin=os.getenv("ALLOWED_ORIGIN", "http://localhost:5173").strip(),
    )


settings = load_settings()
