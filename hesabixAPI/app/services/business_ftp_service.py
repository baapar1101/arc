from __future__ import annotations

import logging
import posixpath
import stat as stat_mod
import time
from collections.abc import Callable
from dataclasses import dataclass
from ftplib import FTP, FTP_TLS, error_perm
from io import BytesIO
from typing import Any

import paramiko
from sqlalchemy.orm import Session

from adapters.db.models.business_ftp_backup_setting import BusinessFtpBackupSetting
from app.core.responses import ApiError
from app.services.encryption_service import get_encryption_service

logger = logging.getLogger(__name__)

FTP_UPLOAD_ATTEMPTS = 3
FTP_RETRY_BASE_SLEEP = 0.6


@dataclass
class FtpConnectionParams:
	host: str
	port: int
	username: str
	password: str
	remote_path: str
	passive: bool
	use_ftps: bool
	use_sftp: bool = False


def _normalize_remote_path(path: str) -> str:
	p = (path or "").strip() or "/"
	if not p.startswith("/"):
		p = "/" + p
	return p


def _with_upload_retries(operation: str, fn: Callable[[], Any]) -> Any:
	last: BaseException | None = None
	for attempt in range(1, FTP_UPLOAD_ATTEMPTS + 1):
		try:
			return fn()
		except (OSError, error_perm, EOFError) as e:
			last = e
			logger.warning(
				"business_ftp %s attempt %s/%s failed: %s",
				operation,
				attempt,
				FTP_UPLOAD_ATTEMPTS,
				e,
				exc_info=False,
			)
			if attempt >= FTP_UPLOAD_ATTEMPTS:
				raise
			time.sleep(FTP_RETRY_BASE_SLEEP * (2 ** (attempt - 1)))
	assert last is not None
	raise last


def _connect_ftp(params: FtpConnectionParams, timeout: int = 45) -> FTP | FTP_TLS:
	if params.use_ftps:
		ftp: FTP | FTP_TLS = FTP_TLS()
		ftp.connect(params.host, params.port, timeout=timeout)
		ftp.login(params.username, params.password)
		try:
			ftp.prot_p()
		except Exception as e:
			logger.warning("FTPS prot_p failed host=%s port=%s: %s", params.host, params.port, e)
			try:
				ftp.quit()
			except Exception:
				try:
					ftp.close()
				except Exception:
					pass
			raise OSError(
				"رمزنگاری کانال داده FTPS فعال نشد (prot_p). تنظیمات TLS سرور یا فایروال را بررسی کنید."
			) from e
	else:
		ftp = FTP()
		ftp.connect(params.host, params.port, timeout=timeout)
		ftp.login(params.username, params.password)
	ftp.set_pasv(params.passive)
	return ftp


def _sftp_connect(params: FtpConnectionParams, timeout: int = 45) -> tuple[paramiko.SFTPClient, paramiko.Transport]:
	t = paramiko.Transport((params.host, int(params.port)))
	t.connect(username=params.username, password=params.password)
	t.set_keepalive(20)
	sftp = paramiko.SFTPClient.from_transport(t)
	if sftp is None:
		t.close()
		raise OSError("SFTP: اتصال برقرار نشد")
	sftp.get_channel().settimeout(timeout)
	return sftp, t


def _sftp_ensure_dir(sftp: paramiko.SFTPClient, remote_dir: str) -> None:
	rp = _normalize_remote_path(remote_dir)
	parts = [p for p in rp.split("/") if p]
	cur = ""
	for p in parts:
		cur = f"{cur}/{p}" if cur else f"/{p}"
		try:
			sftp.stat(cur)
		except OSError:
			try:
				sftp.mkdir(cur)
			except OSError:
				# ممکن است هم‌زمان ساخته شده باشد
				try:
					sftp.stat(cur)
				except OSError as e:
					raise OSError(f"SFTP: نتوانست پوشه را بسازد: {cur}") from e


def _sftp_listdir_names(sftp: paramiko.SFTPClient, path: str) -> list[str]:
	try:
		return [a.filename for a in sftp.listdir_attr(path)]
	except OSError:
		return []


def test_connection(params: FtpConnectionParams) -> dict[str, Any]:
	if params.use_sftp:
		return _test_connection_sftp(params)
	return _test_connection_ftp(params)


def _test_connection_sftp(params: FtpConnectionParams) -> dict[str, Any]:
	sftp, t = _sftp_connect(params)
	try:
		rp = _normalize_remote_path(params.remote_path)
		_sftp_ensure_dir(sftp, rp)
		names = _sftp_listdir_names(sftp, rp)
		return {"ok": True, "cwd": rp, "sample_count": min(len(names), 20), "transport": "sftp"}
	finally:
		try:
			sftp.close()
		except Exception:
			pass
		try:
			t.close()
		except Exception:
			pass


def _test_connection_ftp(params: FtpConnectionParams) -> dict[str, Any]:
	ftp = _connect_ftp(params)
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
		names: list[str] = []
		try:
			ftp.retrlines("NLST", names.append)
		except Exception:
			pass
		return {"ok": True, "cwd": ftp.pwd(), "sample_count": min(len(names), 20), "transport": "ftp"}
	finally:
		try:
			ftp.quit()
		except Exception:
			try:
				ftp.close()
			except Exception:
				pass


def upload_bytes(
	params: FtpConnectionParams,
	filename: str,
	data: bytes | None = None,
	*,
	file_path: str | None = None,
) -> dict[str, Any]:
	if data is None and not file_path:
		raise ValueError("upload_bytes: data یا file_path لازم است")
	if params.use_sftp:
		return _with_upload_retries(
			"upload_sftp",
			lambda: _upload_bytes_sftp(params, filename, data=data, file_path=file_path),
		)
	return _with_upload_retries(
		"upload_ftp",
		lambda: _upload_bytes_ftp(params, filename, data=data, file_path=file_path),
	)


def _upload_bytes_sftp(
	params: FtpConnectionParams,
	filename: str,
	data: bytes | None,
	file_path: str | None,
) -> dict[str, Any]:
	sftp, t = _sftp_connect(params)
	try:
		rp = _normalize_remote_path(params.remote_path)
		_sftp_ensure_dir(sftp, rp)
		remote_name = posixpath.basename(filename) or "backup.hbx"
		remote_full = posixpath.join(rp.rstrip("/") or "/", remote_name)
		if file_path:
			sftp.put(file_path, remote_full)
		elif data is not None:
			with BytesIO(data) as bio:
				sftp.putfo(bio, remote_full)
		else:
			raise ValueError("SFTP upload: بدون داده")
		return {"remote_path": rp, "remote_filename": remote_name, "transport": "sftp"}
	finally:
		try:
			sftp.close()
		except Exception:
			pass
		try:
			t.close()
		except Exception:
			pass


def _upload_bytes_ftp(
	params: FtpConnectionParams,
	filename: str,
	data: bytes | None,
	file_path: str | None,
) -> dict[str, Any]:
	ftp = _connect_ftp(params)
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
		if file_path:
			with open(file_path, "rb") as fh:
				ftp.storbinary(f"STOR {remote_name}", fh, blocksize=65536)
		elif data is not None:
			bio = BytesIO(data)
			ftp.storbinary(f"STOR {remote_name}", bio, blocksize=65536)
		else:
			raise ValueError("FTP upload: بدون داده")
		return {"remote_path": ftp.pwd(), "remote_filename": remote_name, "transport": "ftp"}
	finally:
		try:
			ftp.quit()
		except Exception:
			try:
				ftp.close()
			except Exception:
				pass


def _scan_usage_sftp(
	params: FtpConnectionParams,
	*,
	max_files: int,
	max_depth: int,
) -> dict[str, Any]:
	sftp, t = _sftp_connect(params)
	bytes_total = 0
	files = 0
	truncated = False
	root = _normalize_remote_path(params.remote_path)

	def walk_inner(path: str, depth: int) -> None:
		nonlocal bytes_total, files, truncated
		if files >= max_files or depth > max_depth:
			truncated = True
			return
		try:
			for attr in sftp.listdir_attr(path):
				if files >= max_files:
					truncated = True
					return
				name = attr.filename
				if name in (".", ".."):
					continue
				full = posixpath.join(path.rstrip("/") or "/", name)
				if not full.startswith("/"):
					full = "/" + full
				try:
					mode = attr.st_mode
				except Exception:
					mode = None

				is_dir = False
				if mode is not None:
					is_dir = stat_mod.S_ISDIR(int(mode))
				else:
					try:
						st = sftp.stat(full)
						is_dir = stat_mod.S_ISDIR(st.st_mode)
					except OSError:
						continue
				if is_dir:
					walk_inner(full, depth + 1)
				else:
					try:
						bytes_total += int(attr.st_size or 0)
					except Exception:
						pass
					files += 1
		except OSError:
			return

	try:
		_sftp_ensure_dir(sftp, root)
		walk_inner(root, 0)
		return {
			"total_bytes": bytes_total,
			"file_count": files,
			"truncated": truncated,
			"root": root,
			"transport": "sftp",
		}
	finally:
		try:
			sftp.close()
		except Exception:
			pass
		try:
			t.close()
		except Exception:
			pass


def scan_usage(
	params: FtpConnectionParams,
	*,
	max_files: int = 8000,
	max_depth: int = 14,
) -> dict[str, Any]:
	if params.use_sftp:
		return _scan_usage_sftp(params, max_files=max_files, max_depth=max_depth)
	return _scan_usage_ftp(params, max_files=max_files, max_depth=max_depth)


def _scan_usage_ftp(
	params: FtpConnectionParams,
	*,
	max_files: int,
	max_depth: int,
) -> dict[str, Any]:
	ftp = _connect_ftp(params)
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
			if not _process_dir_nlst_fallback(ftp, abs_path, depth, max_files, max_depth):
				try:
					ftp.cwd(before)
				except Exception:
					pass
				return
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

	def _process_dir_nlst_fallback(
		ftp_: FTP,
		abs_path: str,
		depth: int,
		max_f: int,
		max_d: int,
	) -> bool:
		nonlocal bytes_total, files, truncated
		if files >= max_f or depth > max_d:
			truncated = True
			return True
		try:
			names = ftp_.nlst()
		except Exception:
			return False
		here = ftp_.pwd()
		for raw in names:
			if files >= max_f:
				truncated = True
				return True
			name = posixpath.basename(raw) or raw
			if name in (".", ".."):
				continue
			try:
				sz = ftp_.size(name)
			except Exception:
				sz = -1
			if sz is not None and sz >= 0:
				bytes_total += int(sz)
				files += 1
				continue
			try:
				ftp_.cwd(name)
				child = posixpath.join(abs_path.rstrip("/") or "/", name)
				if not child.startswith("/"):
					child = "/" + child
				_process_dir_nlst_fallback(ftp_, child, depth + 1, max_f, max_d)
				ftp_.cwd(here)
			except Exception:
				try:
					ftp_.cwd(here)
				except Exception:
					pass
		return True

	try:
		root = _normalize_remote_path(params.remote_path)
		process_dir(root, 0)
		return {
			"total_bytes": bytes_total,
			"file_count": files,
			"truncated": truncated,
			"root": root,
			"transport": "ftp",
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
		port=int(row.port or (22 if bool(getattr(row, "use_sftp", False)) else 21)),
		username=row.username,
		password=password,
		remote_path=row.remote_path or "/",
		passive=bool(row.passive),
		use_ftps=bool(row.use_ftps) and not bool(getattr(row, "use_sftp", False)),
		use_sftp=bool(getattr(row, "use_sftp", False)),
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
		"use_sftp": bool(getattr(row, "use_sftp", False)),
		"updated_at": row.updated_at.isoformat() if row.updated_at else None,
	}


def ftp_test_params_from_body(db: Session, business_id: int, body: dict[str, Any]) -> FtpConnectionParams:
	use_saved = bool(body.get("use_saved"))
	if use_saved:
		p = load_decrypted_params(db, business_id)
		if not p:
			raise ApiError("FTP_NOT_CONFIGURED", "تنظیمات FTP ذخیره نشده یا رمز نامعتبر است", http_status=400)
		return p
	host = (body.get("host") or "").strip()
	username = (body.get("username") or "").strip()
	password = body.get("password")
	use_sftp = bool(body.get("use_sftp"))
	raw_port = body.get("port")
	if raw_port is None:
		port = 22 if use_sftp else 21
	else:
		port = int(raw_port)
	if not host or not username or not password:
		raise ApiError("FTP_TEST_INVALID", "برای تست بدون ذخیره، میزبان، نام کاربری و رمز لازم است", http_status=400)
	return FtpConnectionParams(
		host=host,
		port=port,
		username=username,
		password=str(password),
		remote_path=(body.get("remote_path") or "/").strip() or "/",
		passive=body.get("passive") is not False,
		use_ftps=body.get("use_ftps") is True and not use_sftp,
		use_sftp=use_sftp,
	)


def do_ftp_test(
	business_id: int,
	body_dict: dict[str, Any],
	*,
	on_progress: Callable[[int, str], None] | None = None,
) -> dict[str, Any]:
	from adapters.db.session import get_db_session

	def touch(p: int, msg: str) -> None:
		if on_progress:
			on_progress(p, msg)

	touch(15, "Connecting")
	with get_db_session() as db:
		params = ftp_test_params_from_body(db, business_id, body_dict)
	touch(55, "Running checks")
	res = test_connection(params)
	logger.info(
		"business_ftp test ok business_id=%s transport=%s host=%s",
		business_id,
		res.get("transport"),
		params.host,
	)
	return res


def do_ftp_usage_scan(
	business_id: int,
	*,
	on_progress: Callable[[int, str], None] | None = None,
) -> dict[str, Any]:
	from adapters.db.session import get_db_session

	def touch(p: int, msg: str) -> None:
		if on_progress:
			on_progress(p, msg)

	touch(15, "Connecting to FTP")
	with get_db_session() as db:
		params = load_decrypted_params(db, business_id)
		if not params:
			raise ApiError("FTP_NOT_CONFIGURED", "تنظیمات FTP ذخیره نشده یا رمز نامعتبر است", http_status=400)
	touch(40, "Scanning remote folders")
	result = scan_usage(params)
	logger.info(
		"business_ftp usage_scan business_id=%s files=%s bytes=%s truncated=%s",
		business_id,
		result.get("file_count"),
		result.get("total_bytes"),
		result.get("truncated"),
	)
	return result
