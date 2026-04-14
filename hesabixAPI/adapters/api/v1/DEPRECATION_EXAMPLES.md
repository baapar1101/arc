# راهنمای استفاده از Deprecation در Endpoints

## چگونه یک Endpoint را Deprecated کنیم؟

### مثال 1: Endpoint کاملاً منسوخ شده

```python
@router.get(
    "/old-endpoint",
    summary="[منسوخ شده] API قدیمی",
    deprecated=True,
    description="""
    ⚠️ **این endpoint منسوخ شده و در نسخه 2.0 حذف خواهد شد.**
    
    **دلیل منسوخ شدن:**
    - ساختار داده بهینه نیست
    - امنیت کافی ندارد
    - Performance پایین
    
    **جایگزین:**
    - استفاده کنید از: `GET /api/v1/new-endpoint`
    - مستندات: https://docs.hesabix.ir/new-endpoint
    
    **تاریخ حذف:**
    - این endpoint در تاریخ 2025-06-01 حذف خواهد شد
    
    **مایگریشن:**
    ```python
    # قبل:
    GET /api/v1/old-endpoint?param=value
    
    # بعد:
    GET /api/v1/new-endpoint
    Body: {"param": "value"}
    ```
    """,
    responses={
        200: {
            "description": "پاسخ موفق (اما منسوخ شده)",
            "headers": {
                "X-Deprecated-Endpoint": {
                    "description": "نام endpoint جدید",
                    "schema": {"type": "string"}
                },
                "X-Deprecation-Date": {
                    "description": "تاریخ حذف",
                    "schema": {"type": "string"}
                }
            }
        }
    }
)
async def old_endpoint():
    return {
        "success": True,
        "warning": "این endpoint منسوخ شده است. لطفاً از /api/v1/new-endpoint استفاده کنید",
        "deprecation_info": {
            "deprecated_since": "2024-01-01",
            "removal_date": "2025-06-01",
            "replacement": "/api/v1/new-endpoint"
        },
        "data": {}
    }
```

### مثال 2: پارامتر منسوخ شده

```python
@router.get(
    "/users",
    summary="لیست کاربران",
    description="""
    دریافت لیست کاربران با صفحه‌بندی
    
    ### پارامترهای منسوخ شده:
    - ⚠️ `page`: از `skip` و `take` استفاده کنید
    - ⚠️ `pageSize`: از `take` استفاده کنید
    """
)
async def list_users(
    skip: int = Query(0, description="تعداد رکورد رد شده"),
    take: int = Query(10, description="تعداد رکورد در صفحه"),
    page: Optional[int] = Query(
        None, 
        deprecated=True,
        description="[منسوخ] شماره صفحه - از skip/take استفاده کنید"
    ),
    pageSize: Optional[int] = Query(
        None,
        deprecated=True,
        description="[منسوخ] اندازه صفحه - از take استفاده کنید"
    )
):
    # مایگریشن پارامترهای قدیمی
    if page is not None or pageSize is not None:
        warnings.warn("پارامترهای page و pageSize منسوخ شده‌اند")
        if page is not None and pageSize is not None:
            skip = (page - 1) * pageSize
            take = pageSize
    
    return {"items": [], "total": 0}
```

### مثال 3: فیلد منسوخ شده در Response

```python
class UserResponse(BaseModel):
    id: int
    username: str
    email: str
    full_name: str = Field(..., description="نام کامل کاربر")
    
    # فیلد منسوخ شده
    name: Optional[str] = Field(
        None,
        deprecated=True,
        description="[منسوخ] از full_name استفاده کنید"
    )
    
    @validator('name', always=True)
    def set_name_for_backward_compatibility(cls, v, values):
        # برای backward compatibility، name را برابر full_name قرار می‌دهیم
        if v is None and 'full_name' in values:
            return values['full_name']
        return v
```

### مثال 4: نسخه‌گذاری API

```python
# نسخه قدیمی - deprecated
router_v1 = APIRouter(prefix="/api/v1", tags=["API v1 (منسوخ)"], deprecated=True)

@router_v1.get(
    "/users",
    deprecated=True,
    description="⚠️ API نسخه 1 منسوخ شده. از /api/v2/users استفاده کنید"
)
async def list_users_v1():
    pass

# نسخه جدید
router_v2 = APIRouter(prefix="/api/v2", tags=["API v2"])

@router_v2.get("/users")
async def list_users_v2():
    pass
```

## بهترین روش‌ها (Best Practices)

### 1. اطلاع‌رسانی واضح
همیشه دلیل منسوخ شدن و جایگزین را مشخص کنید:

```python
description="""
⚠️ منسوخ شده
**دلیل:** امنیت ضعیف
**جایگزین:** GET /v2/secure-endpoint
**حذف در:** 2025-01-01
"""
```

### 2. دوره انتقالی (Transition Period)
حداقل 6 ماه زمان برای مایگریشن بدهید:

```python
deprecated=True,
description="حذف در: 2025-06-01 (6 ماه دیگر)"
```

### 3. هدرهای سفارشی
از هدرهای HTTP برای اطلاع‌رسانی استفاده کنید:

```python
headers = {
    "X-Deprecated": "true",
    "X-Deprecation-Date": "2024-01-01",
    "X-Sunset-Date": "2025-06-01",
    "Link": '<https://docs.hesabix.ir/migration>; rel="deprecation"'
}
```

### 4. لاگ کردن استفاده از API های منسوخ
```python
import logging
logger = logging.getLogger(__name__)

@router.get("/old-api", deprecated=True)
async def old_api(request: Request):
    logger.warning(
        f"Deprecated endpoint called: {request.url.path} "
        f"by user: {request.state.user_id}"
    )
    return {"warning": "این API منسوخ شده است"}
```

### 5. مستندسازی در CHANGELOG
```markdown
## [1.5.0] - 2024-01-15

### Deprecated
- `GET /api/v1/old-endpoint` - جایگزین: `GET /api/v2/new-endpoint`
- پارامتر `page` در `/users` - جایگزین: `skip` و `take`

### Removed
- در نسخه 2.0 این endpoint ها حذف خواهند شد
```

## چک‌لیست Deprecation

قبل از منسوخ کردن یک API، این موارد را بررسی کنید:

- [ ] دلیل منسوخ شدن مشخص است
- [ ] جایگزین واضح معرفی شده
- [ ] تاریخ حذف مشخص است (حداقل 6 ماه)
- [ ] مستندات به‌روز شده
- [ ] CHANGELOG به‌روز شده
- [ ] هدرهای deprecation اضافه شده
- [ ] لاگ‌گذاری فعال شده
- [ ] کاربران از طریق email/notification مطلع شده‌اند
- [ ] راهنمای مایگریشن نوشته شده
- [ ] backward compatibility حفظ شده (در صورت امکان)

## مثال کامل از یک Deprecation خوب

```python
@router.post(
    "/api/v1/calculate-tax",
    summary="[منسوخ - حذف در 2025-06-01] محاسبه مالیات",
    deprecated=True,
    description="""
    # ⚠️ این API منسوخ شده است
    
    ## چرا منسوخ شد؟
    - الگوریتم محاسبه مالیات به‌روزرسانی شده
    - سازگاری با قوانین جدید مالیاتی
    - Performance بهتر در نسخه جدید
    
    ## جایگزین چیست؟
    از API جدید استفاده کنید:
    ```
    POST /api/v2/tax/calculate
    ```
    
    ## تفاوت‌ها:
    | نسخه قدیم | نسخه جدید |
    |-----------|-----------|
    | `amount` | `taxable_amount` |
    | `rate` | `tax_rate_percent` |
    | بازگشت: `{tax: number}` | بازگشت: `{tax_amount, total_amount, details}` |
    
    ## مایگریشن:
    ```python
    # قبل (v1 - منسوخ):
    response = requests.post('/api/v1/calculate-tax', {
        'amount': 1000000,
        'rate': 9
    })
    tax = response.json()['tax']
    
    # بعد (v2 - جدید):
    response = requests.post('/api/v2/tax/calculate', {
        'taxable_amount': 1000000,
        'tax_rate_percent': 9,
        'tax_type': 'VAT'
    })
    result = response.json()
    tax = result['tax_amount']
    total = result['total_amount']
    ```
    
    ## تاریخ‌های مهم:
    - **منسوخ شده از:** 2024-12-01
    - **حذف می‌شود در:** 2025-06-01
    - **زمان باقی‌مانده:** 6 ماه
    
    ## لینک‌های مفید:
    - [راهنمای مایگریشن](https://docs.hesabix.ir/migration/tax-api)
    - [مستندات API جدید](https://docs.hesabix.ir/api/v2/tax)
    - [تغییرات قوانین مالیاتی](https://docs.hesabix.ir/tax/changes)
    """,
    responses={
        200: {
            "description": "محاسبه با موفقیت انجام شد (اما API منسوخ است)",
            "headers": {
                "X-Deprecated": {
                    "description": "نشان می‌دهد این API منسوخ شده",
                    "schema": {"type": "boolean", "example": True}
                },
                "X-Deprecation-Date": {
                    "description": "تاریخ منسوخ شدن",
                    "schema": {"type": "string", "example": "2024-12-01"}
                },
                "X-Sunset-Date": {
                    "description": "تاریخ حذف",
                    "schema": {"type": "string", "example": "2025-06-01"}
                },
                "Link": {
                    "description": "لینک به API جدید",
                    "schema": {"type": "string", "example": "</api/v2/tax/calculate>; rel=\"successor-version\""}
                },
                "X-Migration-Guide": {
                    "description": "لینک به راهنمای مایگریشن",
                    "schema": {"type": "string"}
                }
            }
        }
    }
)
async def calculate_tax_v1(
    request: Request,
    amount: Decimal = Body(...),
    rate: Decimal = Body(...)
):
    # لاگ استفاده از API منسوخ
    logger.warning(
        f"Deprecated API called: /api/v1/calculate-tax "
        f"by user: {request.state.user_id} "
        f"IP: {request.client.host}"
    )
    
    # محاسبه (برای backward compatibility)
    tax = amount * (rate / 100)
    
    return Response(
        content=json.dumps({
            "success": True,
            "warning": "⚠️ این API منسوخ شده است. لطفاً از /api/v2/tax/calculate استفاده کنید",
            "deprecation_info": {
                "deprecated_since": "2024-12-01",
                "removal_date": "2025-06-01",
                "replacement": "/api/v2/tax/calculate",
                "migration_guide": "https://docs.hesabix.ir/migration/tax-api"
            },
            "data": {
                "tax": float(tax),
                "amount": float(amount),
                "rate": float(rate)
            }
        }),
        headers={
            "X-Deprecated": "true",
            "X-Deprecation-Date": "2024-12-01",
            "X-Sunset-Date": "2025-06-01",
            "Link": '</api/v2/tax/calculate>; rel="successor-version"',
            "X-Migration-Guide": "https://docs.hesabix.ir/migration/tax-api"
        },
        media_type="application/json"
    )
```

این راهنما نشان می‌دهد چگونه به صورت حرفه‌ای API های منسوخ را مدیریت کنیم.


