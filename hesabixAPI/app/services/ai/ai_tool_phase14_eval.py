"""Phase 14 — live canary validation. Does not invent live traffic.

Offline Gold, Production Control, and Production Experiment stay separate.
Gold Recall is never copied as Production Recall.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict

from app.services.ai.ai_constants import (
    ADAPTIVE_DISCOVERY_K,
    CANDIDATE_RETRIEVAL_N,
    HYBRID_TOOL_DISCOVERY,
    INDEXED_CANDIDATE_FALLBACK,
    INDEXED_CANDIDATE_KILL_SWITCH,
    INDEXED_CANDIDATE_MIN_LIVE_SAMPLES,
    INDEXED_CANDIDATE_RETRIEVAL,
    INDEXED_CANDIDATE_ROLLOUT_PERCENT,
    MAX_TOOLS_AUTONOMOUS,
    MAX_TOOLS_PER_REQUEST,
    PROGRESSIVE_SCHEMA_LOADING,
)
from app.services.ai.ai_tool_canary import INDEXED_ROLLOUT_LADDER
from app.services.ai.ai_tool_index_health import tool_index_health
from app.services.ai.ai_tool_indexed_evidence import (
    SOURCE_OFFLINE_GOLD,
    live_indexed_evidence,
    offline_performance_evidence,
)

PHASE13_JSON = Path("/opt/hesabix/app/docs/ai-agent/evals/phase-13/latest.json")
PHASE14_DIR = Path("/opt/hesabix/app/docs/ai-agent/evals/phase-14")


def _offline_gold() -> Dict[str, Any]:
    if PHASE13_JSON.is_file():
        prior = json.loads(PHASE13_JSON.read_text(encoding="utf-8"))
        gold = dict(prior.get("offline_gold") or {})
        gold["source"] = SOURCE_OFFLINE_GOLD
        gold["not_production"] = True
        gold["note"] = (
            "Copied from Phase 13 offline Gold. Not Production Recall. "
            "Not Production Control or Experiment."
        )
        return gold
    return {
        "source": SOURCE_OFFLINE_GOLD,
        "not_production": True,
        "note": "Phase 13 Gold artifact missing. Do not substitute live rates.",
    }


def run_phase14_evaluation(*, write_files: bool = False) -> Dict[str, Any]:
    live = live_indexed_evidence()
    promotion = dict(live.get("promotion") or {})
    report = {
        "offline_gold": _offline_gold(),
        "offline_performance": offline_performance_evidence(),
        "production_control": dict(live.get("production_control") or {}),
        "production_experiment": dict(live.get("production_experiment") or {}),
        "production_live": live,
        "flags": {
            "INDEXED_CANDIDATE_RETRIEVAL": INDEXED_CANDIDATE_RETRIEVAL,
            "INDEXED_CANDIDATE_ROLLOUT_PERCENT": INDEXED_CANDIDATE_ROLLOUT_PERCENT,
            "INDEXED_CANDIDATE_FALLBACK": INDEXED_CANDIDATE_FALLBACK,
            "INDEXED_CANDIDATE_KILL_SWITCH": INDEXED_CANDIDATE_KILL_SWITCH,
            "ADAPTIVE_DISCOVERY_K": ADAPTIVE_DISCOVERY_K,
            "HYBRID_TOOL_DISCOVERY": HYBRID_TOOL_DISCOVERY,
            "PROGRESSIVE_SCHEMA_LOADING": PROGRESSIVE_SCHEMA_LOADING,
            "CANDIDATE_RETRIEVAL_N": CANDIDATE_RETRIEVAL_N,
            "MAX_TOOLS_PER_REQUEST": MAX_TOOLS_PER_REQUEST,
            "MAX_TOOLS_AUTONOMOUS": MAX_TOOLS_AUTONOMOUS,
            "min_live_samples": INDEXED_CANDIDATE_MIN_LIVE_SAMPLES,
            "rollout_ladder": list(INDEXED_ROLLOUT_LADDER),
        },
        "index_health": tool_index_health(),
        "promotion": promotion,
        "decision": {
            "promotion": "HOLD"
            if promotion.get("decision") != "ROLLBACK"
            else "ROLLBACK",
            "reason": promotion.get("reason") or "need_500_per_arm",
            "auto_promotion": False,
        },
        "note": (
            "No live evidence, no promotion. Do not interpret fallback-assisted "
            "success as index success. Do not mix Indexed Retrieval validation "
            "with Adaptive K validation."
        ),
    }
    if write_files:
        PHASE14_DIR.mkdir(parents=True, exist_ok=True)
        (PHASE14_DIR / "latest.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2, default=str),
            encoding="utf-8",
        )
        (PHASE14_DIR / "README.md").write_text(
            "\n".join(
                [
                    "# Phase 14 evaluation outputs",
                    "",
                    "- `offline_gold`, `production_control`, and `production_experiment` are separate objects.",
                    "- Gold Recall is never Production Recall.",
                    "",
                    "```bash",
                    "cd hesabixAPI && .venv/bin/python -m app.services.ai.ai_tool_phase14_eval",
                    "```",
                    "",
                ]
            ),
            encoding="utf-8",
        )
    return report


def main() -> None:
    report = run_phase14_evaluation(write_files=True)
    live = report["production_live"]
    print(
        json.dumps(
            {
                "offline_gold_recall_100": (report["offline_gold"] or {}).get(
                    "candidate_recall_at_100"
                ),
                "live_control": live.get("live_control_requests"),
                "live_experiment": live.get("live_experiment_requests"),
                "task_success": live.get("task_success"),
                "promotion": report["decision"],
                "adaptive_k": ADAPTIVE_DISCOVERY_K,
                "hybrid": HYBRID_TOOL_DISCOVERY,
                "progressive_schema": PROGRESSIVE_SCHEMA_LOADING,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
