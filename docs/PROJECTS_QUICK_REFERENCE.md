# ⚡ راهنمای سریع قابلیت مدیریت پروژه

## 🚀 شروع سریع (5 دقیقه)

### 1. اجرای Migration
```bash
cd /var/www/ark/hesabixAPI
alembic upgrade head
sudo systemctl restart hesabix-api
```

### 2. تست API
```bash
# ایجاد پروژه
curl -X POST http://localhost:8000/api/v1/businesses/1/projects \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"code":"P1","name":"پروژه تست"}'

# لیست پروژه‌ها
curl http://localhost:8000/api/v1/businesses/1/projects/active \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

## 📝 کپی-پیست کدها

### Backend: افزودن فیلتر به گزارش

```python
# در سرویس
def get_your_report(
    db: Session,
    business_id: int,
    project_id: Optional[int] = None,  # اضافه کنید
    # ...
):
    query = db.query(...).join(Document).filter(...)
    
    if project_id:  # اضافه کنید
        query = query.filter(Document.project_id == project_id)
```

```python
# در endpoint
@router.post("/reports/your-report")
async def your_report_endpoint(body: Dict):
    project_id = body.get('project_id')  # اضافه کنید
    if project_id:
        project_id = int(project_id)
    
    result = get_your_report(
        # ...
        project_id=project_id,  # اضافه کنید
    )
```

### Frontend: افزودن فیلتر به صفحه

```dart
// در State
int? _selectedProjectId;

// در Widget
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';

ProjectSelectorWidget(
  businessId: widget.businessId,
  apiClient: widget.apiClient,
  selectedProjectId: _selectedProjectId,
  onChanged: (id) {
    setState(() => _selectedProjectId = id);
    _loadData();
  },
)

// در API Call
final body = {
  // ...
  if (_selectedProjectId != null) 'project_id': _selectedProjectId,
};
```

---

## 📂 فایل‌های کلیدی

| نوع | مسیر | توضیح |
|-----|------|-------|
| Model | `adapters/db/models/project.py` | مدل دیتابیس |
| Service | `app/services/project_service.py` | منطق کسب‌وکار |
| API | `adapters/api/v1/projects.py` | Endpoints |
| Widget | `lib/widgets/project/project_selector_widget.dart` | کمبوباکس |
| Page | `lib/pages/business/projects_page.dart` | صفحه لیست |

---

## 🔗 API Endpoints

```
POST   /api/v1/businesses/{id}/projects          # ایجاد
GET    /api/v1/businesses/{id}/projects          # لیست
GET    /api/v1/businesses/{id}/projects/active   # فعال‌ها
GET    /api/v1/projects/{id}                     # جزئیات
PUT    /api/v1/projects/{id}                     # ویرایش
DELETE /api/v1/projects/{id}                     # حذف
```

---

## 📊 گزارشات با پشتیبانی پروژه

| گزارش | Endpoint | وضعیت |
|-------|----------|-------|
| سود و زیان دوره‌ای | `/reports/pnl-period` | ✅ |
| سود و زیان تجمعی | `/reports/pnl-cumulative` | ✅ |
| دفتر کل | `/reports/general-ledger` | ✅ |
| دفتر روزنامه | `/reports/journal-ledger` | ⏳ |
| تراز آزمایشی | `/reports/trial-balance` | ⏳ |

---

## 🐛 عیب‌یابی سریع

### خطای "PROJECT_NOT_FOUND"
```python
# چک کنید:
- پروژه متعلق به همان business_id باشد
- پروژه is_active=True باشد
```

### فیلتر کار نمی‌کند
```dart
// چک کنید:
- _selectedProjectId به requestBody اضافه شده؟
- _refreshData() صدا زده می‌شود؟
```

### Migration خطا می‌دهد
```bash
# بررسی وضعیت
alembic current

# Rollback
alembic downgrade -1

# Upgrade دوباره
alembic upgrade head
```

---

## ⏱️ زمان‌بندی پیاده‌سازی

| مرحله | زمان |
|-------|------|
| Backend اصلی | ✅ 4h |
| Frontend اصلی | ✅ 3h |
| گزارشات Backend | ✅ 2h |
| گزارشات Frontend | ⏳ 8h |
| تست | ⏳ 4h |
| **جمع** | **21h** |

---

## 📚 مستندات کامل

برای جزئیات بیشتر:
- 📖 `PROJECTS_INTEGRATION_GUIDE.md` - راهنمای کامل
- 📊 `PROJECTS_REPORTS_DETAILED_SCENARIO.md` - سناریوی گزارشات
- 📋 `PROJECTS_COMPLETE_IMPLEMENTATION_SUMMARY.md` - خلاصه جامع

---

**بروز شده**: دسامبر 2025  
**نسخه**: 1.0  
**حجم**: 1 صفحه A4 📄

