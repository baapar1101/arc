from typing import Any
from fastapi import APIRouter,Body,Depends,Query,Request
from sqlalchemy import select
from sqlalchemy.orm import Session
from adapters.db.session import get_db
from adapters.db.models.advanced_plugins import AdvancedPluginAudit
from app.core.auth_dependency import AuthContext,get_current_user
from app.core.permissions import require_business_access_dep,has_business_permission_for_business
from app.core.responses import ApiError,success_response
from app.services import advanced_plugin_service as svc
from app.services.advanced_plugin_operations import OPERATIONS,run_operation

router=APIRouter(prefix='/advanced-plugins',tags=['افزونه‌های تخصصی'],dependencies=[Depends(require_business_access_dep)])


def authorize(db,bid,code,ctx,action='view'):
    svc.module(code)
    if not has_business_permission_for_business(ctx,db,bid,code,action):
        raise ApiError('FORBIDDEN',f'Missing permission: {code}.{action}',http_status=403)
    svc.require_license(db,bid,code)


@router.get('/business/{business_id}')
def overview(request:Request,business_id:int,db:Session=Depends(get_db),ctx:AuthContext=Depends(get_current_user)):
    data=svc.overview(db,business_id)
    for item in data['items']:
        item['can_view']=has_business_permission_for_business(ctx,db,business_id,item['code'],'view')
        item['can_write']=has_business_permission_for_business(ctx,db,business_id,item['code'],'write')
        item['can_settings']=has_business_permission_for_business(ctx,db,business_id,item['code'],'settings')
        item['can_approve']=has_business_permission_for_business(ctx,db,business_id,item['code'],'approve')
        item['operations']=OPERATIONS[item['code']]
        if not item['can_view']:item['counts']={}
        if not item['can_settings']:item['settings']=None
    return success_response(data,request)


@router.get('/business/{business_id}/{code}/settings')
def settings(request:Request,business_id:int,code:str,db:Session=Depends(get_db),ctx:AuthContext=Depends(get_current_user)):
    authorize(db,business_id,code,ctx,'settings')
    return success_response(svc.settings(db,business_id,code),request)


@router.put('/business/{business_id}/{code}/settings')
def save_settings(request:Request,business_id:int,code:str,payload:dict[str,Any]=Body(...),db:Session=Depends(get_db),ctx:AuthContext=Depends(get_current_user)):
    authorize(db,business_id,code,ctx,'settings')
    return success_response(svc.save_settings(db,business_id,code,payload,ctx.get_user_id()),request)


@router.get('/business/{business_id}/{code}/references/{reference_type}')
def references(request:Request,business_id:int,code:str,reference_type:str,q:str=Query('',max_length=100),db:Session=Depends(get_db),ctx:AuthContext=Depends(get_current_user)):
    authorize(db,business_id,code,ctx)
    return success_response({'items':svc.references(db,business_id,code,reference_type,q)},request)


@router.get('/business/{business_id}/{code}/records')
def records(request:Request,business_id:int,code:str,kind:str|None=None,q:str=Query('',max_length=150),skip:int=Query(0,ge=0),take:int=Query(50,ge=1,le=200),parent_id:int|None=Query(None,gt=0),include_archived:bool=False,db:Session=Depends(get_db),ctx:AuthContext=Depends(get_current_user)):
    authorize(db,business_id,code,ctx)
    return success_response(svc.list_records(db,business_id,code,kind,q,skip,take,parent_id,include_archived),request)


@router.get('/business/{business_id}/{code}/records/{record_id}')
def record(request:Request,business_id:int,code:str,record_id:int,db:Session=Depends(get_db),ctx:AuthContext=Depends(get_current_user)):
    authorize(db,business_id,code,ctx)
    return success_response(svc.record_dict(svc.get_record(db,business_id,code,record_id),detail=True),request)


@router.post('/business/{business_id}/{code}/records/{kind}')
def create(request:Request,business_id:int,code:str,kind:str,payload:dict[str,Any]=Body(...),db:Session=Depends(get_db),ctx:AuthContext=Depends(get_current_user)):
    authorize(db,business_id,code,ctx,'write')
    return success_response(svc.save_record(db,business_id,code,kind,payload,ctx.get_user_id()),request)


@router.put('/business/{business_id}/{code}/records/{record_id}')
def update(request:Request,business_id:int,code:str,record_id:int,payload:dict[str,Any]=Body(...),db:Session=Depends(get_db),ctx:AuthContext=Depends(get_current_user)):
    authorize(db,business_id,code,ctx,'write')
    row=svc.get_record(db,business_id,code,record_id)
    return success_response(svc.save_record(db,business_id,code,row.kind,payload,ctx.get_user_id(),record_id),request)


@router.post('/business/{business_id}/{code}/operations/{action}')
def operation(request:Request,business_id:int,code:str,action:str,payload:dict[str,Any]=Body(...),db:Session=Depends(get_db),ctx:AuthContext=Depends(get_current_user)):
    authorize(db,business_id,code,ctx,'settings' if action=='approve_tax_table' else 'write' if action.endswith('_save') else 'view')
    if action=='approve_tax_table':authorize(db,business_id,code,ctx,'view')
    return success_response(run_operation(db,business_id,code,action,payload,ctx.get_user_id()),request)


@router.get('/business/{business_id}/{code}/audit')
def audit(request:Request,business_id:int,code:str,db:Session=Depends(get_db),ctx:AuthContext=Depends(get_current_user)):
    authorize(db,business_id,code,ctx,'settings')
    rows=db.scalars(select(AdvancedPluginAudit).where(AdvancedPluginAudit.business_id==business_id,AdvancedPluginAudit.plugin_code==code).order_by(AdvancedPluginAudit.id.desc()).limit(50))
    return success_response({'items':[{'id':r.id,'record_id':r.record_id,'actor_user_id':r.actor_user_id,'action':r.action,'details':r.details,'created_at':r.created_at.isoformat()} for r in rows]},request)


@router.get('/business/{business_id}/{code}/finance')
def finance(request:Request,business_id:int,code:str,db:Session=Depends(get_db),ctx:AuthContext=Depends(get_current_user)):
    authorize(db,business_id,code,ctx)
    from app.services.advanced_plugin_posting_service import workspace
    return success_response(workspace(db,business_id,code),request)


@router.put('/business/{business_id}/{code}/finance/config')
def finance_config(request:Request,business_id:int,code:str,payload:dict[str,Any]=Body(...),db:Session=Depends(get_db),ctx:AuthContext=Depends(get_current_user)):
    authorize(db,business_id,code,ctx,'approve')
    from app.services.advanced_plugin_posting_service import save_config
    return success_response(save_config(db,business_id,code,payload,ctx.get_user_id()),request)


@router.post('/business/{business_id}/{code}/finance/drafts')
def finance_draft(request:Request,business_id:int,code:str,payload:dict[str,Any]=Body(...),db:Session=Depends(get_db),ctx:AuthContext=Depends(get_current_user)):
    authorize(db,business_id,code,ctx,'write')
    if set(payload)!={'record_id'} or type(payload['record_id']) is not int or payload['record_id']<=0:svc.fail('شناسه رویداد مالی را مشخص کنید.')
    from app.services.advanced_plugin_posting_service import prepare
    return success_response(prepare(db,business_id,code,payload['record_id'],ctx.get_user_id()),request)


@router.post('/business/{business_id}/{code}/finance/{posting_id}/{action}')
def finance_decision(request:Request,business_id:int,code:str,posting_id:int,action:str,payload:dict[str,Any]=Body(...),db:Session=Depends(get_db),ctx:AuthContext=Depends(get_current_user)):
    if action not in {'approve','reject','reverse','refresh'}:svc.fail('عملیات مالی ناشناخته است.')
    authorize(db,business_id,code,ctx,'write' if action=='refresh' else 'approve')
    from app.services.advanced_plugin_posting_service import decide,refresh
    data=refresh(db,business_id,code,posting_id,payload,ctx.get_user_id()) if action=='refresh' else decide(db,business_id,code,posting_id,action,payload,ctx.get_user_id())
    return success_response(data,request)
