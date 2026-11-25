"""Join upstream schema changes with platform task and Sepidar migrations.

This revision only joins the graph. It does not issue financial documents,
reconcile source deletions, enable plugins, or change business settings.
"""

revision = "20261125_000001_safe_upstream"
down_revision = (
    "20260929_000006_task_comment_mentions",
    "20261101_000001_sepidar_reconciliation",
    "20261123_000002_product_measurement_units",
)
branch_labels = None
depends_on = None


def upgrade():
    pass


def downgrade():
    pass
