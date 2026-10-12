from fastapi import APIRouter

from app.api.v1 import (
    auth,
    cases,
    courts,
    devices,
    invites,
    jury,
    notifications,
    public,
    reports,
    users,
    ws,
)

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(courts.router)
api_router.include_router(devices.router)
api_router.include_router(notifications.router)
api_router.include_router(cases.router)
api_router.include_router(invites.router)
api_router.include_router(jury.router)
api_router.include_router(public.router)
api_router.include_router(reports.router)
api_router.include_router(ws.router)

__all__ = ["api_router"]
