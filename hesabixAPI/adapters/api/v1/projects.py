"""
API endpoints برای مدیریت پروژه‌ها
"""

from fastapi import APIRouter, Depends, Path, Body, Query, Request
from sqlalchemy.orm import Session
from typing import Dict, Any, Optional

from app.core.auth_dependency import get_current_user, AuthContext, get_db
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.task_project_permissions import (
    accessible_project_ids,
    business_project_action,
    project_route_guard_dep,
)
from app.core.responses import success_response, ApiError
from app.core.pagination import paginate_query
from app.core.cache import get_cache
from app.services.project_service import (
	create_project,
	update_project,
	delete_project,
	get_project_statistics,
	list_project_documents,
	get_project_workspace,
	get_project_timeline,
	list_project_milestones,
	list_project_cycles,
	create_project_cycle,
	update_project_cycle,
	delete_project_cycle,
	create_project_milestone,
	update_project_milestone,
	delete_project_milestone,
	list_project_members,
	upsert_project_member,
	remove_project_member
)
from adapters.db.repositories.project_repository import ProjectRepository
from adapters.db.models.project import Project
from adapters.db.models.task_management import ProjectMember
from adapters.api.v1.schema_models.project_workspace import (
    ProjectMemberUpsertRequest,
    ProjectMilestoneCreateRequest,
    ProjectMilestoneUpdateRequest,
    ProjectCycleCreateRequest,
    ProjectCycleUpdateRequest,
)
from adapters.api.v1.schema_models.project import (
	ProjectCreateRequest,
	ProjectUpdateRequest,
	ProjectResponse,
	ProjectListResponse,
	ProjectStatisticsResponse,
	ProjectFilterRequest
)
from app.core.responses import format_datetime_fields

router = APIRouter(tags=["پروژه‌ها"], dependencies=[Depends(project_route_guard_dep)])


def _format_project(project: Project, request: Request = None) -> Dict[str, Any]:
	"""فرمت کردن پروژه برای پاسخ"""
	status_names = {
		'active': 'فعال',
		'completed': 'تکمیل شده',
		'on_hold': 'معلق',
		'cancelled': 'لغو شده'
	}
	
	data = {
		'id': project.id,
		'business_id': project.business_id,
		'code': project.code,
		'name': project.name,
		'description': project.description,
		'status': project.status,
		'status_name': status_names.get(project.status, project.status),
		'start_date': project.start_date.isoformat() if project.start_date else None,
		'end_date': project.end_date.isoformat() if project.end_date else None,
		'budget': float(project.budget) if project.budget else None,
		'currency_id': project.currency_id,
		'currency_code': project.currency.code if project.currency else None,
		'currency_symbol': project.currency.symbol if project.currency else None,
		'manager_user_id': project.manager_user_id,
		'manager_name': f"{project.manager.first_name or ''} {project.manager.last_name or ''}".strip() if project.manager else None,
		'person_id': project.person_id,
		'person_name': project.person.alias_name if project.person else None,
		'is_active': project.is_active,
		'created_at': project.created_at.isoformat(),
		'updated_at': project.updated_at.isoformat(),
		'created_by_id': project.created_by_user_id,
		'created_by_name': f"{project.created_by.first_name or ''} {project.created_by.last_name or ''}".strip() if project.created_by else None,
		'extra_info': project.extra_info
	}
	
	if request:
		data = format_datetime_fields(data, request)
	
	return data


@router.post(
	"/businesses/{business_id}/projects",
	summary="ایجاد پروژه جدید",
	description="ایجاد پروژه جدید برای کسب‌وکار"
)
@require_business_access("business_id")
async def create_project_endpoint(
	request: Request,
	business_id: int = Path(..., description="شناسه کسب‌وکار", gt=0),
	data: ProjectCreateRequest = Body(..., description="اطلاعات پروژه"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user)
):
	"""ایجاد پروژه جدید"""
	if not business_project_action(ctx, db, business_id, "project_create"):
		raise ApiError(
			"PROJECT_PERMISSION_DENIED",
			"Missing project capability: project_create",
			http_status=403,
		)
	project = create_project(db, business_id, ctx.get_user_id(), data.dict())
	
	return success_response(
		data={
			'id': project.id,
			'code': project.code,
			'name': project.name
		},
		request=request,
		message="PROJECT_CREATED"
	)


@router.get(
	"/businesses/{business_id}/projects",
	summary="لیست پروژه‌ها",
	description="دریافت لیست پروژه‌های یک کسب‌وکار با امکان فیلتر و جستجو"
)
@require_business_access("business_id")
async def list_projects_endpoint(
	request: Request,
	business_id: int = Path(..., description="شناسه کسب‌وکار", gt=0),
	search: Optional[str] = Query(None, description="عبارت جستجو"),
	status: Optional[str] = Query(None, description="فیلتر وضعیت"),
	is_active: Optional[bool] = Query(None, description="فعال/غیرفعال"),
	person_id: Optional[int] = Query(None, description="شخص مرتبط"),
	manager_user_id: Optional[int] = Query(None, description="مدیر پروژه"),
	page: int = Query(1, ge=1, description="شماره صفحه"),
	limit: int = Query(50, ge=1, le=500, description="تعداد در هر صفحه"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user)
):
	"""لیست پروژه‌ها"""
	repo = ProjectRepository(db)
	
	# ساخت فیلترها
	filters = {}
	if status:
		filters['status'] = status
	if is_active is not None:
		filters['is_active'] = is_active
	if person_id:
		filters['person_id'] = person_id
	if manager_user_id:
		filters['manager_user_id'] = manager_user_id
	
	# جستجو
	allowed_project_ids = accessible_project_ids(ctx, db, business_id)
	skip = (page - 1) * limit
	projects, total = repo.search(
		business_id=business_id,
		search_term=search,
		filters=filters,
		allowed_project_ids=allowed_project_ids,
		skip=skip,
		limit=limit
	)
	
	# فرمت کردن
	items = [_format_project(p, request) for p in projects]
	
	return success_response(
		data={
			'items': items,
			'total': total,
			'page': page,
			'limit': limit,
			'pages': (total + limit - 1) // limit
		},
		request=request,
		message="PROJECTS_LIST_FETCHED"
	)


@router.get(
	"/projects/{project_id}",
	summary="جزئیات پروژه",
	description="دریافت جزئیات یک پروژه همراه با آمار"
)
async def get_project_endpoint(
	request: Request,
	project_id: int = Path(..., description="شناسه پروژه", gt=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user)
):
	"""دریافت جزئیات پروژه"""
	repo = ProjectRepository(db)
	project = repo.get_by_id(project_id, load_relations=True)
	
	if not project:
		raise ApiError("PROJECT_NOT_FOUND", "پروژه یافت نشد", http_status=404)
	
	if not ctx.can_access_business(project.business_id):
		raise ApiError("FORBIDDEN", "No access to this project", http_status=403)
	
	# دریافت آمار
	stats = get_project_statistics(db, project_id)
	
	return success_response(
		data={
			'project': _format_project(project, request),
			'statistics': stats
		},
		request=request,
		message="PROJECT_DETAILS_FETCHED"
	)


@router.put(
	"/projects/{project_id}",
	summary="به‌روزرسانی پروژه",
	description="به‌روزرسانی اطلاعات یک پروژه"
)
async def update_project_endpoint(
	request: Request,
	project_id: int = Path(..., description="شناسه پروژه", gt=0),
	data: ProjectUpdateRequest = Body(..., description="اطلاعات جدید"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user)
):
	"""به‌روزرسانی پروژه"""
	# دریافت business_id از پروژه برای بررسی دسترسی
	repo = ProjectRepository(db)
	project = repo.get_by_id(project_id)
	
	if not project:
		raise ApiError("PROJECT_NOT_FOUND", "پروژه یافت نشد", http_status=404)
	
	if not ctx.can_access_business(project.business_id):
		raise ApiError("FORBIDDEN", "No access to this project", http_status=403)
	
	updated_project = update_project(
		db,
		project_id,
		project.business_id,
		data.dict(exclude_unset=True)
	)
	
	return success_response(
		data={
			'id': updated_project.id,
			'code': updated_project.code,
			'name': updated_project.name
		},
		request=request,
		message="PROJECT_UPDATED"
	)


@router.delete(
	"/projects/{project_id}",
	summary="حذف پروژه",
	description="حذف یک پروژه (soft delete)"
)
async def delete_project_endpoint(
	request: Request,
	project_id: int = Path(..., description="شناسه پروژه", gt=0),
	hard_delete: bool = Query(False, description="حذف کامل"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user)
):
	"""حذف پروژه"""
	# دریافت business_id از پروژه برای بررسی دسترسی
	repo = ProjectRepository(db)
	project = repo.get_by_id(project_id)
	
	if not project:
		raise ApiError("PROJECT_NOT_FOUND", "پروژه یافت نشد", http_status=404)
	
	if not ctx.can_access_business(project.business_id):
		raise ApiError("FORBIDDEN", "No access to this project", http_status=403)
	
	delete_project(db, project_id, project.business_id, hard_delete=hard_delete)
	
	return success_response(
		request=request,
		message="PROJECT_DELETED"
	)


@router.get(
	"/projects/{project_id}/documents",
	summary="لیست اسناد پروژه",
	description="دریافت لیست اسناد مرتبط با یک پروژه"
)
async def list_project_documents_endpoint(
	request: Request,
	project_id: int = Path(..., description="شناسه پروژه", gt=0),
	page: int = Query(1, ge=1, description="شماره صفحه"),
	limit: int = Query(50, ge=1, le=500, description="تعداد در هر صفحه"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user)
):
	"""لیست اسناد پروژه"""
	project = ProjectRepository(db).get_by_id(project_id)
	if not project:
		raise ApiError("PROJECT_NOT_FOUND", "پروژه یافت نشد", http_status=404)
	if not ctx.can_access_business(project.business_id):
		raise ApiError("FORBIDDEN", "No access to this project", http_status=403)
	skip = (page - 1) * limit
	documents, total = list_project_documents(db, project_id, skip=skip, limit=limit)
	
	# فرمت کردن اسناد (ساده)
	items = []
	for doc in documents:
		items.append({
			'id': doc.id,
			'code': doc.code,
			'document_type': doc.document_type,
			'document_date': doc.document_date.isoformat(),
			'description': doc.description
		})
	
	return success_response(
		data={
			'items': items,
			'total': total,
			'page': page,
			'limit': limit
		},
		request=request,
		message="PROJECT_DOCUMENTS_FETCHED"
	)


@router.post(
	"/businesses/{business_id}/projects/search",
	summary="جستجوی پروژه‌ها",
	description="جستجوی پروژه‌ها با فیلترها و صفحه‌بندی (برای استفاده در فرانت)"
)
@require_business_access("business_id")
async def search_projects_endpoint(
	request: Request,
	business_id: int = Path(..., description="شناسه کسب‌وکار", gt=0),
	body_data: Dict[str, Any] = Body(default={}),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user)
):
	"""جستجوی پروژه‌ها با body data"""
	repo = ProjectRepository(db)
	
	# استخراج پارامترها از body
	take = body_data.get('take', 50)
	skip = body_data.get('skip', 0)
	search = body_data.get('search')
	is_active = body_data.get('is_active')
	status = body_data.get('status')
	person_id = body_data.get('person_id')
	manager_user_id = body_data.get('manager_user_id')
	
	# ساخت فیلترها
	filters = {}
	if is_active is not None:
		filters['is_active'] = bool(is_active)
	if status:
		filters['status'] = status
	if person_id:
		filters['person_id'] = int(person_id)
	if manager_user_id:
		filters['manager_user_id'] = int(manager_user_id)
	
	# کش نتایج جستجوی پروژه‌ها بر اساس پارامترها
	cache = get_cache()
	cache_key = None

	if cache.enabled:
		import json, hashlib
		filters_json = json.dumps({
			"search": search,
			"filters": filters,
			"take": take,
			"skip": skip,
		}, sort_keys=True, ensure_ascii=False)
		filters_hash = hashlib.sha256(filters_json.encode("utf-8")).hexdigest()[:16]
		cache_key = f"projects_search:{business_id}:{ctx.get_user_id()}:{filters_hash}"
		cached = cache.get(cache_key)
		if cached is not None:
			return success_response(cached, request)

	# جستجو
	allowed_project_ids = accessible_project_ids(ctx, db, business_id)
	projects, total = repo.search(
		business_id=business_id,
		search_term=search,
		filters=filters if filters else None,
		allowed_project_ids=allowed_project_ids,
		skip=skip,
		limit=take
	)
	
	# فرمت کردن
	items = [_format_project(p, request) for p in projects]
	
	response_data = {
		'items': items,
		'total': total,
		'take': take,
		'skip': skip
	}

	if cache.enabled and cache_key:
		# TTL کوتاه چون جستجوها می‌توانند سریع عوض شوند
		cache.set(cache_key, response_data, ttl=30)
	
	return success_response(
		data=response_data,
		request=request,
		message="PROJECTS_SEARCHED"
	)


@router.get(
	"/businesses/{business_id}/projects/active",
	summary="لیست پروژه‌های فعال (برای کمبوباکس)",
	description="دریافت لیست ساده پروژه‌های فعال برای استفاده در کمبوباکس‌ها"
)
@require_business_access("business_id")
async def list_active_projects_simple_endpoint(
	request: Request,
	business_id: int = Path(..., description="شناسه کسب‌وکار", gt=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user)
):
	"""لیست ساده پروژه‌های فعال"""
	repo = ProjectRepository(db)
	allowed_project_ids = accessible_project_ids(ctx, db, business_id)
	projects = repo.list_by_business(
		business_id=business_id,
		is_active=True,
		allowed_project_ids=allowed_project_ids,
		skip=0,
		limit=1000  # حداکثر برای کمبوباکس
	)
	
	# فرمت با فیلدهای لازم برای مدل فلاتر
	status_names = {
		'active': 'فعال',
		'completed': 'تکمیل شده',
		'on_hold': 'معلق',
		'cancelled': 'لغو شده'
	}
	
	items = []
	for p in projects:
		items.append({
			'id': p.id,
			'business_id': p.business_id,
			'code': p.code,
			'name': p.name,
			'status': p.status,
			'status_name': status_names.get(p.status, p.status),
			'is_active': p.is_active,
			'created_at': p.created_at.isoformat(),
			'updated_at': p.updated_at.isoformat(),
			'created_by_id': p.created_by_user_id
		})
	
	return success_response(
		data={'items': items},
		request=request,
		message="ACTIVE_PROJECTS_FETCHED"
	)




def _format_project_cycle(row: Dict[str, Any]) -> Dict[str, Any]:
    cycle = row["cycle"]
    return {
        "id": cycle.id,
        "business_id": cycle.business_id,
        "project_id": cycle.project_id,
        "name": cycle.name,
        "goal": cycle.goal,
        "start_at": cycle.start_at,
        "end_at": cycle.end_at,
        "status": cycle.status,
        "created_by_user_id": cycle.created_by_user_id,
        "created_at": cycle.created_at,
        "updated_at": cycle.updated_at,
        "task_total": row.get("task_total", 0),
        "task_completed": row.get("task_completed", 0),
        "progress_percent": row.get("progress_percent", 0.0),
    }


def _format_project_milestone(row: Dict[str, Any]) -> Dict[str, Any]:
    milestone = row["milestone"]
    return {
        "id": milestone.id,
        "business_id": milestone.business_id,
        "project_id": milestone.project_id,
        "title": milestone.title,
        "description": milestone.description,
        "start_at": milestone.start_at,
        "target_at": milestone.target_at,
        "status": milestone.status,
        "sort_order": float(milestone.sort_order or 0),
        "created_by_user_id": milestone.created_by_user_id,
        "created_at": milestone.created_at,
        "updated_at": milestone.updated_at,
        "task_total": row.get("task_total", 0),
        "task_completed": row.get("task_completed", 0),
        "progress_percent": row.get("progress_percent", 0.0),
    }


def _format_project_member(member: ProjectMember) -> Dict[str, Any]:
    user = member.user
    name = f"{user.first_name or ''} {user.last_name or ''}".strip() if user else ""
    return {
        "id": member.id,
        "business_id": member.business_id,
        "project_id": member.project_id,
        "user_id": member.user_id,
        "name": name or (user.email if user else None) or f"User {member.user_id}",
        "email": user.email if user else None,
        "role": member.role,
        "created_at": member.created_at,
    }


@router.get("/businesses/{business_id}/projects/{project_id}/workspace", summary="فضای کاری پروژه")
@require_business_access("business_id")
async def get_project_workspace_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    project_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    data = get_project_workspace(db, business_id, project_id)
    project = data.pop("project")
    members = data.pop("members")
    return success_response(
        data={
            "project": _format_project(project, request),
            **data,
            "members": [
                format_datetime_fields(_format_project_member(m), request, business_id)
                for m in members
            ],
        },
        request=request,
        message="PROJECT_WORKSPACE_FETCHED",
    )


@router.get(
    "/businesses/{business_id}/projects/{project_id}/cycles",
    summary="چرخه‌ها / اسپرینت‌های پروژه",
)
@require_business_access("business_id")
async def list_project_cycles_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    project_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    rows = list_project_cycles(db, business_id, project_id)
    return success_response(
        data=format_datetime_fields(
            {"items": [_format_project_cycle(row) for row in rows]},
            request,
            business_id,
        ),
        request=request,
        message="PROJECT_CYCLES_FETCHED",
    )


@router.post(
    "/businesses/{business_id}/projects/{project_id}/cycles",
    summary="ایجاد چرخه / اسپرینت",
)
@require_business_access("business_id")
async def create_project_cycle_endpoint(
    request: Request,
    data: ProjectCycleCreateRequest,
    business_id: int = Path(..., gt=0),
    project_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    cycle = create_project_cycle(
        db,
        business_id,
        project_id,
        ctx.get_user_id(),
        data.dict(),
    )
    row = {
        "cycle": cycle,
        "task_total": 0,
        "task_completed": 0,
        "progress_percent": 0.0,
    }
    return success_response(
        data=format_datetime_fields(
            {"cycle": _format_project_cycle(row)},
            request,
            business_id,
        ),
        request=request,
        message="PROJECT_CYCLE_CREATED",
    )


@router.patch(
    "/businesses/{business_id}/projects/{project_id}/cycles/{cycle_id}",
    summary="ویرایش چرخه / اسپرینت",
)
@require_business_access("business_id")
async def update_project_cycle_endpoint(
    request: Request,
    data: ProjectCycleUpdateRequest,
    business_id: int = Path(..., gt=0),
    project_id: int = Path(..., gt=0),
    cycle_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    cycle = update_project_cycle(
        db,
        business_id,
        project_id,
        cycle_id,
        data.dict(exclude_unset=True),
    )
    rows = list_project_cycles(db, business_id, project_id)
    row = next(
        (item for item in rows if item["cycle"].id == cycle.id),
        {
            "cycle": cycle,
            "task_total": 0,
            "task_completed": 0,
            "progress_percent": 0.0,
        },
    )
    return success_response(
        data=format_datetime_fields(
            {"cycle": _format_project_cycle(row)},
            request,
            business_id,
        ),
        request=request,
        message="PROJECT_CYCLE_UPDATED",
    )


@router.delete(
    "/businesses/{business_id}/projects/{project_id}/cycles/{cycle_id}",
    summary="حذف چرخه / اسپرینت",
)
@require_business_access("business_id")
async def delete_project_cycle_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    project_id: int = Path(..., gt=0),
    cycle_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    delete_project_cycle(db, business_id, project_id, cycle_id)
    return success_response(
        data={"id": cycle_id},
        request=request,
        message="PROJECT_CYCLE_DELETED",
    )


@router.get(
    "/businesses/{business_id}/projects/{project_id}/milestones",
    summary="مایلستون‌های پروژه",
)
@require_business_access("business_id")
async def list_project_milestones_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    project_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    rows = list_project_milestones(db, business_id, project_id)
    return success_response(
        data=format_datetime_fields(
            {"items": [_format_project_milestone(row) for row in rows]},
            request,
            business_id,
        ),
        request=request,
        message="PROJECT_MILESTONES_FETCHED",
    )


@router.post(
    "/businesses/{business_id}/projects/{project_id}/milestones",
    summary="ایجاد مایلستون پروژه",
)
@require_business_access("business_id")
async def create_project_milestone_endpoint(
    request: Request,
    data: ProjectMilestoneCreateRequest,
    business_id: int = Path(..., gt=0),
    project_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    milestone = create_project_milestone(
        db,
        business_id,
        project_id,
        ctx.get_user_id(),
        data.dict(),
    )
    row = {
        "milestone": milestone,
        "task_total": 0,
        "task_completed": 0,
        "progress_percent": 0.0,
    }
    return success_response(
        data=format_datetime_fields(
            {"milestone": _format_project_milestone(row)},
            request,
            business_id,
        ),
        request=request,
        message="PROJECT_MILESTONE_CREATED",
    )


@router.patch(
    "/businesses/{business_id}/projects/{project_id}/milestones/{milestone_id}",
    summary="ویرایش مایلستون پروژه",
)
@require_business_access("business_id")
async def update_project_milestone_endpoint(
    request: Request,
    data: ProjectMilestoneUpdateRequest,
    business_id: int = Path(..., gt=0),
    project_id: int = Path(..., gt=0),
    milestone_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    milestone = update_project_milestone(
        db,
        business_id,
        project_id,
        milestone_id,
        data.dict(exclude_unset=True),
    )
    rows = list_project_milestones(db, business_id, project_id)
    row = next(
        (item for item in rows if item["milestone"].id == milestone.id),
        {
            "milestone": milestone,
            "task_total": 0,
            "task_completed": 0,
            "progress_percent": 0.0,
        },
    )
    return success_response(
        data=format_datetime_fields(
            {"milestone": _format_project_milestone(row)},
            request,
            business_id,
        ),
        request=request,
        message="PROJECT_MILESTONE_UPDATED",
    )


@router.delete(
    "/businesses/{business_id}/projects/{project_id}/milestones/{milestone_id}",
    summary="حذف مایلستون پروژه",
)
@require_business_access("business_id")
async def delete_project_milestone_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    project_id: int = Path(..., gt=0),
    milestone_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    delete_project_milestone(db, business_id, project_id, milestone_id)
    return success_response(
        data={"id": milestone_id},
        request=request,
        message="PROJECT_MILESTONE_DELETED",
    )


@router.get(
    "/businesses/{business_id}/projects/{project_id}/timeline",
    summary="داده زمان‌بندی پروژه",
)
@require_business_access("business_id")
async def get_project_timeline_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    project_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    data = get_project_timeline(db, business_id, project_id)
    return success_response(
        data=format_datetime_fields(data, request, business_id),
        request=request,
        message="PROJECT_TIMELINE_FETCHED",
    )


@router.get("/businesses/{business_id}/projects/{project_id}/members", summary="اعضای پروژه")
@require_business_access("business_id")
async def list_project_members_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    project_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    del ctx
    members = list_project_members(db, business_id, project_id)
    return success_response(
        data={"items": [
            format_datetime_fields(_format_project_member(m), request, business_id)
            for m in members
        ]},
        request=request,
        message="PROJECT_MEMBERS_FETCHED",
    )


@router.post("/businesses/{business_id}/projects/{project_id}/members", summary="افزودن یا تغییر نقش عضو پروژه")
@require_business_access("business_id")
async def upsert_project_member_endpoint(
    request: Request,
    data: ProjectMemberUpsertRequest,
    business_id: int = Path(..., gt=0),
    project_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    member = upsert_project_member(
        db, business_id, project_id, ctx.get_user_id(), data.user_id, data.role
    )
    return success_response(
        data={"member": format_datetime_fields(
            _format_project_member(member), request, business_id
        )},
        request=request,
        message="PROJECT_MEMBER_SAVED",
    )


@router.delete("/businesses/{business_id}/projects/{project_id}/members/{user_id}", summary="حذف عضو از پروژه")
@require_business_access("business_id")
async def remove_project_member_endpoint(
    request: Request,
    business_id: int = Path(..., gt=0),
    project_id: int = Path(..., gt=0),
    user_id: int = Path(..., gt=0),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    remove_project_member(
        db, business_id, project_id, ctx.get_user_id(), user_id
    )
    return success_response(
        data={"user_id": user_id},
        request=request,
        message="PROJECT_MEMBER_REMOVED",
    )
