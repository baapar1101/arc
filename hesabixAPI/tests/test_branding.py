from pathlib import Path
from unittest.mock import MagicMock

from fastapi import FastAPI
from fastapi.testclient import TestClient

from adapters.api.v1.system_branding import router as system_branding_router
from app.core.auth_dependency import get_current_user
from app.core.branding import (
	branding_display_names,
	branding_public_payload,
	etags_match,
	resolve_branding_state,
)

_MIN_PNG = bytes.fromhex(
	"89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
	"0000000a49444154789c63000100000500010d0a2db40000000049454e44ae426082"
)


def _write_deploy_env(path: Path, body: str) -> Path:
	path.write_text(body, encoding="utf-8")
	return path


def test_default_mode_ignores_names(monkeypatch, tmp_path):
	env_file = _write_deploy_env(
		tmp_path / "deploy.env",
		"BRANDING_MODE=default\nAPP_NAME_FA=فروشگاه آرک\nAPP_NAME_EN=Arc Shop\n",
	)
	monkeypatch.setenv("HESABIX_DEPLOY_ENV", str(env_file))
	monkeypatch.delenv("APP_NAME_FA", raising=False)
	monkeypatch.delenv("APP_NAME_EN", raising=False)
	monkeypatch.delenv("BRANDING_MODE", raising=False)
	assert branding_display_names() == ("", "")
	state = resolve_branding_state()
	assert state.enabled is False
	assert branding_public_payload()["mode"] == "default"


def test_empty_mode_is_default_even_with_names(monkeypatch, tmp_path):
	env_file = _write_deploy_env(
		tmp_path / "deploy.env",
		"APP_NAME_FA=فروشگاه آرک\nAPP_NAME_EN=Arc Shop\n",
	)
	monkeypatch.setenv("HESABIX_DEPLOY_ENV", str(env_file))
	monkeypatch.delenv("APP_NAME_FA", raising=False)
	monkeypatch.delenv("APP_NAME_EN", raising=False)
	monkeypatch.delenv("BRANDING_MODE", raising=False)
	assert branding_display_names() == ("", "")


def test_custom_mode_reads_deploy_env_names(monkeypatch, tmp_path):
	env_file = _write_deploy_env(
		tmp_path / "deploy.env",
		"BRANDING_MODE=custom\nAPP_NAME_FA=فروشگاه آرک\nAPP_NAME_EN=Arc Shop\n",
	)
	monkeypatch.setenv("HESABIX_DEPLOY_ENV", str(env_file))
	monkeypatch.delenv("APP_NAME_FA", raising=False)
	monkeypatch.delenv("APP_NAME_EN", raising=False)
	monkeypatch.delenv("BRANDING_MODE", raising=False)
	assert branding_display_names() == ("فروشگاه آرک", "Arc Shop")
	payload = branding_public_payload()
	assert payload["enabled"] is True
	assert payload["has_logo"] is False


def test_custom_pack_logo_and_names_json(monkeypatch, tmp_path):
	pack = tmp_path / "branding"
	pack.mkdir()
	(pack / "names.json").write_text('{"fa": "آرک", "en": "Arc"}', encoding="utf-8")
	(pack / "logo-blue.png").write_bytes(_MIN_PNG)
	env_file = _write_deploy_env(
		tmp_path / "deploy.env",
		f"BRANDING_MODE=custom\nBRANDING_DIR={pack}\n",
	)
	monkeypatch.setenv("HESABIX_DEPLOY_ENV", str(env_file))
	monkeypatch.delenv("APP_NAME_FA", raising=False)
	monkeypatch.delenv("APP_NAME_EN", raising=False)
	monkeypatch.delenv("BRANDING_MODE", raising=False)
	monkeypatch.delenv("BRANDING_DIR", raising=False)
	state = resolve_branding_state()
	assert state.enabled is True
	assert state.name_fa == "آرک"
	assert state.has_logo is True
	payload = branding_public_payload()
	assert payload["has_logo"] is True
	assert payload["logo_content_type"] == "image/png"
	assert payload["logo_etag"]


def test_etags_match_ignores_quotes_and_weak_prefix():
	current = 'W/"abc-def"'
	assert etags_match('W/"abc-def"', current) is True
	assert etags_match('"abc-def"', current) is True
	assert etags_match('abc-def', current) is True
	assert etags_match('W/"abc-def", W/"other"', current) is True
	assert etags_match('W/"nope"', current) is False
	assert etags_match(None, current) is False
	assert etags_match('', current) is False


def _branding_client() -> TestClient:
	app = FastAPI()
	app.include_router(system_branding_router, prefix="/api/v1")
	app.dependency_overrides[get_current_user] = lambda: MagicMock()
	return TestClient(app)


def test_system_branding_endpoint_default(monkeypatch, tmp_path):
	env_file = _write_deploy_env(tmp_path / "deploy.env", "BRANDING_MODE=default\n")
	monkeypatch.setenv("HESABIX_DEPLOY_ENV", str(env_file))
	monkeypatch.delenv("BRANDING_MODE", raising=False)
	client = _branding_client()
	res = client.get("/api/v1/system/branding")
	assert res.status_code == 200
	body = res.json()
	assert body["success"] is True
	assert body["data"]["enabled"] is False
	assert body["data"]["mode"] == "default"
	assert body["data"]["name_fa"] == ""
	logo = client.get("/api/v1/system/branding/logo")
	assert logo.status_code == 404


def test_system_branding_endpoint_custom_with_logo(monkeypatch, tmp_path):
	pack = tmp_path / "branding"
	pack.mkdir()
	(pack / "logo-blue.png").write_bytes(_MIN_PNG)
	env_file = _write_deploy_env(
		tmp_path / "deploy.env",
		f"BRANDING_MODE=custom\nBRANDING_DIR={pack}\nAPP_NAME_FA=آرک\nAPP_NAME_EN=Arc\n",
	)
	monkeypatch.setenv("HESABIX_DEPLOY_ENV", str(env_file))
	monkeypatch.delenv("APP_NAME_FA", raising=False)
	monkeypatch.delenv("APP_NAME_EN", raising=False)
	monkeypatch.delenv("BRANDING_MODE", raising=False)
	monkeypatch.delenv("BRANDING_DIR", raising=False)
	client = _branding_client()
	res = client.get("/api/v1/system/branding")
	assert res.status_code == 200
	data = res.json()["data"]
	assert data["enabled"] is True
	assert data["name_fa"] == "آرک"
	assert data["has_logo"] is True
	logo = client.get("/api/v1/system/branding/logo")
	assert logo.status_code == 200
	assert logo.content[:8] == b"\x89PNG\r\n\x1a\n"
	etag = logo.headers.get("etag")
	assert etag
	cached = client.get("/api/v1/system/branding/logo", headers={"If-None-Match": etag})
	assert cached.status_code == 304
	quoted = client.get(
		"/api/v1/system/branding/logo",
		headers={"If-None-Match": data["logo_etag"]},
	)
	assert quoted.status_code == 304
