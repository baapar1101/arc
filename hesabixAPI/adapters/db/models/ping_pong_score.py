from __future__ import annotations

from datetime import datetime

from sqlalchemy import Integer, DateTime, ForeignKey, Float, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class PingPongScore(Base):
    __tablename__ = "ping_pong_scores"
    
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    score: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    survival_time: Mapped[int] = mapped_column(Integer, nullable=False, comment="زمان زنده ماندن به ثانیه")
    hero_mode_uses: Mapped[int] = mapped_column(Integer, default=0, nullable=False, comment="تعداد استفاده از حالت قهرمان")
    difficulty_level: Mapped[float] = mapped_column(Float, default=1.0, nullable=False, comment="آخرین سطح سختی")
    played_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    
    # Relationships
    user = relationship("User", backref="ping_pong_scores")
    
    # Indexes for performance
    __table_args__ = (
        Index('idx_ping_pong_score', 'score', postgresql_ops={'score': 'DESC'}),
        Index('idx_ping_pong_user_score', 'user_id', 'score'),
    )

