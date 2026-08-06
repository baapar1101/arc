"""Asterisk AudioSocket server — PCM16LE 8kHz bridge برای Softphone Relay."""
from __future__ import annotations

import logging
import socket
import struct
import threading
import uuid
from typing import Callable, Dict, Optional

LOG = logging.getLogger("hesabix.telephony.audiosocket")

# AudioSocket payload types (Asterisk)
AS_UUID = 0x01
AS_PCM = 0x10
AS_HANGUP = 0x00
AS_ERROR = 0xFF


def _read_exact(conn: socket.socket, n: int) -> bytes:
	buf = b""
	while len(buf) < n:
		chunk = conn.recv(n - len(buf))
		if not chunk:
			raise ConnectionError("socket closed")
		buf += chunk
	return buf


def _read_frame(conn: socket.socket) -> tuple[int, bytes]:
	hdr = _read_exact(conn, 3)
	ftype = hdr[0]
	length = struct.unpack(">H", hdr[1:3])[0]
	payload = _read_exact(conn, length) if length else b""
	return ftype, payload


def _write_frame(conn: socket.socket, ftype: int, payload: bytes = b"") -> None:
	conn.sendall(bytes([ftype]) + struct.pack(">H", len(payload)) + payload)


class AudioSocketServer:
	"""گوش دادن روی 127.0.0.1 و تحویل PCM به callback per UUID."""

	def __init__(
		self,
		host: str = "127.0.0.1",
		port: int = 9092,
		on_pcm: Optional[Callable[[str, bytes], None]] = None,
		on_hangup: Optional[Callable[[str], None]] = None,
	) -> None:
		self.host = host
		self.port = port
		self.on_pcm = on_pcm
		self.on_hangup = on_hangup
		self._sock: Optional[socket.socket] = None
		self._thread: Optional[threading.Thread] = None
		self._stop = threading.Event()
		self._conns: Dict[str, socket.socket] = {}
		self._lock = threading.Lock()

	def start(self) -> None:
		if self._thread and self._thread.is_alive():
			return
		self._stop.clear()
		self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
		self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
		self._sock.bind((self.host, self.port))
		self._sock.listen(64)
		self._sock.settimeout(1.0)
		self._thread = threading.Thread(target=self._accept_loop, name="hesabix-audiosocket", daemon=True)
		self._thread.start()
		LOG.info("AudioSocket listening on %s:%s", self.host, self.port)

	def stop(self) -> None:
		self._stop.set()
		with self._lock:
			for c in list(self._conns.values()):
				try:
					c.close()
				except Exception:
					pass
			self._conns.clear()
		if self._sock:
			try:
				self._sock.close()
			except Exception:
				pass
		if self._thread:
			self._thread.join(timeout=3)

	def send_pcm(self, as_uuid: str, pcm: bytes) -> bool:
		with self._lock:
			conn = self._conns.get(as_uuid)
		if not conn:
			return False
		try:
			_write_frame(conn, AS_PCM, pcm)
			return True
		except Exception as e:
			LOG.debug("send_pcm failed %s: %s", as_uuid, e)
			return False

	def hangup(self, as_uuid: str) -> None:
		with self._lock:
			conn = self._conns.pop(as_uuid, None)
		if not conn:
			return
		try:
			_write_frame(conn, AS_HANGUP, b"")
		except Exception:
			pass
		try:
			conn.close()
		except Exception:
			pass

	def _accept_loop(self) -> None:
		assert self._sock is not None
		while not self._stop.is_set():
			try:
				conn, addr = self._sock.accept()
			except socket.timeout:
				continue
			except Exception as e:
				if not self._stop.is_set():
					LOG.warning("accept error: %s", e)
				break
			t = threading.Thread(target=self._handle_conn, args=(conn, addr), daemon=True)
			t.start()

	def _handle_conn(self, conn: socket.socket, addr) -> None:
		as_uuid = ""
		try:
			conn.settimeout(30)
			# اولین فریم باید UUID باشد
			ftype, payload = _read_frame(conn)
			if ftype != AS_UUID or len(payload) < 16:
				LOG.warning("AudioSocket: expected UUID from %s", addr)
				conn.close()
				return
			# Asterisk می‌فرستد 16-byte binary UUID یا ASCII — هر دو را پشتیبانی کن
			if len(payload) == 16:
				as_uuid = str(uuid.UUID(bytes=payload))
			else:
				as_uuid = payload.decode("ascii", errors="ignore").strip()
			with self._lock:
				self._conns[as_uuid] = conn
			LOG.info("AudioSocket connected uuid=%s from=%s", as_uuid, addr)
			while not self._stop.is_set():
				ftype, payload = _read_frame(conn)
				if ftype == AS_PCM:
					if self.on_pcm:
						self.on_pcm(as_uuid, payload)
				elif ftype in (AS_HANGUP, AS_ERROR):
					break
		except Exception as e:
			LOG.debug("AudioSocket conn ended uuid=%s: %s", as_uuid, e)
		finally:
			with self._lock:
				self._conns.pop(as_uuid, None)
			try:
				conn.close()
			except Exception:
				pass
			if as_uuid and self.on_hangup:
				try:
					self.on_hangup(as_uuid)
				except Exception:
					pass
