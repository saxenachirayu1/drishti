"""Email sending (C-11) via Resend, with a console fallback for the demo."""
from .config import settings


def send_email(to: str, subject: str, body: str) -> dict:
    if not settings.RESEND_API_KEY:
        print(f"[EMAIL -> {to}] {subject}\n{body}\n")
        return {"sent": True, "mode": "console"}
    try:
        import resend
        resend.api_key = settings.RESEND_API_KEY
        resend.Emails.send({
            "from": settings.EMAIL_FROM, "to": [to],
            "subject": subject, "text": body,
        })
        return {"sent": True, "mode": "resend"}
    except Exception as e:
        print("[email] Resend failed, logged instead:", e)
        print(f"[EMAIL -> {to}] {subject}\n{body}\n")
        return {"sent": True, "mode": "console-fallback"}
