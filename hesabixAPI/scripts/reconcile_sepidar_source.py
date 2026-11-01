"""Preview or apply an owner-reviewed plan under the normal import business lock.

No automatic approval and no generated/reversal accounting document. This CLI
records the already-given owner's approval; do not expose it to a scheduler.
"""
import argparse
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from adapters.db.session import SessionLocal
from app.services.sepidar_import_service import _sync_lock
from app.services.sepidar_reconciliation_service import build_plan,apply_reviewed_plan

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--business-id',type=int,required=True)
    parser.add_argument('--apply',action='store_true')
    parser.add_argument('--plan-hash')
    parser.add_argument('--approved-by',type=int)
    parser.add_argument('--reason',default='')
    args=parser.parse_args()
    if args.apply and not (args.plan_hash and args.approved_by and args.reason):
        parser.error('--apply requires the reviewed --plan-hash, --approved-by owner and --reason')
    with SessionLocal() as db:
        with _sync_lock(db,args.business_id):
            if args.apply:
                try:
                    with db.begin_nested():
                        result=apply_reviewed_plan(db,args.business_id,args.approved_by,args.plan_hash,args.reason)
                    db.commit()
                    if result.get('changed'):
                        from app.services.sepidar_native_service import invalidate_native_cache
                        invalidate_native_cache(args.business_id)
                except Exception:
                    db.rollback();raise
            else:
                result,_=build_plan(db,args.business_id)
        print(json.dumps(result,ensure_ascii=False,default=str),flush=True)

if __name__=='__main__':main()
