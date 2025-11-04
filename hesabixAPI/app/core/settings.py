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
	db_pool_size: int = 10
	db_max_overflow: int = 20
	db_pool_timeout: int = 10

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

	@property
	def mysql_dsn(self) -> str:
		return (
			f"mysql+pymysql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"
		)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
	return Settings()
