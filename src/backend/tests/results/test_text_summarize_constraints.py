from __future__ import annotations

import pytest

from edgemint.results.text_summarize_constraints import count_summary_words


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("", 0),
        ("   ", 0),
        ("one two three", 3),
        ("  spaced   words  ", 2),
        ("Customer reported late deliveries and inaccurate tracking.", 7),
    ],
)
def test_count_summary_words_shared_convention(text: str, expected: int) -> None:
    assert count_summary_words(text) == expected
