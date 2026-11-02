"""
Triggerهای مربوط به موجودی
"""

from typing import Any, Dict
from app.services.workflow.triggers.base_trigger import BaseTrigger


class InventoryLowTrigger(BaseTrigger):
    """Trigger برای موجودی کم"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "موجودی کم",
            "description": "زمانی که موجودی یک محصول کمتر از حد مشخص می‌شود",
            "config_schema": {
                "product_id": {
                    "type": "integer",
                    "description": "محصول (اختیاری - خالی = همه محصولات)",
                    "required": False,
                    "ui_type": "product_selector",
                    "ui_config": {"business_scoped": True}
                },
                "warehouse_id": {
                    "type": "integer",
                    "description": "انبار (اختیاری)",
                    "required": False,
                    "ui_type": "warehouse_selector",
                    "ui_config": {"business_scoped": True}
                }
            }
        }
    
    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        data = super().execute(context, config)
        
        # فیلتر بر اساس محصول
        product_id = config.get("product_id")
        if product_id is not None:
            if data.get("product_id") != product_id:
                return {}
        
        # فیلتر بر اساس انبار
        warehouse_id = config.get("warehouse_id")
        if warehouse_id is not None:
            if data.get("warehouse_id") != warehouse_id:
                return {}
        
        return data


class InventoryExpiresSoonTrigger(BaseTrigger):
    """Trigger برای لات نزدیک به انقضا یا منقضی"""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "نزدیک به انقضا",
            "description": "زمانی که لات کالا به تاریخ هشدار یا انقضا می‌رسد",
            "config_schema": {
                "product_id": {
                    "type": "integer",
                    "description": "محصول (اختیاری)",
                    "required": False,
                    "ui_type": "product_selector",
                    "ui_config": {"business_scoped": True},
                }
            },
        }

    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        data = super().execute(context, config)
        product_id = config.get("product_id")
        if product_id is not None and data.get("product_id") != product_id:
            return {}
        return data

