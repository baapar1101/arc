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
	# DB Pooling
	# با 4 worker، هر worker نیاز به حدود 10-15 اتصال دارد
	# بنابراین pool_size را به 25 و max_overflow را به 40 افزایش می‌دهیم
	db_pool_size: int = 25
	db_max_overflow: int = 40
	db_pool_timeout: int = 30  # افزایش timeout برای جلوگیری از خطاهای زودرس

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
	cors_allowed_origins: list[str] = ["*"]

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

	@property
	def mysql_dsn(self) -> str:
		return (
			f"mysql+pymysql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"
		)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
	return Settings()
