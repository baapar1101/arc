"""
API endpoints برای مدیریت پروژه‌ها
"""

from fastapi import APIRouter, Depends, Path, Body, Query, Request
from sqlalchemy.orm import Session
from typing import Dict, Any, Optional

from app.core.auth_dependency import get_current_user, AuthContext, get_db
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import success_response, ApiError
from app.core.pagination import paginate_query
from app.services.project_service import (
	create_project,
	update_project,
	delete_project,
	get_project_statistics,
	list_project_documents
)
from adapters.db.repositories.project_repository import ProjectRepository
from adapters.db.models.project import Project
from adapters.api.v1.schema_models.project import (
	ProjectCreateRequest,
	ProjectUpdateRequest,
	ProjectResponse,
	ProjectListResponse,
	ProjectStatisticsResponse,
	ProjectFilterRequest
)
from app.core.responses import format_datetime_fields

router = APIRouter(tags=["پروژه‌ها"])


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
	skip = (page - 1) * limit
	projects, total = repo.search(
		business_id=business_id,
		search_term=search,
		filters=filters,
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
	
	# بررسی دسترسی
	# TODO: اضافه کردن بررسی دسترسی business
	
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
	
	# TODO: بررسی دسترسی کاربر به business
	
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
	
	# TODO: بررسی دسترسی کاربر به business
	
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
	projects = repo.list_by_business(
		business_id=business_id,
		is_active=True,
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

