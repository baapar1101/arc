def test_digipay_catalog_keys_are_translated() -> None:
	from app.core.i18n import Translator

	fa = Translator("fa")
	en = Translator("en")
	assert fa.t("DIGIPAY_PLUGIN_NOT_ACTIVE") == "افزونه پرداخت اعتباری دیجی‌پی برای این کسب‌وکار فعال نیست."
	assert en.t("DIGIPAY_PLUGIN_NOT_ACTIVE") == "The DigiPay credit payment plugin is not active for this business."
	assert fa.t("DIGIPAY_SETTLEMENT_UNBALANCED") == "مبالغ تسویه با هم تراز نیستند."
	assert fa.t("DIGIPAY_SETTLEMENT_NEGATIVE") == "مبلغ خالص تسویه منفی است."
	assert en.t("DIGIPAY_SETTLEMENT_NEGATIVE") == "Settlement net amount is negative."
	assert en.t("DIGIPAY_TICKET_FAILED") == "Could not create a DigiPay ticket."
	assert fa.t("DIGIPAY_SETTLEMENT_DOC") == "تسویه دیجی‌پی"


def test_digipay_plugin_is_in_marketplace_seed() -> None:
	from adapters.db.seed_data.marketplace_plugins_seed import _DEFAULT_PLUGINS

	codes = {p.code for p in _DEFAULT_PLUGINS}
	assert "digipay_credit" in codes
