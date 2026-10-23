"""Manager-approved, atomic and idempotent specialist financial journals."""
revision='20261023_000005_addon_postings'
down_revision='20261023_000004_advanced_addons'
branch_labels=None
depends_on=None

def upgrade():
    from alembic import op
    from adapters.db.models.advanced_plugins import AdvancedPluginPostingConfig,AdvancedPluginPosting
    for model in (AdvancedPluginPostingConfig,AdvancedPluginPosting):
        model.__table__.create(op.get_bind(),checkfirst=True)

def downgrade():
    # Journal history must never be discarded by an automated rollback.
    raise RuntimeError('Financial posting history is retained; roll back code, not the journal tables.')
