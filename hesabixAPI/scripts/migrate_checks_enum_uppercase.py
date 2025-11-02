from sqlalchemy import text
from adapters.db.session import SessionLocal


def run() -> None:
    """Migrate MySQL ENUM values of checks.type to uppercase only.

    Steps:
      1) Allow both lowercase and uppercase temporarily
      2) Update existing rows to uppercase
      3) Restrict enum to uppercase values only
    Safe to re-run.
    """
    with SessionLocal() as db:
        # Case-insensitive collations in MySQL prevent having both 'received' and 'RECEIVED'
        # So we migrate via temporary placeholders.

        # 1) Add placeholders alongside existing lowercase values
        db.execute(text(
            "ALTER TABLE checks MODIFY COLUMN type ENUM('received','transferred','TMP_R','TMP_T') NOT NULL"
        ))

        # 2) Move existing rows to placeholders
        db.execute(text("UPDATE checks SET type='TMP_R' WHERE type='received'"))
        db.execute(text("UPDATE checks SET type='TMP_T' WHERE type='transferred'"))

        # 3) Switch enum to uppercase + placeholders
        db.execute(text(
            "ALTER TABLE checks MODIFY COLUMN type ENUM('RECEIVED','TRANSFERRED','TMP_R','TMP_T') NOT NULL"
        ))

        # 4) Move placeholders to uppercase values
        db.execute(text("UPDATE checks SET type='RECEIVED' WHERE type='TMP_R'"))
        db.execute(text("UPDATE checks SET type='TRANSFERRED' WHERE type='TMP_T'"))

        # 5) Drop placeholders
        db.execute(text(
            "ALTER TABLE checks MODIFY COLUMN type ENUM('RECEIVED','TRANSFERRED') NOT NULL"
        ))

        db.commit()


if __name__ == "__main__":
    run()


