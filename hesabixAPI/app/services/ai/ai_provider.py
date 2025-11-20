from __future__ import annotations

from typing import Dict, Any, List, Optional
from abc import ABC, abstractmethod
import json
import logging

logger = logging.getLogger(__name__)


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


class OpenAIProvider(AIProviderBase):
    """Provider برای OpenAI"""
    
    def __init__(self, api_key: str, api_base_url: Optional[str] = None):
        super().__init__(api_key, api_base_url or "https://api.openai.com/v1")
        try:
            import openai
            self.client = openai.OpenAI(
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
            if "model_not_found" in error_message or "model" in error_message.lower():
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


class AnthropicProvider(AIProviderBase):
    """Provider برای Anthropic (Claude)"""
    
    def __init__(self, api_key: str, api_base_url: Optional[str] = None):
        super().__init__(api_key, api_base_url or "https://api.anthropic.com/v1")
        try:
            import anthropic
            self.client = anthropic.Anthropic(api_key=api_key)
        except ImportError:
            raise ImportError("anthropic package is required. Install it with: pip install anthropic")
    
    def chat_completion(
        self,
        messages: List[Dict[str, Any]],
        model: str,
        max_tokens: int,
        temperature: float,
        tools: Optional[List[Dict[str, Any]]] = None
    ) -> Dict[str, Any]:
        """ارسال درخواست به Anthropic"""
        try:
            # تبدیل messages به فرمت Anthropic
            anthropic_messages = []
            system_message = None
            
            for msg in messages:
                if msg["role"] == "system":
                    system_message = msg["content"]
                else:
                    anthropic_messages.append({
                        "role": msg["role"],
                        "content": msg["content"]
                    })
            
            # تبدیل tools به فرمت Anthropic
            anthropic_tools = None
            if tools:
                anthropic_tools = []
                for tool in tools:
                    if "function" in tool:
                        anthropic_tools.append({
                            "name": tool["function"]["name"],
                            "description": tool["function"]["description"],
                            "input_schema": tool["function"]["parameters"]
                        })
            
            response = self.client.messages.create(
                model=model,
                max_tokens=max_tokens,
                temperature=temperature,
                messages=anthropic_messages,
                system=system_message,
                tools=anthropic_tools if anthropic_tools else None
            )
            
            # تبدیل response به فرمت یکسان
            content = response.content[0].text if response.content else ""
            
            result = {
                "message": {
                    "role": "assistant",
                    "content": content,
                    "function_calls": None  # Anthropic function calling متفاوت است
                },
                "usage": {
                    "input_tokens": response.usage.input_tokens,
                    "output_tokens": response.usage.output_tokens,
                    "total_tokens": response.usage.input_tokens + response.usage.output_tokens
                }
            }
            
            return result
        except Exception as e:
            logger.error(f"Anthropic API error: {e}", exc_info=True)
            raise
    
    def estimate_tokens(self, text: str) -> int:
        """تخمین تعداد توکن"""
        return len(text) // 4


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

