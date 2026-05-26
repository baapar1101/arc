"""
اجرای سناریوهای ارزیابی کیفیت پاسخ AI (regression برای prompt).
"""
from __future__ import annotations

import json
import logging
import time
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.ai_eval_case import AIEvalCase
from adapters.db.models.ai_eval_result import AIEvalResult
from adapters.db.models.ai_eval_run import AIEvalRun
from app.core.auth_dependency import AuthContext

logger = logging.getLogger(__name__)


def _parse_json_list(raw: Optional[str]) -> List[str]:
    if not raw:
        return []
    try:
        data = json.loads(raw)
        if isinstance(data, list):
            return [str(x) for x in data if x]
    except json.JSONDecodeError:
        pass
    return [s.strip() for s in raw.split("\n") if s.strip()]


def case_to_dict(case: AIEvalCase) -> Dict[str, Any]:
    return {
        "id": case.id,
        "name": case.name,
        "description": case.description,
        "role": case.role,
        "business_id": case.business_id,
        "user_message": case.user_message,
        "expected_substrings": _parse_json_list(case.expected_substrings),
        "forbidden_substrings": _parse_json_list(case.forbidden_substrings),
        "use_tools": case.use_tools,
        "is_active": case.is_active,
        "created_at": case.created_at.isoformat() if case.created_at else None,
        "updated_at": case.updated_at.isoformat() if case.updated_at else None,
    }


def list_cases(db: Session, active_only: bool = True) -> List[AIEvalCase]:
    q = db.query(AIEvalCase)
    if active_only:
        q = q.filter(AIEvalCase.is_active == True)  # noqa: E712
    return q.order_by(AIEvalCase.id.asc()).all()


def create_case(db: Session, data: Dict[str, Any]) -> AIEvalCase:
    row = AIEvalCase(
        name=data["name"],
        description=data.get("description"),
        role=data.get("role", "user"),
        business_id=data.get("business_id"),
        user_message=data["user_message"],
        expected_substrings=json.dumps(data.get("expected_substrings") or [], ensure_ascii=False),
        forbidden_substrings=json.dumps(data.get("forbidden_substrings") or [], ensure_ascii=False),
        use_tools=bool(data.get("use_tools", False)),
        is_active=bool(data.get("is_active", True)),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def update_case(db: Session, case_id: int, data: Dict[str, Any]) -> Optional[AIEvalCase]:
    row = db.query(AIEvalCase).filter(AIEvalCase.id == case_id).first()
    if not row:
        return None
    for key in ("name", "description", "role", "business_id", "user_message", "use_tools", "is_active"):
        if key in data:
            setattr(row, key, data[key])
    if "expected_substrings" in data:
        row.expected_substrings = json.dumps(data["expected_substrings"], ensure_ascii=False)
    if "forbidden_substrings" in data:
        row.forbidden_substrings = json.dumps(data["forbidden_substrings"], ensure_ascii=False)
    row.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(row)
    return row


def delete_case(db: Session, case_id: int) -> bool:
    row = db.query(AIEvalCase).filter(AIEvalCase.id == case_id).first()
    if not row:
        return False
    db.delete(row)
    db.commit()
    return True


def _score_response(
    content: str,
    expected: List[str],
    forbidden: List[str],
) -> tuple[bool, Dict[str, Any]]:
    text = content or ""
    lower = text.lower()
    missing = [s for s in expected if s.lower() not in lower]
    found_forbidden = [s for s in forbidden if s.lower() in lower]
    passed = not missing and not found_forbidden
    return passed, {
        "missing_expected": missing,
        "found_forbidden": found_forbidden,
        "response_length": len(text),
    }


async def run_eval_suite(
    db: Session,
    ctx: AuthContext,
    *,
    business_id: Optional[int] = None,
    case_ids: Optional[List[int]] = None,
) -> Dict[str, Any]:
    from app.services.ai.ai_service import AIService

    q = db.query(AIEvalCase).filter(AIEvalCase.is_active == True)  # noqa: E712
    if case_ids:
        q = q.filter(AIEvalCase.id.in_(case_ids))
    cases = q.all()
    if not cases:
        raise ValueError("هیچ سناریوی فعالی برای اجرا یافت نشد")

    run = AIEvalRun(
        user_id=ctx.get_user_id(),
        status="running",
        total_cases=len(cases),
        business_id=business_id,
    )
    db.add(run)
    db.commit()
    db.refresh(run)

    passed_count = 0
    results: List[Dict[str, Any]] = []

    for case in cases:
        eff_business = case.business_id or business_id
        ai = AIService(db, ctx, eff_business)
        messages = [{"role": "user", "content": case.user_message}]
        expected = _parse_json_list(case.expected_substrings)
        forbidden = _parse_json_list(case.forbidden_substrings)
        t0 = time.perf_counter()
        error_msg = None
        content = ""
        try:
            response = await ai.chat_completion(
                messages,
                use_function_calling=case.use_tools,
                session_business_id=eff_business,
                max_iterations=4 if case.use_tools else 1,
            )
            content = response.get("message", {}).get("content") or ""
        except Exception as exc:
            error_msg = str(exc)
            content = ""
        latency_ms = int((time.perf_counter() - t0) * 1000)

        if error_msg:
            passed = False
            details = {"error": error_msg}
        else:
            passed, details = _score_response(content, expected, forbidden)

        if passed:
            passed_count += 1

        row = AIEvalResult(
            run_id=run.id,
            case_id=case.id,
            passed=passed,
            response_text=content[:50_000] if content else None,
            details_json=json.dumps(details, ensure_ascii=False),
            latency_ms=latency_ms,
        )
        db.add(row)
        results.append(
            {
                "case_id": case.id,
                "case_name": case.name,
                "passed": passed,
                "latency_ms": latency_ms,
                "details": details,
            }
        )

    run.passed_cases = passed_count
    run.failed_cases = len(cases) - passed_count
    run.status = "completed"
    run.completed_at = datetime.utcnow()
    db.commit()
    db.refresh(run)

    return {
        "run": {
            "id": run.id,
            "status": run.status,
            "total_cases": run.total_cases,
            "passed_cases": run.passed_cases,
            "failed_cases": run.failed_cases,
            "created_at": run.created_at.isoformat() if run.created_at else None,
            "completed_at": run.completed_at.isoformat() if run.completed_at else None,
        },
        "results": results,
    }


def get_run_with_results(db: Session, run_id: int) -> Optional[Dict[str, Any]]:
    run = db.query(AIEvalRun).filter(AIEvalRun.id == run_id).first()
    if not run:
        return None
    result_rows = db.query(AIEvalResult).filter(AIEvalResult.run_id == run_id).all()
    case_map = {
        c.id: c
        for c in db.query(AIEvalCase).filter(
            AIEvalCase.id.in_([r.case_id for r in result_rows] or [0])
        )
    }
    return {
        "run": {
            "id": run.id,
            "status": run.status,
            "total_cases": run.total_cases,
            "passed_cases": run.passed_cases,
            "failed_cases": run.failed_cases,
            "business_id": run.business_id,
            "created_at": run.created_at.isoformat() if run.created_at else None,
            "completed_at": run.completed_at.isoformat() if run.completed_at else None,
        },
        "results": [
            {
                "case_id": r.case_id,
                "case_name": case_map.get(r.case_id).name if case_map.get(r.case_id) else None,
                "passed": r.passed,
                "latency_ms": r.latency_ms,
                "response_preview": (r.response_text or "")[:500],
                "details": json.loads(r.details_json) if r.details_json else {},
            }
            for r in result_rows
        ],
    }


def list_runs(db: Session, limit: int = 30) -> List[Dict[str, Any]]:
    rows = db.query(AIEvalRun).order_by(AIEvalRun.id.desc()).limit(limit).all()
    return [
        {
            "id": r.id,
            "status": r.status,
            "total_cases": r.total_cases,
            "passed_cases": r.passed_cases,
            "failed_cases": r.failed_cases,
            "created_at": r.created_at.isoformat() if r.created_at else None,
            "completed_at": r.completed_at.isoformat() if r.completed_at else None,
        }
        for r in rows
    ]
