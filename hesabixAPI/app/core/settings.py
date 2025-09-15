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

	# Logging
	log_level: str = "INFO"

	@property
	def mysql_dsn(self) -> str:
		return (
			f"mysql+pymysql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"
		)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
	return Settings()
