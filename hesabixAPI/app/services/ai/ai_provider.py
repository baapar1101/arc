from __future__ import annotations

from typing import Dict, Any, List, Optional, AsyncGenerator
from abc import ABC, abstractmethod
import json
import logging

logger = logging.getLogger(__name__)

# خروجی بیشتر از این در بسیاری از gatewayها (vLLM و مشابه) رد می‌شود؛ حتی اگر
# مدیر در دیتابیس مقدار بسیار بزرگ بگذارد.
_MAX_SAFE_CHAT_OUTPUT_TOKENS = 32000


def _is_openai_model_unavailable_error(error_message: str) -> bool:
    """تشخیص «مدل ناموجود/غیرقابل استفاده» بدون false positive روی max_model_len و ..."""
    s = error_message.lower()
    if "model_not_found" in s or "model not found" in s:
        return True
    if "invalid model" in s or "model does not exist" in s or "does not exist" in s and "model" in s:
        return True
    if "unknown model" in s or "no such model" in s:
        return True
    return False


class AIProviderBase(ABC):
    """کلاس پایه برای AI Providers"""
    
    def __init__(self, api_key: str, api_base_url: Optional[str] = None):
        self.api_key = api_key
        self.api_base_url = api_base_url
    
    @abstractmethod
    def chat_completion(
        self,
        messages: List[Dict[str, Any]],
        model: str,
        max_tokens: int,
        temperature: float,
        tools: Optional[List[Dict[str, Any]]] = None
    ) -> Dict[str, Any]:
        """ارسال درخواست chat completion"""
        pass
    
    @abstractmethod
    def estimate_tokens(self, text: str) -> int:
        """تخمین تعداد توکن"""
        pass
    
    @abstractmethod
    async def chat_completion_stream(
        self,
        messages: List[Dict[str, Any]],
        model: str,
        max_tokens: int,
        temperature: float,
        tools: Optional[List[Dict[str, Any]]] = None
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """
        ارسال درخواست chat completion به صورت streaming
        هر chunk شامل:
        - delta: محتوای جدید (content chunk)
        - usage: در chunk آخر
        - done: آیا streaming تمام شده است
        """
        pass


class OpenAIProvider(AIProviderBase):
    """Provider برای OpenAI"""
    
    def __init__(self, api_key: str, api_base_url: Optional[str] = None):
        super().__init__(api_key, api_base_url or "https://api.openai.com/v1")
        try:
            import openai
            # استفاده از sync client برای non-streaming
            self.client = openai.OpenAI(
                api_key=api_key,
                base_url=api_base_url or None
            )
            # استفاده از async client برای streaming
            self.async_client = openai.AsyncOpenAI(
                api_key=api_key,
                base_url=api_base_url or None
            )
        except ImportError:
            raise ImportError("openai package is required. Install it with: pip install openai")
    
    def chat_completion(
        self,
        messages: List[Dict[str, Any]],
        model: str,
        max_tokens: int,
        temperature: float,
        tools: Optional[List[Dict[str, Any]]] = None
    ) -> Dict[str, Any]:
        """ارسال درخواست به OpenAI"""
        try:
            if max_tokens > _MAX_SAFE_CHAT_OUTPUT_TOKENS:
                max_tokens = _MAX_SAFE_CHAT_OUTPUT_TOKENS
            response = self.client.chat.completions.create(
                model=model,
                messages=messages,
                max_tokens=max_tokens,
                temperature=temperature,
                tools=tools if tools else None
            )
            
            message = response.choices[0].message
            usage = response.usage
            
            result = {
                "message": {
                    "role": message.role,
                    "content": message.content or "",
                    "function_calls": [
                        {
                            "name": fc.function.name,
                            "arguments": json.loads(fc.function.arguments)
                        }
                        for fc in (message.tool_calls or [])
                    ] if message.tool_calls else None
                },
                "usage": {
                    "input_tokens": usage.prompt_tokens,
                    "output_tokens": usage.completion_tokens,
                    "total_tokens": usage.total_tokens
                }
            }
            
            return result
        except Exception as e:
            logger.error(f"OpenAI API error: {e}", exc_info=True)
            # تبدیل خطاهای OpenAI به ApiError
            error_message = str(e)
            el = error_message.lower()
            if (
                "max_model_len" in el
                or "max_total_tokens" in el
                or ("max_tokens" in el and ("cannot" in el or "greater than" in el or "exceed" in el or "invalid" in el))
                or ("context length" in el and ("exceed" in el or "exceeds" in el))
            ):
                from app.core.responses import ApiError
                raise ApiError(
                    "AI_INVALID_MAX_TOKENS",
                    "مقدار «حداکثر توکن» در تنظیمات AI برای این سرویس بیش‌ازحد مجاز است. "
                    f"لطفاً مقدار را به عددی معقول (مثلاً ۴۰۰۰ تا {_MAX_SAFE_CHAT_OUTPUT_TOKENS}) کاهش دهید و دوباره تلاش کنید.",
                    http_status=400
                )
            if _is_openai_model_unavailable_error(error_message):
                from app.core.responses import ApiError
                raise ApiError(
                    "MODEL_NOT_AVAILABLE",
                    f"مدل '{model}' در دسترس نیست. لطفاً مدل دیگری را در تنظیمات AI انتخاب کنید.",
                    http_status=400
                )
            elif "api_key" in error_message.lower() or "authentication" in error_message.lower():
                from app.core.responses import ApiError
                raise ApiError(
                    "INVALID_API_KEY",
                    "API Key نامعتبر است. لطفاً API Key را در تنظیمات AI بررسی کنید.",
                    http_status=400
                )
            elif "rate_limit" in error_message.lower() or "quota" in error_message.lower():
                from app.core.responses import ApiError
                raise ApiError(
                    "RATE_LIMIT_EXCEEDED",
                    "محدودیت استفاده از API رسیده است. لطفاً بعداً تلاش کنید.",
                    http_status=429
                )
            else:
                from app.core.responses import ApiError
                raise ApiError(
                    "AI_PROVIDER_ERROR",
                    f"خطا در ارتباط با AI Provider: {error_message}",
                    http_status=500
                )
    
    def estimate_tokens(self, text: str) -> int:
        """تخمین تعداد توکن (تقریبی: 4 کاراکتر = 1 توکن)"""
        return len(text) // 4
    
    async def chat_completion_stream(
        self,
        messages: List[Dict[str, Any]],
        model: str,
        max_tokens: int,
        temperature: float,
        tools: Optional[List[Dict[str, Any]]] = None
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """ارسال درخواست به OpenAI به صورت streaming با async client"""
        try:
            if max_tokens > _MAX_SAFE_CHAT_OUTPUT_TOKENS:
                max_tokens = _MAX_SAFE_CHAT_OUTPUT_TOKENS
            # استفاده از async client برای streaming
            stream = await self.async_client.chat.completions.create(
                model=model,
                messages=messages,
                max_tokens=max_tokens,
                temperature=temperature,
                tools=tools if tools else None,
                stream=True
            )
            
            accumulated_content = ""
            final_usage = None
            tool_calls_accumulator = {}  # برای جمع‌آوری tool_calls از chunks مختلف
            
            async for chunk in stream:
                # بررسی usage (معمولاً در chunk آخر می‌آید)
                if chunk.usage:
                    final_usage = {
                        "input_tokens": chunk.usage.prompt_tokens,
                        "output_tokens": chunk.usage.completion_tokens,
                        "total_tokens": chunk.usage.total_tokens
                    }
                
                # بررسی content chunks
                if chunk.choices and len(chunk.choices) > 0:
                    delta = chunk.choices[0].delta
                    
                    # محتوای جدید
                    if delta.content:
                        accumulated_content += delta.content
                        yield {
                            "delta": {
                                "content": delta.content
                            },
                            "usage": None,
                            "done": False
                        }
                    
                    # بررسی tool_calls - جمع‌آوری از chunks مختلف
                    if delta.tool_calls:
                        for tool_call_delta in delta.tool_calls:
                            index = tool_call_delta.index
                            if index not in tool_calls_accumulator:
                                tool_calls_accumulator[index] = {
                                    "id": tool_call_delta.id or f"call_{index}",
                                    "type": tool_call_delta.type or "function",
                                    "function": {
                                        "name": "",
                                        "arguments": ""
                                    }
                                }
                            
                            # جمع‌آوری نام function (replace نه append)
                            if tool_call_delta.function and tool_call_delta.function.name:
                                tool_calls_accumulator[index]["function"]["name"] = tool_call_delta.function.name
                            
                            # جمع‌آوری arguments (append)
                            if tool_call_delta.function and tool_call_delta.function.arguments:
                                tool_calls_accumulator[index]["function"]["arguments"] += tool_call_delta.function.arguments
            
            # اگر usage موجود نبود، از accumulated_content تخمین بزن
            if not final_usage:
                # تخمین tokens (تقریبی)
                input_tokens_estimate = self.estimate_tokens("\n".join([msg.get("content", "") for msg in messages]))
                output_tokens_estimate = self.estimate_tokens(accumulated_content)
                final_usage = {
                    "input_tokens": input_tokens_estimate,
                    "output_tokens": output_tokens_estimate,
                    "total_tokens": input_tokens_estimate + output_tokens_estimate
                }
            
            # تبدیل tool_calls به فرمت مورد نیاز (با حفظ id برای tool_call_id)
            function_calls = None
            tool_call_id_map = {}
            if tool_calls_accumulator:
                function_calls = []
                for index in sorted(tool_calls_accumulator.keys()):
                    tc = tool_calls_accumulator[index]
                    try:
                        arguments = json.loads(tc["function"]["arguments"]) if tc["function"]["arguments"] else {}
                    except json.JSONDecodeError:
                        arguments = {}
                    
                    function_name = tc["function"]["name"]
                    tool_call_id = tc.get("id", f"call_{index}")
                    tool_call_id_map[function_name] = tool_call_id
                    
                    function_calls.append({
                        "id": tool_call_id,
                        "name": function_name,
                        "arguments": arguments
                    })
            
            # ارسال chunk نهایی با usage و function_calls
            yield {
                "delta": {
                    "content": ""
                },
                "usage": final_usage,
                "function_calls": function_calls,
                "tool_call_id_map": tool_call_id_map,  # برای استفاده در ai_service
                "done": True
            }
            
        except Exception as e:
            logger.error(f"OpenAI streaming API error: {e}", exc_info=True)
            # تبدیل خطاهای OpenAI به ApiError
            error_message = str(e)
            el = error_message.lower()
            if (
                "max_model_len" in el
                or "max_total_tokens" in el
                or ("max_tokens" in el and ("cannot" in el or "greater than" in el or "exceed" in el or "invalid" in el))
                or ("context length" in el and ("exceed" in el or "exceeds" in el))
            ):
                from app.core.responses import ApiError
                raise ApiError(
                    "AI_INVALID_MAX_TOKENS",
                    "مقدار «حداکثر توکن» در تنظیمات AI برای این سرویس بیش‌ازحد مجاز است. "
                    f"لطفاً مقدار را به عددی معقول (مثلاً ۴۰۰۰ تا {_MAX_SAFE_CHAT_OUTPUT_TOKENS}) کاهش دهید و دوباره تلاش کنید.",
                    http_status=400
                )
            if _is_openai_model_unavailable_error(error_message):
                from app.core.responses import ApiError
                raise ApiError(
                    "MODEL_NOT_AVAILABLE",
                    f"مدل '{model}' در دسترس نیست. لطفاً مدل دیگری را در تنظیمات AI انتخاب کنید.",
                    http_status=400
                )
            elif "api_key" in error_message.lower() or "authentication" in error_message.lower():
                from app.core.responses import ApiError
                raise ApiError(
                    "INVALID_API_KEY",
                    "API Key نامعتبر است. لطفاً API Key را در تنظیمات AI بررسی کنید.",
                    http_status=400
                )
            elif "rate_limit" in error_message.lower() or "quota" in error_message.lower():
                from app.core.responses import ApiError
                raise ApiError(
                    "RATE_LIMIT_EXCEEDED",
                    "محدودیت استفاده از API رسیده است. لطفاً بعداً تلاش کنید.",
                    http_status=429
                )
            else:
                from app.core.responses import ApiError
                raise ApiError(
                    "AI_PROVIDER_ERROR",
                    f"خطا در ارتباط با AI Provider: {error_message}",
                    http_status=500
                )


def _openai_tools_to_anthropic(tools: Optional[List[Dict[str, Any]]]) -> Optional[List[Dict[str, Any]]]:
    if not tools:
        return None
    out: List[Dict[str, Any]] = []
    for tool in tools:
        fn = tool.get("function") if isinstance(tool, dict) else None
        if not fn:
            continue
        out.append(
            {
                "name": fn["name"],
                "description": fn.get("description") or "",
                "input_schema": fn.get("parameters") or {"type": "object", "properties": {}},
            }
        )
    return out or None


def _parse_tool_arguments(raw: Any) -> Dict[str, Any]:
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
            return parsed if isinstance(parsed, dict) else {}
        except json.JSONDecodeError:
            return {}
    return {}


def _openai_messages_to_anthropic(
    messages: List[Dict[str, Any]],
) -> tuple[Optional[str], List[Dict[str, Any]]]:
    system_message: Optional[str] = None
    body: List[Dict[str, Any]] = []
    non_system = [m for m in messages if m.get("role") != "system"]
    for m in messages:
        if m.get("role") == "system":
            system_message = m.get("content") or system_message

    i = 0
    while i < len(non_system):
        msg = non_system[i]
        role = msg.get("role")
        if role == "user":
            body.append({"role": "user", "content": msg.get("content") or ""})
            i += 1
        elif role == "assistant":
            if msg.get("tool_calls"):
                blocks: List[Dict[str, Any]] = []
                if msg.get("content"):
                    blocks.append({"type": "text", "text": msg["content"]})
                for tc in msg["tool_calls"]:
                    fn = tc.get("function") or {}
                    blocks.append(
                        {
                            "type": "tool_use",
                            "id": tc.get("id") or f"call_{fn.get('name', 'tool')}",
                            "name": fn.get("name", "unknown"),
                            "input": _parse_tool_arguments(fn.get("arguments")),
                        }
                    )
                body.append({"role": "assistant", "content": blocks})
            else:
                body.append({"role": "assistant", "content": msg.get("content") or ""})
            i += 1
        elif role == "tool":
            tool_blocks: List[Dict[str, Any]] = []
            while i < len(non_system) and non_system[i].get("role") == "tool":
                tm = non_system[i]
                tool_blocks.append(
                    {
                        "type": "tool_result",
                        "tool_use_id": tm.get("tool_call_id") or "unknown",
                        "content": tm.get("content") or "{}",
                    }
                )
                i += 1
            body.append({"role": "user", "content": tool_blocks})
        else:
            i += 1
    return system_message, body


def _anthropic_blocks_to_openai_result(content_blocks: Any) -> tuple[str, Optional[List[Dict[str, Any]]]]:
    text_parts: List[str] = []
    function_calls: List[Dict[str, Any]] = []
    for block in content_blocks or []:
        btype = getattr(block, "type", None) or (block.get("type") if isinstance(block, dict) else None)
        if btype == "text":
            text_parts.append(getattr(block, "text", None) or (block.get("text") if isinstance(block, dict) else ""))
        elif btype == "tool_use":
            bid = getattr(block, "id", None) or (block.get("id") if isinstance(block, dict) else None)
            name = getattr(block, "name", None) or (block.get("name") if isinstance(block, dict) else "unknown")
            inp = getattr(block, "input", None) if hasattr(block, "input") else block.get("input")
            function_calls.append(
                {
                    "id": bid or f"call_{name}",
                    "name": name,
                    "arguments": inp if isinstance(inp, dict) else {},
                }
            )
    content = "".join(text_parts)
    return content, function_calls or None


class AnthropicProvider(AIProviderBase):
    """Provider برای Anthropic (Claude) با پشتیبانی tool calling."""

    def __init__(self, api_key: str, api_base_url: Optional[str] = None):
        super().__init__(api_key, api_base_url or "https://api.anthropic.com")
        try:
            import anthropic

            base = (api_base_url or "https://api.anthropic.com").rstrip("/")
            self.client = anthropic.Anthropic(api_key=api_key, base_url=base)
            self.async_client = anthropic.AsyncAnthropic(api_key=api_key, base_url=base)
        except ImportError:
            raise ImportError(
                "anthropic package is required. Install it with: pip install anthropic"
            )

    def _build_request_kwargs(
        self,
        messages: List[Dict[str, Any]],
        model: str,
        max_tokens: int,
        temperature: float,
        tools: Optional[List[Dict[str, Any]]],
    ) -> Dict[str, Any]:
        if max_tokens > _MAX_SAFE_CHAT_OUTPUT_TOKENS:
            max_tokens = _MAX_SAFE_CHAT_OUTPUT_TOKENS
        system_message, anthropic_messages = _openai_messages_to_anthropic(messages)
        anthropic_tools = _openai_tools_to_anthropic(tools)
        kwargs: Dict[str, Any] = {
            "model": model,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "messages": anthropic_messages,
        }
        if system_message:
            kwargs["system"] = system_message
        if anthropic_tools:
            kwargs["tools"] = anthropic_tools
        return kwargs

    def chat_completion(
        self,
        messages: List[Dict[str, Any]],
        model: str,
        max_tokens: int,
        temperature: float,
        tools: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        try:
            response = self.client.messages.create(
                **self._build_request_kwargs(messages, model, max_tokens, temperature, tools)
            )
            content, function_calls = _anthropic_blocks_to_openai_result(response.content)
            return {
                "message": {
                    "role": "assistant",
                    "content": content,
                    "function_calls": function_calls,
                },
                "usage": {
                    "input_tokens": response.usage.input_tokens,
                    "output_tokens": response.usage.output_tokens,
                    "total_tokens": response.usage.input_tokens + response.usage.output_tokens,
                },
            }
        except Exception as e:
            logger.error(f"Anthropic API error: {e}", exc_info=True)
            raise

    def estimate_tokens(self, text: str) -> int:
        return len(text) // 4

    async def chat_completion_stream(
        self,
        messages: List[Dict[str, Any]],
        model: str,
        max_tokens: int,
        temperature: float,
        tools: Optional[List[Dict[str, Any]]] = None,
    ) -> AsyncGenerator[Dict[str, Any], None]:
        kwargs = self._build_request_kwargs(messages, model, max_tokens, temperature, tools)
        try:
            accumulated_text = ""
            tool_blocks: Dict[int, Dict[str, Any]] = {}
            final_usage = None

            async with self.async_client.messages.stream(**kwargs) as stream:
                async for event in stream:
                    etype = getattr(event, "type", None)
                    if etype == "content_block_start":
                        block = getattr(event, "content_block", None)
                        if block and getattr(block, "type", None) == "tool_use":
                            idx = getattr(event, "index", 0)
                            tool_blocks[idx] = {
                                "id": getattr(block, "id", f"call_{idx}"),
                                "name": getattr(block, "name", "unknown"),
                                "arguments_json": "",
                            }
                    elif etype == "content_block_delta":
                        delta = getattr(event, "delta", None)
                        if not delta:
                            continue
                        dtype = getattr(delta, "type", None)
                        if dtype == "text_delta":
                            piece = getattr(delta, "text", "") or ""
                            if piece:
                                accumulated_text += piece
                                yield {"delta": {"content": piece}, "usage": None, "done": False}
                        elif dtype == "input_json_delta":
                            idx = getattr(event, "index", 0)
                            if idx in tool_blocks:
                                tool_blocks[idx]["arguments_json"] += getattr(delta, "partial_json", "") or ""
                    elif etype == "message_delta":
                        usage = getattr(event, "usage", None)
                        if usage:
                            final_usage = {
                                "input_tokens": getattr(usage, "input_tokens", 0),
                                "output_tokens": getattr(usage, "output_tokens", 0),
                                "total_tokens": getattr(usage, "input_tokens", 0)
                                + getattr(usage, "output_tokens", 0),
                            }

                final_message = await stream.get_final_message()
                if final_usage is None and final_message.usage:
                    final_usage = {
                        "input_tokens": final_message.usage.input_tokens,
                        "output_tokens": final_message.usage.output_tokens,
                        "total_tokens": final_message.usage.input_tokens
                        + final_message.usage.output_tokens,
                    }

            function_calls = None
            if tool_blocks:
                function_calls = []
                for idx in sorted(tool_blocks.keys()):
                    tb = tool_blocks[idx]
                    function_calls.append(
                        {
                            "id": tb["id"],
                            "name": tb["name"],
                            "arguments": _parse_tool_arguments(tb.get("arguments_json")),
                        }
                    )
            elif final_message.content:
                _, parsed_calls = _anthropic_blocks_to_openai_result(final_message.content)
                function_calls = parsed_calls

            if not final_usage:
                final_usage = {
                    "input_tokens": self.estimate_tokens(str(messages)),
                    "output_tokens": self.estimate_tokens(accumulated_text),
                    "total_tokens": 0,
                }
                final_usage["total_tokens"] = (
                    final_usage["input_tokens"] + final_usage["output_tokens"]
                )

            yield {
                "delta": {"content": ""},
                "usage": final_usage,
                "function_calls": function_calls,
                "done": True,
            }
        except Exception as e:
            logger.error(f"Anthropic streaming API error: {e}", exc_info=True)
            raise


class LocalProvider(AIProviderBase):
    """Provider برای مدل‌های محلی (مثل Ollama)"""
    
    def __init__(self, api_key: str, api_base_url: str):
        super().__init__(api_key, api_base_url)
        import httpx
        self.client = httpx.Client(base_url=api_base_url, timeout=60.0)
    
    def chat_completion(
        self,
        messages: List[Dict[str, Any]],
        model: str,
        max_tokens: int,
        temperature: float,
        tools: Optional[List[Dict[str, Any]]] = None
    ) -> Dict[str, Any]:
        """ارسال درخواست به مدل محلی"""
        try:
            # فرمت Ollama
            response = self.client.post(
                "/api/chat",
                json={
                    "model": model,
                    "messages": messages,
                    "options": {
                        "temperature": temperature,
                        "num_predict": max_tokens
                    }
                }
            )
            response.raise_for_status()
            data = response.json()
            
            return {
                "message": {
                    "role": "assistant",
                    "content": data.get("message", {}).get("content", "")
                },
                "usage": {
                    "input_tokens": data.get("prompt_eval_count", 0),
                    "output_tokens": data.get("eval_count", 0),
                    "total_tokens": data.get("prompt_eval_count", 0) + data.get("eval_count", 0)
                }
            }
        except Exception as e:
            logger.error(f"Local provider error: {e}", exc_info=True)
            raise
    
    def estimate_tokens(self, text: str) -> int:
        """تخمین تعداد توکن"""
        return len(text) // 4
    
    async def chat_completion_stream(
        self,
        messages: List[Dict[str, Any]],
        model: str,
        max_tokens: int,
        temperature: float,
        tools: Optional[List[Dict[str, Any]]] = None
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """ارسال درخواست به مدل محلی به صورت streaming"""
        import httpx
        import asyncio
        
        try:
            # استفاده از AsyncClient برای streaming
            async with httpx.AsyncClient(base_url=self.api_base_url, timeout=120.0) as client:
                async with client.stream(
                    "POST",
                    "/api/chat",
                    json={
                        "model": model,
                        "messages": messages,
                        "stream": True,
                        "options": {
                            "temperature": temperature,
                            "num_predict": max_tokens
                        }
                    }
                ) as response:
                    response.raise_for_status()
                    final_usage = None
                    
                    async for line in response.aiter_lines():
                        if not line:
                            continue
                        
                        try:
                            # Parse JSON از هر خط
                            data = json.loads(line)
                            
                            # بررسی message chunk
                            if "message" in data:
                                message = data["message"]
                                content = message.get("content", "")
                                if content:
                                    yield {
                                        "delta": {
                                            "content": content
                                        },
                                        "usage": None,
                                        "done": False
                                    }
                            
                            # بررسی done و usage
                            if data.get("done", False):
                                final_usage = {
                                    "input_tokens": data.get("prompt_eval_count", 0),
                                    "output_tokens": data.get("eval_count", 0),
                                    "total_tokens": data.get("prompt_eval_count", 0) + data.get("eval_count", 0)
                                }
                                
                                yield {
                                    "delta": {
                                        "content": ""
                                    },
                                    "usage": final_usage,
                                    "done": True
                                }
                                break
                                
                        except json.JSONDecodeError:
                            continue
                        except Exception as e:
                            logger.warning(f"Error parsing Ollama stream chunk: {e}")
                            continue
                            
        except Exception as e:
            logger.error(f"Local provider streaming error: {e}", exc_info=True)
            raise


def create_provider(
    provider_type: str,
    api_key: str,
    api_base_url: Optional[str] = None
) -> AIProviderBase:
    """ایجاد provider بر اساس نوع"""
    if provider_type == "openai":
        return OpenAIProvider(api_key, api_base_url)
    elif provider_type == "anthropic":
        return AnthropicProvider(api_key, api_base_url)
    elif provider_type == "local":
        if not api_base_url:
            raise ValueError("api_base_url is required for local provider")
        return LocalProvider(api_key, api_base_url)
    else:
        raise ValueError(f"Unknown provider type: {provider_type}")

