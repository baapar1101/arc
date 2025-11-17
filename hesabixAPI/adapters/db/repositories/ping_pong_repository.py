from __future__ import annotations

from typing import Optional, List, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import select, desc, func
from datetime import datetime

from adapters.db.models.ping_pong_score import PingPongScore
from adapters.db.models.user import User


class PingPongRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def create_score(
        self,
        user_id: int,
        score: int,
        survival_time: int,
        hero_mode_uses: int,
        difficulty_level: float,
    ) -> PingPongScore:
        """ذخیره امتیاز جدید"""
        ping_pong_score = PingPongScore(
            user_id=user_id,
            score=score,
            survival_time=survival_time,
            hero_mode_uses=hero_mode_uses,
            difficulty_level=difficulty_level,
            played_at=datetime.utcnow(),
        )
        self.db.add(ping_pong_score)
        self.db.commit()
        self.db.refresh(ping_pong_score)
        return ping_pong_score

    def get_best_score(self, user_id: int) -> Optional[PingPongScore]:
        """دریافت بهترین امتیاز کاربر"""
        stmt = (
            select(PingPongScore)
            .where(PingPongScore.user_id == user_id)
            .order_by(desc(PingPongScore.score))
            .limit(1)
        )
        return self.db.execute(stmt).scalars().first()

    def get_leaderboard(self, limit: int = 10) -> List[Dict[str, Any]]:
        """دریافت جدول رده‌بندی (10 نفر برتر)"""
        stmt = (
            select(
                PingPongScore.user_id,
                User.first_name,
                User.last_name,
                PingPongScore.score,
                PingPongScore.survival_time,
                PingPongScore.played_at,
            )
            .join(User, PingPongScore.user_id == User.id)
            .order_by(desc(PingPongScore.score))
            .limit(limit)
        )
        
        results = self.db.execute(stmt).all()
        leaderboard = []
        for rank, row in enumerate(results, start=1):
            user_name = f"{row.first_name or ''} {row.last_name or ''}".strip()
            if not user_name:
                user_name = "کاربر ناشناس"
            
            leaderboard.append({
                "user_id": row.user_id,
                "user_name": user_name,
                "score": row.score,
                "survival_time": row.survival_time,
                "played_at": row.played_at.isoformat(),
                "rank": rank,
            })
        
        return leaderboard

    def get_user_stats(self, user_id: int) -> Dict[str, Any]:
        """دریافت آمار کاربر"""
        # تعداد کل بازی‌ها
        total_games_stmt = (
            select(func.count(PingPongScore.id))
            .where(PingPongScore.user_id == user_id)
        )
        total_games = self.db.execute(total_games_stmt).scalar() or 0

        # بهترین امتیاز
        best_score = self.get_best_score(user_id)
        best_score_value = best_score.score if best_score else 0
        best_survival_time = best_score.survival_time if best_score else 0

        # میانگین امتیاز
        avg_score_stmt = (
            select(func.avg(PingPongScore.score))
            .where(PingPongScore.user_id == user_id)
        )
        avg_score = self.db.execute(avg_score_stmt).scalar()
        average_score = float(avg_score) if avg_score else 0.0

        # مجموع زمان بازی
        total_playtime_stmt = (
            select(func.sum(PingPongScore.survival_time))
            .where(PingPongScore.user_id == user_id)
        )
        total_playtime = self.db.execute(total_playtime_stmt).scalar() or 0

        # مجموع استفاده از حالت قهرمان
        total_hero_uses_stmt = (
            select(func.sum(PingPongScore.hero_mode_uses))
            .where(PingPongScore.user_id == user_id)
        )
        total_hero_uses = self.db.execute(total_hero_uses_stmt).scalar() or 0

        return {
            "total_games": total_games,
            "best_score": best_score_value,
            "best_survival_time": best_survival_time,
            "average_score": round(average_score, 2),
            "total_playtime": total_playtime,
            "hero_mode_uses_total": total_hero_uses,
        }

