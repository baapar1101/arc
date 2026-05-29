from __future__ import annotations

from typing import Optional

from pydantic import BaseModel, Field, field_validator

from app.services.legacy_import.mappers import normalize_server_url


class LegacyImportPreviewRequest(BaseModel):
    server_url: str = Field(
        default="https://app.hesabix.ir",
        description="آدرس سرور نسخه قدیم (مثلاً https://app.hesabix.ir)",
    )
    api_key: str = Field(..., min_length=8, max_length=128, description="کلید API نسخه قدیم")

    @field_validator("server_url", mode="before")
    @classmethod
    def _norm_server(cls, v: object) -> str:
        return normalize_server_url(str(v or ""))

    @field_validator("api_key", mode="before")
    @classmethod
    def _strip_key(cls, v: object) -> str:
        return str(v or "").strip()


class LegacyImportOptionsSchema(BaseModel):
    business_name_override: Optional[str] = Field(default=None, max_length=255)
    business_name_suffix: str = Field(default="", max_length=64)
    import_persons: bool = True
    import_products: bool = True
    import_banks: bool = True
    import_warehouses: bool = True
    import_documents: bool = True
    import_files: bool = True


class LegacyImportExecuteRequest(LegacyImportPreviewRequest):
    options: Optional[LegacyImportOptionsSchema] = None


class LegacyImportPreviewResponse(BaseModel):
    server_url: str
    api_key_masked: str
    legacy_business_id: Optional[int] = None
    business_name: Optional[str] = None
    businesses_accessible: int = 1
    archive_size_bytes: int = 0
    counts: dict = Field(default_factory=dict)
    manifest: dict = Field(default_factory=dict)
    warnings: list[str] = Field(default_factory=list)
