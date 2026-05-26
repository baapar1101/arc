"""پیوست فایل متنی برای گفت‌وگوی AI."""
from __future__ import annotations

import io
import logging
import re
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.ai_chat_attachment import AIChatAttachment
from app.core.responses import ApiError

logger = logging.getLogger(__name__)

MAX_FILE_BYTES = 512 * 1024
MAX_EXTRACTED_CHARS = 20_000
MAX_ATTACHMENTS_PER_SESSION = 10

ALLOWED_EXTENSIONS = {".txt", ".md", ".csv", ".json", ".log", ".xml", ".html", ".htm"}


def _extension(filename: str) -> str:
    if "." not in filename:
        return ""
    return filename[filename.rfind(".") :].lower()


def extract_text_from_bytes(filename: str, data: bytes, mime_type: Optional[str] = None) -> str:
    ext = _extension(filename)
    if ext == ".pdf":
        try:
            from pypdf import PdfReader

            reader = PdfReader(io.BytesIO(data))
            parts = []
            for page in reader.pages[:40]:
                parts.append(page.extract_text() or "")
            text = "\n".join(parts)
        except ImportError:
            raise ApiError(
                "PDF_NOT_SUPPORTED",
                "استخراج PDF در سرور فعال نیست. فایل txt یا csv آپلود کنید.",
                http_status=400,
            )
        except Exception as exc:
            raise ApiError(
                "PDF_PARSE_ERROR",
                f"خطا در خواندن PDF: {exc}",
                http_status=400,
            )
    elif ext in ALLOWED_EXTENSIONS or (mime_type and mime_type.startswith("text/")):
        text = ""
        for encoding in ("utf-8", "utf-8-sig", "cp1256", "latin-1"):
            try:
                text = data.decode(encoding)
                break
            except UnicodeDecodeError:
                continue
        if not text:
            raise ApiError("ENCODING_ERROR", "رمزگذاری فایل پشتیبانی نمی‌شود", http_status=400)
    else:
        raise ApiError(
            "UNSUPPORTED_FILE_TYPE",
            "فقط فایل‌های متنی (txt, md, csv, json) و PDF پشتیبانی می‌شوند",
            http_status=400,
        )

    text = re.sub(r"\s+\n", "\n", text.strip())
    if len(text) > MAX_EXTRACTED_CHARS:
        text = text[:MAX_EXTRACTED_CHARS] + "\n… [متن کوتاه شد]"
    if not text:
        raise ApiError("EMPTY_FILE", "محتوای قابل استفاده‌ای در فایل یافت نشد", http_status=400)
    return text


def create_attachment(
    db: Session,
    session_id: int,
    user_id: int,
    filename: str,
    file_bytes: bytes,
    mime_type: Optional[str] = None,
) -> AIChatAttachment:
    if len(file_bytes) > MAX_FILE_BYTES:
        raise ApiError(
            "FILE_TOO_LARGE",
            f"حداکثر حجم فایل {MAX_FILE_BYTES // 1024} کیلوبایت است",
            http_status=400,
        )

    count = (
        db.query(AIChatAttachment)
        .filter(AIChatAttachment.session_id == session_id)
        .count()
    )
    if count >= MAX_ATTACHMENTS_PER_SESSION:
        raise ApiError(
            "TOO_MANY_ATTACHMENTS",
            f"حداکثر {MAX_ATTACHMENTS_PER_SESSION} پیوست در هر گفت‌وگو",
            http_status=400,
        )

    text = extract_text_from_bytes(filename, file_bytes, mime_type)
    row = AIChatAttachment(
        session_id=session_id,
        user_id=user_id,
        filename=filename[:512],
        mime_type=mime_type,
        extracted_text=text,
        char_count=len(text),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def list_session_attachments(db: Session, session_id: int) -> List[AIChatAttachment]:
    return (
        db.query(AIChatAttachment)
        .filter(AIChatAttachment.session_id == session_id)
        .order_by(AIChatAttachment.created_at.asc())
        .all()
    )


def delete_attachment(db: Session, attachment_id: int, user_id: int) -> bool:
    row = db.query(AIChatAttachment).filter(AIChatAttachment.id == attachment_id).first()
    if not row or row.user_id != user_id:
        return False
    db.delete(row)
    db.commit()
    return True


def attachment_to_dict(row: AIChatAttachment, include_text: bool = False) -> Dict[str, Any]:
    d: Dict[str, Any] = {
        "id": row.id,
        "session_id": row.session_id,
        "filename": row.filename,
        "mime_type": row.mime_type,
        "char_count": row.char_count,
        "created_at": row.created_at.isoformat() if row.created_at else None,
    }
    if include_text:
        d["extracted_text"] = row.extracted_text
    return d


def format_attachments_for_prompt(db: Session, session_id: int, max_chars: int = 12_000) -> str:
    rows = list_session_attachments(db, session_id)
    if not rows:
        return ""

    parts: List[str] = []
    used = 0
    for row in rows:
        header = f"\n[پیوست: {row.filename}]\n"
        body = row.extracted_text
        chunk = header + body
        if used + len(chunk) > max_chars:
            remaining = max_chars - used - len(header) - 20
            if remaining > 100:
                parts.append(header + body[:remaining] + "…")
            break
        parts.append(chunk)
        used += len(chunk)

    return (
        "\n\n--- پیوست‌های این گفت‌وگو (برای پاسخ به سوالات مرتبط استفاده کن) ---"
        + "".join(parts)
    )
