"""
موتور اجرای Workflow
این موتور workflowها را اجرا می‌کند و nodeها را به ترتیب پردازش می‌کند
"""

import json
import logging
import time
from typing import Any, Dict, List, Optional
from datetime import datetime

from sqlalchemy.orm import Session

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
    _cache_lock = None  # برای thread safety
    
    def __init__(self, db: Session, business_id: int, user_id: Optional[int] = None):
        self.db = db
        self.business_id = business_id
        self.user_id = user_id
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
        
        try:
            execution.status = WorkflowExecutionStatus.RUNNING
            execution.started_at = datetime.utcnow()
            self.db.commit()
            
            # اجرای workflow
            result = self._execute_workflow_internal(workflow, execution, trigger_data or {})
            
            execution.status = WorkflowExecutionStatus.COMPLETED
            execution.completed_at = datetime.utcnow()
            execution.execution_data = result
            self.db.commit()
            
            self._log(execution, WorkflowLogLevel.INFO, "Workflow completed successfully")
            
        except Exception as e:
            logger.error(f"Workflow execution failed: {e}", exc_info=True)
            execution.status = WorkflowExecutionStatus.FAILED
            execution.completed_at = datetime.utcnow()
            execution.error_message = str(e)
            self.db.commit()
            
            self._log(execution, WorkflowLogLevel.ERROR, f"Workflow failed: {str(e)}")
        
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
            try:
                result = self._execute_node(node, context, node_results)
                node_results[node_id] = result
                executed_nodes.add(node_id)
                
                self._log(
                    execution,
                    WorkflowLogLevel.INFO,
                    f"Node '{node.get('label', node_id)}' executed successfully",
                    {"node_id": node_id, "result": result}
                )
                
                # پیدا کردن nodeهای بعدی
                next_nodes = self._get_next_nodes(node_id, connections)
                queue.extend(next_nodes)
                
            except Exception as e:
                logger.error(f"Node execution failed: {e}", exc_info=True)
                self._log(
                    execution,
                    WorkflowLogLevel.ERROR,
                    f"Node '{node.get('label', node_id)}' failed: {str(e)}",
                    {"node_id": node_id, "error": str(e)}
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
                    next_nodes = self._get_next_nodes(node_id, connections)
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
                        next_nodes = self._get_next_nodes(node_id, connections)
                        queue.extend(next_nodes)
        
        return {
            "node_results": node_results,
            "executed_nodes": list(executed_nodes),
            "context": context
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
        دریافت نتیجه از cache
        """
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
        ذخیره نتیجه در cache
        """
        WorkflowEngine._result_cache[cache_key] = (result, time.time())
        
        # پاکسازی cache قدیمی (هر 1000 مورد یکبار)
        if len(WorkflowEngine._result_cache) > 1000:
            self._cleanup_cache()
    
    def _cleanup_cache(self):
        """
        پاکسازی cache منقضی شده
        """
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
        """اجرای شرط با expression (JavaScript-like)"""
        expression = config.get("expression")
        if not expression:
            return False
        
        # ساخت یک محیط برای اجرای expression
        env = {
            "context": context,
            "node_results": node_results,
            "resolve": lambda v: WorkflowEngine._resolve_value_static(v, context, node_results),
        }
        
        try:
            # استفاده از eval (در production باید از یک expression engine امن‌تر استفاده شود)
            result = eval(expression, {"__builtins__": {}}, env)
            return bool(result)
        except Exception as e:
            logger.error(f"Expression evaluation failed: {e}")
            raise ValueError(f"Expression evaluation failed: {str(e)}")
    
    @staticmethod
    def _resolve_value_static(
        value: Any,
        context: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> Any:
        """
        حل کردن مقدار (ممکن است reference به node دیگر باشد)
        """
        if isinstance(value, str) and value.startswith("$"):
            # Reference به node دیگر یا context
            ref = value[1:]  # حذف $
            
            # بررسی context
            if ref in context:
                return context[ref]
            
            # بررسی node results
            if ref in node_results:
                return node_results[ref]
            
            # بررسی nested paths مثل $node_id.field
            parts = ref.split(".")
            if len(parts) == 2:
                node_id, field = parts
                if node_id in node_results:
                    result = node_results[node_id]
                    if isinstance(result, dict) and field in result:
                        return result[field]
            
            return value
    
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
        connections: List[Dict[str, Any]]
    ) -> List[str]:
        """
        پیدا کردن nodeهای بعدی بر اساس connections
        """
        next_nodes = []
        for conn in connections:
            if conn.get("source") == node_id:
                target = conn.get("target")
                if target:
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
        ثبت لاگ
        """
        log = WorkflowLog(
            execution_id=execution.id,
            level=level,
            message=message,
            data=data
        )
        self.db.add(log)
        self.db.commit()

