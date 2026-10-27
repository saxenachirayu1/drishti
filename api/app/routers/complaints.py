import os
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Request
from fastapi.responses import FileResponse

from ..auth import require
from ..emailer import send_email
from ..errors import api_error
from ..granite import SUPPORTED_LANGUAGES, draft_complaint
from ..models import ComplaintEdit, ComplaintRequest
from ..pdf import OUT_DIR, make_complaint_pdf
from ..repo import get_repo
from ..serialize import site_facts

router = APIRouter()


@router.post("/complaints")
def create_complaint(req: ComplaintRequest, user=Depends(require("officer", "admin"))):
    """C-07/08: Granite drafts a complaint that cites the site's real numbers."""
    repo = get_repo()
    site = repo.get_site(req.site_id)
    if not site:
        raise api_error(404, "not_found", "No such site")
    if req.language not in SUPPORTED_LANGUAGES:
        raise api_error(400, "bad_language",
                        f"language must be one of {list(SUPPORTED_LANGUAGES)}")
    facts = site_facts(site)
    text = draft_complaint(facts, req.language)
    cid = uuid.uuid4().hex[:8]
    c = {"id": cid, "site_id": site["id"], "ward_id": site.get("ward_id"),
         "draft_text": text, "language": req.language, "status": "draft",
         "pdf_url": None}
    repo.create_complaint(c)
    repo.audit_add(user.user_id, "draft", "complaint", cid)
    return c


@router.patch("/complaints/{cid}")
def edit_complaint(cid: str, body: ComplaintEdit, user=Depends(require("officer", "admin"))):
    repo = get_repo()
    if not repo.get_complaint(cid):
        raise api_error(404, "not_found", "No such complaint")
    return repo.update_complaint(cid, draft_text=body.draft_text)


@router.post("/complaints/{cid}/approve")
def approve_complaint(cid: str, request: Request,
                      user=Depends(require("officer", "admin"))):
    """C-09/10: lock the text and generate the PDF."""
    repo = get_repo()
    c = repo.get_complaint(cid)
    if not c:
        raise api_error(404, "not_found", "No such complaint")
    make_complaint_pdf(cid, c["draft_text"], c.get("language", "English"))
    # Store a URL the dashboard can open, not the server-side file path: the
    # app only offers its "open PDF" button for a pdf_url starting with http.
    pdf_url = str(request.url_for("complaint_pdf", cid=cid))
    repo.audit_add(user.user_id, "approve", "complaint", cid)
    return repo.update_complaint(cid, status="approved", pdf_url=pdf_url,
                                 approved_by=user.user_id)


@router.get("/complaints/{cid}/pdf", name="complaint_pdf")
def complaint_pdf(cid: str, user=Depends(require("officer", "admin"))):
    """Serve the approved complaint PDF so the dashboard can open it."""
    if not get_repo().get_complaint(cid):
        raise api_error(404, "not_found", "No such complaint")
    path = os.path.join(OUT_DIR, f"complaint_{cid}.pdf")
    if not os.path.exists(path):
        raise api_error(404, "no_pdf", "Approve the complaint first")
    return FileResponse(path, media_type="application/pdf",
                        filename=f"drishti-complaint-{cid}.pdf")


@router.post("/complaints/{cid}/send")
def send_complaint(cid: str, user=Depends(require("officer", "admin"))):
    """C-09/11: only an approved complaint can be sent; then email the officer."""
    repo = get_repo()
    c = repo.get_complaint(cid)
    if not c:
        raise api_error(404, "not_found", "No such complaint")
    if c["status"] != "approved":
        raise api_error(409, "not_approved", "Approve the complaint before sending")
    site = repo.get_site(c["site_id"])
    ward = next((w for w in repo.list_wards() if w["id"] == site.get("ward_id")), None)
    to = ward["officer_email"] if ward else "officer@example.com"
    send_email(to, "Suspected illegal dumpsite - action requested", c["draft_text"])
    repo.update_site(site["id"], status="complaint_sent")
    repo.audit_add(user.user_id, "send", "complaint", cid, {"to": to})
    return repo.update_complaint(cid, status="sent",
                                 sent_at=datetime.now(timezone.utc).isoformat())


@router.get("/complaints")
def list_complaints(ward_id: str = None, status: str = None,
                    user=Depends(require("officer", "admin"))):
    return get_repo().list_complaints(ward_id=ward_id, status=status)
