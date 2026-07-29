"""Tests for egress policy and backup file access checks."""

from __future__ import annotations

import pytest

from app.core.egress_policy import assert_public_egress_host
from app.core.responses import ApiError


def test_blocks_loopback_ip():
	with pytest.raises(ApiError) as exc:
		assert_public_egress_host("127.0.0.1")
	assert exc.value.status_code == 400


def test_blocks_private_ip():
	with pytest.raises(ApiError) as exc:
		assert_public_egress_host("10.0.0.5")
	assert exc.value.status_code == 400


def test_allows_public_ip():
	assert_public_egress_host("8.8.8.8")
