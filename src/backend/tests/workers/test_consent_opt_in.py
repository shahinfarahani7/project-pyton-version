from __future__ import annotations

import pytest

from edgemint.workers.consent_opt_in import assert_performance_opt_in_confirmed
from edgemint.workers.errors import WorkerServiceError
from edgemint.workers.resource_policy import validate_contribution_mode_id


def test_performance_mode_requires_explicit_opt_in_flag() -> None:
    performance = validate_contribution_mode_id("performance")
    with pytest.raises(WorkerServiceError) as exc:
        assert_performance_opt_in_confirmed(performance, performance_opt_in_confirmed=False)
    assert exc.value.code == "CONSENT_OPT_IN_REQUIRED"


def test_performance_mode_allowed_with_opt_in_flag() -> None:
    performance = validate_contribution_mode_id("performance")
    assert_performance_opt_in_confirmed(performance, performance_opt_in_confirmed=True)


def test_balanced_mode_never_requires_opt_in_flag() -> None:
    balanced = validate_contribution_mode_id("balanced")
    assert_performance_opt_in_confirmed(balanced, performance_opt_in_confirmed=False)
