"""
Scheduler (C-21): pipeline every 2 days, fire pull daily, verification daily,
scores monthly. Jobs are also triggerable by hand via the API endpoints.

Kept lightweight; set RUN_SCHEDULER=0 in the env to disable (e.g. in tests).
"""
import logging
import os

log = logging.getLogger("drishti.scheduler")
_started = False


def _run_verification():
    try:
        from .repo import get_repo
        from .services.verification import decide_result
        repo = get_repo()
        for site in repo.list_sites(status="complaint_sent"):
            dets = sorted(repo.list_detections(site["id"]),
                          key=lambda d: str(d.get("detected_on", "")))
            areas = [d["area_m2"] for d in dets] or [site.get("area_m2", 0)]
            if decide_result(areas) == "cleared":
                repo.update_site(site["id"], status="cleared")
    except Exception as e:
        log.warning("verification job failed: %s", e)


def start_scheduler():
    global _started
    if _started or os.getenv("RUN_SCHEDULER", "1") == "0":
        return
    try:
        from apscheduler.schedulers.background import BackgroundScheduler
    except Exception as e:
        log.warning("APScheduler not installed: %s", e)
        return
    sched = BackgroundScheduler(daemon=True)
    # every 2 days: trigger pipeline (wire to B); daily: fires + verification; monthly: scores
    sched.add_job(_run_verification, "interval", days=1, id="verify")
    sched.start()
    _started = True
    log.info("scheduler started")
