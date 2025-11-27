from __future__ import annotations

import re
from typing import Optional


def parse_user_agent(user_agent: str | None) -> dict:
	"""
	تجزیه user agent و استخراج اطلاعات دستگاه
	
	Args:
		user_agent: User Agent string
	
	Returns:
		dict با کلیدهای:
			- device_name: نام کامل دستگاه (مثلاً "Chrome on Windows")
			- browser: نام مرورگر
			- browser_version: نسخه مرورگر
			- os: سیستم عامل
			- os_version: نسخه سیستم عامل
			- device_type: نوع دستگاه (desktop, mobile, tablet)
	"""
	if not user_agent:
		return {
			"device_name": "دستگاه نامشخص",
			"browser": None,
			"browser_version": None,
			"os": None,
			"os_version": None,
			"device_type": "unknown"
		}
	
	ua_lower = user_agent.lower()
	
	# تشخیص مرورگر
	browser = None
	browser_version = None
	
	# Chrome
	if "chrome" in ua_lower and "edg" not in ua_lower and "opr" not in ua_lower:
		browser = "Chrome"
		match = re.search(r'chrome/([\d.]+)', ua_lower)
		if match:
			browser_version = match.group(1).split('.')[0]
	
	# Edge
	elif "edg" in ua_lower:
		browser = "Edge"
		match = re.search(r'edg[ea]?/([\d.]+)', ua_lower)
		if match:
			browser_version = match.group(1).split('.')[0]
	
	# Firefox
	elif "firefox" in ua_lower:
		browser = "Firefox"
		match = re.search(r'firefox/([\d.]+)', ua_lower)
		if match:
			browser_version = match.group(1).split('.')[0]
	
	# Safari
	elif "safari" in ua_lower and "chrome" not in ua_lower:
		browser = "Safari"
		match = re.search(r'version/([\d.]+)', ua_lower)
		if match:
			browser_version = match.group(1).split('.')[0]
	
	# Opera
	elif "opr" in ua_lower or "opera" in ua_lower:
		browser = "Opera"
		match = re.search(r'(?:opr|opera)/([\d.]+)', ua_lower)
		if match:
			browser_version = match.group(1).split('.')[0]
	
	# Flutter/Dart (اپلیکیشن موبایل)
	elif "dart" in ua_lower or "flutter" in ua_lower:
		browser = "Flutter App"
		browser_version = None
	
	# تشخیص سیستم عامل
	os_name = None
	os_version = None
	device_type = "desktop"
	
	# Windows
	if "windows" in ua_lower:
		os_name = "Windows"
		if "windows nt 10.0" in ua_lower or "windows 10" in ua_lower:
			os_version = "10"
		elif "windows nt 11.0" in ua_lower or "windows 11" in ua_lower:
			os_version = "11"
		elif "windows nt 6.3" in ua_lower:
			os_version = "8.1"
		elif "windows nt 6.2" in ua_lower:
			os_version = "8"
		elif "windows nt 6.1" in ua_lower:
			os_version = "7"
		else:
			match = re.search(r'windows nt ([\d.]+)', ua_lower)
			if match:
				os_version = match.group(1)
	
	# macOS
	elif "mac os x" in ua_lower or "macintosh" in ua_lower:
		os_name = "macOS"
		match = re.search(r'mac os x ([\d_]+)', ua_lower)
		if match:
			version = match.group(1).replace('_', '.')
			os_version = version.split('.')[0] + '.' + version.split('.')[1] if '.' in version else version
	
	# iOS
	elif "iphone" in ua_lower or "ipad" in ua_lower or "ipod" in ua_lower:
		if "ipad" in ua_lower:
			os_name = "iPadOS"
			device_type = "tablet"
		else:
			os_name = "iOS"
			device_type = "mobile"
		
		match = re.search(r'os ([\d_]+)', ua_lower)
		if match:
			version = match.group(1).replace('_', '.')
			os_version = version
	
	# Android
	elif "android" in ua_lower:
		os_name = "Android"
		device_type = "mobile"
		match = re.search(r'android ([\d.]+)', ua_lower)
		if match:
			os_version = match.group(1).split('.')[0]
		
		# تشخیص تبلت
		if "tablet" in ua_lower or "pad" in ua_lower:
			device_type = "tablet"
	
	# Linux
	elif "linux" in ua_lower:
		os_name = "Linux"
		if "ubuntu" in ua_lower:
			os_name = "Ubuntu"
		elif "debian" in ua_lower:
			os_name = "Debian"
	
	# ساخت نام دستگاه
	device_name = format_device_name(user_agent, None, browser, os_name, device_type)
	
	return {
		"device_name": device_name,
		"browser": browser,
		"browser_version": browser_version,
		"os": os_name,
		"os_version": os_version,
		"device_type": device_type
	}


def _extract_os_version_from_ua(user_agent: str) -> str | None:
	"""استخراج نسخه OS از user agent بدون فراخوانی parse_user_agent"""
	ua_lower = user_agent.lower()
	
	# Windows
	if "windows" in ua_lower:
		match = re.search(r'windows nt ([\d.]+)', ua_lower)
		if match:
			version = match.group(1)
			if version == "10.0":
				return "10"
			elif version == "11.0":
				return "11"
			return version
	
	# macOS
	elif "mac os x" in ua_lower:
		match = re.search(r'mac os x ([\d_]+)', ua_lower)
		if match:
			version = match.group(1).replace('_', '.')
			parts = version.split('.')
			if len(parts) >= 2:
				return f"{parts[0]}.{parts[1]}"
			return version
	
	# iOS
	elif "iphone" in ua_lower or "ipad" in ua_lower:
		match = re.search(r'os ([\d_]+)', ua_lower)
		if match:
			return match.group(1).replace('_', '.')
	
	# Android
	elif "android" in ua_lower:
		match = re.search(r'android ([\d.]+)', ua_lower)
		if match:
			return match.group(1).split('.')[0]
	
	return None


def format_device_name(
	user_agent: str | None,
	device_id: str | None,
	browser: str | None = None,
	os_name: str | None = None,
	device_type: str | None = None
) -> str:
	"""
	تولید نام خوانا برای دستگاه
	
	Args:
		user_agent: User Agent string
		device_id: شناسه دستگاه
		browser: نام مرورگر (اختیاری - اگر parse شده باشد)
		os_name: نام سیستم عامل (اختیاری)
		device_type: نوع دستگاه (اختیاری)
	
	Returns:
		نام خوانا برای دستگاه
	"""
	if not user_agent:
		return "دستگاه نامشخص"
	
	# اگر اطلاعات parse شده در دسترس است، استفاده کن
	if browser and os_name:
		if device_type == "mobile" and os_name == "iOS":
			# برای iOS سعی می‌کنیم مدل دستگاه را تشخیص دهیم
			ua_lower = user_agent.lower()
			if "iphone" in ua_lower:
				return f"{browser} on iPhone"
			elif "ipad" in ua_lower:
				return f"{browser} on iPad"
			else:
				return f"{browser} on {os_name}"
		elif device_type == "mobile" and os_name == "Android":
			return f"{browser} on {os_name}"
		else:
			# استخراج os_version بدون فراخوانی parse_user_agent
			os_version = _extract_os_version_from_ua(user_agent)
			if os_version:
				return f"{browser} on {os_name} {os_version}"
			else:
				return f"{browser} on {os_name}"
	
	# Fallback: اگر browser و os_name نداریم، باید از parse_user_agent استفاده کنیم
	# اما این فقط در صورتی اتفاق می‌افتد که از session_service مستقیماً format_device_name را صدا بزنیم
	# که در آن صورت browser و os_name را نداریم
	# در این حالت، باید یک parse ساده انجام دهیم بدون فراخوانی format_device_name
	ua_lower = user_agent.lower()
	
	# تشخیص browser
	if not browser:
		if "chrome" in ua_lower and "edg" not in ua_lower and "opr" not in ua_lower:
			browser = "Chrome"
		elif "edg" in ua_lower:
			browser = "Edge"
		elif "firefox" in ua_lower:
			browser = "Firefox"
		elif "safari" in ua_lower and "chrome" not in ua_lower:
			browser = "Safari"
		elif "opr" in ua_lower or "opera" in ua_lower:
			browser = "Opera"
		elif "dart" in ua_lower or "flutter" in ua_lower:
			browser = "Flutter App"
		else:
			browser = "مرورگر نامشخص"
	
	# تشخیص OS
	if not os_name:
		if "windows" in ua_lower:
			os_name = "Windows"
		elif "mac os x" in ua_lower or "macintosh" in ua_lower:
			os_name = "macOS"
		elif "iphone" in ua_lower or "ipod" in ua_lower:
			os_name = "iOS"
		elif "ipad" in ua_lower:
			os_name = "iPadOS"
		elif "android" in ua_lower:
			os_name = "Android"
		elif "linux" in ua_lower:
			os_name = "Linux"
		else:
			os_name = "سیستم عامل نامشخص"
	
	# تشخیص device_type
	if not device_type:
		if "iphone" in ua_lower or ("android" in ua_lower and "tablet" not in ua_lower and "pad" not in ua_lower):
			device_type = "mobile"
		elif "ipad" in ua_lower or ("android" in ua_lower and ("tablet" in ua_lower or "pad" in ua_lower)):
			device_type = "tablet"
		else:
			device_type = "desktop"
	
	# ساخت نام نهایی
	if device_type == "mobile":
		if os_name == "iOS":
			return f"{browser} on iPhone"
		else:
			return f"{browser} on {os_name}"
	elif device_type == "tablet":
		if os_name == "iPadOS":
			return f"{browser} on iPad"
		else:
			return f"{browser} on {os_name} (Tablet)"
	else:
		os_version = _extract_os_version_from_ua(user_agent)
		if os_version:
			return f"{browser} on {os_name} {os_version}"
		else:
			return f"{browser} on {os_name}"

