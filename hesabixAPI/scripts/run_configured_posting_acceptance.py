"""Run the configured-account tests only against an explicit disposable DB."""
import os
from pathlib import Path
import sys

from sqlalchemy.engine import make_url

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def main():
    dsn = os.environ.get('SEPIDAR_TEST_DSN')
    if not dsn:
        raise SystemExit('Set SEPIDAR_TEST_DSN to an isolated PostgreSQL *_sepidar_test database.')
    target = make_url(dsn)
    if target.get_backend_name() != 'postgresql' or not (target.database or '').endswith('_sepidar_test'):
        raise SystemExit('Refusing tests outside a PostgreSQL *_sepidar_test database.')
    from app.core.settings import get_settings
    if target.database == make_url(get_settings().postgresql_dsn).database:
        raise SystemExit('Refusing to use the application database as the test database.')
    import pytest
    print('Disposable test database: ' + target.database, flush=True)
    return pytest.main(['-q', '--disable-warnings', '--tb=short', '--maxfail=1',
                        str(ROOT / 'tests/test_configured_posting_acceptance.py')])


if __name__ == '__main__':
    raise SystemExit(main())
