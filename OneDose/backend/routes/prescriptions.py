# File: backend/routes/prescriptions.py
# Owner: Bhavya  (only the owner edits this file)
# Purpose: Prescription endpoints: GET /brands/search, POST /prescriptions/check, POST /prescriptions, POST /alerts/{id}/override. Calls SQL functions only, no safety logic here.
# Inputs: Brand text, patient id, brand id, dose (mg) and frequency code, override reasons.
# Outputs: Brand matches, ranked alerts with explanations, safer alternatives, saved prescription.
# Depends on: db.py, auth.py, schemas.py, llm.py
#
# check  : read-only preview. fn_check_prescription (+ fn_safe_alternatives when something is flagged). Nothing is saved.
# save   : ONE SERIALIZABLE transaction inserts the prescription and the item; the trigger in 07 writes the real alerts.
#          Every critical/major alert needs an override reason in the request, otherwise nothing is saved (409).
#          Then a second short transaction adds the explanation and resolves each alert (overridden, or accepted).
#          The LLM is called between the two, never inside a transaction (the audit log holds a lock until commit).
# The dashboard overrides alerts at check time, before any alert row exists. Those preview ids look like
# 'allergy:12:0:1'; overriding one only validates the reason, and the reason is saved with the prescription.
import asyncio
import re
from datetime import datetime, timezone
from decimal import ROUND_HALF_UP, Decimal

from fastapi import APIRouter, Depends, HTTPException, Query

import auth
import db
import llm
from schemas import FREQUENCY_PER_DAY, CheckIn, OverrideIn, PrescribeIn

router = APIRouter(tags=["prescriptions"])
REASON_REQUIRED = {"critical", "major"}
DISPLAY = {"duplicate": "Duplicate therapy", "interaction": "Interaction", "allergy": "Allergy",
           "contraindication": "Drug-disease", "dose_limit": "Max daily dose"}
LINE = {1: "First line", 2: "Second line", 3: "Third line", 4: "Fourth line"}
CHECK_SQL = "SELECT * FROM fn_check_prescription(%s, %s, %s, %s)"
PREVIEW_ID = re.compile(r"[a-z_]+:\d+:\d+:\d+")
_vocabulary: list[str] = []  # every ingredient name, used to check that explanations stay on topic


def _key(check_type, ingredient_id, related_id) -> str:
    return f"{check_type}:{ingredient_id}:{related_id or 0}"


def _row_key(r: dict) -> str:
    return _key(r["check_type"], r["ingredient_id"], r["related_ingredient_id"])


def _convert(t: db.Tx, body: CheckIn) -> tuple[Decimal, int]:
    """Dashboard dose (mg of the brand's first ingredient) -> tablets per intake, plus doses per day."""
    ref = t.one("SELECT strength_mg FROM fn_expand_brand(%s) LIMIT 1", (body.brand_id,), show=False)
    if ref is None:
        raise HTTPException(404, "Unknown medicine")
    units = (body.dose / ref["strength_mg"]).quantize(Decimal("0.01"), ROUND_HALF_UP)
    if units <= 0 or units > 20:
        raise HTTPException(422, "That dose is not a sensible number of tablets for this medicine")
    return units, FREQUENCY_PER_DAY[body.frequency]


async def _explain(row: dict | None, names: list[str]) -> str | None:
    return await llm.explain(row, names) if row else None


async def _ingredient_names(user: auth.User) -> list[str]:
    if not _vocabulary:
        def work():
            with db.tx(user.role, user.username) as t:
                return [r["name"] for r in t.query("SELECT name FROM ingredients", show=False)]
        _vocabulary.extend(await db.run(work))
    return _vocabulary


@router.get("/brands/search")
async def search_brands(q: str = Query(default="", max_length=60), limit: int = Query(default=10, ge=1, le=25),
                        user: auth.User = Depends(auth.require("clinician", "pharmacist"))):
    if not q.strip():
        return []

    def work():
        with db.tx(user.role, user.username) as t:
            return t.query("SELECT * FROM fn_search_brands(%s, %s)", (q, limit), show=False)
    return await db.run(work)


@router.post("/prescriptions/check")
async def check(body: CheckIn, user: auth.User = Depends(auth.require("clinician"))):
    def work():
        with db.tx(user.role, user.username) as t:
            t.require_consent(body.patient_id)
            units, per_day = _convert(t, body)
            alerts = t.query(CHECK_SQL, (body.patient_id, body.brand_id, units, per_day))
            alts = t.query("SELECT * FROM fn_safe_alternatives(%s, %s)", (body.patient_id, body.brand_id)) if alerts else []
            parts: dict[int, list[str]] = {}
            if alts:
                for r in t.query("SELECT bi.brand_id, i.name, bi.strength_mg FROM brand_ingredients bi "
                                 "JOIN ingredients i ON i.ingredient_id = bi.ingredient_id "
                                 "WHERE bi.brand_id = ANY(%s) ORDER BY i.name", ([a["brand_id"] for a in alts],), show=False):
                    parts.setdefault(r["brand_id"], []).append(f"{r['name']} {float(r['strength_mg']):g} mg")
            return alerts, alts, parts, t.debug

    alerts, alts, parts, debug = await db.run(work)
    names = await _ingredient_names(user)
    texts = await asyncio.gather(*(llm.explain(a, names) for a in alerts))
    return {
        "alerts": [{"id": f"{_row_key(a)}:{a['alert_rank']}", "severity": a["severity"], "check_type": a["check_type"],
                    "display_type": DISPLAY[a["check_type"]],
                    "ingredients": [n for n in (a["ingredient_name"], a["related_ingredient_name"]) if n],
                    "explanation": text, "source": a["source_name"], "management": a["management"],
                    "detail": a["detail"], "status": "open", "requires_reason": a["severity"] in REASON_REQUIRED}
                   for a, text in zip(alerts, texts)],
        "alternatives": [{"brand_id": a["brand_id"], "brand_name": a["brand_name"], "manufacturer": a["manufacturer"],
                          "strength": a["strength"], "indication": a["indication_name"],
                          "line_of_therapy": LINE.get(a["line_of_therapy"], "Alternative"),
                          "ingredients": parts.get(a["brand_id"], []),
                          "status_text": "No conflicts with current medicines" if a["minor_count"] == 0
                          else f"{a['minor_count']} minor interaction(s) only"} for a in alts],
        "sql": debug,
    }


@router.post("/prescriptions")
async def create(body: PrescribeIn, user: auth.User = Depends(auth.require("clinician"))):
    reasons = {a.id.rsplit(":", 1)[0]: a.override_reason.strip() for a in body.alerts
               if a.override_reason and a.override_reason.strip()}
    if any(len(r) < 10 for r in reasons.values()):
        raise HTTPException(422, "Each override reason must be at least 10 characters")

    def save():
        with db.tx(user.role, user.username, serializable=True) as t:
            t.require_consent(body.patient_id)
            units, per_day = _convert(t, body)
            pre = t.query(CHECK_SQL, (body.patient_id, body.brand_id, units, per_day), show=False)
            rx = t.one("INSERT INTO prescriptions (patient_id, clinician_id, notes) VALUES (%s, %s, %s) "
                       "RETURNING prescription_id", (body.patient_id, user.clinician_id, body.notes), show=False)
            item = t.one("INSERT INTO prescription_items (prescription_id, patient_id, brand_id, dose_units, doses_per_day) "
                         "VALUES (%s, %s, %s, %s, %s) RETURNING item_id",
                         (rx["prescription_id"], body.patient_id, body.brand_id, units, per_day), show=False)
            real = t.query("SELECT alert_id, check_type, severity, ingredient_id, related_ingredient_id "
                           "FROM alerts WHERE item_id = %s ORDER BY alert_id", (item["item_id"],), show=False)
            missing = [a for a in real if a["severity"] in REASON_REQUIRED and _row_key(a) not in reasons]
            if missing:  # raising rolls everything back: nothing is saved
                raise HTTPException(409, f"An override reason is required for {len(missing)} alert(s) before this can be prescribed")
            return rx["prescription_id"], item["item_id"], real, pre

    prescription_id, item_id, real, pre = await db.run(save)

    by_key = {}
    for r in pre:
        by_key.setdefault(_row_key(r), r)
    names = await _ingredient_names(user)
    texts = await asyncio.gather(*(_explain(by_key.get(_row_key(a)), names) for a in real))
    updates = [(text, "overridden" if _row_key(a) in reasons else "accepted", reasons.get(_row_key(a)),
                user.clinician_id, a["alert_id"]) for a, text in zip(real, texts)]
    resolved = True
    if updates:
        def resolve():
            with db.tx(user.role, user.username) as t:
                for u in updates:
                    t.query("UPDATE alerts SET explanation = %s, status = %s, override_reason = %s, resolved_by = %s "
                            "WHERE alert_id = %s AND status = 'open'", u, show=False)
        try:
            await db.run(resolve)
        except Exception:  # the prescription is saved; leftover open alerts can still be overridden one by one
            resolved = False
    return {"success": True, "prescription_id": prescription_id, "item_id": item_id, "alerts_recorded": len(real),
            "overridden": sum(1 for u in updates if u[1] == "overridden"), "alerts_resolved": resolved}


@router.post("/alerts/{alert_id}/override")
async def override(alert_id: str, body: OverrideIn, user: auth.User = Depends(auth.require("clinician"))):
    if alert_id.isdigit():  # a real alert row that is still open
        def work():
            with db.tx(user.role, user.username) as t:
                return t.one("UPDATE alerts SET status = 'overridden', override_reason = %s, resolved_by = %s "
                             "WHERE alert_id = %s AND status = 'open' "
                             "RETURNING alert_id, status, override_reason, resolved_at",
                             (body.reason, user.clinician_id, int(alert_id)), show=False)
        row = await db.run(work)
        if row is None:
            raise HTTPException(404, "Alert not found, already resolved, or not accessible")
        return {"success": True, "alert_id": row["alert_id"], "status": row["status"],
                "override_reason": row["override_reason"], "overridden_at": row["resolved_at"], "recorded": True}
    if not PREVIEW_ID.fullmatch(alert_id):
        raise HTTPException(404, "Unknown alert")
    return {"success": True, "alert_id": alert_id, "status": "overridden", "override_reason": body.reason,
            "overridden_at": datetime.now(timezone.utc).isoformat(), "recorded": False}
