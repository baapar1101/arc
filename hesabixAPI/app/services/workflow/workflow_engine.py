"""
موتور اجرای Workflow
این موتور workflowها را اجرا می‌کند و nodeها را به ترتیب پردازش می‌کند
"""

import json
import logging
import re
import threading
import time
import traceback
import uuid
from typing import Any, Dict, List, Optional
from datetime import datetime

from sqlalchemy.orm import Session
from simpleeval import SimpleEval

from adapters.db.models.workflow import (
    Workflow,
    WorkflowExecution,
    WorkflowExecutionStatus,
    WorkflowLog,
    WorkflowLogLevel,
)
from app.services.workflow.trigger_registry import TriggerRegistry
from app.services.workflow.action_registry import ActionRegistry

logger = logging.getLogger(__name__)


class WorkflowEngine:
    """موتور اجرای workflow"""
    
    # کلاس-سطح cache برای نتایج nodeها
    _result_cache: Dict[str, tuple] = {}  # cache_key -> (result, timestamp)
    _cache_lock = threading.Lock()  # برای thread safety
    
    def __init__(self, db: Session, business_id: int, user_id: Optional[int] = None):
        self.db = db
        self.business_id = business_id
        self.user_id = user_id
        self.correlation_id = str(uuid.uuid4())  # اضافه کردن correlation_id برای trace کردن
        self.trigger_registry = TriggerRegistry()
        self.action_registry = ActionRegistry()
        self.cache_enabled = True
        self.cache_ttl = 300  # 5 minutes default
    
    def execute_workflow(
        self,
        workflow: Workflow,
        trigger_data: Optional[Dict[str, Any]] = None
    ) -> WorkflowExecution:
        """
        اجرای یک workflow
        
        Args:
            workflow: workflow برای اجرا
            trigger_data: داده‌های trigger که workflow را فعال کرده
        
        Returns:
            WorkflowExecution: نتیجه اجرا
        """
        # ایجاد execution record
        execution = WorkflowExecution(
            workflow_id=workflow.id,
            status=WorkflowExecutionStatus.PENDING,
            trigger_data=trigger_data or {},
            execution_data={}
        )
        self.db.add(execution)
        self.db.commit()
        self.db.refresh(execution)
        
        workflow_start_time = time.time()  # شروع زمان‌سنجی کلی
        
        try:
            execution.status = WorkflowExecutionStatus.RUNNING
            execution.started_at = datetime.utcnow()
            self.db.commit()
            
            self._log(
                execution,
                WorkflowLogLevel.INFO,
                f"Workflow '{workflow.name}' started",
                {
                    "workflow_id": workflow.id,
                    "workflow_name": workflow.name,
                    "correlation_id": self.correlation_id,
                    "business_id": self.business_id,
                    "user_id": self.user_id,
                    "trigger_data_preview": str(trigger_data)[:200] if trigger_data else None
                }
            )
            
            # اجرای workflow
            result = self._execute_workflow_internal(workflow, execution, trigger_data or {})
            
            execution.status = WorkflowExecutionStatus.COMPLETED
            execution.completed_at = datetime.utcnow()
            execution.execution_data = result
            self.db.commit()
            
            # محاسبه مدت زمان کلی
            total_duration_ms = (time.time() - workflow_start_time) * 1000
            
            self._log(
                execution,
                WorkflowLogLevel.INFO,
                f"Workflow '{workflow.name}' completed successfully",
                {
                    "workflow_id": workflow.id,
                    "workflow_name": workflow.name,
                    "correlation_id": self.correlation_id,
                    "total_duration_ms": round(total_duration_ms, 2),
                    "total_nodes_executed": len(result.get("executed_nodes", [])),
                    "success": True
                }
            )
            
            # لاگ‌گیری اجرای موفق workflow در activity log
            try:
                from app.services.activity_log_service import log_activity
                log_activity(
                    db=self.db,
                    user_id=self.user_id,
                    business_id=self.business_id,
                    category="workflow",
                    action="execute",
                    entity_type="workflow",
                    entity_id=workflow.id,
                    description=f"اجرای موفق گردش کار '{workflow.name}'",
                    extra_info={
                        "workflow_id": workflow.id,
                        "workflow_name": workflow.name,
                        "execution_id": execution.id,
                        "duration_ms": round(total_duration_ms, 2),
                        "nodes_executed": len(result.get("executed_nodes", []))
                    }
                )
                self.db.commit()
            except Exception as e:
                logger.warning(f"Failed to log workflow execution activity: {e}")
            
        except Exception as e:
            total_duration_ms = (time.time() - workflow_start_time) * 1000
            
            logger.error(f"Workflow execution failed: {e}", exc_info=True)
            
            # Rollback transaction در صورت خطا
            try:
                self.db.rollback()
            except Exception as rollback_error:
                logger.error(f"Error during rollback: {rollback_error}", exc_info=True)
            
            # ایجاد execution record جدید برای خطا
            try:
                execution.status = WorkflowExecutionStatus.FAILED
                execution.completed_at = datetime.utcnow()
                execution.error_message = str(e)
                self.db.commit()
            except Exception as commit_error:
                logger.error(f"Error committing failed execution: {commit_error}", exc_info=True)
                try:
                    self.db.rollback()
                except Exception:
                    pass
            
            self._log(
                execution,
                WorkflowLogLevel.ERROR,
                f"Workflow '{workflow.name}' failed: {str(e)}",
                {
                    "workflow_id": workflow.id,
                    "workflow_name": workflow.name,
                    "correlation_id": self.correlation_id,
                    "total_duration_ms": round(total_duration_ms, 2),
                    "error_type": type(e).__name__,
                    "error_message": str(e),
                    "stack_trace": traceback.format_exc(),
                    "success": False
                }
            )
            
            # لاگ‌گیری اجرای ناموفق workflow در activity log
            try:
                from app.services.activity_log_service import log_activity
                log_activity(
                    db=self.db,
                    user_id=self.user_id,
                    business_id=self.business_id,
                    category="workflow",
                    action="execute_failed",
                    entity_type="workflow",
                    entity_id=workflow.id,
                    description=f"خطا در اجرای گردش کار '{workflow.name}': {str(e)[:100]}",
                    extra_info={
                        "workflow_id": workflow.id,
                        "workflow_name": workflow.name,
                        "execution_id": execution.id,
                        "duration_ms": round(total_duration_ms, 2),
                        "error_type": type(e).__name__,
                        "error_message": str(e)
                    }
                )
                self.db.commit()
            except Exception as log_error:
                logger.warning(f"Failed to log workflow execution failure activity: {log_error}")
        
        return execution
    
    def _execute_workflow_internal(
        self,
        workflow: Workflow,
        execution: WorkflowExecution,
        trigger_data: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        اجرای داخلی workflow
        """
        workflow_data = workflow.workflow_data
        nodes = workflow_data.get("nodes", [])
        connections = workflow_data.get("connections", [])
        
        # پیدا کردن trigger node
        trigger_node = None
        for node in nodes:
            if node.get("type") == "trigger":
                trigger_node = node
                break
        
        if not trigger_node:
            raise ValueError("No trigger node found in workflow")
        
        # اجرای trigger و دریافت داده‌های اولیه
        context = {
            "business_id": self.business_id,
            "user_id": self.user_id,
            "trigger_data": trigger_data,
            "execution_id": execution.id,
            "workflow_id": workflow.id,
            "correlation_id": self.correlation_id,  # اضافه کردن correlation_id
            "db": self.db,  # اضافه کردن db برای استفاده در actions
        }
        
        # اجرای nodeها به ترتیب
        executed_nodes = set()
        node_results = {}
        
        # شروع از trigger node
        queue = [trigger_node["id"]]
        
        while queue:
            node_id = queue.pop(0)
            
            if node_id in executed_nodes:
                continue
            
            # پیدا کردن node
            node = next((n for n in nodes if n["id"] == node_id), None)
            if not node:
                continue
            
            # اجرای node
            node_start_time = time.time()  # شروع زمان‌سنجی
            try:
                result = self._execute_node(node, context, node_results)
                node_results[node_id] = result
                executed_nodes.add(node_id)
                
                # محاسبه مدت زمان اجرا
                node_duration_ms = (time.time() - node_start_time) * 1000
                
                self._log(
                    execution,
                    WorkflowLogLevel.INFO,
                    f"Node '{node.get('label', node_id)}' executed successfully",
                    {
                        "node_id": node_id,
                        "node_type": node.get("type"),
                        "node_label": node.get("label"),
                        "duration_ms": round(node_duration_ms, 2),
                        "correlation_id": self.correlation_id,
                        "result_preview": str(result)[:200] if result else None,  # فقط 200 کاراکتر اول
                        "success": True
                    }
                )
                
                # پیدا کردن nodeهای بعدی (برای condition: فقط شاخه منطبق با نتیجه)
                condition_result = result if node.get("type") == "condition" else None
                next_nodes = self._get_next_nodes(
                    node_id, connections, condition_result=condition_result
                )
                queue.extend(next_nodes)
                
            except Exception as e:
                # محاسبه مدت زمان اجرا حتی در صورت خطا
                node_duration_ms = (time.time() - node_start_time) * 1000
                
                logger.error(f"Node execution failed: {e}", exc_info=True)
                self._log(
                    execution,
                    WorkflowLogLevel.ERROR,
                    f"Node '{node.get('label', node_id)}' failed: {str(e)}",
                    {
                        "node_id": node_id,
                        "node_type": node.get("type"),
                        "node_label": node.get("label"),
                        "duration_ms": round(node_duration_ms, 2),
                        "correlation_id": self.correlation_id,
                        "error_type": type(e).__name__,
                        "error_message": str(e),
                        "stack_trace": traceback.format_exc(),  # اضافه کردن stack trace کامل
                        "success": False
                    }
                )
                
                # بررسی error handling strategy از workflow config
                workflow_config = workflow.workflow_data.get("config", {})
                error_handling = workflow_config.get("error_handling", {})
                strategy = error_handling.get("strategy", "fail_fast")
                
                if strategy == "fail_fast":
                    # متوقف کردن workflow
                    raise
                elif strategy == "continue":
                    # ادامه دادن workflow
                    node_results[node_id] = {"success": False, "error": str(e)}
                    executed_nodes.add(node_id)
                    
                    # اجرای fallback action اگر وجود داشته باشد
                    fallback_action = error_handling.get("fallback_action", {})
                    if fallback_action.get("enabled", False):
                        try:
                            self._execute_fallback_action(
                                fallback_action, context, node_results, node, e, execution
                            )
                        except Exception as fallback_error:
                            logger.error(f"Fallback action failed: {fallback_error}", exc_info=True)
                    
                    # پیدا کردن nodeهای بعدی و ادامه
                    condition_result = node_results.get(node_id, {}).get("result") if node.get("type") == "condition" else None
                    next_nodes = self._get_next_nodes(
                        node_id, connections, condition_result=condition_result
                    )
                    queue.extend(next_nodes)
                elif strategy == "retry":
                    # تلاش مجدد
                    retry_policy = error_handling.get("retry_policy", {})
                    max_attempts = retry_policy.get("max_attempts", 3)
                    initial_delay = retry_policy.get("initial_delay", 1.0)
                    max_delay = retry_policy.get("max_delay", 60.0)
                    exponential_backoff = retry_policy.get("exponential_backoff", True)
                    
                    retry_success = False
                    last_exception = e
                    
                    for attempt in range(1, max_attempts + 1):
                        if attempt > 1:
                            if exponential_backoff:
                                delay = min(initial_delay * (2 ** (attempt - 2)), max_delay)
                            else:
                                delay = initial_delay
                            
                            logger.info(f"Retrying node '{node.get('label', node_id)}' (attempt {attempt}/{max_attempts}) after {delay}s...")
                            time.sleep(delay)
                        
                        try:
                            result = self._execute_node(node, context, node_results)
                            node_results[node_id] = result
                            executed_nodes.add(node_id)
                            retry_success = True
                            
                            self._log(
                                execution,
                                WorkflowLogLevel.INFO,
                                f"Node '{node.get('label', node_id)}' executed successfully after {attempt} attempt(s)",
                                {"node_id": node_id, "result": result, "attempt": attempt}
                            )
                            break
                        except Exception as retry_error:
                            last_exception = retry_error
                            logger.warning(f"Retry attempt {attempt} failed: {retry_error}")
                    
                    if not retry_success:
                        # بعد از تمام تلاش‌ها، بر اساس continue_on_error تصمیم بگیر
                        if error_handling.get("continue_on_error", False):
                            node_results[node_id] = {"success": False, "error": str(last_exception)}
                            executed_nodes.add(node_id)
                            next_nodes = self._get_next_nodes(node_id, connections)
                            queue.extend(next_nodes)
                        else:
                            raise last_exception
                    else:
                        # پیدا کردن nodeهای بعدی
                        condition_result = result if node.get("type") == "condition" else None
                        next_nodes = self._get_next_nodes(
                            node_id, connections, condition_result=condition_result
                        )
                        queue.extend(next_nodes)
        
        # حذف db از context قبل از ذخیره‌سازی (چون قابل serialize نیست)
        context_for_storage = {k: v for k, v in context.items() if k != "db"}
        
        return {
            "node_results": node_results,
            "executed_nodes": list(executed_nodes),
            "context": context_for_storage
        }
    
    def _execute_node(
        self,
        node: Dict[str, Any],
        context: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> Any:
        """
        اجرای یک node
        """
        node_id = node.get("id")
        node_type = node.get("type")
        node_config = node.get("config", {})
        
        # بررسی cache
        cache_enabled = node_config.get("cache_enabled", self.cache_enabled)
        if cache_enabled and node_type in ["action", "condition"]:
            cache_key = self._get_cache_key(node, context, node_results)
            cached_result = self._get_cached_result(cache_key)
            if cached_result is not None:
                logger.debug(f"Using cached result for node '{node_id}'")
                return cached_result
        
        # اجرای node
        if node_type == "trigger":
            # اجرای trigger
            trigger_type = node_config.get("trigger_type")
            trigger_handler = self.trigger_registry.get_handler(trigger_type)
            if not trigger_handler:
                raise ValueError(f"Trigger handler not found: {trigger_type}")
            
            result = trigger_handler.execute(context, node_config)
        
        elif node_type == "action":
            # اجرای action
            action_type = node_config.get("action_type")
            action_handler = self.action_registry.get_handler(action_type)
            if not action_handler:
                raise ValueError(f"Action handler not found: {action_type}")
            
            result = action_handler.execute(context, node_config, node_results)
        
        elif node_type == "condition":
            # اجرای شرط
            result = self._execute_condition(node, context, node_results)
        
        elif node_type == "loop":
            # اجرای حلقه
            result = self._execute_loop(node, context, node_results)
        
        else:
            raise ValueError(f"Unknown node type: {node_type}")
        
        # ذخیره در cache
        if cache_enabled and node_type in ["action", "condition"]:
            cache_key = self._get_cache_key(node, context, node_results)
            cache_ttl = node_config.get("cache_ttl", self.cache_ttl)
            self._set_cached_result(cache_key, result, cache_ttl)
        
        return result
    
    def _get_cache_key(
        self,
        node: Dict[str, Any],
        context: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> str:
        """
        ساخت کلید cache برای node
        """
        node_id = node.get("id")
        node_type = node.get("type")
        node_config = node.get("config", {})
        
        # ساخت کلید بر اساس node id و config (بدون مقادیر dynamic)
        cache_config = {}
        for key, value in node_config.items():
            if key not in ["cache_enabled", "cache_ttl"]:
                # اگر مقدار یک reference است، آن را حذف کن
                if not (isinstance(value, str) and value.startswith("$")):
                    cache_config[key] = value
        
        import hashlib
        import json
        
        cache_data = {
            "node_id": node_id,
            "node_type": node_type,
            "config": cache_config,
            "business_id": self.business_id,
        }
        
        cache_str = json.dumps(cache_data, sort_keys=True)
        cache_key = f"workflow_node:{hashlib.md5(cache_str.encode()).hexdigest()}"
        
        return cache_key
    
    def _get_cached_result(self, cache_key: str) -> Optional[Any]:
        """
        دریافت نتیجه از cache (thread-safe)
        """
        with WorkflowEngine._cache_lock:
            if cache_key not in WorkflowEngine._result_cache:
                return None
            
            result, timestamp = WorkflowEngine._result_cache[cache_key]
            
            # بررسی expiration
            if time.time() - timestamp > self.cache_ttl:
                del WorkflowEngine._result_cache[cache_key]
                return None
            
            return result
    
    def _set_cached_result(self, cache_key: str, result: Any, ttl: float):
        """
        ذخیره نتیجه در cache (thread-safe)
        """
        with WorkflowEngine._cache_lock:
            WorkflowEngine._result_cache[cache_key] = (result, time.time())
            
            # پاکسازی cache قدیمی (هر 1000 مورد یکبار)
            if len(WorkflowEngine._result_cache) > 1000:
                self._cleanup_cache()
    
    def _cleanup_cache(self):
        """
        پاکسازی cache منقضی شده (thread-safe)
        """
        # این متد باید از داخل _set_cached_result که lock دارد فراخوانی شود
        # اما برای اطمینان، lock را چک می‌کنیم
        current_time = time.time()
        keys_to_remove = []
        
        for cache_key, (result, timestamp) in WorkflowEngine._result_cache.items():
            if current_time - timestamp > self.cache_ttl:
                keys_to_remove.append(cache_key)
        
        for key in keys_to_remove:
            del WorkflowEngine._result_cache[key]
        
        logger.debug(f"Cleaned up {len(keys_to_remove)} expired cache entries")
    
    def _execute_condition(
        self,
        node: Dict[str, Any],
        context: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> bool:
        """
        اجرای شرط
        """
        config = node.get("config", {})
        condition_type = config.get("condition_type", "simple")
        on_error = config.get("on_error", "fail")
        
        try:
            if condition_type == "simple":
                return self._execute_simple_condition(config, context, node_results)
            elif condition_type == "complex":
                return self._execute_complex_condition(config, context, node_results)
            elif condition_type == "expression":
                return self._execute_expression_condition(config, context, node_results)
            else:
                raise ValueError(f"Unknown condition type: {condition_type}")
        except Exception as e:
            logger.error(f"Condition evaluation failed: {e}", exc_info=True)
            if on_error == "fail":
                raise
            elif on_error == "false":
                return False
            elif on_error == "true":
                return True
            else:
                raise
    
    def _execute_simple_condition(
        self,
        config: Dict[str, Any],
        context: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> bool:
        """اجرای شرط ساده"""
        left_value = WorkflowEngine._resolve_value_static(config.get("left_value"), context, node_results)
        right_value = WorkflowEngine._resolve_value_static(config.get("right_value"), context, node_results)
        operator = config.get("operator", "==")
        case_sensitive = config.get("case_sensitive", True)
        
        # برای عملگرهای رشته‌ای
        if operator in ["contains", "not_contains", "starts_with", "ends_with"]:
            left_str = str(left_value)
            right_str = str(right_value)
            
            if not case_sensitive:
                left_str = left_str.lower()
                right_str = right_str.lower()
            
            if operator == "contains":
                return right_str in left_str
            elif operator == "not_contains":
                return right_str not in left_str
            elif operator == "starts_with":
                return left_str.startswith(right_str)
            elif operator == "ends_with":
                return left_str.endswith(right_str)
        
        # برای عملگرهای آرایه
        if operator == "in":
            if isinstance(right_value, list):
                return left_value in right_value
            return False
        elif operator == "not_in":
            if isinstance(right_value, list):
                return left_value not in right_value
            return True
        
        # برای null checking
        if operator == "is_null":
            return left_value is None
        elif operator == "is_not_null":
            return left_value is not None
        
        # مقایسه‌های عددی و رشته‌ای استاندارد
        try:
            if operator == "==":
                return left_value == right_value
            elif operator == "!=":
                return left_value != right_value
            elif operator == ">":
                return float(left_value) > float(right_value)
            elif operator == "<":
                return float(left_value) < float(right_value)
            elif operator == ">=":
                return float(left_value) >= float(right_value)
            elif operator == "<=":
                return float(left_value) <= float(right_value)
        except (ValueError, TypeError):
            # اگر تبدیل به عدد ممکن نبود، مقایسه رشته‌ای انجام بده
            if operator in [">", "<", ">=", "<="]:
                return str(left_value) > str(right_value) if operator == ">" else \
                       str(left_value) < str(right_value) if operator == "<" else \
                       str(left_value) >= str(right_value) if operator == ">=" else \
                       str(left_value) <= str(right_value)
            raise
        
        raise ValueError(f"Unknown operator: {operator}")
    
    def _execute_complex_condition(
        self,
        config: Dict[str, Any],
        context: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> bool:
        """اجرای شرط پیچیده (AND/OR)"""
        logical_operator = config.get("logical_operator", "AND")
        conditions = config.get("conditions", [])
        
        if not conditions:
            return True
        
        results = []
        for condition_config in conditions:
            # هر شرط به صورت ساده اجرا می‌شود
            result = self._execute_simple_condition(condition_config, context, node_results)
            results.append(result)
        
        if logical_operator == "AND":
            return all(results)
        elif logical_operator == "OR":
            return any(results)
        else:
            raise ValueError(f"Unknown logical operator: {logical_operator}")
    
    def _execute_expression_condition(
        self,
        config: Dict[str, Any],
        context: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> bool:
        """اجرای شرط با expression (JavaScript-like) - استفاده از simpleeval برای امنیت"""
        expression = config.get("expression")
        if not expression:
            return False
        
        try:
            # استفاده از SimpleEval برای evaluation امن expression
            # SimpleEval فقط عملیات‌های مجاز را اجرا می‌کند و از اجرای کد دلخواه جلوگیری می‌کند
            evaluator = SimpleEval(
                names={
                    "context": context,
                    "node_results": node_results,
                    "resolve": lambda v: WorkflowEngine._resolve_value_static(v, context, node_results),
                },
                functions={
                    # اضافه کردن توابع مجاز
                    "len": len,
                    "str": str,
                    "int": int,
                    "float": float,
                    "bool": bool,
                    "abs": abs,
                    "min": min,
                    "max": max,
                    "sum": sum,
                },
                operators={
                    # فقط عملگرهای مجاز
                    "Add": lambda a, b: a + b,
                    "Sub": lambda a, b: a - b,
                    "Mult": lambda a, b: a * b,
                    "Div": lambda a, b: a / b if b != 0 else 0,
                    "Mod": lambda a, b: a % b if b != 0 else 0,
                    "Pow": lambda a, b: a ** b,
                    "Lt": lambda a, b: a < b,
                    "LtE": lambda a, b: a <= b,
                    "Gt": lambda a, b: a > b,
                    "GtE": lambda a, b: a >= b,
                    "Eq": lambda a, b: a == b,
                    "NotEq": lambda a, b: a != b,
                    "And": lambda a, b: a and b,
                    "Or": lambda a, b: a or b,
                    "Not": lambda a: not a,
                    "In": lambda a, b: a in b if hasattr(b, "__contains__") else False,
                    "NotIn": lambda a, b: a not in b if hasattr(b, "__contains__") else True,
                }
            )
            
            result = evaluator.eval(expression)
            return bool(result)
        except Exception as e:
            logger.error(f"Expression evaluation failed: {e}", exc_info=True)
            raise ValueError(f"Expression evaluation failed: {str(e)}")
    
    # token: $node_id یا $node_id.field — فقط ASCII برای id/field تا \w یونیکد با متن فارسی قاطی نشود
    _WORKFLOW_REF_TOKEN_RE = re.compile(
        r"\$([A-Za-z0-9_-]+(?:\.[A-Za-z0-9_]+)?)",
        re.ASCII,
    )

    @staticmethod
    def _lookup_node_result(node_results: Dict[str, Any], node_id: str) -> Any:
        """یافتن خروجی نود با سازگاری کلید str/int (JSON گاهی تفاوت ایجاد می‌کند)."""
        if not node_results or not node_id:
            return None
        if node_id in node_results:
            return node_results[node_id]
        for k, v in node_results.items():
            if str(k) == str(node_id):
                return v
        return None

    @staticmethod
    def _resolve_ref_token(
        ref: str,
        context: Dict[str, Any],
        node_results: Dict[str, Any],
    ) -> Any:
        """حل یک reference بدون پیشوند $ (مثلاً node_id یا node_id.field)."""
        if ref in context:
            return context[ref]
        whole = WorkflowEngine._lookup_node_result(node_results, ref)
        if whole is not None:
            return whole
        parts = ref.split(".")
        if len(parts) == 2:
            node_id, field = parts
            result = WorkflowEngine._lookup_node_result(node_results, node_id)
            if isinstance(result, dict) and field in result:
                return result[field]
            # تریگر گاهی {} برمی‌گرداند (مثلاً cooldown) اما trigger_data در context کامل است
            if isinstance(result, dict) and not result:
                td = context.get("trigger_data")
                if isinstance(td, dict) and field in td:
                    return td[field]
        return None

    @staticmethod
    def _resolve_value_static(
        value: Any,
        context: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> Any:
        """
        حل کردن مقدار (reference به نود دیگر یا چند reference داخل یک رشته).

        - اگر کل رشته دقیقاً یک token به شکل $node یا $node.field باشد، همان رفتار قبلی
          (نوع برگشتی می‌تواند غیر رشته باشد).
        - اگر رشته شامل متن ثابت و یک یا چند $node.field باشد، هر token با str(resolved)
          جایگزین می‌شود؛ token حل‌نشده بدون تغییر می‌ماند.
        """
        if not isinstance(value, str) or "$" not in value:
            return value

        m = WorkflowEngine._WORKFLOW_REF_TOKEN_RE.fullmatch(value)
        if m is not None:
            ref = m.group(1)
            resolved = WorkflowEngine._resolve_ref_token(ref, context, node_results)
            if resolved is not None:
                return resolved
            return value

        def _replace_token(match: re.Match) -> str:
            ref = match.group(1)
            resolved = WorkflowEngine._resolve_ref_token(ref, context, node_results)
            if resolved is None:
                return match.group(0)
            return str(resolved)

        return WorkflowEngine._WORKFLOW_REF_TOKEN_RE.sub(_replace_token, value)
    
    def _resolve_value(
        self,
        value: Any,
        context: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> Any:
        """Wrapper برای استفاده instance method"""
        return WorkflowEngine._resolve_value_static(value, context, node_results)
    
    def _execute_loop(
        self,
        node: Dict[str, Any],
        context: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> List[Any]:
        """
        اجرای حلقه
        """
        config = node.get("config", {})
        loop_type = config.get("loop_type")
        max_iterations = config.get("max_iterations", 1000)
        break_on_error = config.get("break_on_error", False)
        continue_on_error = config.get("continue_on_error", False)
        
        if loop_type == "for_each":
            return self._execute_for_each_loop(node, context, node_results, max_iterations, break_on_error, continue_on_error)
        elif loop_type == "for_range":
            return self._execute_for_range_loop(node, context, node_results, max_iterations, break_on_error, continue_on_error)
        elif loop_type == "while":
            return self._execute_while_loop(node, context, node_results, max_iterations, break_on_error, continue_on_error)
        else:
            raise ValueError(f"Unknown loop type: {loop_type}")
    
    def _execute_for_each_loop(
        self,
        node: Dict[str, Any],
        context: Dict[str, Any],
        node_results: Dict[str, Any],
        max_iterations: int,
        break_on_error: bool,
        continue_on_error: bool
    ) -> List[Any]:
        """اجرای حلقه for_each"""
        config = node.get("config", {})
        
        # دریافت منبع آیتم‌ها
        items_source = config.get("items_source")
        items = WorkflowEngine._resolve_value_static(items_source, context, node_results)
        
        if not isinstance(items, (list, tuple)):
            if items is None:
                items = []
            else:
                # اگر لیست نبود، یک لیست تک‌عضو بساز
                items = [items]
        
        item_variable = config.get("item_variable", "item")
        index_variable = config.get("index_variable", "index")
        parallel_execution = config.get("parallel_execution", False)
        max_parallel = config.get("max_parallel", 5)
        batch_size = config.get("batch_size")
        
        results = []
        
        if parallel_execution and len(items) > 1:
            # اجرای موازی
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor(max_workers=max_parallel) as executor:
                futures = []
                for index, item in enumerate(items[:max_iterations]):
                    future = executor.submit(
                        self._execute_loop_iteration,
                        node, context, node_results, item, index, item_variable, index_variable,
                        break_on_error, continue_on_error
                    )
                    futures.append(future)
                
                for future in concurrent.futures.as_completed(futures):
                    try:
                        result = future.result()
                        if result is not None:
                            results.append(result)
                    except Exception as e:
                        if break_on_error:
                            raise
                        elif not continue_on_error:
                            logger.error(f"Loop iteration failed: {e}", exc_info=True)
        else:
            # اجرای ترتیبی
            if batch_size and batch_size > 0:
                # پردازش دسته‌ای
                for batch_start in range(0, min(len(items), max_iterations), batch_size):
                    batch_end = min(batch_start + batch_size, len(items), max_iterations)
                    batch_items = items[batch_start:batch_end]
                    
                    for index, item in enumerate(batch_items, start=batch_start):
                        try:
                            result = self._execute_loop_iteration(
                                node, context, node_results, item, index,
                                item_variable, index_variable, break_on_error, continue_on_error
                            )
                            if result is not None:
                                results.append(result)
                        except Exception as e:
                            if break_on_error:
                                raise
                            elif not continue_on_error:
                                logger.error(f"Loop iteration failed: {e}", exc_info=True)
            else:
                # پردازش معمولی
                for index, item in enumerate(items[:max_iterations]):
                    try:
                        result = self._execute_loop_iteration(
                            node, context, node_results, item, index,
                            item_variable, index_variable, break_on_error, continue_on_error
                        )
                        if result is not None:
                            results.append(result)
                    except Exception as e:
                        if break_on_error:
                            raise
                        elif not continue_on_error:
                            logger.error(f"Loop iteration failed: {e}", exc_info=True)
        
        return results
    
    def _execute_for_range_loop(
        self,
        node: Dict[str, Any],
        context: Dict[str, Any],
        node_results: Dict[str, Any],
        max_iterations: int,
        break_on_error: bool,
        continue_on_error: bool
    ) -> List[Any]:
        """اجرای حلقه for_range"""
        config = node.get("config", {})
        
        start = WorkflowEngine._resolve_value_static(config.get("start", 0), context, node_results)
        end = WorkflowEngine._resolve_value_static(config.get("end"), context, node_results)
        step = WorkflowEngine._resolve_value_static(config.get("step", 1), context, node_results)
        index_variable = config.get("index_variable", "index")
        
        try:
            start = int(start)
            end = int(end)
            step = int(step)
        except (ValueError, TypeError):
            raise ValueError("start, end, and step must be integers")
        
        if step == 0:
            raise ValueError("step cannot be zero")
        
        results = []
        iteration_count = 0
        
        for index in range(start, end, step):
            if iteration_count >= max_iterations:
                logger.warning(f"Loop exceeded max_iterations ({max_iterations})")
                break
            
            try:
                # تنظیم متغیر index در context
                loop_context = context.copy()
                loop_context[index_variable] = index
                
                # در اینجا باید nodeهای داخل حلقه را اجرا کنیم
                # اما چون ما در سطح node هستیم، فقط مقدار index را برمی‌گردانیم
                # اجرای کامل loop در _execute_workflow_internal باید handle شود
                result = index
                results.append(result)
                iteration_count += 1
            except Exception as e:
                if break_on_error:
                    raise
                elif not continue_on_error:
                    logger.error(f"Loop iteration failed: {e}", exc_info=True)
        
        return results
    
    def _execute_while_loop(
        self,
        node: Dict[str, Any],
        context: Dict[str, Any],
        node_results: Dict[str, Any],
        max_iterations: int,
        break_on_error: bool,
        continue_on_error: bool
    ) -> List[Any]:
        """اجرای حلقه while"""
        config = node.get("config", {})
        condition = config.get("condition", {})
        
        results = []
        iteration_count = 0
        
        while iteration_count < max_iterations:
            # بررسی شرط
            try:
                condition_result = self._execute_simple_condition(condition, context, node_results)
                if not condition_result:
                    break
            except Exception as e:
                if break_on_error:
                    raise
                logger.error(f"While loop condition evaluation failed: {e}", exc_info=True)
                break
            
            try:
                # اجرای iteration
                result = iteration_count
                results.append(result)
                iteration_count += 1
            except Exception as e:
                if break_on_error:
                    raise
                elif not continue_on_error:
                    logger.error(f"Loop iteration failed: {e}", exc_info=True)
                    break
        
        if iteration_count >= max_iterations:
            logger.warning(f"While loop exceeded max_iterations ({max_iterations})")
        
        return results
    
    def _execute_loop_iteration(
        self,
        node: Dict[str, Any],
        context: Dict[str, Any],
        node_results: Dict[str, Any],
        item: Any,
        index: int,
        item_variable: str,
        index_variable: str,
        break_on_error: bool,
        continue_on_error: bool
    ) -> Any:
        """اجرای یک iteration از حلقه"""
        # ساخت context جدید برای iteration
        loop_context = context.copy()
        loop_context[item_variable] = item
        loop_context[index_variable] = index
        
        # در اینجا باید nodeهای داخل حلقه را اجرا کنیم
        # اما چون ما loop node را اجرا می‌کنیم، باید workflow engine را تغییر دهیم
        # تا بتواند loop body را اجرا کند
        
        # فعلاً فقط item را برمی‌گردانیم
        return item
    
    def _get_next_nodes(
        self,
        node_id: str,
        connections: List[Dict[str, Any]],
        condition_result: Optional[bool] = None
    ) -> List[str]:
        """
        پیدا کردن nodeهای بعدی بر اساس connections.
        برای نود شرط: اگر condition_result مشخص باشد، فقط اتصالاتی با sourceHandle
        منطبق (true/false) دنبال می‌شوند. اگر sourceHandle در اتصال نباشد،
        برای سازگاری با گذشته همه اتصالات دنبال می‌شوند.
        """
        next_nodes = []
        expected_handle = "true" if condition_result else "false" if condition_result is False else None
        for conn in connections:
            if conn.get("source") != node_id:
                continue
            target = conn.get("target")
            if not target:
                continue
            source_handle = conn.get("sourceHandle") or conn.get("source_output")
            if condition_result is not None and source_handle is not None:
                if source_handle != expected_handle:
                    continue
            next_nodes.append(target)
        return next_nodes
    
    def _execute_fallback_action(
        self,
        fallback_config: Dict[str, Any],
        context: Dict[str, Any],
        node_results: Dict[str, Any],
        failed_node: Dict[str, Any],
        error: Exception,
        execution: WorkflowExecution
    ):
        """
        اجرای fallback action در صورت خطا
        """
        action_type = fallback_config.get("action_type", "log")
        action_config = fallback_config.get("action_config", {})
        
        if action_type == "log":
            self._log(
                execution,
                WorkflowLogLevel.ERROR,
                f"Fallback: Node '{failed_node.get('label')}' failed with error: {str(error)}",
                {
                    "node_id": failed_node.get("id"),
                    "error": str(error),
                    "fallback_type": "log"
                }
            )
        elif action_type == "set_variable":
            # تنظیم یک متغیر که نشان دهد خطا رخ داده
            variable_name = action_config.get("variable_name", "last_error")
            if "variables" not in context:
                context["variables"] = {}
            context["variables"][variable_name] = {
                "error": str(error),
                "node_id": failed_node.get("id"),
                "node_label": failed_node.get("label")
            }
        else:
            # اجرای یک action خاص
            action_handler = self.action_registry.get_handler(action_type)
            if action_handler:
                # اضافه کردن اطلاعات خطا به context
                error_context = context.copy()
                error_context["error"] = {
                    "message": str(error),
                    "node_id": failed_node.get("id"),
                    "node_label": failed_node.get("label"),
                    "node_type": failed_node.get("type")
                }
                
                try:
                    action_handler.execute(error_context, action_config, node_results)
                except Exception as fallback_error:
                    logger.error(f"Fallback action '{action_type}' failed: {fallback_error}", exc_info=True)
    
    def _log(
        self,
        execution: WorkflowExecution,
        level: WorkflowLogLevel,
        message: str,
        data: Optional[Dict[str, Any]] = None
    ):
        """
        ثبت لاگ با قابلیت هشدار خودکار
        """
        log = WorkflowLog(
            execution_id=execution.id,
            level=level,
            message=message,
            data=data
        )
        self.db.add(log)
        self.db.commit()
        
        # ارسال هشدار برای خطاهای حیاتی
        if level == WorkflowLogLevel.ERROR:
            try:
                self._send_error_alert(execution, message, data)
            except Exception as e:
                logger.error(f"Failed to send error alert: {e}", exc_info=True)
    
    def _send_error_alert(
        self,
        execution: WorkflowExecution,
        message: str,
        data: Optional[Dict[str, Any]]
    ):
        """
        ارسال هشدار برای خطاهای حیاتی
        
        این متد در صورت رخ دادن خطا در workflow:
        - به admin/owner کسب‌وکار notification می‌فرستد
        - اگر تنظیمات alert فعال باشد، از کانال‌های مختلف (email, telegram) هم استفاده می‌کند
        """
        try:
            # دریافت Workflow
            workflow = self.db.get(Workflow, execution.workflow_id)
            if not workflow:
                return
            
            # بررسی تنظیمات Alert
            settings = workflow.settings or {}
            alert_config = settings.get("alerts", {})
            
            # اگر alert غیرفعال است، خروج
            if not alert_config.get("enabled", False):
                return
            
            # دریافت کانال‌های هشدار
            channels = alert_config.get("channels", ["inapp"])
            
            # تنظیم پیام هشدار
            alert_subject = f"⚠️ خطا در اجرای workflow: {workflow.name}"
            alert_message = f"""
خطایی در اجرای workflow رخ داده است:

📋 **Workflow:** {workflow.name}
🔢 **Execution ID:** {execution.id}
🔗 **Correlation ID:** {self.correlation_id}
⚠️ **خطا:** {message}

🕒 **زمان:** {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}

جزئیات بیشتر در بخش لاگ‌های workflow موجود است.
"""
            
            # ارسال Notification به admin/owner
            from app.services.notification_service import NotificationService
            
            notification_service = NotificationService(self.db)
            
            # دریافت owner کسب‌وکار
            from adapters.db.models.business import Business
            business = self.db.get(Business, self.business_id)
            
            if business and business.owner_id:
                try:
                    # ارسال notification داخلی
                    if "inapp" in channels:
                        notification_service.send(
                            user_id=business.owner_id,
                            event_key="workflow.error",
                            context={
                                "subject": alert_subject,
                                "message": alert_message,
                                "workflow_id": workflow.id,
                                "workflow_name": workflow.name,
                                "execution_id": execution.id,
                                "correlation_id": self.correlation_id,
                                "error_type": data.get("error_type") if data else None,
                                "error_message": data.get("error_message") if data else message
                            },
                            preferred_channels=["inapp"]
                        )
                        logger.info(f"In-app alert sent for workflow {workflow.id} error")
                    
                    # ارسال ایمیل
                    if "email" in channels:
                        from app.services.email_service import EmailService
                        email_service = EmailService(self.db)
                        
                        # دریافت ایمیل owner
                        from adapters.db.models.user import User
                        owner = self.db.get(User, business.owner_id)
                        
                        if owner and owner.email:
                            try:
                                email_service.send_email(
                                    to=owner.email,
                                    subject=alert_subject,
                                    body=alert_message,
                                    html_body=None
                                )
                                logger.info(f"Email alert sent to {owner.email} for workflow {workflow.id} error")
                            except Exception as e:
                                logger.error(f"Failed to send email alert: {e}")
                    
                    # ارسال تلگرام
                    if "telegram" in channels:
                        from app.services.providers.telegram_provider import TelegramProvider
                        from app.services.system_settings_service import get_effective_notifications_settings
                        from adapters.db.models.user import User
                        
                        owner = self.db.get(User, business.owner_id)
                        
                        if owner and owner.telegram_chat_id:
                            try:
                                notify_cfg = get_effective_notifications_settings(self.db)
                                telegram = TelegramProvider(
                                    bot_token=notify_cfg.get("telegram_bot_token"),
                                    proxy_config=notify_cfg.get("telegram_proxy"),
                                )
                                
                                if telegram.is_configured():
                                    telegram.send_text(
                                        chat_id=int(owner.telegram_chat_id),
                                        text=alert_message,
                                        parse_mode=None
                                    )
                                    logger.info(f"Telegram alert sent for workflow {workflow.id} error")
                            except Exception as e:
                                logger.error(f"Failed to send telegram alert: {e}")
                
                except Exception as e:
                    logger.error(f"Error sending notifications: {e}", exc_info=True)
            
            # ثبت لاگ در سطح WARNING که alert ارسال شد
            logger.warning(
                f"Error alert triggered for workflow {workflow.id}",
                extra={
                    "workflow_id": workflow.id,
                    "execution_id": execution.id,
                    "correlation_id": self.correlation_id,
                    "alert_channels": channels,
                    "event": "alert_sent"
                }
            )
            
        except Exception as e:
            logger.error(f"Failed to send error alert: {e}", exc_info=True)

