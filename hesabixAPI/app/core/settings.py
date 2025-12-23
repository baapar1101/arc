from functools import lru_cache
from pydantic import BaseModel
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
	model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

	app_name: str = "Hesabix API"
	app_version: str = "0.1.0"
	api_v1_prefix: str = "/api/v1"
	environment: str = "development"
	debug: bool = True

	# Database
	db_user: str = "hesabix"
	db_password: str = "change_me"
	db_host: str = "localhost"
	db_port: int = 3306
	db_name: str = "hesabix"
	sqlalchemy_echo: bool = False
	# DB Pooling - بهینه‌سازی برای مقیاس‌پذیری بالا
	# Phase 1 Optimization: افزایش Connection Pool برای پشتیبانی از بارهای بالا
	# محاسبه: (تعداد Worker ها * اتصالات مورد نیاز per Worker) + Buffer
	# مثال Production: 5 Workers * 100 اتصال = 500 + 300 buffer = 800
	# برای Development: pool_size=50, max_overflow=50 = 100 max connections
	# ⚠️ توجه: بعد از رفع connection leak در WebSocket، این مقادیر باید کاهش یابد
	db_pool_size: int = 50  # افزایش از 20 - اتصالات پایه در Pool
	db_max_overflow: int = 50  # افزایش از 30 - اتصالات اضافی در صورت نیاز
	db_pool_timeout: int = 30  # افزایش از 10 - timeout بیشتر برای Pool
	db_pool_recycle: int = 300  # Recycle اتصالات هر 5 دقیقه - کاهش برای جلوگیری از connection leak و بهبود performance

	# Logging
	log_level: str = "INFO"

	# Captcha / Security
	captcha_length: int = 5
	captcha_ttl_seconds: int = 180
	captcha_secret: str = "change_me_captcha"
	reset_password_ttl_seconds: int = 3600

	# Phone normalization
	# Used as default region when parsing phone numbers without a country code
	default_phone_region: str = "IR"

	# CORS
	# نکته: وقتی allow_credentials=True است، نمی‌توان از "*" استفاده کرد
	# باید دامنه‌های خاص را مشخص کنید
	cors_allowed_origins: list[str] = [
		"https://arc.hesabix.ir",
		"https://hsxn.hesabix.ir",
		"http://localhost:3000",
		"http://localhost:8080",
	]

	# Telegram Bot
	telegram_bot_token: str | None = None
	telegram_bot_username: str | None = None  # optional, used to build deep-links
	telegram_webhook_secret: str | None = None
	telegram_secret_header: str | None = None  # optional header to validate Telegram webhook
	telegram_proxy_enabled: bool | None = None
	telegram_proxy_base_url: str | None = None
	telegram_proxy_api_key: str | None = None
	# SMS (optional)
	sms_provider_name: str | None = None  # e.g., "twilio" or custom
	sms_api_key: str | None = None
	sms_sender: str | None = None
	sms_provider_username: str | None = None  # برای behinsms
	sms_provider_password: str | None = None  # برای behinsms

	# Share link / public card settings
	share_link_code_length: int = 9
	share_link_default_ttl_hours: int = 168  # 7 days
	share_link_max_ttl_hours: int = 720      # 30 days
	share_link_public_base_url: str = "https://app.hesabix.com/p"
	share_link_secret: str = "change_me_share_link"
	share_link_public_app_url: str = "https://app.hesabix.com/public"

	# Tax system (Moadian) integration
	tax_system_force_simulation: bool = True
	tax_system_timeout_seconds: int = 45
	tax_system_sandbox_base_url: str = "https://sandboxrc.tax.gov.ir"
	tax_system_production_base_url: str = "https://tp.tax.gov.ir"
	tax_system_user_agent: str = "HesabixTaxClient/1.0"

	# Redis Cache
	redis_enabled: bool = False
	redis_host: str = "localhost"
	redis_port: int = 6379
	redis_db: int = 0
	redis_password: str | None = None
	
	# Pagination
	max_page_size: int = 100  # حداکثر تعداد آیتم در هر صفحه
	default_page_size: int = 20  # اندازه پیش‌فرض صفحه
	
	# Query Timeout
	query_timeout_seconds: int = 60  # Timeout برای query های طولانی (60 ثانیه)

	# =========================
	# Voice AI (STT/TTS/VAD)
	# =========================
	voice_enabled: bool = True
	voice_sample_rate_hz: int = 16000
	voice_frame_ms: int = 20
	voice_vad_mode: int = 2
	voice_vad_silence_ms: int = 650
	voice_vad_min_speech_ms: int = 250
	voice_vad_pre_roll_ms: int = 200
	voice_vad_max_utterance_ms: int = 30_000

	# STT (Whisper)
	voice_stt_language: str = "fa"
	voice_stt_model_size_or_path: str = "small"
	voice_stt_device: str = "auto"
	voice_stt_compute_type: str = "int8"

	# TTS (متن‌باز)
	# engine: "coqui" | "dummy"
	voice_tts_engine: str = "dummy"
	voice_tts_language: str = "fa"
	voice_tts_model_name: str | None = None
	voice_tts_model_path: str | None = None
	voice_tts_output_sample_rate_hz: int = 16000
	voice_tts_frame_ms: int = 20

	# Data collection (اختیاری، برای بهبود کیفیت در آینده)
	voice_data_collection_enabled: bool = False
	voice_data_collection_dir: str = "/var/lib/hesabix/voice-data"

	@property
	def mysql_dsn(self) -> str:
		return (
			f"mysql+pymysql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"
		)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
	return Settings()
