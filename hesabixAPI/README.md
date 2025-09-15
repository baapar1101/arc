# Hesabix API

Monolithic modular backend (DDD-lite) using FastAPI + SQLAlchemy + MySQL.

## Quickstart (Dev)

1. Create and fill `.env` from `.env.example`.
2. Install dependencies:
```bash
pip install -e .[dev]
```
3. Run app:
```bash
uvicorn app.main:app --reload
```

Health endpoint: `GET /api/v1/health`.

## Configuration
- See `app/core/settings.py` and `.env.example`.
