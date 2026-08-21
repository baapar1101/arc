"""Phase 13 — production evidence gate. Does not invent live traffic.

Gold is labeled offline_gold. Live is labeled production_live.
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
    SOURCE_PRODUCTION_LIVE,
    live_indexed_evidence,
    offline_performance_evidence,
)
from app.services.ai.ai_tool_phase11_eval import run_phase11_evaluation

PHASE13_DIR = Path("/opt/hesabix/app/docs/ai-agent/evals/phase-13")


def run_phase13_evaluation(*, write_files: bool = False) -> Dict[str, Any]:
    gold = run_phase11_evaluation(write_files=False)
    live = live_indexed_evidence()
    recall_100 = next(
        row["candidate_recall"]
        for row in gold["candidate_recall"]
        if row["n"] == 100
    )
    promotion = dict(live.get("promotion") or {})
    report = {
        "offline_gold": {
            "source": SOURCE_OFFLINE_GOLD,
            "not_production": True,
            "candidate_recall_at_100": recall_100,
            "indexed_final": gold["indexed_final"],
            "baseline_final": gold["baseline_final"],
            "note": "Gold Recall is offline design evidence. Do not report as Production Recall.",
        },
        "offline_performance": offline_performance_evidence(),
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
            "No live evidence, no promotion. Gold proves the design is plausible; "
            "production evidence proves the feature is safe and useful."
        ),
    }
    if write_files:
        PHASE13_DIR.mkdir(parents=True, exist_ok=True)
        (PHASE13_DIR / "latest.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2, default=str),
            encoding="utf-8",
        )
        (PHASE13_DIR / "README.md").write_text(
            "\n".join(
                [
                    "# Phase 13 evaluation outputs",
                    "",
                    "- [`latest.json`](latest.json) — **offline_gold** and **production_live** are separate objects.",
                    "- Production Recall is never copied from Gold Recall.",
                    "",
                    "```bash",
                    "cd hesabixAPI && .venv/bin/python -m app.services.ai.ai_tool_phase13_eval",
                    "```",
                    "",
                ]
            ),
            encoding="utf-8",
        )
    return report


def main() -> None:
    report = run_phase13_evaluation(write_files=True)
    live = report["production_live"]
    print(
        json.dumps(
            {
                "offline_gold_recall_100": report["offline_gold"]["candidate_recall_at_100"],
                "production_live_control": live.get("control_requests"),
                "production_live_experiment": live.get("experiment_requests"),
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
