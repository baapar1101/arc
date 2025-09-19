from fastapi import APIRouter
from .schemas import SuccessResponse

router = APIRouter(prefix="/health", tags=["health"]) 


@router.get("", 
	summary="بررسی وضعیت سرویس", 
	description="بررسی وضعیت کلی سرویس و در دسترس بودن آن",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "سرویس در دسترس است",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "سرویس در دسترس است",
						"data": {
							"status": "ok",
							"timestamp": "2024-01-01T00:00:00Z"
						}
					}
				}
			}
		}
	}
)
def health() -> dict[str, str]:
	return {"status": "ok"}
