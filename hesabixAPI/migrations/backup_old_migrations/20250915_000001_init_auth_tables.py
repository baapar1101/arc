from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from datetime import datetime

# revision identifiers, used by Alembic.
revision = "20250915_000001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"users",
		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
		sa.Column("email", sa.String(length=255), nullable=True),
		sa.Column("mobile", sa.String(length=32), nullable=True),
		sa.Column("first_name", sa.String(length=100), nullable=True),
		sa.Column("last_name", sa.String(length=100), nullable=True),
		sa.Column("password_hash", sa.String(length=255), nullable=False),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("1")),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP")),
	)
	op.create_index("ix_users_email", "users", ["email"], unique=True)
	op.create_index("ix_users_mobile", "users", ["mobile"], unique=True)

	op.create_table(
		"api_keys",
		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
		sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
		sa.Column("key_hash", sa.String(length=128), nullable=False),
		sa.Column("key_type", sa.String(length=16), nullable=False),
		sa.Column("name", sa.String(length=100), nullable=True),
		sa.Column("scopes", sa.String(length=500), nullable=True),
		sa.Column("device_id", sa.String(length=100), nullable=True),
		sa.Column("user_agent", sa.String(length=255), nullable=True),
		sa.Column("ip", sa.String(length=64), nullable=True),
		sa.Column("expires_at", sa.DateTime(), nullable=True),
		sa.Column("last_used_at", sa.DateTime(), nullable=True),
		sa.Column("revoked_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
	)
	op.create_index("ix_api_keys_key_hash", "api_keys", ["key_hash"], unique=True)
	op.create_index("ix_api_keys_user_id", "api_keys", ["user_id"], unique=False)

	op.create_table(
		"captchas",
		sa.Column("id", sa.String(length=40), primary_key=True),
		sa.Column("code_hash", sa.String(length=128), nullable=False),
		sa.Column("expires_at", sa.DateTime(), nullable=False),
		sa.Column("attempts", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
	)

	op.create_table(
		"password_resets",
		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
		sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
		sa.Column("token_hash", sa.String(length=128), nullable=False),
		sa.Column("expires_at", sa.DateTime(), nullable=False),
		sa.Column("used_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
	)
	op.create_index("ix_password_resets_token_hash", "password_resets", ["token_hash"], unique=True)
	op.create_index("ix_password_resets_user_id", "password_resets", ["user_id"], unique=False)


def downgrade() -> None:
	from sqlalchemy import inspect
	bind = op.get_bind()
	inspector = inspect(bind)
	tables = set(inspector.get_table_names())
	
	if "password_resets" in tables:
		existing_indexes = {idx["name"] for idx in inspector.get_indexes("password_resets")}
		if "ix_password_resets_user_id" in existing_indexes:
			try:
				op.drop_index("ix_password_resets_user_id", table_name="password_resets")
			except Exception:
				pass
		if "ix_password_resets_token_hash" in existing_indexes:
			try:
				op.drop_index("ix_password_resets_token_hash", table_name="password_resets")
			except Exception:
				pass
		try:
			op.drop_table("password_resets")
		except Exception:
			pass

	if "captchas" in tables:
		try:
			op.drop_table("captchas")
		except Exception:
			pass

	if "api_keys" in tables:
		existing_indexes = {idx["name"] for idx in inspector.get_indexes("api_keys")}
		if "ix_api_keys_user_id" in existing_indexes:
			try:
				op.drop_index("ix_api_keys_user_id", table_name="api_keys")
			except Exception:
				pass
		if "ix_api_keys_key_hash" in existing_indexes:
			try:
				op.drop_index("ix_api_keys_key_hash", table_name="api_keys")
			except Exception:
				pass
		try:
			op.drop_table("api_keys")
		except Exception:
			pass

	if "users" in tables:
		existing_indexes = {idx["name"] for idx in inspector.get_indexes("users")}
		if "ix_users_mobile" in existing_indexes:
			try:
				op.drop_index("ix_users_mobile", table_name="users")
			except Exception:
				pass
		if "ix_users_email" in existing_indexes:
			try:
				op.drop_index("ix_users_email", table_name="users")
			except Exception:
				pass
		try:
			op.drop_table("users")
		except Exception:
			pass


