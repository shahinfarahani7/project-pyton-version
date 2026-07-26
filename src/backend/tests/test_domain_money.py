import pytest
from edgemint.domain.money import Money

def test_money_uses_integer_micro_eur() -> None:
    assert (Money(100) + Money(250)).amount_micros == 350

def test_money_rejects_floating_point() -> None:
    with pytest.raises(TypeError):
        Money(1.2)  # type: ignore[arg-type]
