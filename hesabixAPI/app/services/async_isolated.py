"""
اجرای کوروتین وقتی ممکن است در همان ترد حلقهٔ asyncio فعال باشد
(مثلاً فراخوانی از ورک‌فلو هم‌زمان با درخواست FastAPI).

در این حالت `asyncio.run` / `anyio.run` خطای «Already running asyncio in this thread» می‌دهند؛
راه‌حل: اجرای `asyncio.run` در یک ترد جدا بدون حلقهٔ فعال.
"""

from __future__ import annotations

import asyncio
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Callable, Coroutine, TypeVar

T = TypeVar("T")


def run_coroutine_isolated(factory: Callable[[], Coroutine[Any, Any, T]]) -> T:
    """
    factory باید در هر فراخوانی یک کوروتین تازه برگرداند، مثلاً:
        run_coroutine_isolated(lambda: my_async_fn())
    """
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        return asyncio.run(factory())

    def _in_thread() -> T:
        return asyncio.run(factory())

    with ThreadPoolExecutor(max_workers=1) as ex:
        return ex.submit(_in_thread).result()
