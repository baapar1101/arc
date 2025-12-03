"""
ماژول برای مدیریت پاسخ‌های صفحات پرداخت
شامل تشخیص هوشمند منبع (اپ/موبایل/دسکتاپ) و render کردن template های HTML
"""
from typing import Dict, Any, Optional
from fastapi import Request
from fastapi.responses import HTMLResponse
from jinja2 import Environment, FileSystemLoader, select_autoescape
import os
from datetime import datetime
import re


# تنظیم Jinja2 environment
TEMPLATE_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "templates")
jinja_env = Environment(
    loader=FileSystemLoader(TEMPLATE_DIR),
    autoescape=select_autoescape(['html', 'xml']),
    enable_async=True
)


def format_number(value):
    """فرمت کردن عدد با جداکننده هزارگان"""
    try:
        return "{:,}".format(int(value))
    except (ValueError, TypeError):
        return str(value)


# اضافه کردن فیلتر به jinja
jinja_env.filters['format_number'] = format_number


def detect_source(request: Request, source_param: Optional[str] = None) -> str:
    """
    تشخیص منبع درخواست (اپ/موبایل/دسکتاپ)
    
    اولویت:
    1. پارامتر source از URL (دقیق‌ترین)
    2. User-Agent header (پشتیبان)
    
    Returns:
        'app': از اپلیکیشن موبایل
        'mobile_web': از مرورگر موبایل
        'desktop': از مرورگر دسکتاپ
    """
    # اولویت اول: پارامتر صریح
    if source_param:
        source_param = source_param.lower().strip()
        if source_param in ['app', 'mobile_app', 'mobile-app']:
            return 'app'
        elif source_param in ['mobile_web', 'mobile-web', 'mobile']:
            return 'mobile_web'
        elif source_param in ['desktop', 'web']:
            return 'desktop'
    
    # اولویت دوم: User-Agent
    user_agent = request.headers.get('user-agent', '').lower()
    
    # تشخیص اپلیکیشن موبایل (معمولاً اپ‌ها User-Agent خاصی دارند)
    if 'hesabix' in user_agent or 'flutter' in user_agent or 'dart' in user_agent:
        return 'app'
    
    # تشخیص موبایل
    mobile_keywords = ['android', 'iphone', 'ipad', 'ipod', 'mobile', 'webos', 'blackberry', 'windows phone']
    if any(keyword in user_agent for keyword in mobile_keywords):
        return 'mobile_web'
    
    # پیش‌فرض: دسکتاپ
    return 'desktop'


def detect_is_mobile(user_agent: str) -> bool:
    """تشخیص اینکه درخواست از موبایل است یا نه"""
    mobile_keywords = ['android', 'iphone', 'ipad', 'ipod', 'mobile', 'webos', 'blackberry', 'windows phone']
    return any(keyword in user_agent.lower() for keyword in mobile_keywords)


def render_payment_success(
    request: Request,
    transaction_id: int,
    amount: float,
    external_ref: str,
    card_num: Optional[str] = None,
    source: Optional[str] = None,
    dashboard_url: str = "/",
) -> HTMLResponse:
    """
    رندر صفحه موفقیت پرداخت
    
    Args:
        request: FastAPI Request object
        transaction_id: شماره تراکنش
        amount: مبلغ پرداخت شده
        external_ref: شماره پیگیری
        card_num: شماره کارت (اختیاری)
        source: منبع درخواست (app/mobile_web/desktop)
        dashboard_url: URL داشبورد
    """
    if source is None:
        source = detect_source(request)
    
    template = jinja_env.get_template('payment/success.html')
    
    # تنظیم URL داشبورد بر اساس منبع
    if source == 'app':
        dashboard_url = f"hesabix://dashboard"
    
    context = {
        'transaction_id': transaction_id,
        'amount': amount,
        'external_ref': external_ref,
        'card_num': card_num,
        'timestamp': datetime.now().strftime('%Y/%m/%d - %H:%M'),
        'source': source,
        'dashboard_url': dashboard_url,
    }
    
    html_content = template.render(**context)
    return HTMLResponse(content=html_content, status_code=200)


def render_payment_failed(
    request: Request,
    transaction_id: int,
    external_ref: Optional[str] = None,
    error_message: Optional[str] = None,
    error_code: Optional[str] = None,
    source: Optional[str] = None,
    retry_url: str = "/",
    dashboard_url: str = "/",
    support_url: str = "/support",
) -> HTMLResponse:
    """
    رندر صفحه شکست پرداخت
    
    Args:
        request: FastAPI Request object
        transaction_id: شماره تراکنش
        external_ref: شماره پیگیری (اختیاری)
        error_message: پیام خطا
        error_code: کد خطا
        source: منبع درخواست
        retry_url: URL برای تلاش مجدد
        dashboard_url: URL داشبورد
        support_url: URL پشتیبانی
    """
    if source is None:
        source = detect_source(request)
    
    template = jinja_env.get_template('payment/failed.html')
    
    # تنظیم URL‌ها بر اساس منبع
    if source == 'app':
        dashboard_url = f"hesabix://dashboard"
        retry_url = f"hesabix://wallet/topup"
        support_url = f"hesabix://support"
    
    context = {
        'transaction_id': transaction_id,
        'external_ref': external_ref,
        'error_message': error_message or 'خطایی در پردازش تراکنش رخ داده است.',
        'error_code': error_code,
        'timestamp': datetime.now().strftime('%Y/%m/%d - %H:%M'),
        'source': source,
        'retry_url': retry_url,
        'dashboard_url': dashboard_url,
        'support_url': support_url,
    }
    
    html_content = template.render(**context)
    return HTMLResponse(content=html_content, status_code=200)


def should_return_json(request: Request) -> bool:
    """
    تشخیص اینکه باید JSON برگردونیم یا HTML
    
    بر اساس:
    1. Accept header
    2. پارامتر format در URL
    """
    # بررسی پارامتر format
    format_param = request.query_params.get('format', '').lower()
    if format_param == 'json':
        return True
    if format_param == 'html':
        return False
    
    # بررسی Accept header
    accept = request.headers.get('accept', '').lower()
    if 'application/json' in accept and 'text/html' not in accept:
        return True
    
    # پیش‌فرض: HTML برای تجربه بهتر کاربری
    return False

