"""init schema

Revision ID: 20250101_000000
Revises: 
Create Date: 2025-01-01 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '20250101_000000'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Import the modular migration
from migrations.versions.init_schema import upgrade as init_schema_upgrade, downgrade as init_schema_downgrade


def upgrade() -> None:
    init_schema_upgrade()


def downgrade() -> None:
    init_schema_downgrade()

