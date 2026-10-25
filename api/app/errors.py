"""One error shape everywhere (C-03): {"error": {"code": ..., "message": ...}}."""
from fastapi import HTTPException


def api_error(status: int, code: str, message: str) -> HTTPException:
    return HTTPException(status_code=status, detail={"error": {"code": code, "message": message}})
