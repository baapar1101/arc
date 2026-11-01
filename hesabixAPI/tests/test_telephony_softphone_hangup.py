"""تست Hangup سافت‌فون و تطبیق رویداد AMI با تماس موجود."""
from __future__ import annotations

from types import SimpleNamespace

from app.services.telephony.ami_channels import (
	append_ami_uniqueid,
	expand_hangup_channels,
	is_local_secondary_leg,
	local_channel_mate,
	match_call_by_ami_ids,
	match_softphone_relay_call,
	numbers_look_same,
	should_create_call_from_ami_event,
	should_ignore_softphone_outbound_hangup,
	should_skip_unmatched_ami_event,
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
		from_number_normalized="500",
		from_number_raw="500",
		extension="500",
		extra_info={"softphone": True, "session_id": "abc"},
	)
	other = SimpleNamespace(
		to_number_normalized="09330000000",
		to_number_raw="09330000000",
		from_number_normalized="500",
		from_number_raw="500",
		extension="500",
		extra_info={"softphone": True},
	)
	desk = SimpleNamespace(
		to_number_normalized="09121234567",
		to_number_raw="09121234567",
		from_number_normalized="500",
		from_number_raw="500",
		extension="500",
		extra_info={},
	)
	matched = match_softphone_relay_call(
		[desk, other, call],
		{"to": "9121234567", "channel": "Local/09121234567@from-internal-00000001;2"},
	)
	assert matched is call


def test_match_softphone_relay_still_matches_already_bound():
	call = SimpleNamespace(
		to_number_normalized="09121234567",
		to_number_raw="09121234567",
		from_number_normalized="500",
		from_number_raw="500",
		extension="500",
		extra_info={"softphone": True, "asterisk_uniqueid_bound": True},
	)
	assert match_softphone_relay_call([call], {"to": "09121234567"}) is call


def test_match_softphone_relay_swapped_ami_parties():
	"""DialBegin سمت ترانک from=موبایل to=داخلی است."""
	call = SimpleNamespace(
		to_number_normalized="09183282405",
		to_number_raw="09183282405",
		from_number_normalized="500",
		from_number_raw="500",
		extension="500",
		extra_info={"softphone": True, "asterisk_uniqueid_bound": True},
	)
	matched = match_softphone_relay_call(
		[call],
		{"from": "09183282405", "to": "500", "channel": "PJSIP/voip-00000023"},
	)
	assert matched is call


def test_ami_event_create_and_skip_rules():
	assert should_create_call_from_ami_event("call.ringing")
	assert should_create_call_from_ami_event("ringing")
	assert not should_create_call_from_ami_event("hangup")
	assert should_skip_unmatched_ami_event("hangup")
	assert should_skip_unmatched_ami_event("call.ended")
	assert should_skip_unmatched_ami_event("answered")
	assert not should_skip_unmatched_ami_event("ringing")


def test_ignore_local_secondary_hangup_on_live_softphone_outbound():
	call = SimpleNamespace(
		direction="outbound",
		status="ringing",
		ended_at=None,
		extra_info={"softphone": True},
	)
	assert is_local_secondary_leg("Local/09183282405@from-internal-00000001;2")
	assert not is_local_secondary_leg("Local/09183282405@from-internal-00000001;1")
	assert should_ignore_softphone_outbound_hangup(
		call,
		{"channel": "Local/09183282405@from-internal-00000001;2"},
		"hangup",
	)
	assert not should_ignore_softphone_outbound_hangup(
		call,
		{"channel": "PJSIP/voip-00000023"},
		"hangup",
	)


def test_append_and_match_ami_uniqueids():
	extra = append_ami_uniqueid({"softphone": True}, "ami-1")
	extra = append_ami_uniqueid(extra, "ami-2")
	extra = append_ami_uniqueid(extra, "ami-1")
	assert extra["ami_uniqueids"] == ["ami-1", "ami-2"]
	call = SimpleNamespace(
		asterisk_uniqueid="hsx-sf-abc",
		asterisk_linkedid="hsx-sf-abc",
		extra_info=extra,
	)
	assert match_call_by_ami_ids([call], "ami-2") is call
	assert match_call_by_ami_ids([call], "missing") is None
