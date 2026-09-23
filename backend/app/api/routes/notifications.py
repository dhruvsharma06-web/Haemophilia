import logging
from typing import Any, Dict, Optional

from fastapi import APIRouter
from pydantic import BaseModel

logger = logging.getLogger("notifications")

router = APIRouter(
    prefix="/v1/notifications",
    tags=["Notifications"],
)


class NotificationPayload(BaseModel):
    target_user_id: str
    title: str
    body: str
    data: Optional[Dict[str, Any]] = None


@router.post("/send")
async def send_notification(payload: NotificationPayload):
    """
    Receives notification requests from the client and dispatches them via FCM.
    If firebase-admin is installed and configured on the server, it dispatches push notifications.
    Otherwise, it logs the notification safely without exposing server secrets to Flutter.
    """
    logger.info(
        f"Notification requested for user {payload.target_user_id}: "
        f"'{payload.title}' - '{payload.body}' (data: {payload.data})"
    )

    try:
        import firebase_admin
        from firebase_admin import messaging

        if firebase_admin._apps:
            # Build and send message if Firebase Admin is initialized
            message = messaging.Message(
                notification=messaging.Notification(
                    title=payload.title,
                    body=payload.body,
                ),
                data={str(k): str(v) for k, v in (payload.data or {}).items()},
                topic=f"user_{payload.target_user_id}",
            )
            response = messaging.send(message)
            return {
                "status": "sent",
                "message_id": response,
            }
    except Exception as e:
        logger.warning(f"FCM server dispatch unavailable or skipped: {e}")

    return {
        "status": "logged",
        "target_user_id": payload.target_user_id,
        "title": payload.title,
    }
