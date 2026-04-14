from __future__ import annotations

from logging.config import fileConfig

from sqlalchemy import engine_from_config, pool
from alembic import context

from adapters.db.session import Base
from app.core.settings import get_settings
import adapters.db.models  # noqa: F401  # Import models to register metadata

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
config.set_main_option("sqlalchemy.url", settings.postgresql_dsn)

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
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        # Ensure alembic_version.version_num can hold long revision strings
        try:
            res = connection.exec_driver_sql(
                "SELECT character_maximum_length FROM information_schema.columns "
                "WHERE table_name='alembic_version' AND column_name='version_num';"
            )
            row = res.fetchone()
            if row is not None:
                length = row[0] or 0
                if length < 255:
                    connection.exec_driver_sql(
                        "ALTER TABLE alembic_version ALTER COLUMN version_num TYPE VARCHAR(255);"
                    )
        except Exception:
            # Best-effort; ignore if table doesn't exist yet
            pass
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
