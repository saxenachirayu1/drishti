from fastapi import APIRouter, Depends

from ..auth import current_user
from ..errors import api_error
from ..services import legal

router = APIRouter()


@router.get("/legal/search")
def legal_search(q: str, limit: int = 3, user=Depends(current_user)):
    """C-18: look up the provisions a complaint can cite."""
    if not q.strip():
        raise api_error(400, "bad_query", "q must not be empty")
    return {"query": q, "results": legal.search(q, limit=limit)}


@router.get("/legal/provisions")
def legal_provisions(user=Depends(current_user)):
    """The whole corpus, so A can show it in the UI."""
    return legal.CORPUS
