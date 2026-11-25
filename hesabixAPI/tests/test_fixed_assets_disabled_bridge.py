"""A new native module cannot bypass an existing manager-disabled policy."""
from adapters.db.models.advanced_plugins import AdvancedPluginSetting
from app.core import fixed_assets_plugin_dependency as dependency
from tests.test_sepidar_native_projection import native_db


def test_native_entitlement_respects_explicit_disabled_specialist(native_db, monkeypatch):
    db = native_db
    monkeypatch.setattr(dependency, 'is_plugin_active', lambda *a: True)
    policy = AdvancedPluginSetting(
        business_id=1, plugin_code='fixed_assets', enabled=False, sync_enabled=False,
    )
    db.add(policy)
    db.flush()
    assert dependency.check_fixed_assets_plugin_active(db, 1) is False
    policy.enabled = True
    db.flush()
    assert dependency.check_fixed_assets_plugin_active(db, 1) is True
