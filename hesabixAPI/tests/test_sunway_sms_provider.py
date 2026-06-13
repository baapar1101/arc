from unittest.mock import MagicMock, patch

import pytest

from app.services.providers.sms_provider import SmsProvider
from app.services.providers.sunway_sms_provider import SunwaySmsProvider


class TestSunwaySmsProvider:
	def test_init_strips_sender_country_prefix(self) -> None:
		provider = SunwaySmsProvider(username="user", password="pass", sender="983000123456")
		assert provider.sender == "3000123456"

	def test_parse_response_success_message_id(self) -> None:
		provider = SunwaySmsProvider(username="u", password="p", sender="3000")
		ok, result, err = provider._parse_response("1234567")
		assert ok is True
		assert result == "1234567"
		assert err is None

	def test_parse_response_error_code(self) -> None:
		provider = SunwaySmsProvider(username="u", password="p", sender="3000")
		ok, result, err = provider._parse_response("51")
		assert ok is False
		assert result == "51"
		assert err == "نام کاربری یا رمز عبور اشتباه است"

	@patch("app.services.providers.sunway_sms_provider.httpx.Client")
	def test_send_text_uses_pascal_case_params(self, mock_client_cls: MagicMock) -> None:
		mock_response = MagicMock()
		mock_response.text = "1234567"
		mock_response.status_code = 200
		mock_response.request.url = "https://sms.sunwaysms.com/smsws/HttpService.ashx"

		mock_client = MagicMock()
		mock_client.__enter__.return_value = mock_client
		mock_client.get.return_value = mock_response
		mock_client_cls.return_value = mock_client

		provider = SunwaySmsProvider(username="myuser", password="mypass", sender="30001234")
		ok, message_id, err = provider.send_text(to_phone="09121234567", text="سلام")

		assert ok is True
		assert message_id == "1234567"
		assert err is None

		call_kwargs = mock_client.get.call_args
		params = call_kwargs.kwargs["params"]
		assert params["service"] == "SendArray"
		assert params["UserName"] == "myuser"
		assert params["Password"] == "mypass"
		assert params["To"] == "09121234567"
		assert params["Message"] == "سلام"
		assert params["From"] == "30001234"
		assert params["Flash"] == "false"


class TestSmsProviderRouting:
	def test_sunwaysms_is_configured_with_credentials(self) -> None:
		provider = SmsProvider(
			provider_name="sunwaysms",
			username="user",
			password="pass",
			sender="30001234",
		)
		assert provider.is_configured() is True
		assert isinstance(provider._provider, SunwaySmsProvider)

	def test_sunway_sms_alias_is_configured(self) -> None:
		provider = SmsProvider(
			provider_name="sunway_sms",
			username="user",
			password="pass",
			sender="30001234",
		)
		assert provider.is_configured() is True
		assert isinstance(provider._provider, SunwaySmsProvider)

	def test_sunwaysms_missing_credentials_not_configured(self) -> None:
		provider = SmsProvider(provider_name="sunwaysms", sender="30001234")
		assert provider.is_configured() is False
		assert provider._provider is None
