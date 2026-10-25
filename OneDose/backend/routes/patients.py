# File: backend/routes/patients.py
# Owner: Bhavya  (only the owner edits this file)
# Purpose: Patient and card-scan endpoints: POST /scan, GET /scan/latest, GET /patients/{id}, GET /patients/{id}/medications (also /meds), with ?as_of=YYYY-MM-DD for time travel.
# Inputs: Scan payload from the hardware (or the mock-tap button), patient id, date.
# Outputs: Patient summary and medicine lists in the shape the dashboard expects.
# Depends on: db.py, auth.py, schemas.py
#
# POST /scan has two callers. The card reader sends X-Device-Key and the 64-hex hash; it gets {outcome, matched} only,
# never a patient. The dashboard's mock tap sends its JWT and a card id (hashed here with CARD_SALT); it gets the patient.
import hashlib
import re
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
from psycopg import errors as pg_errors

import auth
import db
from config import settings
from schemas import CODE_FOR_PER_DAY, PatientOut, ScanIn

router = APIRouter(tags=["patients"])
HEX64 = re.compile(r"[0-9a-fA-F]{64}")
SCAN_ERRORS = {"unknown_card": (404, "Card not recognised"), "inactive_card": (403, "This card is inactive"),
               "no_consent": (403, "No active consent for this patient")}
_logged_scans: set[int] = set()  # /scan/latest is polled; write one READ audit row per scan, not one per poll


def _meds(t: db.Tx, patient_id: int, as_of: date) -> list[dict]:
    """Active medicines, one entry per prescription item with its ingredients, dose in mg and frequency code."""
    items: dict[int, dict] = {}
    for r in t.query("SELECT * FROM fn_meds_as_of(%s, %s)", (patient_id, as_of)):
        item = items.setdefault(r["prescription_item_id"], {
            "prescription_item_id": r["prescription_item_id"], "brand_id": r["brand_id"],
            "brand_name": r["brand_name"], "start_date": r["start_date"], "end_date": r["end_date"],
            "ingredients": []})
        item["ingredients"].append({"name": r["ingredient_name"], "strength_mg": float(r["strength_mg"])})
    if not items:
        return []
    rows = t.query("SELECT item_id, dose_units, doses_per_day FROM prescription_items WHERE item_id = ANY(%s)",
                   (list(items),), show=False)
    for r in rows:
        item = items[r["item_id"]]
        dose = round(float(r["dose_units"]) * item["ingredients"][0]["strength_mg"], 2)
        per_day = float(r["doses_per_day"])
        freq = CODE_FOR_PER_DAY.get(per_day) or f"{per_day:g}x/day"
        item.update(dose=dose, frequency=freq, dose_frequency=f"{dose:g} mg - {freq}")
    return list(items.values())


def patient_payload(t: db.Tx, patient_id: int, role: str, log_read: bool = True) -> dict:
    t.require_consent(patient_id)
    if role == "pharmacist":  # masked: initials only, no date of birth or sex
        s = t.one("SELECT * FROM v_pharmacist_patients WHERE patient_id = %s", (patient_id,))
        name, sex, has_consent = (s or {}).get("masked_name"), None, True
    else:
        s = t.one("SELECT * FROM v_patient_summary WHERE patient_id = %s", (patient_id,))
        name, has_consent = (s or {}).get("display_name"), (s or {}).get("has_active_consent")
        sex = (t.one("SELECT sex FROM patients WHERE patient_id = %s", (patient_id,), show=False) or {}).get("sex")
    if s is None:
        raise HTTPException(404, "Patient not found")
    if log_read:
        t.log_read("patients", patient_id)
    until = s["consent_expires_at"]
    return PatientOut(
        patient_id=patient_id, id=patient_id, full_name=name, age_years=s["age_years"], sex=sex,
        initials="".join(w[0] for w in re.split(r"\s+", name.strip()) if w[:1].isalpha())[:2].upper(),
        has_active_consent=has_consent,
        consent_status=f"Consent active until {until:%d %b %Y}" if has_consent else "No active consent",
        allergies=[{"name": a["ingredient_name"] or f"{a['class_name']} class", "severity": a.get("severity"),
                    "reaction": a.get("reaction")} for a in s["allergies"]],
        conditions=[{"name": c["condition_name"], "icd10": c.get("icd10_code")} for c in s["conditions"]],
        active_medications=_meds(t, patient_id, date.today()),
    ).model_dump()


@router.post("/scan")
async def scan(body: ScanIn, who=Depends(auth.device_or_user)):
    kind, user = who
    uid = body.uid_hash.strip()
    if not HEX64.fullmatch(uid):
        if kind == "device":
            raise HTTPException(422, "uid_hash must be a 64-character SHA-256 hex string")
        uid = hashlib.sha256(f"{uid}::{settings.card_salt}".encode()).hexdigest()  # mock tap: plain card id

    def work():
        with db.tx("scanner") as t:
            try:
                result = t.one("SELECT * FROM fn_record_scan(decode(%s, 'hex'), %s)", (uid, body.device), show=False)
            except pg_errors.InvalidParameterValue as exc:
                raise HTTPException(400, "Unknown device name") from exc
        patient = None
        if kind == "user" and result["outcome"] == "matched":
            with db.tx(user.role, user.username) as t:
                patient = patient_payload(t, result["patient_id"], user.role)
        return result, patient

    result, patient = await db.run(work)
    if kind == "device":
        return {"outcome": result["outcome"], "matched": result["outcome"] == "matched"}
    if result["outcome"] != "matched":
        code, message = SCAN_ERRORS[result["outcome"]]
        raise HTTPException(code, message)
    return {"outcome": "matched", "matched": True, "patient": patient}


@router.get("/scan/latest")
async def latest_scan(user: auth.User = Depends(auth.require("clinician"))):
    """The newest successful card tap in the last 2 minutes, with the patient (the dashboard polls this)."""
    def work():
        with db.tx(user.role, user.username) as t:
            scan_row = t.one("SELECT scan_id, scanned_at, patient_id FROM v_latest_scan", show=False)
            if scan_row is None:
                return None
            first_time = scan_row["scan_id"] not in _logged_scans
            payload = patient_payload(t, scan_row["patient_id"], user.role, log_read=first_time)
            _logged_scans.add(scan_row["scan_id"])
            return {**scan_row, "patient": payload}

    return await db.run(work) or {"scan_id": None, "scanned_at": None, "patient": None}


@router.get("/patients/{patient_id}")
async def get_patient(patient_id: int, user: auth.User = Depends(auth.require("clinician", "pharmacist"))):
    def work():
        with db.tx(user.role, user.username) as t:
            return patient_payload(t, patient_id, user.role)
    return await db.run(work)


@router.get("/patients/{patient_id}/medications")
@router.get("/patients/{patient_id}/meds", include_in_schema=False)
async def medications(patient_id: int, as_of: date | None = Query(default=None),
                      user: auth.User = Depends(auth.require("clinician", "pharmacist"))):
    def work():
        with db.tx(user.role, user.username) as t:
            t.require_consent(patient_id)
            meds = _meds(t, patient_id, as_of or date.today())
            t.log_read("prescription_items", patient_id)
            return meds
    return await db.run(work)
