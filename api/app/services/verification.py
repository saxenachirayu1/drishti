"""
Verification logic (C-12): decide a site's cleanup state from its detections.

Pure function so it is easy to test. Rules:
  - newest detection area smaller than earlier  -> "shrinking"
  - still detected at similar/larger area       -> "still_present"
  - no detection in the last `clear_scenes` scenes -> "cleared"
Both thresholds are configurable (VERIFY_CLEAR_SCENES, VERIFY_SHRINK_RATIO)
because the right values depend on B's revisit rate and detector noise, which
we will only know once real scenes arrive.
"""
from typing import Optional

from ..config import settings


def decide_result(detection_areas: list, clear_scenes: Optional[int] = None,
                  shrink_ratio: Optional[float] = None) -> str:
    """
    detection_areas: areas (m2) for the last few scenes, oldest first.
                     Use 0 for a scene where the site was not detected.

    clear_scenes / shrink_ratio default to the configured values; pass them to
    try other thresholds against B's real detection history.
    """
    clear_scenes = settings.VERIFY_CLEAR_SCENES if clear_scenes is None else clear_scenes
    shrink_ratio = settings.VERIFY_SHRINK_RATIO if shrink_ratio is None else shrink_ratio

    if not detection_areas:
        return "still_present"
    recent = detection_areas[-clear_scenes:]
    if len(recent) >= clear_scenes and all(a == 0 for a in recent):
        return "cleared"
    present = [a for a in detection_areas if a > 0]
    if len(present) >= 2 and present[-1] < present[0] * shrink_ratio:
        return "shrinking"
    return "still_present"
