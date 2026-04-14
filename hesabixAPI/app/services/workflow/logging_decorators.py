"""
Logging Decorators برای Workflow System
این ماژول شامل decoratorهایی برای لاگ خودکار اجرای actions و triggers است
"""

import logging
import time
import traceback
from functools import wraps
from typing import Any, Callable, Dict

logger = logging.getLogger(__name__)


def log_action_execution(func: Callable) -> Callable:
    """
    Decorator برای لاگ خودکار اجرای actions
    
    این decorator به صورت خودکار:
    - زمان شروع و پایان action را ثبت می‌کند
    - مدت زمان اجرا را محاسبه می‌کند
    - خطاها را با stack trace کامل لاگ می‌کند
    - اطلاعات correlation_id را اضافه می‌کند
    """
    @wraps(func)
    def wrapper(self, context: Dict[str, Any], config: Dict[str, Any], node_results: Dict[str, Any]) -> Dict[str, Any]:
        action_name = self.__class__.__name__
        start_time = time.time()
        
        # دریافت اطلاعات context
        correlation_id = context.get("correlation_id", "N/A")
        business_id = context.get("business_id", "N/A")
        execution_id = context.get("execution_id", "N/A")
        
        # لاگ شروع action
        logger.info(
            f"Starting action: {action_name}",
            extra={
                "action_name": action_name,
                "correlation_id": correlation_id,
                "business_id": business_id,
                "execution_id": execution_id,
                "config_keys": list(config.keys()) if config else [],
                "event": "action_start"
            }
        )
        
        try:
            # اجرای action
            result = func(self, context, config, node_results)
            
            # محاسبه مدت زمان
            duration_ms = (time.time() - start_time) * 1000
            
            # لاگ موفقیت
            logger.info(
                f"Action completed: {action_name}",
                extra={
                    "action_name": action_name,
                    "correlation_id": correlation_id,
                    "business_id": business_id,
                    "execution_id": execution_id,
                    "duration_ms": round(duration_ms, 2),
                    "success": result.get("success", True) if isinstance(result, dict) else True,
                    "event": "action_complete"
                }
            )
            
            return result
            
        except Exception as e:
            # محاسبه مدت زمان
            duration_ms = (time.time() - start_time) * 1000
            
            # لاگ خطا با جزئیات کامل
            logger.error(
                f"Action failed: {action_name}",
                extra={
                    "action_name": action_name,
                    "correlation_id": correlation_id,
                    "business_id": business_id,
                    "execution_id": execution_id,
                    "duration_ms": round(duration_ms, 2),
                    "error_type": type(e).__name__,
                    "error_message": str(e),
                    "stack_trace": traceback.format_exc(),
                    "event": "action_error"
                },
                exc_info=True
            )
            
            # بازگشت خطا به workflow engine
            raise
    
    return wrapper


def log_trigger_execution(func: Callable) -> Callable:
    """
    Decorator برای لاگ خودکار اجرای triggers
    
    این decorator به صورت خودکار:
    - زمان شروع و پایان trigger را ثبت می‌کند
    - مدت زمان اجرا را محاسبه می‌کند
    - خطاها را با stack trace کامل لاگ می‌کند
    """
    @wraps(func)
    def wrapper(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        trigger_name = self.__class__.__name__
        start_time = time.time()
        
        # دریافت اطلاعات context
        correlation_id = context.get("correlation_id", "N/A")
        business_id = context.get("business_id", "N/A")
        execution_id = context.get("execution_id", "N/A")
        
        # لاگ شروع trigger
        logger.info(
            f"Starting trigger: {trigger_name}",
            extra={
                "trigger_name": trigger_name,
                "correlation_id": correlation_id,
                "business_id": business_id,
                "execution_id": execution_id,
                "trigger_type": config.get("trigger_type"),
                "event": "trigger_start"
            }
        )
        
        try:
            # اجرای trigger
            result = func(self, context, config)
            
            # محاسبه مدت زمان
            duration_ms = (time.time() - start_time) * 1000
            
            # لاگ موفقیت
            logger.info(
                f"Trigger completed: {trigger_name}",
                extra={
                    "trigger_name": trigger_name,
                    "correlation_id": correlation_id,
                    "business_id": business_id,
                    "execution_id": execution_id,
                    "duration_ms": round(duration_ms, 2),
                    "result_keys": list(result.keys()) if isinstance(result, dict) else [],
                    "event": "trigger_complete"
                }
            )
            
            return result
            
        except Exception as e:
            # محاسبه مدت زمان
            duration_ms = (time.time() - start_time) * 1000
            
            # لاگ خطا
            logger.error(
                f"Trigger failed: {trigger_name}",
                extra={
                    "trigger_name": trigger_name,
                    "correlation_id": correlation_id,
                    "business_id": business_id,
                    "execution_id": execution_id,
                    "duration_ms": round(duration_ms, 2),
                    "error_type": type(e).__name__,
                    "error_message": str(e),
                    "stack_trace": traceback.format_exc(),
                    "event": "trigger_error"
                },
                exc_info=True
            )
            
            raise
    
    return wrapper


def log_node_execution(node_type: str):
    """
    Decorator factory برای لاگ خودکار اجرای انواع مختلف nodeها
    
    Args:
        node_type: نوع node (action, trigger, condition, loop)
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            start_time = time.time()
            
            logger.debug(
                f"Executing {node_type} node",
                extra={
                    "node_type": node_type,
                    "event": f"{node_type}_start"
                }
            )
            
            try:
                result = func(*args, **kwargs)
                duration_ms = (time.time() - start_time) * 1000
                
                logger.debug(
                    f"{node_type} node completed",
                    extra={
                        "node_type": node_type,
                        "duration_ms": round(duration_ms, 2),
                        "event": f"{node_type}_complete"
                    }
                )
                
                return result
                
            except Exception as e:
                duration_ms = (time.time() - start_time) * 1000
                
                logger.error(
                    f"{node_type} node failed",
                    extra={
                        "node_type": node_type,
                        "duration_ms": round(duration_ms, 2),
                        "error_type": type(e).__name__,
                        "error_message": str(e),
                        "event": f"{node_type}_error"
                    },
                    exc_info=True
                )
                
                raise
        
        return wrapper
    return decorator


