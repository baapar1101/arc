from __future__ import annotations

import posixpath
from dataclasses import dataclass
from ftplib import FTP, FTP_TLS, error_perm
from io import BytesIO
from typing import Any

from sqlalchemy.orm import Session

from adapters.db.models.business_ftp_backup_setting import BusinessFtpBackupSetting
from app.services.encryption_service import get_encryption_service


@dataclass
class FtpConnectionParams:
	host: str
	port: int
	username: str
	password: str
	remote_path: str
	passive: bool
	use_ftps: bool


def _normalize_remote_path(path: str) -> str:
	p = (path or "").strip() or "/"
	if not p.startswith("/"):
		p = "/" + p
	return p


def _connect(params: FtpConnectionParams, timeout: int = 45):
	if params.use_ftps:
		ftp: FTP | FTP_TLS = FTP_TLS()
		ftp.connect(params.host, params.port, timeout=timeout)
		ftp.login(params.username, params.password)
		try:
			ftp.prot_p()
		except Exception:
			pass
	else:
		ftp = FTP()
		ftp.connect(params.host, params.port, timeout=timeout)
		ftp.login(params.username, params.password)
	ftp.set_pasv(params.passive)
	return ftp


def test_connection(params: FtpConnectionParams) -> dict[str, Any]:
	ftp = _connect(params)
	try:
		rp = _normalize_remote_path(params.remote_path)
		try:
			ftp.cwd(rp)
		except error_perm:
			parts = [p for p in rp.split("/") if p]
			ftp.cwd("/")
			for p in parts:
				try:
					ftp.cwd(p)
				except error_perm:
					ftp.mkd(p)
					ftp.cwd(p)
		# یک لیست کوتاه برای اطمینان از دسترسی خواندن
		names = []
		try:
			ftp.retrlines("NLST", names.append)
		except Exception:
			pass
		return {"ok": True, "cwd": ftp.pwd(), "sample_count": min(len(names), 20)}
	finally:
		try:
			ftp.quit()
		except Exception:
			try:
				ftp.close()
			except Exception:
				pass


def upload_bytes(params: FtpConnectionParams, filename: str, data: bytes) -> dict[str, Any]:
	ftp = _connect(params)
	try:
		rp = _normalize_remote_path(params.remote_path)
		try:
			ftp.cwd(rp)
		except error_perm:
			parts = [p for p in rp.split("/") if p]
			ftp.cwd("/")
			for p in parts:
				try:
					ftp.cwd(p)
				except error_perm:
					ftp.mkd(p)
					ftp.cwd(p)
		remote_name = posixpath.basename(filename) or "backup.hbx"
		bio = BytesIO(data)
		ftp.storbinary(f"STOR {remote_name}", bio, blocksize=65536)
		return {"remote_path": ftp.pwd(), "remote_filename": remote_name}
	finally:
		try:
			ftp.quit()
		except Exception:
			try:
				ftp.close()
			except Exception:
				pass


def scan_usage(
	params: FtpConnectionParams,
	*,
	max_files: int = 8000,
	max_depth: int = 14,
) -> dict[str, Any]:
	ftp = _connect(params)
	bytes_total = 0
	files = 0
	truncated = False

	def process_dir(abs_path: str, depth: int) -> None:
		nonlocal bytes_total, files, truncated
		if files >= max_files or depth > max_depth:
			truncated = True
			return
		try:
			before = ftp.pwd()
		except Exception:
			before = "/"
		try:
			ftp.cwd(abs_path)
		except Exception:
			return
		try:
			listing = list(ftp.mlsd())
		except Exception:
			try:
				ftp.cwd(before)
			except Exception:
				pass
			return
		for name, facts in listing:
			if files >= max_files:
				truncated = True
				break
			if name in (".", ".."):
				continue
			typ = (facts.get("type") or "").lower()
			if typ == "file":
				try:
					bytes_total += int(facts.get("size") or 0)
				except (TypeError, ValueError):
					pass
				files += 1
			elif typ == "dir":
				here = ftp.pwd()
				child = posixpath.join(here.rstrip("/") or "/", name)
				if not child.startswith("/"):
					child = "/" + child
				process_dir(child, depth + 1)
				try:
					ftp.cwd(here)
				except Exception:
					break
		try:
			ftp.cwd(before)
		except Exception:
			pass

	try:
		root = _normalize_remote_path(params.remote_path)
		process_dir(root, 0)
		return {
			"total_bytes": bytes_total,
			"file_count": files,
			"truncated": truncated,
			"root": root,
		}
	finally:
		try:
			ftp.quit()
		except Exception:
			try:
				ftp.close()
			except Exception:
				pass


def load_decrypted_params(db: Session, business_id: int) -> FtpConnectionParams | None:
	row = db.query(BusinessFtpBackupSetting).filter(BusinessFtpBackupSetting.business_id == business_id).first()
	if not row or not row.password_encrypted:
		return None
	try:
		password = get_encryption_service().decrypt(row.password_encrypted)
	except Exception:
		return None
	return FtpConnectionParams(
		host=row.host,
		port=int(row.port or 21),
		username=row.username,
		password=password,
		remote_path=row.remote_path or "/",
		passive=bool(row.passive),
		use_ftps=bool(row.use_ftps),
	)


def row_to_public_dict(row: BusinessFtpBackupSetting | None) -> dict[str, Any]:
	if not row:
		return {"configured": False}
	return {
		"configured": True,
		"host": row.host,
		"port": row.port,
		"username": row.username,
		"has_password": bool(row.password_encrypted),
		"remote_path": row.remote_path,
		"passive": row.passive,
		"use_ftps": row.use_ftps,
		"updated_at": row.updated_at.isoformat() if row.updated_at else None,
	}
