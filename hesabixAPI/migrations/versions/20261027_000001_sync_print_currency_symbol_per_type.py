"""Inherit show_currency_symbol from general print settings onto per-type rows.

Enabling the flag on document_type='all' left existing per-type rows at the
column default (false), so sales/purchase PDFs omitted the currency symbol.
"""

from __future__ import annotations

from alembic import op

revision = "20261027_000001_sync_print_currency_symbol_per_type"
down_revision = "20261026_000001_business_print_settings_currency_symbol"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.execute(
		"""
		UPDATE business_print_settings AS child
		SET show_currency_symbol = TRUE,
		    updated_at = NOW()
		FROM business_print_settings AS parent
		WHERE parent.business_id = child.business_id
		  AND parent.document_type = 'all'
		  AND child.document_type <> 'all'
		  AND parent.show_currency_symbol IS TRUE
		  AND child.show_currency_symbol IS FALSE
		"""
	)


def downgrade() -> None:
	# One-way data repair; previous per-type defaults cannot be reconstructed.
	pass
