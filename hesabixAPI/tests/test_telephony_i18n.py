def test_telephony_catalog_keys_are_translated() -> None:
	from app.core.i18n import Translator

	fa = Translator("fa")
	en = Translator("en")
	assert fa.t("CALL_NOT_FOUND") == "تماس یافت نشد"
	assert en.t("CALL_NOT_FOUND") == "Call was not found"
	assert fa.t("PBX_NOT_FOUND") == "مرکز تلفن یافت نشد"
	assert en.t("SOFTPHONE_NO_EXTENSION") == "Softphone requires an extension mapped to the user"
	assert fa.t("TELEPHONY_PLUGIN_NOT_ACTIVE") == "افزونه اتصال استریسک/ایزابل برای این کسب‌وکار فعال نیست"
	assert en.t("TELEPHONY_PERMISSION_DENIED") == "You do not have the required telephony permission"


def test_document_catalog_keys_are_translated() -> None:
	from app.core.i18n import Translator

	fa = Translator("fa")
	en = Translator("en")
	assert fa.t("DOCUMENT_NOT_FOUND") == "سند یافت نشد"
	assert en.t("DOCUMENT_NOT_FOUND") == "Document not found"
	assert fa.t("CANNOT_DELETE_AUTO_DOCUMENT") == "اسناد اتوماتیک قابل حذف نیستند. از منبع اصلی حذف کنید."
	assert en.t("PROJECT_NOT_FOUND") == "Project was not found or is inactive"
	assert fa.t("FIXED_ASSET_DOCUMENT_DELETE_SOURCE_ONLY") == "اسناد دارایی ثابت فقط از بخش کنترل اموال قابل حذف هستند"
