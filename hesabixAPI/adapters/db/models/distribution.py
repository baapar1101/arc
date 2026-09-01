"""مدل‌های افزونه پخش مویرگی."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

from sqlalchemy import (
	Boolean,
	Date,
	DateTime,
	ForeignKey,
	Integer,
	JSON,
	Numeric,
	String,
	Text,
	UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base




class DistributionBusinessSettings(Base):
	"""تنظیمات افزونه پخش مویرگی در سطح کسب‌وکار."""

	__tablename__ = "distribution_business_settings"

	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), primary_key=True)
	shared_routing_catalog: Mapped[bool] = mapped_column(
		Boolean, nullable=False, default=False,
		comment="اگر False باشد ویزیتور عادی فقط مسیرهای تخصیص‌داده‌شده به خود را می‌بیند.",
	)
	require_visit_in_daily_plan: Mapped[bool] = mapped_column(
		Boolean, nullable=False, default=False,
		comment="شروع ویزیت فقط برای اشخاص موجود در برنامهٔ روز.",
	)
	geofence_radius_meters: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	require_geofence: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	visit_checklist_template: Mapped[list | dict | None] = mapped_column(JSON, nullable=True)
	enable_van_sales: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	default_source_warehouse_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("warehouses.id", ondelete="SET NULL"), nullable=True,
	)
	enable_presell: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	enable_promotions: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	visitor_max_discount_percent: Mapped[float] = mapped_column(Numeric(5, 2), nullable=False, default=0)
	enable_suggested_order: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class DistributionTerritory(Base):
	__tablename__ = "distribution_territories"
	__table_args__ = (UniqueConstraint("business_id", "code", name="uq_distribution_territories_business_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	code: Mapped[str] = mapped_column(String(50), nullable=False)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	routes: Mapped[list["DistributionRoute"]] = relationship(
		"DistributionRoute",
		back_populates="territory",
	)


class DistributionRoute(Base):
	__tablename__ = "distribution_routes"
	__table_args__ = (UniqueConstraint("business_id", "code", name="uq_distribution_routes_business_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	territory_id: Mapped[int | None] = mapped_column(
		Integer,
		ForeignKey("distribution_territories.id", ondelete="SET NULL"),
		index=True,
		nullable=True,
	)
	code: Mapped[str] = mapped_column(String(50), nullable=False)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	plan_sort_overrides: Mapped[Any | None] = mapped_column(
		JSON,
		nullable=True,
		comment="ترتیب بهینه‌شدهٔ روزمحور: {YYYY-MM-DD: {stop_id: sort_order}}",
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	territory: Mapped[DistributionTerritory | None] = relationship("DistributionTerritory", back_populates="routes")
	stops: Mapped[list["DistributionRouteStop"]] = relationship(
		"DistributionRouteStop",
		back_populates="route",
		cascade="all, delete-orphan",
		order_by="DistributionRouteStop.sort_order",
	)
	assignments: Mapped[list["DistributionRouteAssignment"]] = relationship(
		"DistributionRouteAssignment",
		back_populates="route",
		cascade="all, delete-orphan",
	)


class DistributionRouteStop(Base):
	__tablename__ = "distribution_route_stops"
	__table_args__ = (
		UniqueConstraint("route_id", "person_id", "weekday", name="uq_distribution_route_stop_route_person_weekday"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	route_id: Mapped[int] = mapped_column(Integer, ForeignKey("distribution_routes.id", ondelete="CASCADE"), index=True)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), index=True)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	weekday: Mapped[int | None] = mapped_column(Integer, nullable=True)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	route: Mapped["DistributionRoute"] = relationship("DistributionRoute", back_populates="stops")


class DistributionRouteAssignment(Base):
	__tablename__ = "distribution_route_assignments"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	route_id: Mapped[int] = mapped_column(Integer, ForeignKey("distribution_routes.id", ondelete="CASCADE"), index=True)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)
	valid_from: Mapped[date] = mapped_column(Date, nullable=False)
	valid_to: Mapped[date | None] = mapped_column(Date, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	route: Mapped["DistributionRoute"] = relationship("DistributionRoute", back_populates="assignments")


class DistributionFieldVisit(Base):
	__tablename__ = "distribution_field_visits"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), index=True)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)
	route_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("distribution_routes.id", ondelete="SET NULL"), nullable=True)
	route_stop_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("distribution_route_stops.id", ondelete="SET NULL"), nullable=True)
	status: Mapped[str] = mapped_column(String(32), nullable=False)
	started_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
	ended_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	outcome: Mapped[str | None] = mapped_column(String(32), nullable=True)
	no_order_reason: Mapped[str | None] = mapped_column(String(255), nullable=True)
	document_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True)
	deal_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("crm_deals.id", ondelete="SET NULL"), nullable=True)
	crm_activity_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("crm_activities.id", ondelete="SET NULL"), nullable=True)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)
	start_latitude: Mapped[float | None] = mapped_column(Numeric(11, 8), nullable=True)
	start_longitude: Mapped[float | None] = mapped_column(Numeric(11, 8), nullable=True)
	end_latitude: Mapped[float | None] = mapped_column(Numeric(11, 8), nullable=True)
	end_longitude: Mapped[float | None] = mapped_column(Numeric(11, 8), nullable=True)
	checklist_answers: Mapped[dict | list | None] = mapped_column(JSON, nullable=True)
	shelf_photo_file_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
	extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class DistributionReturnRequest(Base):
	__tablename__ = "distribution_return_requests"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), index=True)
	visit_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("distribution_field_visits.id", ondelete="SET NULL"), nullable=True)
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="pending")
	lines: Mapped[Any] = mapped_column(JSON, nullable=False)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)
	resolved_document_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"))
	resolved_by_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	resolved_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class DistributionVan(Base):
	"""ون توزیع — هر رکورد به یک انبار (موجودی ون) متصل است."""

	__tablename__ = "distribution_vans"
	__table_args__ = (UniqueConstraint("business_id", "code", name="uq_distribution_vans_business_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	warehouse_id: Mapped[int] = mapped_column(Integer, ForeignKey("warehouses.id", ondelete="RESTRICT"), index=True)
	user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
	code: Mapped[str] = mapped_column(String(50), nullable=False)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class DistributionOfflineSyncBatch(Base):
	__tablename__ = "distribution_offline_sync_batches"
	__table_args__ = (UniqueConstraint("business_id", "client_batch_id", name="uq_distribution_offline_batch"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)
	client_batch_id: Mapped[str] = mapped_column(String(64), nullable=False)
	actions: Mapped[Any] = mapped_column(JSON, nullable=False)
	results: Mapped[Any] = mapped_column(JSON, nullable=True)
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="completed")
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class DistributionSalesTarget(Base):
	"""هدف فروش ویزیتور — روزانه یا ماهانه."""

	__tablename__ = "distribution_sales_targets"
	__table_args__ = (
		UniqueConstraint(
			"business_id",
			"user_id",
			"period_type",
			"period_start",
			"metric",
			"product_id",
			name="uq_distribution_sales_target_metric",
		),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)
	period_type: Mapped[str] = mapped_column(String(16), nullable=False)  # day | month
	period_start: Mapped[date] = mapped_column(Date, nullable=False)
	target_amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
	metric: Mapped[str] = mapped_column(String(32), nullable=False, default="amount")  # amount|visits|sku_qty|coverage_pct
	# 0 = بدون SKU (برای یکتایی پایدار؛ بدون FK تا sentinel مجاز باشد)
	product_id: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	target_value: Mapped[float | None] = mapped_column(Numeric(18, 2), nullable=True)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class DistributionDailySettlement(Base):
	"""تسویه روزانه ویزیتور میدانی."""

	__tablename__ = "distribution_daily_settlements"
	__table_args__ = (
		UniqueConstraint(
			"business_id",
			"user_id",
			"settlement_date",
			name="uq_distribution_daily_settlement",
		),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)
	settlement_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="draft")
	expected_sales: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	cash_collected: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	cheque_collected: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	card_collected: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	other_collected: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	expenses: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	variance: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	visit_snapshot: Mapped[Any] = mapped_column(JSON, nullable=True)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)
	receipt_document_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True)
	cash_register_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
	cheque_refs: Mapped[Any | None] = mapped_column(JSON, nullable=True)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"))
	confirmed_by_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	confirmed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class DistributionVisitHeartbeat(Base):
	"""نقاط GPS زنده ویزیت برای trail روز."""

	__tablename__ = "distribution_visit_heartbeats"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	visit_id: Mapped[int] = mapped_column(Integer, ForeignKey("distribution_field_visits.id", ondelete="CASCADE"), index=True)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
	latitude: Mapped[float] = mapped_column(Numeric(11, 8), nullable=False)
	longitude: Mapped[float] = mapped_column(Numeric(11, 8), nullable=False)
	recorded_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)


class DistributionVisitOrder(Base):
	"""سفارش پیش‌فروش ویزیتور (جدا از فروش ون)."""

	__tablename__ = "distribution_visit_orders"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	visit_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("distribution_field_visits.id", ondelete="SET NULL"), nullable=True)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), index=True)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)
	route_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("distribution_routes.id", ondelete="SET NULL"), nullable=True)
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="draft")
	lines: Mapped[Any] = mapped_column(JSON, nullable=False)
	document_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True)
	delivery_trip_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("distribution_delivery_trips.id", ondelete="SET NULL"), nullable=True,
	)
	requested_delivery_date: Mapped[date | None] = mapped_column(Date, nullable=True)
	promotion_ids: Mapped[Any | None] = mapped_column(JSON, nullable=True)
	discount_total: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	net_total: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)
	extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class DistributionTradePromotion(Base):
	__tablename__ = "distribution_trade_promotions"
	__table_args__ = (UniqueConstraint("business_id", "code", name="uq_distribution_promo_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	code: Mapped[str] = mapped_column(String(50), nullable=False)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	mechanic: Mapped[str] = mapped_column(String(32), nullable=False)  # percent_off|amount_off|bxgy|foc
	config: Mapped[Any] = mapped_column(JSON, nullable=False)
	valid_from: Mapped[date] = mapped_column(Date, nullable=False)
	valid_to: Mapped[date | None] = mapped_column(Date, nullable=True)
	territory_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("distribution_territories.id", ondelete="SET NULL"), nullable=True)
	route_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("distribution_routes.id", ondelete="SET NULL"), nullable=True)
	product_ids: Mapped[Any | None] = mapped_column(JSON, nullable=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class DistributionDeliveryTrip(Base):
	__tablename__ = "distribution_delivery_trips"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	driver_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)
	van_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("distribution_vans.id", ondelete="SET NULL"), nullable=True)
	trip_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="draft")
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)
	started_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	completed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"))
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	stops: Mapped[list["DistributionDeliveryStop"]] = relationship(
		"DistributionDeliveryStop",
		back_populates="trip",
		cascade="all, delete-orphan",
		order_by="DistributionDeliveryStop.sort_order",
	)


class DistributionDeliveryStop(Base):
	__tablename__ = "distribution_delivery_stops"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	trip_id: Mapped[int] = mapped_column(Integer, ForeignKey("distribution_delivery_trips.id", ondelete="CASCADE"), index=True)
	order_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("distribution_visit_orders.id", ondelete="SET NULL"), nullable=True)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"))
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="pending")
	pod_confirmed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	pod_signer_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
	pod_note: Mapped[str | None] = mapped_column(Text, nullable=True)
	pod_photo_file_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
	pod_latitude: Mapped[float | None] = mapped_column(Numeric(11, 8), nullable=True)
	pod_longitude: Mapped[float | None] = mapped_column(Numeric(11, 8), nullable=True)
	delivered_qty_snapshot: Mapped[Any | None] = mapped_column(JSON, nullable=True)
	failure_reason: Mapped[str | None] = mapped_column(String(255), nullable=True)
	completed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	trip: Mapped["DistributionDeliveryTrip"] = relationship("DistributionDeliveryTrip", back_populates="stops")


class DistributionLoadPlan(Base):
	__tablename__ = "distribution_load_plans"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	plan_date: Mapped[date] = mapped_column(Date, nullable=False)
	warehouse_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("warehouses.id", ondelete="SET NULL"), nullable=True)
	van_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("distribution_vans.id", ondelete="SET NULL"), nullable=True)
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="draft")
	lines: Mapped[Any] = mapped_column(JSON, nullable=False)
	order_ids: Mapped[Any | None] = mapped_column(JSON, nullable=True)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="RESTRICT"))
	confirmed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class DistributionCommissionRule(Base):
	__tablename__ = "distribution_commission_rules"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	rule_type: Mapped[str] = mapped_column(String(32), nullable=False, default="percent_of_sales")
	config: Mapped[Any] = mapped_column(JSON, nullable=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	valid_from: Mapped[date | None] = mapped_column(Date, nullable=True)
	valid_to: Mapped[date | None] = mapped_column(Date, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class DistributionCommissionRun(Base):
	__tablename__ = "distribution_commission_runs"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)
	period_start: Mapped[date] = mapped_column(Date, nullable=False)
	period_end: Mapped[date] = mapped_column(Date, nullable=False)
	rule_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("distribution_commission_rules.id", ondelete="SET NULL"), nullable=True)
	sales_amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	commission_amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="draft")
	breakdown: Mapped[Any | None] = mapped_column(JSON, nullable=True)
	created_by_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class DistributionShelfAudit(Base):
	__tablename__ = "distribution_shelf_audits"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	visit_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("distribution_field_visits.id", ondelete="SET NULL"), nullable=True)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), index=True)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
	answers: Mapped[Any] = mapped_column(JSON, nullable=False)
	score: Mapped[float | None] = mapped_column(Numeric(5, 2), nullable=True)
	photo_file_ids: Mapped[Any | None] = mapped_column(JSON, nullable=True)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class DistributionCustomerAsset(Base):
	__tablename__ = "distribution_customer_assets"
	__table_args__ = (UniqueConstraint("business_id", "asset_code", name="uq_dist_customer_asset_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), index=True)
	asset_code: Mapped[str] = mapped_column(String(64), nullable=False)
	asset_type: Mapped[str] = mapped_column(String(64), nullable=False)
	name: Mapped[str] = mapped_column(String(255), nullable=False)
	status: Mapped[str] = mapped_column(String(32), nullable=False, default="active")
	placed_at: Mapped[date | None] = mapped_column(Date, nullable=True)
	last_checked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)
	extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
