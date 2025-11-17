from typing import Dict, Any
from fastapi import APIRouter, Depends, Request, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.api.v1.schemas import SuccessResponse
from app.core.responses import success_response, format_datetime_fields
from app.core.auth_dependency import get_current_user, AuthContext
from adapters.db.repositories.ping_pong_repository import PingPongRepository

router = APIRouter(prefix="/ping-pong", tags=["ping-pong"])

class SaveScoreRequest(BaseModel):
    score: int = Field(..., ge=0, description="امتیاز نهایی (بر حسب ثانیه بقا)")
    survival_time: int = Field(..., ge=0, description="زمان بقا به ثانیه")
    hero_mode_uses: int = Field(0, ge=0, le=3, description="تعداد دفعات استفاده از حالت قهرمان")
    difficulty_level: float = Field(1.0, ge=1.0, description="ضریب سختی نهایی")


@router.post(
    "/scores",
    summary="ذخیره امتیاز بازی پینگ‌پنگ",
    description="ذخیره امتیاز و اطلاعات بازی پینگ‌پنگ کاربر",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "امتیاز با موفقیت ذخیره شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "امتیاز با موفقیت ذخیره شد",
                        "data": {
                            "id": 123,
                            "user_id": 45,
                            "score": 120,
                            "survival_time": 120,
                            "hero_mode_uses": 2,
                            "difficulty_level": 2.5,
                            "played_at": "2024-01-15T10:30:00Z",
                            "created_at": "2024-01-15T10:30:00Z",
                        }
                    }
                }
            }
        },
        400: {
            "description": "خطا در اعتبارسنجی داده‌ها"
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        }
    }
)
def save_score(
    request: Request,
    payload: SaveScoreRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """ذخیره امتیاز جدید"""
    if payload.score < 0 or payload.survival_time < 0:
        raise HTTPException(status_code=400, detail="امتیاز و زمان نمی‌توانند منفی باشند")
    
    if payload.hero_mode_uses < 0 or payload.hero_mode_uses > 3:
        raise HTTPException(status_code=400, detail="تعداد استفاده از حالت قهرمان باید بین 0 تا 3 باشد")
    
    if payload.difficulty_level < 1.0:
        raise HTTPException(status_code=400, detail="سطح سختی نمی‌تواند کمتر از 1 باشد")
    
    repo = PingPongRepository(db)
    result = repo.create_score(
        user_id=ctx.get_user_id(),
        score=payload.score,
        survival_time=payload.survival_time,
        hero_mode_uses=payload.hero_mode_uses,
        difficulty_level=payload.difficulty_level,
    )
    
    data = {
        "id": result.id,
        "user_id": result.user_id,
        "score": result.score,
        "survival_time": result.survival_time,
        "hero_mode_uses": result.hero_mode_uses,
        "difficulty_level": result.difficulty_level,
        "played_at": result.played_at.isoformat(),
        "created_at": result.created_at.isoformat(),
    }
    
    return success_response(
        data=format_datetime_fields(data, request),
        request=request,
        message="امتیاز با موفقیت ذخیره شد"
    )


@router.get(
    "/scores/best",
    summary="دریافت بهترین امتیاز کاربر",
    description="دریافت بهترین امتیاز کاربر جاری",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "بهترین امتیاز با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "data": {
                            "id": 123,
                            "user_id": 45,
                            "score": 180,
                            "survival_time": 180,
                            "hero_mode_uses": 1,
                            "difficulty_level": 3.0,
                            "played_at": "2024-01-10T15:20:00Z",
                            "created_at": "2024-01-10T15:20:00Z",
                        }
                    }
                }
            }
        },
        404: {
            "description": "هیچ امتیازی یافت نشد"
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        }
    }
)
def get_best_score(
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """دریافت بهترین امتیاز کاربر"""
    repo = PingPongRepository(db)
    best_score = repo.get_best_score(ctx.get_user_id())
    
    if not best_score:
        raise HTTPException(status_code=404, detail="هیچ امتیازی یافت نشد")
    
    data = {
        "id": best_score.id,
        "user_id": best_score.user_id,
        "score": best_score.score,
        "survival_time": best_score.survival_time,
        "hero_mode_uses": best_score.hero_mode_uses,
        "difficulty_level": best_score.difficulty_level,
        "played_at": best_score.played_at.isoformat(),
        "created_at": best_score.created_at.isoformat(),
    }
    
    return success_response(
        data=format_datetime_fields(data, request),
        request=request
    )


@router.get(
    "/scores/leaderboard",
    summary="دریافت جدول رده‌بندی",
    description="دریافت جدول رده‌بندی 10 نفر برتر",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "جدول رده‌بندی با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "data": [
                            {
                                "user_id": 10,
                                "user_name": "علی احمدی",
                                "score": 300,
                                "survival_time": 300,
                                "played_at": "2024-01-15T12:00:00Z",
                                "rank": 1
                            }
                        ]
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        }
    }
)
def get_leaderboard(
    request: Request,
    limit: int = Query(10, ge=1, le=50, description="تعداد نتایج"),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """دریافت جدول رده‌بندی"""
    repo = PingPongRepository(db)
    leaderboard = repo.get_leaderboard(limit=limit)
    
    return success_response(
        data=leaderboard,
        request=request
    )


@router.get(
    "/scores/stats",
    summary="دریافت آمار کاربر",
    description="دریافت آمار کامل بازی‌های کاربر",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "آمار با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "data": {
                            "total_games": 25,
                            "best_score": 180,
                            "best_survival_time": 180,
                            "average_score": 95.5,
                            "total_playtime": 2387,
                            "hero_mode_uses_total": 45
                        }
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        }
    }
)
def get_stats(
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """دریافت آمار کاربر"""
    repo = PingPongRepository(db)
    stats = repo.get_user_stats(ctx.get_user_id())
    
    return success_response(
        data=stats,
        request=request
    )

