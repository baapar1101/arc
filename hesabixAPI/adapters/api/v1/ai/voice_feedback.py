from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, Request, Path, Body
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.models.ai_voice_interaction import AIVoiceInteraction
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError


router = APIRouter(prefix="/ai/voice", tags=["هوش مصنوعی"])


class VoiceFeedbackRequest(BaseModel):
	rating: int = Field(..., ge=1, le=5, description="امتیاز کیفیت صدا (1 تا 5)")
	feedback_text: Optional[str] = Field(None, description="نظر کاربر درباره کیفیت صدا")


@router.post("/interactions/{interaction_id}/feedback", summary="ثبت بازخورد کیفیت صدای AI")
async def submit_voice_feedback(
	interaction_id: int = Path(...),
	request: Request = None,
	payload: VoiceFeedbackRequest = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	obj = db.get(AIVoiceInteraction, interaction_id)
	if not obj:
		raise ApiError("NOT_FOUND", "تعامل صوتی یافت نشد", http_status=404)
	if obj.user_id != ctx.get_user_id():
		raise ApiError("FORBIDDEN", "دسترسی غیرمجاز", http_status=403)

	obj.rating = payload.rating
	obj.feedback_text = payload.feedback_text
	db.add(obj)
	db.commit()

	return success_response({"id": obj.id, "rating": obj.rating}, request, "بازخورد ثبت شد")


