"""
Simulation control endpoints and WebSocket broadcaster.

All REST endpoints return 404 unless IS_DEMO=true in settings.
WebSocket endpoint is always available (clients just get no events when sim is off).
"""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel

from backend.config import get_settings
from backend.simulation.broadcaster import manager
from backend.simulation.clock import clock, ClockMode
from backend.simulation.loop import dispatch_loop
from backend.simulation.strategy import MLStrategy

router = APIRouter()
settings = get_settings()


def _require_demo():
    if not settings.IS_DEMO:
        raise HTTPException(status_code=404, detail="Not found")


# ── WebSocket ────────────────────────────────────────────────────────────────

@router.websocket("/ws")
async def simulation_ws(ws: WebSocket):
    """Stream DispatchEvents to connected clients as JSON arrays."""
    await manager.connect(ws)
    try:
        while True:
            await ws.receive_text()  # keep connection alive; client can send pings
    except WebSocketDisconnect:
        manager.disconnect(ws)


# ── Control endpoints ────────────────────────────────────────────────────────

class StartRequest(BaseModel):
    virtual_start: datetime | None = None  # defaults to today 08:00 UTC
    speed: float = 500.0


class SpeedRequest(BaseModel):
    speed: float


@router.post("/start")
async def sim_start(req: StartRequest):
    _require_demo()
    # Always reset + reseed — demo starts from a clean state every time
    from backend.database.connection import reset_db, AsyncSessionLocal
    from backend.database.seeds.seed_data import seed_all
    from backend.logic.routing.auto_router import auto_route_jobs
    dispatch_loop.stop()
    await reset_db()
    await seed_all()
    # Pre-route every today's job so the demo shows a fully-routed day.
    # Niche-skill jobs that ML would leave PENDING get assigned upfront here.
    async with AsyncSessionLocal() as db:
        await auto_route_jobs(db)
    virtual_start = req.virtual_start or datetime.now(timezone.utc).replace(
        hour=8, minute=0, second=0, microsecond=0
    )
    if virtual_start.tzinfo is None:
        raise HTTPException(status_code=422, detail="virtual_start must be timezone-aware")
    clock.start_simulation(virtual_start, speed=req.speed)
    dispatch_loop.start(MLStrategy(), on_events=manager.broadcast_events)
    return {"status": "started", "virtual_start": virtual_start.isoformat(), "speed": req.speed}


@router.post("/pause")
async def sim_pause():
    _require_demo()
    clock.pause()
    return {"status": "paused", "virtual_time": clock.now().isoformat()}


@router.post("/resume")
async def sim_resume():
    _require_demo()
    clock.resume()
    return {"status": "resumed", "virtual_time": clock.now().isoformat()}


@router.post("/stop")
async def sim_stop():
    _require_demo()
    dispatch_loop.stop()
    clock.use_real_time()
    return {"status": "stopped"}


@router.post("/speed")
async def sim_set_speed(req: SpeedRequest):
    _require_demo()
    if clock.mode != ClockMode.SIMULATED:
        raise HTTPException(status_code=400, detail="Simulation not running")
    clock.set_speed(req.speed)
    return {"status": "ok", "speed": req.speed}


@router.get("/status")
async def sim_status():
    """Always available — frontend polls this to know if sim is running."""
    return {
        "is_demo": settings.IS_DEMO,
        "mode": clock.mode,
        "speed": clock.speed,
        "is_paused": clock.is_paused,
        "loop_running": dispatch_loop.is_running,
        "virtual_time": clock.now().isoformat(),
        "ws_clients": manager.connection_count,
    }
