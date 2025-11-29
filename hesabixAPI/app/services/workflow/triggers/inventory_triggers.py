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
                    "description": "شناسه محصول (اختیاری - اگر مشخص نشود برای همه محصولات)",
                    "required": False
                },
                "warehouse_id": {
                    "type": "integer",
                    "description": "شناسه انبار (اختیاری)",
                    "required": False
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

