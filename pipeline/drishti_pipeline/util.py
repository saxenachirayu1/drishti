"""N-14: retries for flaky network calls."""

from __future__ import annotations

import logging
import time
from collections.abc import Callable
from typing import TypeVar

T = TypeVar("T")
log = logging.getLogger("drishti")


def retry(fn: Callable[[], T], attempts: int = 3, backoff_s: float = 2.0,
          sleep: Callable[[float], None] | None = None) -> T:
    """Call fn up to `attempts` times, waiting 2 s, 4 s, ... between tries. Re-raises the last error."""
    last: Exception | None = None
    for i in range(attempts):
        try:
            return fn()
        except Exception as exc:  # noqa: BLE001 - we re-raise below
            last = exc
            if i < attempts - 1:
                log.warning("attempt %d/%d failed: %s", i + 1, attempts, exc)
                (sleep or time.sleep)(backoff_s * (2 ** i))
    assert last is not None
    raise last
