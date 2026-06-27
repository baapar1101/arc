from adapters.db.session import Base  # re-export Base for Alembic

# Import support models to register with SQLAlchemy metadata
from .category import Category  # noqa: F401
from .priority import Priority  # noqa: F401
from .status import Status  # noqa: F401
from .ticket import Ticket  # noqa: F401
from .message import Message  # noqa: F401
from .ticket_event import TicketEvent  # noqa: F401
from .attachment import SupportAttachment  # noqa: F401
from .response_template import SupportResponseTemplate  # noqa: F401
from .sla_policy import SlaPolicy  # noqa: F401
