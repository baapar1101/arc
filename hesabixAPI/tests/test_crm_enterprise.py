"""قواعد سازمان فروش بدون پایگاه داده."""
from app.services.crm_enterprise import (
    descendant_ids,
    effective_forecast,
    manager_link_creates_cycle,
    person_belongs_to_organization,
    quota_progress,
    record_access,
)


def test_forecast_uses_outcome_before_override():
    assert effective_forecast(closed=True, is_win=True, is_lost=False, probability=10, override="pipeline") == "closed"
    assert effective_forecast(closed=False, is_win=False, is_lost=False, probability=80, override=None) == "commit"
    assert effective_forecast(closed=False, is_win=False, is_lost=False, probability=10, override="best_case") == "best_case"


def test_quota_does_not_invent_percent_without_a_target():
    assert quota_progress(0, 100)["percent"] is None
    assert quota_progress(200, 50)["percent"] == 25
    assert quota_progress(200, 50)["remaining"] == 150


def test_organization_requires_the_billing_person_or_a_contact():
    assert person_belongs_to_organization(5, {6}, 5) is True
    assert person_belongs_to_organization(5, {6}, 6) is True
    assert person_belongs_to_organization(5, {6}, 7) is False


def test_manager_cycle_and_descendants():
    links = [(1, 2), (2, 3)]
    assert manager_link_creates_cycle(links, 3, 1) is True
    assert manager_link_creates_cycle(links, 1, 4) is False
    assert manager_link_creates_cycle(links, 4, 4) is True
    assert set(descendant_ids(links, 1)) == {2, 3}


def test_record_acl_stays_open_until_enforced():
    hidden = record_access(
        enforced=True, is_owner=False, user_id=9, assigned_to=2, created_by=3,
        acl_access=None, manages_assignee=False, queue_member=False,
    )
    open_business = record_access(
        enforced=False, is_owner=False, user_id=9, assigned_to=2, created_by=3,
        acl_access=None, manages_assignee=False, queue_member=False,
    )
    assert hidden == "none"
    assert open_business == "edit"
