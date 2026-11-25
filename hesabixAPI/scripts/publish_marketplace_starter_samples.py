"""انتشار نمونه‌های آمادهٔ ورک‌فلو برای یک کسب‌وکار.

استفاده:
  python scripts/publish_marketplace_starter_samples.py --business-id 6262
ناشر، مالک همان کسب‌وکار است. ورک‌فلوهای منبع پیش‌نویس می‌مانند.
"""

from __future__ import annotations

import argparse
import json

from adapters.db.models.business import Business
from adapters.db.session import get_db_session
from app.services.workflow.marketplace_starter_samples import publish_starter_samples


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--business-id", type=int, required=True)
    args = parser.parse_args()
    with get_db_session() as db:
        business = db.get(Business, int(args.business_id))
        if business is None or business.owner_id is None:
            raise SystemExit(f"business {args.business_id} or its owner was not found")
        results = publish_starter_samples(
            db,
            business_id=int(business.id),
            user_id=int(business.owner_id),
        )
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
