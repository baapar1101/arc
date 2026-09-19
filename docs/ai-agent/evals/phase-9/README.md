# Phase 9 evaluation outputs

- [`latest.json`](latest.json) — Control K=48 vs Adaptive tight on Gold 2026-08-19.v1
- Live canary samples are in-process (`telemetry_snapshot`); production remains at 0% until an operator raises `ADAPTIVE_K_ROLLOUT_PERCENT`.

```bash
cd hesabixAPI && .venv/bin/python -m app.services.ai.ai_tool_phase9_eval
cd hesabixAPI && .venv/bin/python -m app.services.ai.ai_tool_scale_bench
```
