from sqlalchemy import text
from adapters.db.session import SessionLocal


def run() -> None:
    """Normalize existing checks.type values to uppercase to match Enum.

    Converts 'received' -> 'RECEIVED' and 'transferred' -> 'TRANSFERRED'.
    Safe to run multiple times.
    """
    with SessionLocal() as db:
        db.execute(text("UPDATE checks SET type='RECEIVED' WHERE LOWER(type)='received'"))
        db.execute(text("UPDATE checks SET type='TRANSFERRED' WHERE LOWER(type)='transferred'"))
        db.commit()


if __name__ == "__main__":
    run()


