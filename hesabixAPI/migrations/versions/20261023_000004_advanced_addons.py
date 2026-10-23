"""Five specialist operational add-on workspaces (no automatic financial posts)."""
from alembic import op
import sqlalchemy as sa
revision='20261023_000004_advanced_addons'
down_revision='20261023_000003_sepidar_plugins'
branch_labels=None
depends_on=None


def upgrade():
    from adapters.db.models.advanced_plugins import AdvancedPluginSetting,AdvancedPluginRecord,AdvancedPluginAudit
    bind=op.get_bind()
    for model in (AdvancedPluginSetting,AdvancedPluginRecord,AdvancedPluginAudit):model.__table__.create(bind=bind,checkfirst=True)
    names=[('fixed_assets','دارایی ثابت و استهلاک','operations'),('contracting','پیمانکاری و صورت‌وضعیت','operations'),
        ('payroll_calendar_tax','تقویم حقوق، مرخصی و مالیات تاریخ‌دار','hr_payroll'),
        ('conditional_pricing','قیمت‌گذاری شرطی و چندبعدی','sales'),('inventory_trace_cost','ردیابی بچ و بهای لایه‌ای انبار','product_management')]
    for code,name,category in names:
        bind.execute(sa.text('''INSERT INTO marketplace_plugins(code,name,description,category,is_active,trial_allowed,created_at,updated_at)
            VALUES(:code,:name,:description,:category,true,false,NOW(),NOW()) ON CONFLICT(code) DO NOTHING'''),
            dict(code=code,name=name,description='فضای کاری تخصصی، تنظیمات مستقل و اتصال لایو سپیدار؛ تعرفه توسط مدیر بازار تعیین می‌شود.',category=category))


def downgrade():
    # Marketplace identities/licenses may have been used; do not destroy them.
    for table in ['advanced_plugin_audits','advanced_plugin_records','advanced_plugin_settings']:op.drop_table(table)
