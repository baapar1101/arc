# PDF Service - Modular Architecture

## Overview
This is a modular PDF generation service designed for scalability and AI integration. Each module handles specific business domains and can be easily extended.

## Structure
```
app/services/pdf/
├── __init__.py
├── base_pdf_service.py          # Base classes and main service
├── modules/                     # Business domain modules
│   ├── __init__.py
│   └── marketing/               # Marketing & referrals module
│       ├── __init__.py
│       ├── marketing_module.py  # Module implementation
│       └── templates/           # HTML templates
│           └── marketing_referrals.html
└── README.md
```

## Adding New Modules

### 1. Create Module Directory
```bash
mkdir -p app/services/pdf/modules/your_module/templates
```

### 2. Implement Module Class
```python
# app/services/pdf/modules/your_module/your_module.py
from ..base_pdf_service import BasePDFModule
from app.core.calendar import CalendarType

class YourModulePDFModule(BasePDFModule):
    def __init__(self):
        super().__init__("your_module")
    
    def generate_pdf(self, data, calendar_type="jalali", locale="fa"):
        # Your PDF generation logic
        pass
    
    def generate_excel_data(self, data, calendar_type="jalali", locale="fa"):
        # Your Excel data generation logic
        pass
```

### 3. Register Module
Add to `base_pdf_service.py`:
```python
def _register_modules(self):
    from .modules.marketing.marketing_module import MarketingPDFModule
    from .modules.your_module.your_module import YourModulePDFModule
    self.modules['marketing'] = MarketingPDFModule()
    self.modules['your_module'] = YourModulePDFModule()
```

## Usage

### Generate PDF
```python
from app.services.pdf import PDFService

pdf_service = PDFService()
pdf_bytes = pdf_service.generate_pdf(
    module_name='marketing',
    data=your_data,
    calendar_type='jalali',
    locale='fa'
)
```

### Generate Excel Data
```python
excel_data = pdf_service.generate_excel_data(
    module_name='marketing',
    data=your_data,
    calendar_type='jalali',
    locale='fa'
)
```

## Features

### 1. Calendar Support
- Automatic Jalali/Gregorian conversion
- Configurable via `calendar_type` parameter

### 2. Internationalization
- Built-in translation support
- Template-level translation integration
- Configurable via `locale` parameter

### 3. Modular Design
- Easy to add new business domains
- Clean separation of concerns
- Reusable base classes

### 4. AI Integration Ready
- Function calling compatible
- Clear module boundaries
- Extensible architecture

## Template Development

### Using Translations
```html
<!-- In your template -->
<h1>{{ t('yourTranslationKey') }}</h1>
<div>{{ t('anotherKey') }}</div>
```

### Calendar Formatting
```python
# In your module
formatted_date = self.format_datetime(datetime_obj, calendar_type)
```

### Data Formatting
```python
# In your module
formatted_data = self._format_data_for_template(data, calendar_type, translator)
```

## Future Extensions

### AI Integration
Each module can be exposed as a function for AI systems:
```python
# Example AI function definition
{
    "name": "generate_marketing_pdf",
    "description": "Generate marketing referrals PDF report",
    "parameters": {
        "type": "object",
        "properties": {
            "user_id": {"type": "integer"},
            "filters": {"type": "object"},
            "calendar_type": {"type": "string", "enum": ["jalali", "gregorian"]}
        }
    }
}
```

### Additional Modules
- `invoices/` - Invoice generation
- `reports/` - General reports
- `analytics/` - Analytics dashboards
- `notifications/` - Notification templates
