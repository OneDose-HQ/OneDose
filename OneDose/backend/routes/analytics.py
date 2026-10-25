# File: backend/routes/analytics.py
# Owner: Bhavya  (only the owner edits this file)
# Purpose: Dashboard statistics and the audit trail: GET /analytics/overrides (clinician, admin), GET /analytics/audit (also /audit) and GET /analytics/audit/verify (admin only).
# Inputs: JWT of a clinician or admin.
# Outputs: Override statistics in the shape the Analytics page expects, and recent audit rows.
# Depends on: db.py, auth.py
#
# The numbers come from SQL (mv_alert_stats, fn_alert_severity_counts, fn_top_overridden). This file only reshapes them
# for the page: totals are sums of the per-check rows, and the label of each check type is display text.
from fastapi import APIRouter, Depends

import auth
import db

router = APIRouter(tags=["analytics"])
LABELS = {"dose_limit": "Dose Limit", "interaction": "Interaction", "contraindication": "Contraindication",
          "allergy": "Allergy", "duplicate": "Duplicate"}


@router.get("/analytics/overrides")
async def overrides(user: auth.User = Depends(auth.require("clinician", "admin"))):
    def work():
        with db.tx(user.role, user.username) as t:
            t.query("SELECT fn_refresh_alert_stats()", show=False)
            per_check = t.query("SELECT check_type, total_alerts, overridden_alerts, override_rate_pct "
                                "FROM mv_alert_stats ORDER BY override_rate_pct DESC, check_type", show=False)
            severities = t.query("SELECT severity, alert_count FROM fn_alert_severity_counts()", show=False)
            top = t.query("SELECT ingredient_pair, check_type, override_count FROM fn_top_overridden(5)", show=False)
            return per_check, severities, top

    per_check, severities, top = await db.run(work)
    total = sum(r["total_alerts"] for r in per_check)
    overridden = sum(r["overridden_alerts"] for r in per_check)
    worst = next((r for r in per_check if r["total_alerts"] > 0), None)  # rows are sorted by override rate
    return {
        "totals": {"alerts": total, "overrides": overridden,
                   "override_rate": round(100 * overridden / total, 1) if total else 0,
                   "highest_override_check": LABELS[worst["check_type"]] if worst else "None yet"},
        "per_check": [{"check_type": r["check_type"], "label": LABELS[r["check_type"]], "total": r["total_alerts"],
                       "overridden": r["overridden_alerts"], "override_rate": float(r["override_rate_pct"])}
                      for r in per_check],
        "by_severity": [{"severity": r["severity"], "label": r["severity"].capitalize(), "count": r["alert_count"]}
                        for r in severities],
        "top_overridden": [{"ingredient_pair": r["ingredient_pair"], "check_type": r["check_type"],
                            "count": r["override_count"]} for r in top],
    }


@router.get("/analytics/audit")
@router.get("/audit", include_in_schema=False)
async def audit(user: auth.User = Depends(auth.require("admin"))):
    def work():
        with db.tx(user.role, user.username) as t:
            return t.query("SELECT audit_id, occurred_at, actor, action, table_name, row_id, hash_prefix "
                           "FROM v_audit_recent", show=False)
    return [{"id": r["audit_id"], "at": r["occurred_at"], "actor": r["actor"], "action": r["action"],
             "entity": f"{r['table_name']}:{r['row_id']}" if r["row_id"] else r["table_name"],
             "hash": r["hash_prefix"]} for r in await db.run(work)]


@router.get("/analytics/audit/verify")
async def verify_audit(user: auth.User = Depends(auth.require("admin"))):
    """Recompute the whole hash chain. is_valid=false means a row was changed after it was written."""
    def work():
        with db.tx(user.role, user.username) as t:
            return t.one("SELECT is_valid, rows_checked, first_bad_audit_id FROM fn_verify_audit_chain()", show=False)
    return await db.run(work)
