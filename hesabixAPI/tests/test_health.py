import pytest
from httpx import AsyncClient, ASGITransport
from fastapi import status

from app.main import app


@pytest.mark.asyncio
async def test_health_returns_ok() -> None:
	transport = ASGITransport(app=app)
	async with AsyncClient(transport=transport, base_url="http://test") as ac:
		response = await ac.get("/api/v1/health")
	assert response.status_code == status.HTTP_200_OK
	assert response.json() == {"status": "ok"}
