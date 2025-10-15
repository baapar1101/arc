from adapters.db.session import Base  # re-export Base for Alembic

# Import models to register with SQLAlchemy metadata
from .user import User  # noqa: F401
from .api_key import ApiKey  # noqa: F401
from .captcha import Captcha  # noqa: F401
from .password_reset import PasswordReset  # noqa: F401
from .business import Business  # noqa: F401
from .business_permission import BusinessPermission  # noqa: F401
from .person import Person, PersonBankAccount  # noqa: F401
# Business user models removed - using business_permissions instead

# Import support models
from .support import *  # noqa: F401, F403

# Import file storage models
from .file_storage import *

# Import email config models
from .email_config import EmailConfig  # noqa: F401, F403


# Accounting / Fiscal models
from .fiscal_year import FiscalYear  # noqa: F401

# Currency models
from .currency import Currency, BusinessCurrency  # noqa: F401

# Documents
from .document import Document  # noqa: F401
from .document_line import DocumentLine  # noqa: F401
from .account import Account  # noqa: F401
from .category import BusinessCategory  # noqa: F401
from .product_attribute import ProductAttribute  # noqa: F401
from .product import Product  # noqa: F401
from .price_list import PriceList, PriceItem  # noqa: F401
from .product_attribute_link import ProductAttributeLink  # noqa: F401
from .tax_unit import TaxUnit  # noqa: F401
from .tax_type import TaxType  # noqa: F401
from .bank_account import BankAccount  # noqa: F401
from .cash_register import CashRegister  # noqa: F401
from .petty_cash import PettyCash  # noqa: F401
from .check import Check  # noqa: F401
