from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
	String,
	Integer,
	DateTime,
	ForeignKey,
	Numeric,
	Boolean,
	Text,
	UniqueConstraint,
	JSON,
	SmallInteger,
)
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class CustomerClubSettings(Base):
	"""تنظیمات باشگاه مشتریان به ازای هر کسب‌وکار."""

	__tablename__ = "customer_club_settings"
	__table_args__ = (UniqueConstraint("business_id", name="uq_customer_club_settings_business"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("businesses.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	# percent_basis | points_per_currency
	earn_mode: Mapped[str] = mapped_column(String(40), nullable=False, default="percent_basis")
	# net | total_with_tax
	amount_basis: Mapped[str] = mapped_column(String(40), nullable=False, default="net")
	percent_of_basis: Mapped[Decimal | None] = mapped_column(Numeric(18, 8), nullable=True)
	step_currency_amount: Mapped[Decimal | None] = mapped_column(Numeric(18, 4), nullable=True)
	points_per_step: Mapped[Decimal | None] = mapped_column(Numeric(18, 8), nullable=True)
	# floor | ceil | round
	rounding_mode: Mapped[str] = mapped_column(String(16), nullable=False, default="floor")
	max_points_per_invoice: Mapped[Decimal | None] = mapped_column(Numeric(18, 4), nullable=True)
	min_basis_amount: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))
	require_customer_person_type: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	currency_value_per_point: Mapped[Decimal | None] = mapped_column(
		Numeric(18, 8), nullable=True, comment="مبلغ تخفیف به ازای هر امتیاز در ارز فاکتور"
	)
	max_redeem_points_per_invoice: Mapped[Decimal | None] = mapped_column(Numeric(18, 4), nullable=True)
	points_expire_after_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
	referral_points: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	survey_points: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))

	# decoupled: سطح/ضریب از مانده امتیاز | rfm_based_tiers: ضریب از نمره نرمال‌شده RFM
	loyalty_rfm_integration_mode: Mapped[str] = mapped_column(
		String(32), nullable=False, default="decoupled"
	)

	rfm_analytics_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	clv_analytics_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	rfm_analysis_window_months: Mapped[int] = mapped_column(Integer, nullable=False, default=12)
	rfm_monetary_basis: Mapped[str] = mapped_column(String(40), nullable=False, default="net")
	rfm_scoring_method: Mapped[str] = mapped_column(String(32), nullable=False, default="quintiles")
	rfm_weight_recency: Mapped[Decimal | None] = mapped_column(Numeric(18, 8), nullable=True)
	rfm_weight_frequency: Mapped[Decimal | None] = mapped_column(Numeric(18, 8), nullable=True)
	rfm_weight_monetary: Mapped[Decimal | None] = mapped_column(Numeric(18, 8), nullable=True)
	clv_formula: Mapped[str] = mapped_column(String(40), nullable=False, default="historical_total")
	clv_avg_lifespan_years: Mapped[Decimal | None] = mapped_column(Numeric(10, 4), nullable=True)
	rfm_segment_labels_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class CustomerClubBalance(Base):
	"""مانده امتیاز به ازای هر شخص در کسب‌وکار."""

	__tablename__ = "customer_club_balances"
	__table_args__ = (UniqueConstraint("business_id", "person_id", name="uq_customer_club_balance_biz_person"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("businesses.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	person_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("persons.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	balance_points: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))

	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class CustomerClubLedger(Base):
	"""دفتر تراکنش‌های امتیاز (append-only منطقی)."""

	__tablename__ = "customer_club_ledger"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("businesses.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	person_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("persons.id", ondelete="SET NULL"),
		nullable=True,
		index=True,
	)
	delta_points: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
	balance_after: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
	# accrual | reversal | adjustment | sync_delta
	transaction_type: Mapped[str] = mapped_column(String(32), nullable=False)
	reference_document_id: Mapped[int | None] = mapped_column(
		Integer,
		ForeignKey("documents.id", ondelete="SET NULL"),
		nullable=True,
		index=True,
	)
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[int | None] = mapped_column(
		Integer,
		ForeignKey("users.id", ondelete="SET NULL"),
		nullable=True,
		index=True,
	)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class CustomerClubPointLot(Base):
	"""بخش مستقل امتیازهای کسب‌شده برای مصرف FIFO و انقضای واقعی."""

	__tablename__ = "customer_club_point_lots"
	__table_args__ = (
		UniqueConstraint("ledger_id", name="uq_customer_club_point_lot_ledger"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), nullable=False, index=True)
	ledger_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("customer_club_ledger.id", ondelete="SET NULL"), nullable=True)
	original_points: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
	remaining_points: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
	expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class CustomerClubReward(Base):
	"""تعریف جایزه‌های قابل‌خرید با امتیاز یا قابل‌اعطا در کمپین."""

	__tablename__ = "customer_club_rewards"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	name: Mapped[str] = mapped_column(String(160), nullable=False)
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	reward_type: Mapped[str] = mapped_column(String(32), nullable=False, default="discount_amount")
	points_cost: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	value: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))
	product_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("products.id", ondelete="SET NULL"), nullable=True)
	valid_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
	max_issuances: Mapped[int | None] = mapped_column(Integer, nullable=True)
	active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class CustomerClubVoucher(Base):
	"""جایزهٔ صادرشده برای عضو با وضعیت چرخهٔ عمر قابل‌ردیابی."""

	__tablename__ = "customer_club_vouchers"
	__table_args__ = (UniqueConstraint("business_id", "code", name="uq_customer_club_voucher_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), nullable=False, index=True)
	reward_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("customer_club_rewards.id", ondelete="SET NULL"), nullable=True)
	product_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("products.id", ondelete="SET NULL"), nullable=True)
	campaign_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("customer_club_campaigns.id", ondelete="SET NULL"), nullable=True)
	code: Mapped[str] = mapped_column(String(40), nullable=False)
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="issued")
	value: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))
	reward_type: Mapped[str] = mapped_column(String(32), nullable=False)
	expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True)
	redeemed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	redeemed_document_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class CustomerClubCampaign(Base):
	"""کمپین امتیاز/جایزه با شرط‌های محدود و امن و امکان بخش‌بندی اعضا."""

	__tablename__ = "customer_club_campaigns"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	name: Mapped[str] = mapped_column(String(160), nullable=False)
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	trigger_type: Mapped[str] = mapped_column(String(24), nullable=False, default="manual")
	segment_json: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
	reward_type: Mapped[str] = mapped_column(String(32), nullable=False, default="points")
	reward_value: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))
	min_purchase_amount: Mapped[Decimal | None] = mapped_column(Numeric(18, 4), nullable=True)
	reward_valid_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
	message_template: Mapped[str | None] = mapped_column(Text, nullable=True)
	channel: Mapped[str] = mapped_column(String(16), nullable=False, default="none")
	starts_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	ends_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="draft")
	created_by_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class CustomerClubCampaignMember(Base):
	"""ثبت نتیجهٔ هر اجرای کمپین برای جلوگیری از اجرای دوباره و سنجش عملکرد."""

	__tablename__ = "customer_club_campaign_members"
	__table_args__ = (UniqueConstraint("campaign_id", "person_id", name="uq_customer_club_campaign_member"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	campaign_id: Mapped[int] = mapped_column(Integer, ForeignKey("customer_club_campaigns.id", ondelete="CASCADE"), nullable=False, index=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), nullable=False, index=True)
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="rewarded")
	reward_value: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))
	voucher_code: Mapped[str | None] = mapped_column(String(40), nullable=True)
	conversion_document_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True)
	conversion_amount: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))
	converted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	sent_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	send_error: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class CustomerClubMember(Base):
	"""عضویت، کد معرفی و رضایت ارتباطی مشتری در باشگاه."""

	__tablename__ = "customer_club_members"
	__table_args__ = (
		UniqueConstraint("business_id", "person_id", name="uq_customer_club_member_biz_person"),
		UniqueConstraint("business_id", "referral_code", name="uq_customer_club_member_referral"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), nullable=False, index=True)
	joined_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	referral_code: Mapped[str | None] = mapped_column(String(24), nullable=True)
	referrer_person_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("persons.id", ondelete="SET NULL"), nullable=True)
	referral_rewarded_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	sms_consent: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	sms_consent_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	email_consent: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	email_consent_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class CustomerClubSurveyResponse(Base):
	"""یک پاسخ نظرسنجیِ امتیازپذیر، با کلید idempotency برای جلوگیری از تکرار."""

	__tablename__ = "customer_club_survey_responses"
	__table_args__ = (UniqueConstraint("business_id", "person_id", "survey_key", name="uq_customer_club_survey_person"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	person_id: Mapped[int] = mapped_column(Integer, ForeignKey("persons.id", ondelete="CASCADE"), nullable=False, index=True)
	survey_key: Mapped[str] = mapped_column(String(80), nullable=False)
	score: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
	comment: Mapped[str | None] = mapped_column(Text, nullable=True)
	points_awarded: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class CustomerClubInvoiceSnapshot(Base):
	"""آخرین امتیاز ثبت‌شده برای یک سند فاکتور جهت همگام‌سازی و حذف."""

	__tablename__ = "customer_club_invoice_snapshots"

	document_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("documents.id", ondelete="CASCADE"),
		primary_key=True,
	)
	business_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("businesses.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	person_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("persons.id", ondelete="SET NULL"),
		nullable=True,
		index=True,
	)
	accrued_points: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	redeemed_points: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	voucher_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("customer_club_vouchers.id", ondelete="SET NULL"), nullable=True)

	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class CustomerClubTier(Base):
	"""سطح وفاداری (ضریب امتیاز)."""

	__tablename__ = "customer_club_tiers"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("businesses.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	name: Mapped[str] = mapped_column(String(120), nullable=False)
	min_balance_points: Mapped[Decimal] = mapped_column(
		Numeric(18, 6), nullable=False, default=Decimal("0")
	)
	min_rfm_normalized: Mapped[Decimal | None] = mapped_column(Numeric(10, 6), nullable=True)
	benefits_json: Mapped[list | None] = mapped_column(JSON, nullable=True)
	earn_multiplier: Mapped[Decimal] = mapped_column(
		Numeric(18, 6), nullable=False, default=Decimal("1")
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class CustomerClubRfmSnapshot(Base):
	"""ذخیرهٔ نتیجهٔ تحلیل RFM/CLV برای هر شخص در یک کسب‌وکار."""

	__tablename__ = "customer_club_rfm_snapshots"
	__table_args__ = (UniqueConstraint("business_id", "person_id", name="uq_cc_rfm_snap_biz_person"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("businesses.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	person_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("persons.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	recency_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
	frequency_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	monetary_total: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))
	r_score: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
	f_score: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
	m_score: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
	rfm_cell: Mapped[str | None] = mapped_column(String(16), nullable=True)
	segment_label: Mapped[str | None] = mapped_column(String(160), nullable=True)
	composite_score: Mapped[Decimal | None] = mapped_column(Numeric(18, 8), nullable=True)
	clv_estimate: Mapped[Decimal | None] = mapped_column(Numeric(18, 4), nullable=True)
	computed_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
