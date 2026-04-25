from __future__ import annotations

import os
from logging.config import fileConfig

from sqlalchemy import engine_from_config, pool
from alembic import context

from adapters.db.session import Base
from app.core.settings import get_settings
import adapters.db.models  # noqa: F401  # Import models to register metadata
import adapters.db.models.crm_chat  # noqa: F401  # CRM embed chat tables
import adapters.db.models.business_crm_settings  # noqa: F401

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

# Interpret the config file for Python logging.
# This line sets up loggers basically.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# add your model's MetaData object here
# for 'autogenerate' support
# from myapp import mymodel
# target_metadata = mymodel.Base.metadata

settings = get_settings()
# استفاده از رمز از .env (pydantic-settings)؛ override فقط اگر DB_PASSWORD در محیط ست شده
if (pw := os.getenv('DB_PASSWORD')) is not None:
    settings.db_password = pw
from urllib.parse import quote_plus
dsn = f"postgresql+psycopg2://{settings.db_user}:{quote_plus(settings.db_password)}@{settings.db_host}:{settings.db_port}/{settings.db_name}"
# Set DSN directly in attributes to avoid ConfigParser % interpolation issues
config.attributes['sqlalchemy.url'] = dsn

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    # Get DSN from attributes (set above) or config
    url = config.attributes.get('sqlalchemy.url') or config.get_main_option("sqlalchemy.url")
    connectable = engine_from_config(
        {"sqlalchemy.url": url},
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    # Ensure alembic_version exists with version_num VARCHAR(255) for long revision IDs.
    # Run in a separate connection so any failure doesn't abort the migration transaction.
    with connectable.connect() as aux:
        with aux.begin():
            try:
                res = aux.exec_driver_sql(
                    "SELECT 1 FROM information_schema.tables "
                    "WHERE table_schema='public' AND table_name='alembic_version';"
                )
                if res.fetchone() is None:
                    # Table doesn't exist: create with VARCHAR(255) so Alembic won't create it with VARCHAR(32)
                    aux.exec_driver_sql(
                        "CREATE TABLE public.alembic_version (version_num VARCHAR(255) PRIMARY KEY);"
                    )
                else:
                    # Table exists: expand version_num if too short
                    res = aux.exec_driver_sql(
                        "SELECT character_maximum_length FROM information_schema.columns "
                        "WHERE table_schema='public' AND table_name='alembic_version' AND column_name='version_num';"
                    )
                    row = res.fetchone()
                    if row is not None and (row[0] or 0) < 255:
                        aux.exec_driver_sql(
                            "ALTER TABLE public.alembic_version ALTER COLUMN version_num TYPE VARCHAR(255);"
                        )
            except Exception:
                # Best-effort; ignore errors
                pass

    with connectable.begin() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
