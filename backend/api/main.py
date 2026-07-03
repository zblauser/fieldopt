"""
FieldOpt Main API Application
"""
import asyncio
import logging
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from backend.config import get_settings
from backend.database.connection import init_db
from backend.api.routes import technicians, jobs, assignments, routing, simulation, htmx

logger = logging.getLogger(__name__)
settings = get_settings()


async def _daily_reseed_loop() -> None:
	"""Wipe + reseed the demo DB once per UTC day at 04:00.

	Keeps the long-running demo box self-refreshing so jobs always have
	today's date without manual intervention.
	"""
	from backend.database.connection import reset_db
	from backend.database.seeds.seed_data import seed_all

	while True:
		now = datetime.now(timezone.utc)
		next_run = now.replace(hour=4, minute=0, second=0, microsecond=0)
		if next_run <= now:
			next_run += timedelta(days=1)
		await asyncio.sleep((next_run - now).total_seconds())
		try:
			await reset_db()
			await seed_all()
			logger.info("Daily reseed complete at %s", datetime.now(timezone.utc).isoformat())
		except Exception:
			logger.exception("Daily reseed failed")

# React SPA (Path A) is archived. HTMX UI is the only frontend.


@asynccontextmanager
async def lifespan(app: FastAPI):
	"""Handle startup and shutdown events"""
	await init_db()
	print(f"🚀 {settings.APP_NAME} v{settings.APP_VERSION} started")
	print(f"📄 API Documentation: http://localhost:{settings.API_PORT}/docs")
	reseed_task: asyncio.Task | None = None
	if settings.IS_DEMO:
		print("🎬 IS_DEMO=true — simulation engine active")
		# Auto-refresh demo DB nightly at 04:00 UTC so the AWS box stays fresh
		# without a manual reseed. /simulation/start also resets on demand.
		reseed_task = asyncio.create_task(_daily_reseed_loop(), name="daily_reseed")
	yield
	from backend.simulation.loop import dispatch_loop
	dispatch_loop.stop()
	if reseed_task:
		reseed_task.cancel()
	print(f"🛑 {settings.APP_NAME} shutting down")


app = FastAPI(
	title=settings.APP_NAME,
	description="Open-source field service management system",
	version=settings.APP_VERSION,
	docs_url="/docs",
	redoc_url="/redoc",
	lifespan=lifespan,
)

app.add_middleware(
	CORSMiddleware,
	allow_origins=settings.CORS_ORIGINS,
	allow_credentials=True,
	allow_methods=["*"],
	allow_headers=["*"],
)


@app.get("/health")
async def health_check():
	return {
		"status": "healthy",
		"version": settings.APP_VERSION,
	}


# Routers
app.include_router(
	technicians.router,
	prefix=f"{settings.API_V1_PREFIX}/technicians",
	tags=["Technicians"],
)

app.include_router(
	jobs.router,
	prefix=f"{settings.API_V1_PREFIX}/jobs",
	tags=["Jobs"],
)

app.include_router(
	assignments.router,
	prefix=f"{settings.API_V1_PREFIX}/assignments",
	tags=["Assignments"],
)

app.include_router(
	routing.router,
	prefix=f"{settings.API_V1_PREFIX}/routing",
	tags=["Routing"],
)

app.include_router(
	simulation.router,
	prefix=f"{settings.API_V1_PREFIX}/simulation",
	tags=["Simulation"],
)

# HTMX UI — primary frontend, mounted at /. All dashboard fragments + sim
# controls live under root. /api/v1/* routers above win on prefix.
app.include_router(htmx.router, prefix="", tags=["HTMX"], include_in_schema=False)

_STATIC_DIR = Path(__file__).resolve().parents[1] / "static"
if _STATIC_DIR.is_dir():
	app.mount("/static", StaticFiles(directory=str(_STATIC_DIR)), name="static")


if __name__ == "__main__":
	import uvicorn
	uvicorn.run(
		"backend.api.main:app",
		host=settings.API_HOST,
		port=settings.API_PORT,
		reload=settings.API_RELOAD,
	)
