"""
Marketing PDF Module for referrals and marketing reports
"""
from typing import Dict, Any, List
from datetime import datetime

from ...base_pdf_service import BasePDFModule
from app.core.calendar import CalendarType


class MarketingPDFModule(BasePDFModule):
    """PDF Module for marketing and referrals"""
    
    def __init__(self):
        super().__init__("marketing")
        self.template_name = 'marketing_referrals.html'
    
    def generate_pdf(
        self, 
        data: Dict[str, Any], 
        calendar_type: CalendarType = "jalali",
        locale: str = "fa"
    ) -> bytes:
        """Generate marketing referrals PDF"""
        # Get translator
        t = self.get_translator(locale)
        
        # Format data with translations and calendar
        formatted_data = self._format_data_for_template(data, calendar_type, t)
        
        # Render template
        html_content = self.render_template('marketing_referrals.html', formatted_data)
        
        # Generate PDF
        html_doc = HTML(string=html_content)
        pdf_bytes = html_doc.write_pdf(font_config=self.font_config)
        
        return pdf_bytes
    
    def generate_excel_data(
        self, 
        data: Dict[str, Any], 
        calendar_type: CalendarType = "jalali",
        locale: str = "fa"
    ) -> list:
        """Generate marketing referrals Excel data"""
        # Get translator
        t = self.get_translator(locale)
        
        # Format data
        items = data.get('items', [])
        excel_data = []
        
        for i, item in enumerate(items, 1):
            # Format created_at based on calendar type
            created_at = item.get('created_at', '')
            if created_at and isinstance(created_at, datetime):
                created_at = self.format_datetime(created_at, calendar_type)
            elif created_at and isinstance(created_at, str):
                try:
                    dt = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                    created_at = self.format_datetime(dt, calendar_type)
                except:
                    pass
            
            excel_data.append({
                t('row_number'): i,
                t('first_name'): item.get('first_name', ''),
                t('last_name'): item.get('last_name', ''),
                t('email'): item.get('email', ''),
                t('registration_date'): created_at,
                t('referral_code'): item.get('referral_code', ''),
                t('status'): t('active') if item.get('is_active', False) else t('inactive')
            })
        
        return excel_data
    
    def _format_data_for_template(
        self, 
        data: Dict[str, Any], 
        calendar_type: CalendarType, 
        translator
    ) -> Dict[str, Any]:
        """Format data for template rendering"""
        # Format items
        items = data.get('items', [])
        formatted_items = []
        
        for item in items:
            formatted_item = item.copy()
            if item.get('created_at'):
                if isinstance(item['created_at'], datetime):
                    formatted_item['created_at'] = self.format_datetime(item['created_at'], calendar_type)
                elif isinstance(item['created_at'], str):
                    try:
                        dt = datetime.fromisoformat(item['created_at'].replace('Z', '+00:00'))
                        formatted_item['created_at'] = self.format_datetime(dt, calendar_type)
                    except:
                        pass
            formatted_items.append(formatted_item)
        
        # Format current date
        now = datetime.now()
        formatted_now = self.format_datetime(now, calendar_type)
        
        # Prepare template data with translations
        template_data = {
            'items': formatted_items,
            'total_count': data.get('total_count', 0),
            'report_date': formatted_now.split(' ')[0] if ' ' in formatted_now else formatted_now,
            'report_time': formatted_now.split(' ')[1] if ' ' in formatted_now else '',
            'selected_only': data.get('selected_only', False),
            'stats': data.get('stats', {}),
            'filters': self._format_filters(data.get('filters', []), translator),
            'calendar_type': calendar_type,
            'locale': translator.locale,
            't': translator,  # Pass translator to template
        }
        
        return template_data
    
    def _format_filters(self, query_info, locale: str, calendar_type: CalendarType = "jalali") -> List[str]:
        """Format query filters for display in PDF"""
        formatted_filters = []
        translator = self.get_translator(locale)
        
        # Add search filter
        if query_info.search and query_info.search.strip():
            search_fields = ', '.join(query_info.search_fields) if query_info.search_fields else translator.t('allFields')
            formatted_filters.append(f"{translator.t('search')}: '{query_info.search}' {translator.t('in')} {search_fields}")
        
        # Add column filters
        if query_info.filters:
            for filter_item in query_info.filters:
                if filter_item.property == "referred_by_user_id":
                    continue  # Skip internal filter
                
                # Get translated column name
                column_name = self._get_column_translation(filter_item.property, translator)
                operator_text = self._get_operator_translation(filter_item.operator, translator)
                
                # Format value based on column type and calendar
                formatted_value = self._format_filter_value(filter_item.property, filter_item.value, calendar_type, translator)
                
                formatted_filters.append(f"{column_name} {operator_text} '{formatted_value}'")
        
        return formatted_filters
    
    def _get_operator_translation(self, op: str, translator) -> str:
        """Convert operator to translated text"""
        operator_map = {
            '=': translator.t('equals'),
            '>': translator.t('greater_than'),
            '>=': translator.t('greater_equal'),
            '<': translator.t('less_than'),
            '<=': translator.t('less_equal'),
            '!=': translator.t('not_equals'),
            '*': translator.t('contains'),
            '*?': translator.t('starts_with'),
            '?*': translator.t('ends_with'),
            'in': translator.t('in_list')
        }
        
        operator_text = operator_map.get(op, op)
        return operator_text
    
    def _get_column_translation(self, property_name: str, translator) -> str:
        """Get translated column name"""
        column_map = {
            'first_name': translator.t('firstName'),
            'last_name': translator.t('lastName'),
            'email': translator.t('email'),
            'created_at': translator.t('registrationDate'),
            'referral_code': translator.t('referralCode'),
            'is_active': translator.t('status'),
        }
        return column_map.get(property_name, property_name)
    
    def _format_filter_value(self, property_name: str, value: Any, calendar_type: CalendarType, translator) -> str:
        """Format filter value based on column type and calendar"""
        # Handle date fields
        if property_name == 'created_at':
            try:
                if isinstance(value, str):
                    # Try to parse ISO format
                    dt = datetime.fromisoformat(value.replace('Z', '+00:00'))
                elif isinstance(value, datetime):
                    dt = value
                else:
                    return str(value)
                
                # Format based on calendar type - only date, no time
                from app.core.calendar import CalendarConverter
                formatted_date = CalendarConverter.format_datetime(dt, calendar_type)
                return formatted_date['date_only']  # Only show date, not time
            except:
                return str(value)
        
        # Handle boolean fields
        elif property_name == 'is_active':
            if isinstance(value, bool):
                return translator.t('active') if value else translator.t('inactive')
            elif str(value).lower() in ['true', '1', 'yes']:
                return translator.t('active')
            elif str(value).lower() in ['false', '0', 'no']:
                return translator.t('inactive')
            else:
                return str(value)
        
        # Default: return as string
        return str(value)
    
    def _get_referral_data(self, db, user_id: int, query_info, selected_indices: List[int] | None = None) -> tuple[List[Dict[str, Any]], int]:
        """Get referral data from database"""
        from adapters.db.repositories.user_repo import UserRepository
        from adapters.api.v1.schemas import FilterItem
        from sqlalchemy.orm import Session
        from adapters.db.models.user import User
        
        repo = UserRepository(db)
        
        # Add filter for referrals only (users with referred_by_user_id = current user)
        referral_filter = FilterItem(
            property="referred_by_user_id",
            operator="=",
            value=user_id
        )
        
        # Create a mutable copy of query_info.filters
        current_filters = list(query_info.filters) if query_info.filters else []
        current_filters.append(referral_filter)
        
        # For export, we need to get all data without take limit
        # Use the repository's direct query method
        try:
            # Get all referrals for the user without pagination
            query = db.query(User).filter(User.referred_by_user_id == user_id)
            
            # Apply search if provided
            if query_info.search and query_info.search.strip():
                search_term = f"%{query_info.search}%"
                if query_info.search_fields:
                    search_conditions = []
                    for field in query_info.search_fields:
                        if hasattr(User, field):
                            search_conditions.append(getattr(User, field).ilike(search_term))
                    if search_conditions:
                        from sqlalchemy import or_
                        query = query.filter(or_(*search_conditions))
                else:
                    # Search in common fields
                    query = query.filter(
                        (User.first_name.ilike(search_term)) |
                        (User.last_name.ilike(search_term)) |
                        (User.email.ilike(search_term))
                    )
            
            # Apply additional filters
            for filter_item in current_filters:
                if filter_item.property == "referred_by_user_id":
                    continue  # Already applied
                
                if hasattr(User, filter_item.property):
                    field = getattr(User, filter_item.property)
                    if filter_item.operator == "=":
                        query = query.filter(field == filter_item.value)
                    elif filter_item.operator == "!=":
                        query = query.filter(field != filter_item.value)
                    elif filter_item.operator == ">":
                        query = query.filter(field > filter_item.value)
                    elif filter_item.operator == ">=":
                        query = query.filter(field >= filter_item.value)
                    elif filter_item.operator == "<":
                        query = query.filter(field < filter_item.value)
                    elif filter_item.operator == "<=":
                        query = query.filter(field <= filter_item.value)
                    elif filter_item.operator == "*":  # contains
                        query = query.filter(field.ilike(f"%{filter_item.value}%"))
                    elif filter_item.operator == "*?":  # starts with
                        query = query.filter(field.ilike(f"{filter_item.value}%"))
                    elif filter_item.operator == "?*":  # ends with
                        query = query.filter(field.ilike(f"%{filter_item.value}"))
                    elif filter_item.operator == "in":
                        query = query.filter(field.in_(filter_item.value))
            
            # Apply sorting
            if query_info.sort_by and hasattr(User, query_info.sort_by):
                sort_field = getattr(User, query_info.sort_by)
                if query_info.sort_desc:
                    query = query.order_by(sort_field.desc())
                else:
                    query = query.order_by(sort_field.asc())
            else:
                # Default sort by created_at desc
                query = query.order_by(User.created_at.desc())
            
            # Execute query
            referrals = query.all()
            total = len(referrals)
            referral_dicts = [repo.to_dict(referral) for referral in referrals]
            
            # Apply selected indices filter if provided
            if selected_indices is not None:
                filtered_referrals = [referral_dicts[i] for i in selected_indices if i < len(referral_dicts)]
                return filtered_referrals, len(filtered_referrals)
            
            return referral_dicts, total
            
        except Exception as e:
            print(f"Error in _get_referral_data: {e}")
            # Fallback to repository method with max take
            data_query_info = query_info.__class__(
                sort_by=query_info.sort_by,
                sort_desc=query_info.sort_desc,
                search=query_info.search,
                search_fields=query_info.search_fields,
                filters=current_filters,
                take=1000,
                skip=0,
            )
            
            referrals, total = repo.query_with_filters(data_query_info)
            referral_dicts = [repo.to_dict(referral) for referral in referrals]
            
            if selected_indices is not None:
                filtered_referrals = [referral_dicts[i] for i in selected_indices if i < len(referral_dicts)]
                return filtered_referrals, len(filtered_referrals)
            
            return referral_dicts, total
    
    def generate_pdf_content(
        self, 
        db, 
        user_id: int, 
        query_info, 
        selected_indices: List[int] | None = None, 
        stats: Dict[str, Any] | None = None, 
        calendar_type: CalendarType = "jalali", 
        locale: str = "fa", 
        common_data: Dict[str, Any] = None
    ) -> bytes:
        """Generate PDF content using the new signature"""
        # Get referral data
        referrals_data, total_count = self._get_referral_data(db, user_id, query_info, selected_indices)
        
        # Format datetime fields for display in PDF
        for item in referrals_data:
            if 'created_at' in item and item['created_at']:
                if isinstance(item['created_at'], datetime):
                    from app.core.calendar import CalendarConverter
                    formatted_date = CalendarConverter.format_datetime(item['created_at'], calendar_type)
                    item['formatted_created_at'] = formatted_date['formatted']
                else:
                    try:
                        dt = datetime.fromisoformat(item['created_at'].replace('Z', '+00:00'))
                        from app.core.calendar import CalendarConverter
                        formatted_date = CalendarConverter.format_datetime(dt, calendar_type)
                        item['formatted_created_at'] = formatted_date['formatted']
                    except:
                        item['formatted_created_at'] = str(item['created_at'])
            else:
                item['formatted_created_at'] = '-'
        
        # Prepare context for template
        from app.core.calendar import CalendarConverter
        current_time = datetime.now()
        formatted_current_time = CalendarConverter.format_datetime(current_time, calendar_type)
        
        context = {
            'items': referrals_data,
            'total_count': total_count,
            'stats': stats,
            'filters': self._format_filters(query_info, locale, calendar_type),
            'report_date': formatted_current_time['date_only'],
            'report_time': formatted_current_time['time_only'],
            'locale': locale,
            'selected_only': selected_indices is not None and len(selected_indices) > 0,
        }
        
        # Include common data if provided
        if common_data:
            context.update(common_data)
        
        # Get translator
        t = self.get_translator(locale)
        context['t'] = t.t  # Pass the t method instead of the object
        
        # Render template
        html_content = self.render_template(self.template_name, context)
        
        # Generate PDF from HTML
        from weasyprint import HTML
        from pathlib import Path
        pdf_file = HTML(string=html_content, base_url=str(Path(__file__).parent / "templates")).write_pdf(font_config=self.font_config)
        return pdf_file
    
    def generate_excel_content(
        self, 
        db, 
        user_id: int, 
        query_info, 
        selected_indices: List[int] | None = None, 
        calendar_type: CalendarType = "jalali", 
        locale: str = "fa", 
        common_data: Dict[str, Any] = None
    ) -> List[Dict[str, Any]]:
        """Generate Excel content using the new signature"""
        # Get referral data
        referrals_data, total_count = self._get_referral_data(db, user_id, query_info, selected_indices)
        
        # Format data for Excel with calendar support
        excel_data = []
        t = self.get_translator(locale)
        
        for i, item in enumerate(referrals_data, 1):
            # Format created_at based on calendar type
            created_at = item.get('created_at', '')
            if created_at and isinstance(created_at, datetime):
                from app.core.calendar import CalendarConverter
                formatted_date = CalendarConverter.format_datetime(created_at, calendar_type)
                created_at = formatted_date['formatted']
            elif created_at and isinstance(created_at, str):
                try:
                    dt = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                    from app.core.calendar import CalendarConverter
                    formatted_date = CalendarConverter.format_datetime(dt, calendar_type)
                    created_at = formatted_date['formatted']
                except:
                    pass
            
            excel_data.append({
                t.t('rowNumber'): i,
                t.t('firstName'): item.get('first_name', ''),
                t.t('lastName'): item.get('last_name', ''),
                t.t('email'): item.get('email', ''),
                t.t('registrationDate'): created_at,
                t.t('referralCode'): item.get('referral_code', ''),
                t.t('status'): t.t('active') if item.get('is_active', False) else t.t('inactive')
            })
        
        return excel_data
