from typing import List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_, func
from datetime import datetime, timedelta
from adapters.db.models.ai_usage_log import AIUsageLog
from adapters.db.repositories.base_repo import BaseRepository


class AIUsageLogRepository(BaseRepository[AIUsageLog]):
    def __init__(self, db: Session):
        super().__init__(db, AIUsageLog)
    
    def get_user_usage(
        self,
        user_id: int,
        business_id: Optional[int] = None,
        from_date: Optional[datetime] = None,
        to_date: Optional[datetime] = None,
        limit: int = 100,
        skip: int = 0
    ) -> List[AIUsageLog]:
        """دریافت لاگ استفاده کاربر"""
        query = self.db.query(self.model_class).filter(
            self.model_class.user_id == user_id
        )
        
        if business_id:
            query = query.filter(self.model_class.business_id == business_id)
        
        if from_date:
            query = query.filter(self.model_class.created_at >= from_date)
        
        if to_date:
            query = query.filter(self.model_class.created_at <= to_date)
        
        return query.order_by(self.model_class.created_at.desc()).offset(skip).limit(limit).all()
    
    def get_usage_statistics(
        self,
        user_id: int,
        business_id: Optional[int] = None,
        from_date: Optional[datetime] = None,
        to_date: Optional[datetime] = None
    ) -> dict:
        """آمار استفاده کاربر"""
        query = self.db.query(self.model_class).filter(
            self.model_class.user_id == user_id
        )
        
        if business_id:
            query = query.filter(self.model_class.business_id == business_id)
        
        if from_date:
            query = query.filter(self.model_class.created_at >= from_date)
        
        if to_date:
            query = query.filter(self.model_class.created_at <= to_date)
        
        stats = query.with_entities(
            func.sum(self.model_class.input_tokens).label('total_input_tokens'),
            func.sum(self.model_class.output_tokens).label('total_output_tokens'),
            func.sum(self.model_class.cost).label('total_cost'),
            func.count(self.model_class.id).label('total_requests')
        ).first()
        
        return {
            "total_input_tokens": int(stats.total_input_tokens or 0),
            "total_output_tokens": int(stats.total_output_tokens or 0),
            "total_tokens": int((stats.total_input_tokens or 0) + (stats.total_output_tokens or 0)),
            "total_cost": float(stats.total_cost or 0),
            "total_requests": int(stats.total_requests or 0)
        }
    
    def get_business_usage_stats(
        self,
        business_id: int,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None
    ) -> dict:
        """آمار استفاده کسب و کار"""
        query = self.db.query(self.model_class).filter(
            self.model_class.business_id == business_id
        )
        
        if start_date:
            query = query.filter(self.model_class.created_at >= start_date)
        if end_date:
            query = query.filter(self.model_class.created_at <= end_date)
        
        stats = query.with_entities(
            func.sum(self.model_class.input_tokens).label('input_tokens'),
            func.sum(self.model_class.output_tokens).label('output_tokens'),
            func.sum(self.model_class.cost).label('total_cost'),
            func.count(self.model_class.id).label('total_requests')
        ).first()
        
        # Handle case when no records exist
        if stats is None:
            return {
                "input_tokens": 0,
                "output_tokens": 0,
                "total_tokens": 0,
                "total_cost": 0.0,
                "total_requests": 0
            }
        
        total_tokens = int((stats.input_tokens or 0) + (stats.output_tokens or 0))
        
        return {
            "input_tokens": int(stats.input_tokens or 0),
            "output_tokens": int(stats.output_tokens or 0),
            "total_tokens": total_tokens,
            "total_cost": float(stats.total_cost or 0),
            "total_requests": int(stats.total_requests or 0)
        }
    
    def get_daily_usage_stats(
        self,
        business_id: int,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None
    ) -> List[dict]:
        """آمار روزانه استفاده"""
        query = self.db.query(self.model_class).filter(
            self.model_class.business_id == business_id
        )
        
        if start_date:
            query = query.filter(self.model_class.created_at >= start_date)
        if end_date:
            query = query.filter(self.model_class.created_at <= end_date)
        
        # گروه‌بندی بر اساس تاریخ
        daily_stats = query.with_entities(
            func.date(self.model_class.created_at).label('date'),
            func.sum(self.model_class.input_tokens + self.model_class.output_tokens).label('tokens'),
            func.sum(self.model_class.cost).label('cost'),
            func.count(self.model_class.id).label('requests')
        ).group_by(
            func.date(self.model_class.created_at)
        ).order_by(
            func.date(self.model_class.created_at)
        ).all()
        
        return [
            {
                "date": stat.date,
                "tokens": int(stat.tokens or 0),
                "cost": float(stat.cost or 0),
                "requests": int(stat.requests or 0)
            }
            for stat in daily_stats
        ]
    
    def get_model_usage_stats(
        self,
        business_id: int,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None
    ) -> List[dict]:
        """آمار استفاده بر اساس مدل"""
        query = self.db.query(self.model_class).filter(
            self.model_class.business_id == business_id
        )
        
        if start_date:
            query = query.filter(self.model_class.created_at >= start_date)
        if end_date:
            query = query.filter(self.model_class.created_at <= end_date)
        
        model_stats = query.with_entities(
            self.model_class.model,
            func.sum(self.model_class.input_tokens + self.model_class.output_tokens).label('tokens'),
            func.sum(self.model_class.cost).label('cost'),
            func.count(self.model_class.id).label('requests')
        ).group_by(
            self.model_class.model
        ).order_by(
            func.sum(self.model_class.cost).desc()
        ).all()
        
        return [
            {
                "model": stat.model,
                "tokens": int(stat.tokens or 0),
                "cost": float(stat.cost or 0),
                "requests": int(stat.requests or 0)
            }
            for stat in model_stats
        ]
    
    def get_business_logs(
        self,
        business_id: int,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        limit: int = 50,
        skip: int = 0
    ) -> List[AIUsageLog]:
        """دریافت لاگ‌های کسب و کار"""
        query = self.db.query(self.model_class).filter(
            self.model_class.business_id == business_id
        )
        
        if start_date:
            query = query.filter(self.model_class.created_at >= start_date)
        if end_date:
            query = query.filter(self.model_class.created_at <= end_date)
        
        return query.order_by(
            self.model_class.created_at.desc()
        ).offset(skip).limit(limit).all()

