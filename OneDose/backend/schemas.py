# File: backend/schemas.py
# Owner: Bhavya  (only the owner edits this file)
# Purpose: Define the shape of every request and response (LoginIn, TokenOut, ScanIn, CheckIn, PrescribeIn, OverrideIn, AlertOut, AlternativeOut, PatientOut) and the frequency codes the dashboard uses.
# Inputs: JSON bodies.
# Outputs: Validated objects.
# Depends on: none
#
# The shapes follow frontend/src/api.js: login by email, dose in mg plus a frequency code, alerts with a string id.
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field, field_validator

# Dashboard frequency code -> doses per day. SOS (as needed) is counted as 1 per day.
FREQUENCY_PER_DAY = {"OD": 1, "BD": 2, "TDS": 3, "QID": 4, "SOS": 1}
CODE_FOR_PER_DAY = {1: "OD", 2: "BD", 3: "TDS", 4: "QID"}
Frequency = Literal["OD", "BD", "TDS", "QID", "SOS"]


class LoginIn(BaseModel):
    email: str = Field(min_length=1, max_length=120)  # an email or a db username
    password: str = Field(min_length=1, max_length=200)


class UserOut(BaseModel):
    name: str
    role: str
    email: str
    clinician_id: int


class TokenOut(BaseModel):
    token: str
    token_type: str = "bearer"
    user: UserOut


class ScanIn(BaseModel):
    # The reader sends the 64-hex SHA-256 of the card UID. The dashboard's mock tap may send the plain card id.
    uid_hash: str = Field(min_length=4, max_length=64)
    device: str | None = Field(default=None, max_length=60)


class CheckIn(BaseModel):
    patient_id: int = Field(gt=0)
    brand_id: int = Field(gt=0)
    dose: Decimal = Field(gt=0, le=5000)  # mg per intake, of the brand's first ingredient
    frequency: Frequency


class ClientAlert(BaseModel):
    """What the dashboard sends back at save time. Only the override reason is used; alerts are recomputed by the database."""
    id: str = Field(max_length=80)
    override_reason: str | None = Field(default=None, max_length=300)


class PrescribeIn(CheckIn):
    alerts: list[ClientAlert] = Field(default_factory=list, max_length=50)
    notes: str | None = Field(default=None, max_length=500)


class OverrideIn(BaseModel):
    reason: str = Field(min_length=10, max_length=300)

    @field_validator("reason")
    @classmethod
    def not_blank(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 10:
            raise ValueError("Reason must be at least 10 characters")
        return v


class AlertOut(BaseModel):
    id: str
    severity: str
    check_type: str
    display_type: str
    ingredients: list[str]
    explanation: str
    source: str | None = None
    management: str | None = None
    detail: str | None = None
    status: str = "open"
    requires_reason: bool


class AlternativeOut(BaseModel):
    brand_id: int
    brand_name: str
    manufacturer: str | None = None
    strength: str | None = None
    indication: str | None = None
    line_of_therapy: str
    ingredients: list[str]
    status_text: str


class PatientOut(BaseModel):
    patient_id: int
    id: int
    full_name: str
    initials: str
    age_years: int
    sex: str | None = None
    has_active_consent: bool
    consent_status: str
    allergies: list[dict]
    conditions: list[dict]
    active_medications: list[dict]
