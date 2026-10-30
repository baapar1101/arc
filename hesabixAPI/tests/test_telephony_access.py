"""تست محدوده دسترسی اپراتور / سرپرست / مدیر تلفن."""
from datetime import datetime

from app.services.telephony.reports_service import _tehran_hour
from app.services.telephony.telephony_access import TelephonyScope


class _Call:
	def __init__(self, assigned_user_id=None, extension=None, queue_code=None):
		self.assigned_user_id = assigned_user_id
		self.extension = extension
		self.queue_code = queue_code


def _agent(**kwargs):
	return TelephonyScope(
		user_id=kwargs.get("user_id", 10),
		view_all=False,
		can_manage=False,
		can_supervise=False,
		extensions=frozenset(kwargs.get("extensions", {"101"})),
		team_codes=frozenset(),
		extension_ids=frozenset({1}),
	)


def _supervisor():
	return TelephonyScope(
		user_id=11,
		view_all=False,
		can_manage=False,
		can_supervise=True,
		extensions=frozenset({"201", "202"}),
		team_codes=frozenset({"sales"}),
		extension_ids=frozenset({2, 3}),
	)


def _manager():
	return TelephonyScope(
		user_id=1,
		view_all=True,
		can_manage=True,
		can_supervise=True,
		extensions=frozenset(),
		team_codes=frozenset(),
		extension_ids=frozenset(),
	)


def test_agent_sees_own_assigned_call():
	scope = _agent()
	assert scope.allows_call(_Call(assigned_user_id=10, extension="999")) is True


def test_agent_sees_own_extension_call():
	scope = _agent()
	assert scope.allows_call(_Call(assigned_user_id=99, extension="101")) is True


def test_agent_cannot_see_peer_call():
	scope = _agent()
	assert scope.allows_call(_Call(assigned_user_id=99, extension="102", queue_code="sales")) is False


def test_supervisor_sees_team_queue_and_team_extensions():
	scope = _supervisor()
	assert scope.allows_call(_Call(assigned_user_id=99, extension="999", queue_code="sales")) is True
	assert scope.allows_call(_Call(assigned_user_id=99, extension="201")) is True
	assert scope.allows_call(_Call(assigned_user_id=99, extension="302", queue_code="support")) is False


def test_manager_sees_every_call():
	scope = _manager()
	assert scope.allows_call(_Call(assigned_user_id=99, extension="x", queue_code="y")) is True


def test_operator_only_flag():
	assert _agent().is_operator_only is True
	assert _supervisor().is_operator_only is False
	assert _manager().is_operator_only is False


def test_tehran_hourly_histogram_offset():
	# 20:30 UTC + 03:30 = 00:00 تهران
	assert _tehran_hour(datetime(2026, 1, 1, 20, 30)) == 0
	# 08:00 UTC + 03:30 = 11:30 تهران
	assert _tehran_hour(datetime(2026, 1, 1, 8, 0)) == 11


def test_call_to_dict_does_not_leak_recording_url():
	from types import SimpleNamespace
	from app.services.telephony.telephony_service import call_to_dict

	row = SimpleNamespace(
		id=1,
		business_id=1,
		pbx_id=1,
		asterisk_uniqueid="u1",
		asterisk_linkedid=None,
		direction="inbound",
		status="completed",
		from_number_raw="0912",
		from_number_normalized="0912",
		to_number_raw="101",
		to_number_normalized="101",
		extension="101",
		queue_code=None,
		transferred_from=None,
		transferred_to=None,
		started_at=datetime(2026, 1, 1, 12, 0),
		answered_at=None,
		ended_at=None,
		duration_sec=10,
		talk_sec=8,
		hangup_cause=None,
		recording_status="available",
		recording_url="https://secret.example/rec.wav",
		person_id=None,
		lead_id=None,
		deal_id=None,
		document_id=None,
		crm_activity_id=None,
		assigned_user_id=10,
		category=None,
		outcome=None,
		note=None,
		match_method=None,
		is_anonymous=False,
		extra_info={"recording_url": "https://secret.example/rec.wav", "channel": "SIP/101"},
		created_at=datetime(2026, 1, 1, 12, 0),
		updated_at=datetime(2026, 1, 1, 12, 0),
	)
	data = call_to_dict(row)
	assert data["recording_url"] is None
	assert data["recording_available"] is True
	assert "recording_url" not in data["extra_info"]
	assert data["extra_info"]["channel"] == "SIP/101"


def _settings_db(mode: str):
	class Settings:
		recording_access_mode = mode

	class FakeQuery:
		def __init__(self, row):
			self._row = row

		def filter(self, *a, **k):
			return self

		def first(self):
			return self._row

		def all(self):
			return []

	class FakeDb:
		def query(self, model):
			return FakeQuery(Settings())

	return FakeDb()


class _Ctx:
	def get_user_id(self):
		return 10

	def is_superadmin(self):
		return False

	def is_business_owner(self, bid):
		return False


def test_can_listen_owner_and_managers_mode():
	from app.services.telephony.telephony_access import can_listen_recording

	scope = _agent(user_id=10)
	own = _Call(assigned_user_id=10, extension="101")
	peer = _Call(assigned_user_id=99, extension="102")
	db = _settings_db("owner_and_managers")
	assert can_listen_recording(_Ctx(), db, 1, own, scope=scope) is True
	assert can_listen_recording(_Ctx(), db, 1, peer, scope=scope) is False
	assert can_listen_recording(_Ctx(), db, 1, peer, scope=_manager()) is True
	team_call = _Call(assigned_user_id=99, extension="201", queue_code="sales")
	assert can_listen_recording(_Ctx(), db, 1, team_call, scope=_supervisor()) is True
	assert can_listen_recording(_Ctx(), db, 1, peer, scope=_supervisor()) is False


def test_can_listen_all_operators_stays_in_scope():
	from app.services.telephony.telephony_access import can_listen_recording

	db = _settings_db("all_operators")
	scope = _agent(user_id=10)
	assert can_listen_recording(_Ctx(), db, 1, _Call(assigned_user_id=10, extension="101"), scope=scope) is True
	assert can_listen_recording(_Ctx(), db, 1, _Call(assigned_user_id=99, extension="102"), scope=scope) is False


def test_can_listen_permission_based_requires_flag(monkeypatch):
	from app.services.telephony import telephony_access as access

	monkeypatch.setattr(access, "has_telephony_perm", lambda *a, **k: False)
	db = _settings_db("permission_based")
	scope = _agent(user_id=10)
	own = _Call(assigned_user_id=10, extension="101")
	assert access.can_listen_recording(_Ctx(), db, 1, own, scope=scope) is False
	monkeypatch.setattr(access, "has_telephony_perm", lambda *a, **k: True)
	assert access.can_listen_recording(_Ctx(), db, 1, own, scope=scope) is True


def test_apply_call_filter_operator_sql_mentions_own_extension():
	class Q:
		def __init__(self):
			self.clause = None

		def filter(self, *a, **k):
			self.clause = a[0] if a else None
			return self

	q = Q()
	_agent().apply_call_filter(q)
	sql = str(q.clause.compile(compile_kwargs={"literal_binds": True}))
	assert "101" in sql
	assert "assigned_user_id" in sql.lower() or "assigned_user_id" in str(q.clause)


def test_apply_call_filter_manager_is_noop():
	class Q:
		def filter(self, *a, **k):
			raise AssertionError("view_all must not add a filter")

	assert _manager().apply_call_filter(Q()) is not None


def test_exclusive_extension_taken_skips_when_shared():
	from app.services.telephony.telephony_access import exclusive_extension_taken

	class FakeDb:
		def query(self, model):
			raise AssertionError("shared mapping must not query existing owners")

	assert list(exclusive_extension_taken(FakeDb(), business_id=1, extension_id=1, user_id=2, allow_shared=True)) == []


def test_supervisor_queue_and_extension_helpers():
	scope = _supervisor()
	assert scope.allows_queue("sales") is True
	assert scope.allows_queue("support") is False
	assert scope.allows_extension("201") is True
	assert scope.allows_extension("101") is False
	assert _manager().allows_queue("anything") is True
	assert _agent().allows_queue("sales") is False
