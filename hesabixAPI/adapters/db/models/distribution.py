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
