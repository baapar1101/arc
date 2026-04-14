"""
بهینه‌سازی Pagination
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional
from math import ceil

from sqlalchemy.orm import Query
from sqlalchemy import func

from app.core.settings import get_settings


class PaginationParams:
    """پارامترهای pagination"""
    
    def __init__(
        self,
        page: int = 1,
        page_size: int = 20,
        max_page_size: int = 100
    ):
        self.page = max(1, page)
        self.page_size = min(max(1, page_size), max_page_size)
        self.offset = (self.page - 1) * self.page_size
        self.limit = self.page_size
    
    @classmethod
    def from_request(cls, page: int = 1, page_size: int = 20) -> "PaginationParams":
        """ساخت PaginationParams از request parameters"""
        settings = get_settings()
        max_page_size = getattr(settings, 'max_page_size', 100)
        return cls(page=page, page_size=page_size, max_page_size=max_page_size)


def paginate_query(
    query: Query,
    pagination: PaginationParams,
    count_query: Optional[Query] = None
) -> Dict[str, Any]:
    """
    Paginate کردن یک SQLAlchemy query
    
    Args:
        query: SQLAlchemy query
        pagination: PaginationParams
        count_query: Query جداگانه برای count (اختیاری، برای بهینه‌سازی)
    
    Returns:
        Dictionary شامل:
        - items: لیست آیتم‌ها
        - total: تعداد کل
        - page: صفحه فعلی
        - page_size: اندازه صفحه
        - total_pages: تعداد کل صفحات
        - has_next: آیا صفحه بعدی وجود دارد
        - has_prev: آیا صفحه قبلی وجود دارد
    """
    # استفاده از count_query اگر ارائه شده باشد
    if count_query is not None:
        total = count_query.scalar()
    else:
        # Count با استفاده از subquery برای بهینه‌سازی
        total = query.with_entities(func.count()).scalar()
    
    # دریافت آیتم‌ها
    items = query.offset(pagination.offset).limit(pagination.limit).all()
    
    # محاسبه تعداد صفحات
    total_pages = ceil(total / pagination.page_size) if pagination.page_size > 0 else 0
    
    return {
        "items": items,
        "total": total,
        "page": pagination.page,
        "page_size": pagination.page_size,
        "total_pages": total_pages,
        "has_next": pagination.page < total_pages,
        "has_prev": pagination.page > 1,
    }


def paginate_list(
    items: List[Any],
    pagination: PaginationParams
) -> Dict[str, Any]:
    """
    Paginate کردن یک لیست Python
    
    Args:
        items: لیست آیتم‌ها
        pagination: PaginationParams
    
    Returns:
        Dictionary شامل pagination info و items
    """
    total = len(items)
    start = pagination.offset
    end = start + pagination.limit
    
    paginated_items = items[start:end]
    total_pages = ceil(total / pagination.page_size) if pagination.page_size > 0 else 0
    
    return {
        "items": paginated_items,
        "total": total,
        "page": pagination.page,
        "page_size": pagination.page_size,
        "total_pages": total_pages,
        "has_next": pagination.page < total_pages,
        "has_prev": pagination.page > 1,
    }


def create_pagination_response(
    paginated_data: Dict[str, Any],
    serializer: Optional[callable] = None
) -> Dict[str, Any]:
    """
    ساخت response استاندارد برای pagination
    
    Args:
        paginated_data: نتیجه paginate_query یا paginate_list
        serializer: تابع برای serialize کردن هر آیتم (اختیاری)
    
    Returns:
        Response dictionary با ساختار استاندارد
    """
    items = paginated_data["items"]
    
    # Serialize کردن آیتم‌ها اگر serializer ارائه شده باشد
    if serializer:
        items = [serializer(item) for item in items]
    
    return {
        "success": True,
        "data": {
            "items": items,
            "pagination": {
                "total": paginated_data["total"],
                "page": paginated_data["page"],
                "page_size": paginated_data["page_size"],
                "total_pages": paginated_data["total_pages"],
                "has_next": paginated_data["has_next"],
                "has_prev": paginated_data["has_prev"],
            }
        }
    }


def optimize_count_query(query: Query) -> Query:
    """
    بهینه‌سازی query برای count
    
    Args:
        query: Query اصلی
    
    Returns:
        Query بهینه‌سازی شده برای count
    """
    # حذف order_by برای بهینه‌سازی count
    count_query = query.order_by(None)
    
    # استفاده از count() به جای len()
    return count_query.with_entities(func.count())

