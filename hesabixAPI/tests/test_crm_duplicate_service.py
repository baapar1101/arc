"""کلید هویت تلفن و تصمیم ادامه با وجود شباهت."""
from app.services.crm_duplicate_service import duplicate_should_block, phone_match_key


def test_phone_key_folds_local_international_and_persian_digits():
    assert phone_match_key("09121234567") == "9121234567"
    assert phone_match_key("+98 912 123 4567") == "9121234567"
    assert phone_match_key("۰۰۹۸۹۱۲۱۲۳۴۵۶۷") == "9121234567"
    assert phone_match_key("9121234567") == "9121234567"


def test_short_or_empty_phone_is_not_an_identity():
    assert phone_match_key(None) is None
    assert phone_match_key("   ") is None
    assert phone_match_key("12345") is None


def test_similar_match_blocks_until_explicitly_allowed():
    matches = {"leads": [{"id": 1}], "persons": []}
    assert duplicate_should_block(matches, False) is True
    assert duplicate_should_block(matches, True) is False
    assert duplicate_should_block({"leads": [], "persons": []}, False) is False
