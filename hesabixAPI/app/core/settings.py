from functools import lru_cache
from urllib.parse import quote_plus
from pydantic import BaseModel, Field
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
	db_port: int = 5432
	db_name: str = "hesabix"
	sqlalchemy_echo: bool = False
	# DB Pooling - بهینه‌سازی برای مقیاس‌پذیری بالا
	# بهینه‌سازی برای 24 worker و PostgreSQL با max_connections=300
	# محاسبه: (تعداد Worker ها * اتصالات مورد نیاز per Worker)
	# 24 workers * 12 connections = 288 + buffer = 300 (مطابق با max_connections PostgreSQL)
	# برای استفاده حداکثری از منابع و کمترین زمان پاسخگویی
	db_pool_size: int = 150  # اتصالات پایه در Pool (50% از max_connections)
	db_max_overflow: int = 150  # اتصالات اضافی در صورت نیاز (50% از max_connections)
	db_pool_timeout: int = 30  # Timeout برای Pool (30 ثانیه)
	db_pool_recycle: int = 1800  # Recycle اتصالات هر 30 دقیقه - بهینه برای جلوگیری از connection leak و بهبود performance

	# Logging — پیش‌فرض پروداکشن: حداقل خروجی (از env با نام LOG_LEVEL هم خوانده می‌شود)
	log_level: str = Field(
		default="WARNING",
		description="DEBUG | INFO | WARNING | ERROR | CRITICAL — برای دیباگ موقت LOG_LEVEL=DEBUG و ری‌استارت",
	)

	# Captcha / Security
	captcha_length: int = 5
	captcha_ttl_seconds: int = 180
	captcha_secret: str = "change_me_captcha"
	reset_password_ttl_seconds: int = 3600

	# Phone normalization
	# Used as default region when parsing phone numbers without a country code
	default_phone_region: str = "IR"

	# لینک‌های وب (مثلاً ساخت /login?reset_token=... برای ادمین و قالب اعلان)
	# اگر خالی باشد، در endpoint بازنشانی از header Origin (درخواست مرورگر) استفاده می‌شود
	app_public_url: str = ""

	# CORS — پذیرش هر Origin (API باز برای کلاینت‌های وب/موبایل/ابزارها)
	# نکته: با allow_origins=["*"] در Starlette باید allow_credentials=False بماند (در app/main.py).
	cors_allowed_origins: list[str] = ["*"]

	# Telegram Bot
	telegram_bot_token: str | None = None
	telegram_bot_username: str | None = None  # optional, used to build deep-links
	telegram_webhook_secret: str | None = None
	telegram_secret_header: str | None = None  # optional header to validate Telegram webhook
	telegram_proxy_enabled: bool | None = None
	telegram_proxy_base_url: str | None = None
	telegram_proxy_api_key: str | None = None
	# Bale messenger (optional)
	bale_bot_token: str | None = None
	bale_bot_username: str | None = None  # for deep-link to bot
	bale_webhook_secret: str | None = None
	# SMS (optional)
	sms_provider_name: str | None = None  # e.g., "twilio" or custom
	sms_api_key: str | None = None
	sms_sender: str | None = None
	sms_provider_username: str | None = None  # برای behinsms
	sms_provider_password: str | None = None  # برای behinsms
	# سقف ارسال به هر شماره مقصد (مشترک بین همه worker؛ بدون Redis) — جلو ارسال از IPهای مختلف
	sms_destination_rate_enabled: bool = True
	sms_destination_rate_max_sends: int = 40  # حداکثر تعداد ارسال به همان شماره در پنجره
	sms_destination_rate_window_minutes: int = 60  # طول پنجره (دقیقه)

	# Share link / public card settings
	share_link_code_length: int = 9
	share_link_default_ttl_hours: int = 168  # 7 days
	share_link_max_ttl_hours: int = 720      # 30 days
	share_link_public_base_url: str = "https://app.hesabix.com/p"
	share_link_secret: str = "change_me_share_link"
	share_link_public_app_url: str = "https://app.hesabix.com/public"

	# Tax system (Moadian) integration
	# پیش‌فرض روی حالت واقعی است؛ برای محیط‌های توسعه در env روی true ست شود
	tax_system_force_simulation: bool = False
	tax_system_timeout_seconds: int = 45
	tax_system_sandbox_base_url: str = "https://sandboxrc.tax.gov.ir"
	tax_system_production_base_url: str = "https://tp.tax.gov.ir"
	tax_system_user_agent: str = "HesabixTaxClient/1.0"
	tax_system_rate_limit_max_requests: int = 100  # حداکثر تعداد درخواست در window
	tax_system_rate_limit_window_seconds: int = 3600  # بازه زمانی rate limit (ثانیه)
	tax_system_inquire_max_workers: int = 5  # حداکثر تعداد thread برای parallel inquiries
	tax_system_retry_max_attempts: int = 3  # حداکثر تعداد تلاش برای retry
	tax_system_retry_initial_delay_seconds: float = 2.0  # تاخیر اولیه retry (ثانیه)

	# Redis Cache
	redis_enabled: bool = False
	redis_host: str = "localhost"
	redis_port: int = 6379
	redis_db: int = 0
	redis_password: str | None = None

	# مانیتورینگ صف اعلان / پیامک (آستانه هشدار در پنل)
	monitoring_outbox_due_retry_warn: int = 500
	monitoring_outbox_sms_pending_warn: int = 50
	
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
	# مدل Coqui پیش‌فرض فارسی (محلی، بدون API) وقتی model_name خالی است
	voice_tts_coqui_model_fa: str = "tts_models/fa/cv/vits/glow-tts"
	voice_tts_output_sample_rate_hz: int = 16000
	voice_tts_frame_ms: int = 20

	# Data collection (اختیاری، برای بهبود کیفیت در آینده)
	voice_data_collection_enabled: bool = False
	voice_data_collection_dir: str = "/var/lib/hesabix/voice-data"

	@property
	def postgresql_dsn(self) -> str:
		return (
			f"postgresql+psycopg2://{self.db_user}:{quote_plus(self.db_password)}@{self.db_host}:{self.db_port}/{self.db_name}"
		)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
	return Settings()
