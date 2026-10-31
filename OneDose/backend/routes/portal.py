# File: backend/routes/portal.py
# Owner: Bhavya
# Purpose: Patient portal endpoints (/portal/...) and the doctor's "Before coming in" endpoint (GET /patients/{id}/self-reported).
# Inputs: A patient JWT (role 'patient'); for the doctor endpoint a clinician JWT.
# Outputs: The patient's own home, medicines, schedule, ingredient notes, allergies and conditions, consent, access log,
#          symptom search results and self-reported medicines.
# Depends on: db.py, auth.py, schemas.py, routes/patients.py (_meds), dbms/09_patient_portal.sql
#
# Every request runs as the database role onedose_patient, so row-level security limits it to the patient's own rows.
# Self-reported medicines are NEVER mixed with prescriptions: they are labelled unverified and only a brand picked from the
# list gets an allergy match (computed by the database, chk_allergy). Typed names say "We couldn't check this one".
# The schedule (morning / afternoon / night) is only a display of "doses per day"; it makes no safety decision.
from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query

import auth
import db
from routes.patients import _meds
from schemas import ConsentGrantIn, FREQUENCY_PER_DAY, SelfReportedIn

router = APIRouter(prefix="/portal", tags=["patient portal"])
staff_router = APIRouter(tags=["patient portal (staff view)"])
patient_only = auth.require("patient")

SLOTS = ("morning", "afternoon", "night")
SLOT_PLAN = {1: ["morning"], 2: ["morning", "night"], 3: list(SLOTS), 4: list(SLOTS)}


def _me(t: db.Tx) -> dict:
    p = t.one("SELECT patient_id, full_name, fn_age_years(date_of_birth) AS age_years, sex "
              "FROM patients WHERE patient_id = fn_current_patient_id()", show=False)
    if p is None:
        raise HTTPException(403, "No patient record is linked to this login")
    return p


def _consent(t: db.Tx, pid: int) -> dict:
    c = t.one("SELECT granted_at, expires_at, revoked_at FROM consents WHERE patient_id = %s "
              "ORDER BY granted_at DESC, consent_id DESC LIMIT 1", (pid,), show=False)
    now = datetime.now(timezone.utc)
    if c is None:
        return {"active": False, "status": "No consent recorded", "expires_at": None}
    if c["revoked_at"] is not None:
        return {"active": False, "status": f"You withdrew access on {c['revoked_at']:%d %b %Y}", "expires_at": c["expires_at"]}
    if c["expires_at"] <= now:
        return {"active": False, "status": f"Your consent expired on {c['expires_at']:%d %b %Y}", "expires_at": c["expires_at"]}
    return {"active": True, "status": f"Your care team can see your record until {c['expires_at']:%d %b %Y}",
            "expires_at": c["expires_at"]}


def _allergies(t: db.Tx, pid: int) -> list[dict]:
    return t.query(
        "SELECT coalesce(i.name, dc.name || ' class') AS name, pa.reaction, pa.severity::text AS severity "
        "FROM patient_allergies pa LEFT JOIN ingredients i ON i.ingredient_id = pa.ingredient_id "
        "LEFT JOIN drug_classes dc ON dc.class_id = pa.class_id "
        "WHERE pa.patient_id = %s AND pa.valid_from <= current_date AND (pa.valid_to IS NULL OR pa.valid_to > current_date) "
        "ORDER BY pa.allergy_id", (pid,), show=False)


def _conditions(t: db.Tx, pid: int) -> list[dict]:
    return t.query(
        "SELECT c.name, c.icd10_code AS icd10, pc.valid_from FROM patient_conditions pc "
        "JOIN conditions c ON c.condition_id = pc.condition_id "
        "WHERE pc.patient_id = %s AND pc.valid_from <= current_date AND (pc.valid_to IS NULL OR pc.valid_to > current_date) "
        "ORDER BY c.name", (pid,), show=False)


@router.get("/home")
async def home(user: auth.User = Depends(patient_only)):
    def work():
        with db.tx("patient", user.username) as t:
            me = _me(t)
            return {"name": me["full_name"], "age_years": me["age_years"], "consent": _consent(t, me["patient_id"]),
                    "allergies": _allergies(t, me["patient_id"]), "medications": _meds(t, me["patient_id"], date.today())}
    return await db.run(work)


@router.get("/medications")
async def medications(as_of: date | None = Query(default=None), user: auth.User = Depends(patient_only)):
    day = as_of or date.today()
    if day > date.today():
        raise HTTPException(422, "Pick today or an earlier day")

    def work():
        with db.tx("patient", user.username) as t:
            return {"as_of": day, "medications": _meds(t, _me(t)["patient_id"], day)}
    return await db.run(work)


@router.get("/schedule")
async def schedule(user: auth.User = Depends(patient_only)):
    def work():
        with db.tx("patient", user.username) as t:
            pid = _me(t)["patient_id"]
            rows = t.query(
                "SELECT pi.item_id, b.brand_name, b.form, pi.dose_units, pi.doses_per_day FROM prescription_items pi "
                "JOIN brands b ON b.brand_id = pi.brand_id WHERE pi.patient_id = %s AND pi.start_date <= current_date "
                "AND (pi.end_date IS NULL OR pi.end_date >= current_date) ORDER BY b.brand_name", (pid,), show=False)
            slots = {s: [] for s in SLOTS}
            for r in rows:
                per_day = float(r["doses_per_day"])
                n = max(1, min(4, round(per_day)))
                units = float(r["dose_units"])
                entry = {"item_id": r["item_id"], "brand_name": r["brand_name"],
                         "dose": f"{units:g} x {r['form'] or 'dose'}", "times_per_day": per_day,
                         "note": "4 doses a day: ask your doctor or pharmacist for the exact times." if n == 4 else None}
                for s in SLOT_PLAN[n]:
                    slots[s].append(entry)
            return {"slots": [{"slot": s, "items": slots[s]} for s in SLOTS],
                    "disclaimer": "Suggested times only. Follow your doctor's or pharmacist's instructions."}
    return await db.run(work)


@router.get("/ingredients")
async def ingredients(user: auth.User = Depends(patient_only)):
    """One plain sentence per active ingredient, built from the indication data (ingredient_indications)."""
    def work():
        with db.tx("patient", user.username) as t:
            pid = _me(t)["patient_id"]
            meds = t.query("SELECT DISTINCT ingredient_id, ingredient_name, brand_name FROM fn_meds_as_of(%s, current_date) "
                           "ORDER BY ingredient_name, brand_name", (pid,), show=False)
            ids = sorted({m["ingredient_id"] for m in meds})
            uses: dict[int, list[str]] = {i: [] for i in ids}
            if ids:
                for r in t.query("SELECT ii.ingredient_id, ind.name FROM ingredient_indications ii "
                                 "JOIN indications ind ON ind.indication_id = ii.indication_id "
                                 "WHERE ii.ingredient_id = ANY(%s) ORDER BY ii.line_of_therapy, ind.name", (ids,), show=False):
                    uses[r["ingredient_id"]].append(r["name"])
            out: dict[int, dict] = {}
            for m in meds:
                e = out.setdefault(m["ingredient_id"], {"ingredient": m["ingredient_name"], "brands": [], "sentence": None})
                e["brands"].append(m["brand_name"])
                u = uses[m["ingredient_id"]]
                name = m["ingredient_name"].capitalize()
                e["sentence"] = (f"{name} is used for {', '.join(u[:-1])} and {u[-1]}." if len(u) > 1 else
                                 f"{name} is used for {u[0]}." if u else
                                 "We do not have a plain-language note for this ingredient yet.")
            return list(out.values())
    return await db.run(work)


@router.get("/health")
async def health_record(user: auth.User = Depends(patient_only)):
    def work():
        with db.tx("patient", user.username) as t:
            pid = _me(t)["patient_id"]
            return {"allergies": _allergies(t, pid), "conditions": _conditions(t, pid)}
    return await db.run(work)


@router.get("/consent")
async def consent_status(user: auth.User = Depends(patient_only)):
    def work():
        with db.tx("patient", user.username) as t:
            return _consent(t, _me(t)["patient_id"])
    return await db.run(work)


@router.post("/consent/revoke")
async def revoke_consent(user: auth.User = Depends(patient_only)):
    def work():
        with db.tx("patient", user.username) as t:
            t.one("SELECT fn_portal_revoke_consent() AS n", show=False)
            return _consent(t, _me(t)["patient_id"])
    return await db.run(work)


@router.post("/consent/grant")
async def grant_consent(body: ConsentGrantIn, user: auth.User = Depends(patient_only)):
    def work():
        with db.tx("patient", user.username) as t:
            t.one("SELECT fn_portal_grant_consent(%s) AS expires_at", (body.days,), show=False)
            return _consent(t, _me(t)["patient_id"])
    return await db.run(work)


@router.get("/access-log")
async def access_log(user: auth.User = Depends(patient_only)):
    def work():
        with db.tx("patient", user.username) as t:
            return t.query("SELECT * FROM fn_portal_access_log(50)", show=False)
    return await db.run(work)


@router.get("/symptoms")
async def symptoms(q: str = Query(min_length=2, max_length=60), user: auth.User = Depends(patient_only)):
    def work():
        with db.tx("patient", user.username) as t:
            rows = t.query("SELECT * FROM fn_portal_symptom_search(%s)", (q.strip(),), show=False)
            return [{"item_id": r["item_id"], "brand_name": r["brand_name"], "ingredients": r["ingredients"],
                     "indication": r["indication"], "start_date": r["start_date"], "end_date": r["end_date"],
                     "dose": f"{float(r['dose_units']):g} per dose, {float(r['doses_per_day']):g} time(s) a day",
                     "prescriber": r["prescriber"]} for r in rows]
    return await db.run(work)


@router.get("/brands/search")
async def brand_search(q: str = Query(min_length=1, max_length=60), user: auth.User = Depends(patient_only)):
    def work():
        with db.tx("patient", user.username) as t:
            rows = t.query("SELECT brand_id, brand_name, form, strength, ingredients FROM fn_search_brands(%s, 8)",
                           (q.strip(),), show=False)
            return [{**r, "ingredients": [i["name"] for i in r["ingredients"]]} for r in rows]
    return await db.run(work)


def _shape(r: dict, for_patient: bool) -> dict:
    """One self-reported medicine with its label. Always unverified; only brand picks are allergy-checked."""
    if not r["checked"]:
        check = {"state": "unchecked", "text": "We couldn't check this one"}
    elif r["allergy_match"]:
        who = "your record lists" if for_patient else "this patient's record lists"
        check = {"state": "warning", "text": f"Allergy match: {who} an allergy that matches {r['allergy_ingredients']}."}
    else:
        check = {"state": "no_match", "text": "No allergy match found. This is not a full safety check."}
    per_day = float(r["doses_per_day"]) if r["doses_per_day"] is not None else None
    return {"report_id": r["report_id"], "medicine": r["medicine"], "strength": r["form_strength"],
            "times_per_day": per_day, "note": r["note"], "started_on": r["started_on"], "stopped_on": r["stopped_on"],
            "active": r["stopped_on"] is None, "verified": False, "check": check}


@router.get("/self-reported")
async def my_self_reported(user: auth.User = Depends(patient_only)):
    def work():
        with db.tx("patient", user.username) as t:
            pid = _me(t)["patient_id"]
            return [_shape(r, True) for r in t.query("SELECT * FROM fn_self_reported_rows(%s)", (pid,), show=False)]
    return await db.run(work)


@router.post("/self-reported", status_code=201)
async def add_self_reported(body: SelfReportedIn, user: auth.User = Depends(patient_only)):
    def work():
        with db.tx("patient", user.username) as t:
            _me(t)
            row = t.one("INSERT INTO self_reported_meds (patient_id, brand_id, free_text_name, doses_per_day, note, started_on) "
                        "VALUES (fn_current_patient_id(), %s, %s, %s, %s, coalesce(%s, current_date)) RETURNING report_id",
                        (body.brand_id, body.free_text_name, FREQUENCY_PER_DAY[body.frequency], body.note, body.started_on),
                        show=False)
            return {"report_id": row["report_id"]}
    return await db.run(work)


@router.post("/self-reported/{report_id}/stop")
async def stop_self_reported(report_id: int, user: auth.User = Depends(patient_only)):
    def work():
        with db.tx("patient", user.username) as t:
            row = t.one("UPDATE self_reported_meds SET stopped_on = current_date "
                        "WHERE report_id = %s AND stopped_on IS NULL RETURNING report_id", (report_id,), show=False)
            if row is None:
                raise HTTPException(404, "Medicine not found or already stopped")
            return {"report_id": report_id, "stopped": True}
    return await db.run(work)


@staff_router.get("/patients/{patient_id}/self-reported")
async def before_coming_in(patient_id: int, user: auth.User = Depends(auth.require("clinician"))):
    """The doctor's 'Before coming in' list: what the patient reported themselves. Unverified, consent required."""
    def work():
        with db.tx(user.role, user.username) as t:
            t.require_consent(patient_id)
            rows = t.query("SELECT * FROM fn_self_reported_rows(%s)", (patient_id,), show=False)
            t.log_read("self_reported_meds", patient_id)
            return [_shape(r, False) for r in rows]
    return await db.run(work)
