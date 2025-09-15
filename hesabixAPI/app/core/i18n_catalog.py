from __future__ import annotations

import gettext
import os
from functools import lru_cache
from typing import Optional

BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
LOCALES_DIR = os.path.join(BASE_DIR, 'locales')


@lru_cache(maxsize=32)
def get_gettext_translation(locale: str, domain: str = 'messages') -> Optional[gettext.NullTranslations]:
	try:
		return gettext.translation(domain=domain, localedir=LOCALES_DIR, languages=[locale], fallback=True)
	except Exception:
		return None
