# PDF Templates

This directory contains HTML templates for PDF generation using WeasyPrint.

## Structure

```
templates/
├── pdf/
│   ├── marketing_referrals.html    # Marketing referrals report template
│   └── ...                         # Future templates
└── README.md                       # This file
```

## Template Guidelines

### 1. RTL Support
- All templates should support RTL (Right-to-Left) layout
- Use `dir="rtl"` in HTML tag
- Use `text-align: right` in CSS

### 2. Font Support
- Use 'Vazirmatn' font for Persian text
- Fallback to Arial, sans-serif
- Ensure proper font loading in CSS

### 3. Page Layout
- Use `@page` CSS rule for page settings
- Set appropriate margins (2cm recommended)
- Include page numbers in header/footer

### 4. Styling
- Use CSS Grid or Flexbox for layouts
- Ensure print-friendly colors
- Use appropriate font sizes (12px base)
- Include proper spacing and padding

### 5. Data Binding
- Use Jinja2 template syntax
- Handle null/empty values gracefully
- Format dates and numbers appropriately

## Adding New Templates

1. Create HTML file in appropriate subdirectory
2. Follow naming convention: `{feature}_{type}.html`
3. Include proper CSS styling
4. Test with sample data
5. Update PDF service to use new template

## Example Usage

```python
from app.services.pdf_service import PDFService

pdf_service = PDFService()
pdf_bytes = pdf_service.generate_marketing_referrals_pdf(
    db=db,
    user_id=user_id,
    query_info=query_info,
    selected_indices=indices,
    stats=stats
)
```

## Future Enhancements

- Template inheritance system
- Dynamic template selection
- Multi-language support
- Template preview functionality
- Template versioning
