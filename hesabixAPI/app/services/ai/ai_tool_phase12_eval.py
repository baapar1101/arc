"""Phase 12 — live canary dress rehearsal. Does not invent live traffic."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict

from app.services.ai.ai_constants import (
    ADAPTIVE_DISCOVERY_K,
    ADAPTIVE_K_ROLLOUT_PERCENT,
    HYBRID_TOOL_DISCOVERY,
    INDEXED_CANDIDATE_FALLBACK,
    INDEXED_CANDIDATE_KILL_SWITCH,
    INDEXED_CANDIDATE_MIN_LIVE_SAMPLES,
    INDEXED_CANDIDATE_RETRIEVAL,
    INDEXED_CANDIDATE_ROLLOUT_PERCENT,
    PROGRESSIVE_SCHEMA_LOADING,
)
from app.services.ai.ai_tool_canary import recommend_indexed_promotion
from app.services.ai.ai_tool_discovery_telemetry import telemetry_snapshot
from app.services.ai.ai_tool_phase11_eval import run_phase11_evaluation

PHASE12_DIR = Path("/opt/hesabix/app/docs/ai-agent/evals/phase-12")


def run_phase12_evaluation(*, write_files: bool = False) -> Dict[str, Any]:
    gold = run_phase11_evaluation(write_files=False)
    live = telemetry_snapshot()
    promotion = recommend_indexed_promotion(live)
    report = {
        "canary": {
            "INDEXED_CANDIDATE_RETRIEVAL": INDEXED_CANDIDATE_RETRIEVAL,
            "INDEXED_CANDIDATE_ROLLOUT_PERCENT": INDEXED_CANDIDATE_ROLLOUT_PERCENT,
            "INDEXED_CANDIDATE_FALLBACK": INDEXED_CANDIDATE_FALLBACK,
            "INDEXED_CANDIDATE_KILL_SWITCH": INDEXED_CANDIDATE_KILL_SWITCH,
            "min_live_samples": INDEXED_CANDIDATE_MIN_LIVE_SAMPLES,
        },
        "other_planes": {
            "ADAPTIVE_DISCOVERY_K": ADAPTIVE_DISCOVERY_K,
            "ADAPTIVE_K_ROLLOUT_PERCENT": ADAPTIVE_K_ROLLOUT_PERCENT,
            "HYBRID_TOOL_DISCOVERY": HYBRID_TOOL_DISCOVERY,
            "PROGRESSIVE_SCHEMA_LOADING": PROGRESSIVE_SCHEMA_LOADING,
        },
        "gold": {
            "candidate_recall": gold["candidate_recall"],
            "indexed_final": gold["indexed_final"],
            "baseline_final": gold["baseline_final"],
            "latency": gold["latency"],
        },
        "live": live,
        "promotion": promotion,
        "note": (
            "Rollout is 5%. Promotion requires 500 live discovery requests "
            "per arm. This process snapshot is not production traffic."
        ),
    }
    if write_files:
        PHASE12_DIR.mkdir(parents=True, exist_ok=True)
        (PHASE12_DIR / "latest.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2, default=str),
            encoding="utf-8",
        )
        (PHASE12_DIR / "README.md").write_text(
            "\n".join(
                [
                    "# Phase 12 evaluation outputs",
                    "",
                    "- [`latest.json`](latest.json) — canary config, Gold confirmation, live snapshot",
                    "",
                    "```bash",
                    "cd hesabixAPI && .venv/bin/python -m app.services.ai.ai_tool_phase12_eval",
                    "```",
                    "",
                ]
            ),
            encoding="utf-8",
        )
    return report


def main() -> None:
    report = run_phase12_evaluation(write_files=True)
    print(
        json.dumps(
            {
                "canary": report["canary"],
                "other_planes": report["other_planes"],
                "promotion": report["promotion"],
                "gold_candidate_recall_100": next(
                    row["candidate_recall"]
                    for row in report["gold"]["candidate_recall"]
                    if row["n"] == 100
                ),
                "live_requests": report["live"].get("live_requests", 0),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
