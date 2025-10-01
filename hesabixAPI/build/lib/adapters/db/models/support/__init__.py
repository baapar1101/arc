from adapters.db.session import Base  # re-export Base for Alembic

# Import support models to register with SQLAlchemy metadata
from .category import Category  # noqa: F401
from .priority import Priority  # noqa: F401
from .status import Status  # noqa: F401
from .ticket import Ticket  # noqa: F401
from .message import Message  # noqa: F401
