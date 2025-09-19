"""
Base PDF Service for modular PDF generation
"""
import os
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional, List
from datetime import datetime
from pathlib import Path

from weasyprint import HTML, CSS
from weasyprint.text.fonts import FontConfiguration
from jinja2 import Environment, FileSystemLoader, select_autoescape

from app.core.calendar import CalendarConverter, CalendarType
from app.core.i18n import get_translator
from adapters.api.v1.schemas import QueryInfo


class BasePDFModule(ABC):
    """Base class for PDF modules"""
    
    def __init__(self, module_name: str):
        self.module_name = module_name
        self.template_dir = Path(__file__).parent / "modules" / module_name / "templates"
        self.jinja_env = Environment(
            loader=FileSystemLoader(str(self.template_dir)),
            autoescape=select_autoescape(['html', 'xml'])
        )
        self.font_config = FontConfiguration()
    
    @abstractmethod
    def generate_pdf(
        self, 
        data: Dict[str, Any], 
        calendar_type: CalendarType = "jalali",
        locale: str = "fa"
    ) -> bytes:
        """Generate PDF for this module"""
        pass
    
    @abstractmethod
    def generate_excel_data(
        self, 
        data: Dict[str, Any], 
        calendar_type: CalendarType = "jalali",
        locale: str = "fa"
    ) -> list:
        """Generate Excel data for this module"""
        pass
    
    def format_datetime(self, dt: datetime, calendar_type: CalendarType) -> str:
        """Format datetime based on calendar type"""
        if dt is None:
            return ""
        
        formatted_date = CalendarConverter.format_datetime(dt, calendar_type)
        return formatted_date['formatted']
    
    def get_translator(self, locale: str = "fa"):
        """Get translator for the given locale"""
        return get_translator(locale)
    
    def render_template(self, template_name: str, context: Dict[str, Any]) -> str:
        """Render template with context"""
        template = self.jinja_env.get_template(template_name)
        return template.render(**context)


class PDFService:
    """Main PDF Service that manages modules"""
    
    def __init__(self):
        self.modules: Dict[str, BasePDFModule] = {}
        self._register_modules()
    
    def _register_modules(self):
        """Register all available modules"""
        from .modules.marketing.marketing_module import MarketingPDFModule
        self.modules['marketing'] = MarketingPDFModule()
    
    def generate_pdf(
        self, 
        module_name: str, 
        data: Dict[str, Any], 
        calendar_type: CalendarType = "jalali",
        locale: str = "fa",
        db=None,
        user_id: Optional[int] = None,
        query_info: Optional[QueryInfo] = None,
        selected_indices: Optional[List[int]] = None,
        stats: Optional[Dict[str, Any]] = None
    ) -> bytes:
        """Generate PDF using specified module"""
        if module_name not in self.modules:
            raise ValueError(f"Module '{module_name}' not found")
        
        return self.modules[module_name].generate_pdf_content(
            db=db,
            user_id=user_id,
            query_info=query_info,
            selected_indices=selected_indices,
            stats=stats,
            calendar_type=calendar_type,
            locale=locale,
            common_data=data
        )
    
    def generate_excel_data(
        self, 
        module_name: str, 
        data: Dict[str, Any], 
        calendar_type: CalendarType = "jalali",
        locale: str = "fa",
        db=None,
        user_id: Optional[int] = None,
        query_info: Optional[QueryInfo] = None,
        selected_indices: Optional[List[int]] = None
    ) -> list:
        """Generate Excel data using specified module"""
        if module_name not in self.modules:
            raise ValueError(f"Module '{module_name}' not found")
        
        return self.modules[module_name].generate_excel_content(
            db=db,
            user_id=user_id,
            query_info=query_info,
            selected_indices=selected_indices,
            calendar_type=calendar_type,
            locale=locale,
            common_data=data
        )
    
    def list_modules(self) -> list:
        """List all available modules"""
        return list(self.modules.keys())
