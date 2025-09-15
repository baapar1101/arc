from adapters.db.session import Base  # re-export Base for Alembic

# Import models to register with SQLAlchemy metadata
from .user import User  # noqa: F401
from .api_key import ApiKey  # noqa: F401
from .captcha import Captcha  # noqa: F401
from .password_reset import PasswordReset  # noqa: F401


