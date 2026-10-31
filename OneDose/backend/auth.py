# File: backend/auth.py
# Owner: Bhavya  (only the owner edits this file)
# Purpose: Login, JWT creation and checking, role guard (clinician, pharmacist, admin, patient), scanner device-key check. Endpoint: POST /auth/login (staff first, then patients).
# Inputs: Email (or username) and password, JWT token, device key header (X-Device-Key).
# Outputs: A JWT, the current user, or an access-denied error.
# Depends on: db.py, config.py
#
# The password is checked inside the database (fn_login), so the API never reads password hashes.
# Five wrong passwords for the same email from the same address lock that pair out for five minutes.
import hmac
import time
from dataclasses import dataclass

import jwt
from psycopg import errors as pg_errors
from fastapi import APIRouter, Depends, Header, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

import db
from config import settings
from schemas import LoginIn, TokenOut

router = APIRouter(prefix="/auth", tags=["auth"])
bearer = HTTPBearer(auto_error=False)

MAX_FAILS, WINDOW_SECONDS = 5, 300
_fails: dict[str, list[float]] = {}


@dataclass(frozen=True)
class User:
    username: str  # clinicians.db_username or patients.db_username, also written to the audit log
    clinician_id: int  # 0 for a patient
    role: str  # clinician | pharmacist | admin | patient
    name: str
    patient_id: int | None = None  # set for a patient


def _recent_fails(key: str) -> list[float]:
    now = time.time()
    _fails[key] = [t for t in _fails.get(key, []) if now - t < WINDOW_SECONDS]
    return _fails[key]


@router.post("/login", response_model=TokenOut)
async def login(body: LoginIn, request: Request):
    email = body.email.strip().lower()
    key = f"{email}|{request.client.host if request.client else '-'}"
    if len(_recent_fails(key)) >= MAX_FAILS:
        raise HTTPException(429, "Too many failed attempts. Try again in a few minutes")

    def work():
        with db.tx() as t:  # runs as the API login: only the two login functions are allowed here
            staff = t.one("SELECT * FROM fn_login(%s, %s)", (email, body.password), show=False)
            if staff is not None:
                return staff, None
            try:
                return None, t.one("SELECT * FROM fn_patient_login(%s, %s)", (email, body.password), show=False)
            except pg_errors.UndefinedFunction:  # 09_patient_portal.sql not loaded yet: staff login still works
                return None, None

    staff, patient = await db.run(work)
    if staff is None and patient is None:
        _fails[key].append(time.time())
        raise HTTPException(401, "Invalid email or password")
    _fails.pop(key, None)

    now = int(time.time())
    if staff is not None:
        claims = {"sub": staff["db_username"], "cid": staff["clinician_id"], "role": staff["role"],
                  "name": staff["full_name"]}
        user = {"name": staff["full_name"], "role": staff["role"], "email": email, "clinician_id": staff["clinician_id"]}
    else:
        claims = {"sub": patient["db_username"], "cid": 0, "pid": patient["patient_id"], "role": "patient",
                  "name": patient["full_name"]}
        user = {"name": patient["full_name"], "role": "patient", "email": email, "patient_id": patient["patient_id"]}
    token = jwt.encode({**claims, "iat": now, "exp": now + settings.jwt_hours * 3600},
                       settings.jwt_secret, algorithm="HS256")
    return {"token": token, "user": user}


def current_user(creds: HTTPAuthorizationCredentials | None = Depends(bearer)) -> User:
    if creds is None:
        raise HTTPException(401, "Not signed in")
    try:
        p = jwt.decode(creds.credentials, settings.jwt_secret, algorithms=["HS256"])
        return User(username=p["sub"], clinician_id=p.get("cid", 0), role=p["role"], name=p["name"],
                    patient_id=p.get("pid"))
    except (jwt.PyJWTError, KeyError):
        raise HTTPException(401, "Session expired. Please sign in again")


def require(*roles: str):
    """Dependency: the signed-in user must have one of these roles."""
    def guard(user: User = Depends(current_user)) -> User:
        if user.role not in roles:
            raise HTTPException(403, "Your role cannot do that")
        return user
    return guard


def device_or_user(x_device_key: str | None = Header(default=None),
                   creds: HTTPAuthorizationCredentials | None = Depends(bearer)):
    """For POST /scan: the card reader (device key) or a signed-in clinician/pharmacist (mock tap button)."""
    if x_device_key is not None:
        if not hmac.compare_digest(x_device_key.encode(), settings.device_key.encode()):
            raise HTTPException(401, "Invalid device key")
        return "device", None
    user = current_user(creds)
    if user.role not in ("clinician", "pharmacist"):
        raise HTTPException(403, "Your role cannot do that")
    return "user", user
