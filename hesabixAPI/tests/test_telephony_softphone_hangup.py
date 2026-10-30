"""تست Hangup سافت‌فون و تطبیق رویداد AMI با تماس موجود."""
from __future__ import annotations

from types import SimpleNamespace

from app.services.telephony.ami_channels import (
	expand_hangup_channels,
	local_channel_mate,
	match_softphone_relay_call,
	numbers_look_same,
)


def test_local_channel_mate_swaps_legs():
	assert local_channel_mate("Local/0912@from-internal-00000001;1") == "Local/0912@from-internal-00000001;2"
	assert local_channel_mate("Local/0912@from-internal-00000001;2") == "Local/0912@from-internal-00000001;1"
	assert local_channel_mate("PJSIP/trunk-00000001") is None
	assert local_channel_mate("") is None


def test_expand_hangup_channels_includes_local_pair_and_dest():
	out = expand_hangup_channels(
		["PJSIP/voip-00000001", "Local/09121234567@from-internal-00000001;1"],
		["PJSIP/voip-00000001"],
	)
	assert "PJSIP/voip-00000001" in out
	assert "Local/09121234567@from-internal-00000001;1" in out
	assert "Local/09121234567@from-internal-00000001;2" in out
	assert out.count("PJSIP/voip-00000001") == 1


def test_numbers_look_same():
	assert numbers_look_same("09121234567", "+989121234567")
	assert numbers_look_same("09121234567", "9121234567")
	assert not numbers_look_same("09121234567", "09330000000")
	assert not numbers_look_same("", "0912")


def test_match_softphone_relay_call_by_destination():
	call = SimpleNamespace(
		to_number_normalized="09121234567",
		to_number_raw="09121234567",
		extra_info={"softphone": True, "session_id": "abc"},
	)
	other = SimpleNamespace(
		to_number_normalized="09330000000",
		to_number_raw="09330000000",
		extra_info={"softphone": True},
	)
	desk = SimpleNamespace(
		to_number_normalized="09121234567",
		to_number_raw="09121234567",
		extra_info={},
	)
	matched = match_softphone_relay_call(
		[desk, other, call],
		{"to": "9121234567", "channel": "Local/09121234567@from-internal-00000001;2"},
	)
	assert matched is call


def test_match_softphone_relay_skips_already_bound():
	call = SimpleNamespace(
		to_number_normalized="09121234567",
		to_number_raw="09121234567",
		extra_info={"softphone": True, "asterisk_uniqueid_bound": True},
	)
	assert match_softphone_relay_call([call], {"to": "09121234567"}) is None
