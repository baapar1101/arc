from __future__ import annotations

from typing import Any, Optional

from sqlalchemy.orm import Session

from app.core.auth_dependency import AuthContext
from app.services.ai.ai_ops_metrics import log_ai_event
from app.services.ai.ai_service import AIService


def log_voice_media_usage(
	db: Session,
	ctx: AuthContext,
	business_id: Optional[int],
	*,
	kind: str,
	provider: str,
	model: str,
	duration_ms: int,
	char_count: int = 0,
	cloud: bool = False,
	extra: Optional[dict[str, Any]] = None,
) -> None:
	context = {
		"type": f"voice_{kind}",
		"duration_ms": duration_ms,
		"char_count": char_count,
		"cloud": cloud,
	}
	if extra:
		context.update(extra)
	try:
		service = AIService(db, ctx, business_id)
		service.log_usage(
			provider=provider,
			model=model,
			input_tokens=0,
			output_tokens=0,
			cost=0,
			payment_method="free",
			context=context,
		)
	except Exception:
		log_ai_event(
			f"voice_{kind}_usage",
			business_id=business_id,
			user_id=ctx.get_user_id(),
			extra=context,
		)
