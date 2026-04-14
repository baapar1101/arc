from __future__ import annotations

from fastapi import Request
from .calendar import get_calendar_type_from_header, CalendarType


async def add_calendar_type(request: Request, call_next):
    """Middleware to add calendar type to request state"""
    calendar_header = request.headers.get("X-Calendar-Type")
    calendar_type = get_calendar_type_from_header(calendar_header)
    request.state.calendar_type = calendar_type
    
    response = await call_next(request)
    return response
