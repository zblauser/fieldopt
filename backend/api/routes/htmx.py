"""
HTMX/SSE routes — server-rendered dashboard. Primary frontend.

Mounted at / (root). /api/v1/* JSON routers win on prefix.
No Node, no npm. Jinja2 + vanilla htmx (vendored single JS file).
"""
from __future__ import annotations

import asyncio
import json
from datetime import datetime, time, timedelta, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, Response, StreamingResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.config import get_settings
from backend.database.connection import get_db
from backend.database.models import Assignment, Job, JobStatus, Technician
from backend.simulation.broadcaster import manager
from backend.simulation.clock import clock, ClockMode
from backend.simulation.loop import dispatch_loop
from backend.simulation.strategy import MLStrategy

router = APIRouter()
settings = get_settings()

TEMPLATES_DIR = Path(__file__).resolve().parents[2] / "templates"
STATIC_DIR = Path(__file__).resolve().parents[2] / "static"
templates = Jinja2Templates(directory=str(TEMPLATES_DIR))


def _static_v() -> str:
	"""mtime of app.css → cache-bust query string. Edits + rebuilds bump it."""
	try:
		return str(int((STATIC_DIR / "app.css").stat().st_mtime))
	except OSError:
		return settings.APP_VERSION


templates.env.globals["app_version"] = settings.APP_VERSION
templates.env.globals["static_v"] = _static_v()


def _sim_state() -> dict:
	"""Snapshot for the SimBar template."""
	return {
		"is_demo": settings.IS_DEMO,
		"mode": clock.mode.value,
		"speed": clock.speed,
		"is_paused": clock.is_paused,
		"loop_running": dispatch_loop.is_running,
		"running": clock.mode == ClockMode.SIMULATED and not clock.is_paused,
		"hms": clock.now().strftime("%H:%M:%S"),
	}


def _require_demo():
	if not settings.IS_DEMO:
		raise HTTPException(status_code=404, detail="Not found")


async def _todays_jobs(
	db: AsyncSession,
	status: str | None = None,
	job_type: str | None = None,
	tech_id: str | None = None,
	route: str | None = None,
) -> list[Job]:
	"""Today's jobs with optional filters. Tech filter accepts 'unassigned' or a tech id."""
	from backend.database.models import Assignment, JobType
	now = clock.now()
	day_start = datetime.combine(now.date(), time.min, tzinfo=timezone.utc)
	day_end = day_start + timedelta(days=1)
	q = select(Job).where(Job.scheduled_date >= day_start, Job.scheduled_date < day_end)
	if status:
		q = q.where(Job.status == JobStatus(status))
	if job_type:
		q = q.where(Job.job_type == JobType(job_type))
	if route:
		q = q.where(Job.route_criteria == route)
	if tech_id == "unassigned":
		q = q.where(~Job.id.in_(select(Assignment.job_id)))
	elif tech_id:
		try:
			tid = int(tech_id)
			q = q.where(Job.id.in_(select(Assignment.job_id).where(Assignment.technician_id == tid)))
		except ValueError:
			pass
	q = q.order_by(Job.time_slot_start.nullsfirst(), Job.id)
	return list((await db.execute(q)).scalars().all())


async def _counts(db: AsyncSession) -> dict:
	from backend.database.models import TechnicianStatus
	jobs = await _todays_jobs(db)
	techs = (await db.execute(select(Technician).where(Technician.is_active == True))).scalars().all()
	c = {s.value: 0 for s in JobStatus}
	for j in jobs:
		c[j.status.value] = c.get(j.status.value, 0) + 1
	tech_avail = sum(1 for t in techs if t.status == TechnicianStatus.AVAILABLE)
	tech_busy = sum(1 for t in techs if t.status in (TechnicianStatus.EN_ROUTE, TechnicianStatus.ON_JOB))
	tech_off = sum(1 for t in techs if t.status in (TechnicianStatus.OFF_DUTY, TechnicianStatus.ON_BREAK))
	c["tech_available"] = tech_avail
	c["tech_busy"] = tech_busy
	c["tech_off"] = tech_off
	return c


@router.get("/counts", response_class=HTMLResponse)
async def counts_fragment(request: Request, db: AsyncSession = Depends(get_db)):
	return templates.TemplateResponse(
		"_dash_bar.html",
		{"request": request, "counts": await _counts(db)},
	)


@router.get("/", response_class=HTMLResponse)
async def dashboard(request: Request, db: AsyncSession = Depends(get_db)):
	from backend.database.models import JobType
	techs = (await db.execute(select(Technician).order_by(Technician.name))).scalars().all()
	jobs = await _todays_jobs(db)
	# Routes seen on today's jobs
	routes = sorted({j.route_criteria for j in jobs if j.route_criteria})
	return templates.TemplateResponse(
		"dashboard.html",
		{
			"request": request,
			"techs": techs,
			"jobs": jobs,
			"sim": _sim_state(),
			"now_minutes": clock.now().hour * 60 + clock.now().minute,
			"statuses": [s.value for s in JobStatus],
			"job_types": [t.value for t in JobType],
			"routes": routes,
			"selected_status": "",
			"counts": await _counts(db),
		},
	)


@router.get("/techs", response_class=HTMLResponse)
async def techs_fragment(request: Request, db: AsyncSession = Depends(get_db)):
	techs = (await db.execute(select(Technician).order_by(Technician.name))).scalars().all()
	return templates.TemplateResponse(
		"_tech_list.html",
		{"request": request, "techs": techs},
	)


@router.get("/jobs", response_class=HTMLResponse)
async def jobs_fragment(
	request: Request,
	status: str = "",
	job_type: str = "",
	tech_id: str = "",
	route: str = "",
	db: AsyncSession = Depends(get_db),
):
	jobs = await _todays_jobs(db, status=status or None, job_type=job_type or None, tech_id=tech_id or None, route=route or None)
	return templates.TemplateResponse(
		"_job_table.html",
		{
			"request": request,
			"jobs": jobs,
			"now_minutes": clock.now().hour * 60 + clock.now().minute,
			"selected_status": status,
		},
	)


# Timeline window (virtual hours, UTC). Matches sim shift window.
TIMELINE_START_HOUR = 8
TIMELINE_END_HOUR = 17


async def _timeline_rows(db: AsyncSession) -> list[dict]:
	"""Build [{tech, blocks: [...]}] for the timeline SVG.

	Blocks are ordered by ETA; positions are computed in the template using
	`offset_min` (minutes from TIMELINE_START_HOUR) and `width_min`.
	"""
	now = clock.now()
	day_start = datetime.combine(now.date(), time.min, tzinfo=timezone.utc)
	day_end = day_start + timedelta(days=1)

	techs = (
		await db.execute(
			select(Technician)
			.where(Technician.is_active == True)
			.order_by(Technician.name)
		)
	).scalars().all()

	assigns = (
		await db.execute(
			select(Assignment)
			.join(Job, Assignment.job_id == Job.id)
			.where(Job.scheduled_date >= day_start, Job.scheduled_date < day_end)
		)
	).scalars().all()

	by_tech: dict[int, list] = {}
	for a in assigns:
		eta = a.estimated_arrival or a.job.scheduled_date
		if eta is None:
			continue
		# Convert ETA to minutes from timeline start of THIS virtual day
		eta_min = (eta - day_start).total_seconds() / 60.0
		offset = eta_min - TIMELINE_START_HOUR * 60
		duration = a.actual_duration_minutes or a.job.estimated_duration or 60
		by_tech.setdefault(a.technician_id, []).append(
			{
				"job_id": a.job_id,
				"job_number": a.job.job_number or a.job.id,
				"customer": a.job.customer_name,
				"status": a.job.status.value,
				"offset_min": max(0.0, offset),
				"width_min": max(15.0, float(duration)),  # minimum 15min for visibility
				"eta_hms": eta.strftime("%H:%M"),
			}
		)

	rows = []
	for t in techs:
		blocks = sorted(by_tech.get(t.id, []), key=lambda b: b["offset_min"])
		rows.append({"tech": t, "blocks": blocks})
	return rows


# ── Assignment (drag-drop + context menu) ───────────────────────────────────

def _candoo_issues(job: Job, tech: Technician) -> list[dict]:
	"""Return list of {label, pass} for skill + route checks. Mirrors React doAssignWithCheck."""
	issues = []
	missing = [s for s in (job.required_skills or []) if s not in (tech.skills or [])]
	issues.append({
		"label": f"Skill{(' (missing: ' + ', '.join(missing) + ')') if missing else ''}",
		"pass": len(missing) == 0,
	})
	# route check — Technician has skills but route via separate join in real model;
	# falling back to permissive pass if no route_criteria on job.
	route_ok = not job.route_criteria  # if no criteria, always OK
	# NOTE: full route check requires tech.assigned_routes which lives in a relation.
	# Slice 6 keeps it simple — skill check is the gating one; route shown advisory.
	issues.append({"label": f"Route{'' if route_ok else ' (' + job.route_criteria + ')'}", "pass": route_ok})
	return issues


def _demo_lock_block() -> HTMLResponse | None:
	"""Return a toast response if sim is running (demo playback lock)."""
	if clock.mode == ClockMode.SIMULATED and not clock.is_paused:
		return _toast_response("Stop the demo to assign jobs", "warning")
	return None


@router.post("/assign", response_class=HTMLResponse)
async def assign(
	request: Request,
	job_id: int = Form(...),
	tech_id: int = Form(...),
	override: int = Form(0),
	db: AsyncSession = Depends(get_db),
):
	"""Assign a job to a tech. If CanDo issues exist and !override, return modal HTML."""
	blocked = _demo_lock_block()
	if blocked:
		return blocked
	from backend.logic import assignments as assign_logic

	job = (await db.execute(select(Job).where(Job.id == job_id))).scalar_one_or_none()
	tech = (await db.execute(select(Technician).where(Technician.id == tech_id))).scalar_one_or_none()
	if not job or not tech:
		raise HTTPException(status_code=404, detail="Job or tech not found")

	if not override:
		issues = _candoo_issues(job, tech)
		if any(not i["pass"] for i in issues):
			return templates.TemplateResponse(
				"_override_modal.html",
				{"request": request, "job": job, "tech": tech, "issues": issues},
			)

	# Unassign first if reassigning
	if job.assignment and job.assignment.technician_id != tech_id:
		await assign_logic.unassign_job(db, job_id)
	elif job.assignment and job.assignment.technician_id == tech_id:
		# already on this tech, no-op
		return _toast_response(f"Already on {tech.name}", "warning")

	try:
		await assign_logic.create_assignment(db, job_id, tech_id, now=clock.now())
	except ValueError as e:
		return _toast_response(str(e), "error")

	return _toast_response(f"Job #{job.job_number or job_id} → {tech.name}", "success")


def _toast_response(msg: str, kind: str = "success") -> HTMLResponse:
	"""Return an out-of-band toast + trigger refresh of dependent panels."""
	html = (
		f'<div id="toast" hx-swap-oob="true" class="toast toast--{kind}">{msg}</div>'
	)
	resp = HTMLResponse(html)
	# Tell htmx to re-fetch panels on the page.
	resp.headers["HX-Trigger"] = "refreshAll"
	return resp


@router.post("/unassign", response_class=HTMLResponse)
async def unassign(job_id: int = Form(...), db: AsyncSession = Depends(get_db)):
	blocked = _demo_lock_block()
	if blocked:
		return blocked
	from backend.logic import assignments as assign_logic
	ok = await assign_logic.unassign_job(db, job_id)
	if not ok:
		return _toast_response("Job not assigned", "warning")
	return _toast_response(f"Job #{job_id} unassigned", "success")


@router.get("/map", response_class=HTMLResponse)
async def map_window(request: Request):
	"""Standalone map page — opened in a popup window from the main dashboard."""
	return templates.TemplateResponse("map_window.html", {"request": request})


# ── Floating window contents ────────────────────────────────────────────────

@router.get("/window/personnel", response_class=HTMLResponse)
async def personnel_window(request: Request, db: AsyncSession = Depends(get_db)):
	from backend.database.models import TechnicianStatus
	techs = (await db.execute(select(Technician).order_by(Technician.name))).scalars().all()
	by_status = {s.value: [t for t in techs if t.status == s] for s in TechnicianStatus}
	return templates.TemplateResponse(
		"_win_personnel.html",
		{"request": request, "techs": techs, "by_status": by_status},
	)


@router.get("/window/search", response_class=HTMLResponse)
async def search_window(
	request: Request,
	q: str = "",
	date_from: str = "",
	date_to: str = "",
	job_id: str = "",
	tech_id: str = "",
	customer: str = "",
	status: str = "",
	job_type: str = "",
	route: str = "",
	db: AsyncSession = Depends(get_db),
):
	"""Job search with full criteria. Empty form = no results yet."""
	from sqlalchemy import or_
	from backend.database.models import Assignment, JobType
	any_criteria = any([q, date_from, date_to, job_id, tech_id, customer, status, job_type, route])
	jobs = []
	if any_criteria:
		query = select(Job)
		if q:
			query = query.where(or_(
				Job.job_number.ilike(f"%{q}%"),
				Job.customer_name.ilike(f"%{q}%"),
				Job.service_address.ilike(f"%{q}%"),
			))
		if date_from:
			query = query.where(Job.scheduled_date >= datetime.fromisoformat(date_from).replace(tzinfo=timezone.utc))
		if date_to:
			query = query.where(Job.scheduled_date < datetime.fromisoformat(date_to).replace(tzinfo=timezone.utc) + timedelta(days=1))
		if job_id:
			try: query = query.where(Job.id == int(job_id))
			except ValueError: pass
		if customer:
			query = query.where(Job.customer_name.ilike(f"%{customer}%"))
		if status:
			query = query.where(Job.status == JobStatus(status))
		if job_type:
			query = query.where(Job.job_type == JobType(job_type))
		if route:
			query = query.where(Job.route_criteria == route)
		if tech_id:
			try: query = query.where(Job.id.in_(select(Assignment.job_id).where(Assignment.technician_id == int(tech_id))))
			except ValueError: pass
		query = query.order_by(Job.scheduled_date.desc().nullslast(), Job.id.desc()).limit(200)
		jobs = list((await db.execute(query)).scalars().all())

	techs = (await db.execute(select(Technician).order_by(Technician.name))).scalars().all()
	return templates.TemplateResponse(
		"_win_search.html",
		{
			"request": request, "jobs": jobs,
			"q": q, "date_from": date_from, "date_to": date_to,
			"job_id": job_id, "tech_id": tech_id, "customer": customer,
			"status": status, "job_type": job_type, "route": route,
			"techs": techs,
			"statuses": [s.value for s in JobStatus],
			"job_types": [t.value for t in JobType],
			"any_criteria": any_criteria,
		},
	)


@router.get("/qualified/{job_id}")
async def qualified_techs(job_id: int, db: AsyncSession = Depends(get_db)):
	"""Return list of techs qualified for a job, partitioned by skill match.

	Used by the job context menu's Assign-To submenu.
	"""
	job = (await db.execute(select(Job).where(Job.id == job_id))).scalar_one_or_none()
	if not job:
		return {"qualified": [], "missing_skills": []}
	techs = (await db.execute(
		select(Technician).where(Technician.is_active == True).order_by(Technician.name)
	)).scalars().all()
	required = set(job.required_skills or [])
	qualified = []
	unqualified = []
	for t in techs:
		if t.status.value == "off_duty":
			continue
		tech_skills = set(t.skills or [])
		missing = required - tech_skills
		entry = {"id": t.id, "name": t.name, "status": t.status.value, "missing": list(missing)}
		(qualified if not missing else unqualified).append(entry)
	return {"qualified": qualified, "unqualified": unqualified, "required": list(required)}


@router.get("/window/job/{job_id}", response_class=HTMLResponse)
async def job_detail_window(request: Request, job_id: int, db: AsyncSession = Depends(get_db)):
	job = (await db.execute(select(Job).where(Job.id == job_id))).scalar_one_or_none()
	if not job:
		return HTMLResponse('<div class="win-empty">Job not found.</div>', status_code=404)
	return templates.TemplateResponse(
		"_win_job_detail.html",
		{"request": request, "job": job},
	)


@router.get("/window/tech/{tech_id}", response_class=HTMLResponse)
async def tech_detail_window(request: Request, tech_id: int, db: AsyncSession = Depends(get_db)):
	tech = (await db.execute(select(Technician).where(Technician.id == tech_id))).scalar_one_or_none()
	if not tech:
		return HTMLResponse('<div class="win-empty">Tech not found.</div>', status_code=404)
	# Today's assignments for context
	now = clock.now()
	day_start = datetime.combine(now.date(), time.min, tzinfo=timezone.utc)
	day_end = day_start + timedelta(days=1)
	from backend.database.models import Assignment
	assignments = list((await db.execute(
		select(Assignment).join(Job, Assignment.job_id == Job.id)
		.where(Assignment.technician_id == tech_id, Job.scheduled_date >= day_start, Job.scheduled_date < day_end)
		.order_by(Assignment.estimated_arrival.nullsfirst())
	)).scalars().all())
	return templates.TemplateResponse(
		"_win_tech_detail.html",
		{"request": request, "tech": tech, "assignments": assignments},
	)


@router.get("/window/settings", response_class=HTMLResponse)
async def settings_window(request: Request):
	return templates.TemplateResponse(
		"_win_settings.html",
		{"request": request, "sim": _sim_state()},
	)


@router.get("/window/filter", response_class=HTMLResponse)
async def filter_window(request: Request, db: AsyncSession = Depends(get_db)):
	from backend.database.models import JobType
	techs = (await db.execute(select(Technician).order_by(Technician.name))).scalars().all()
	jobs = await _todays_jobs(db)
	routes = sorted({j.route_criteria for j in jobs if j.route_criteria})
	return templates.TemplateResponse(
		"_win_filter.html",
		{
			"request": request,
			"techs": techs,
			"routes": routes,
			"statuses": [s.value for s in JobStatus],
			"job_types": [t.value for t in JobType],
		},
	)


@router.get("/map/markers")
async def map_markers(db: AsyncSession = Depends(get_db)):
	"""JSON markers + per-tech route polylines for the Leaflet map."""
	from backend.database.models import Assignment
	jobs = await _todays_jobs(db)
	techs = (
		await db.execute(select(Technician).where(Technician.is_active == True))
	).scalars().all()

	# Build routes: per tech, [home → job1 → job2 → ...] ordered by ETA
	now = clock.now()
	day_start = datetime.combine(now.date(), time.min, tzinfo=timezone.utc)
	day_end = day_start + timedelta(days=1)
	all_assigns = list((await db.execute(
		select(Assignment).join(Job, Assignment.job_id == Job.id)
		.where(Job.scheduled_date >= day_start, Job.scheduled_date < day_end)
	)).scalars().all())

	by_tech: dict[int, list] = {}
	for a in all_assigns:
		by_tech.setdefault(a.technician_id, []).append(a)
	for tid in by_tech:
		by_tech[tid].sort(key=lambda a: (a.estimated_arrival or a.job.scheduled_date or datetime.max.replace(tzinfo=timezone.utc)))

	routes = []
	for t in techs:
		assigns = by_tech.get(t.id, [])
		if not assigns:
			continue
		path = [[t.current_latitude or t.home_latitude, t.current_longitude or t.home_longitude]]
		path.extend([[a.job.latitude, a.job.longitude] for a in assigns])
		# Count done so the rendered route grays the completed legs
		done_count = sum(1 for a in assigns if a.job.status.value in ("completed", "cancelled"))
		routes.append({"tech_id": t.id, "tech_name": t.name, "path": path, "done_count": done_count})

	return {
		"jobs": [
			{"id": j.id, "job_number": j.job_number or j.id, "customer": j.customer_name,
			 "address": j.service_address, "status": j.status.value,
			 "lat": j.latitude, "lng": j.longitude}
			for j in jobs
		],
		"techs": [
			{"id": t.id, "name": t.name, "status": t.status.value,
			 "lat": t.current_latitude or t.home_latitude,
			 "lng": t.current_longitude or t.home_longitude}
			for t in techs
			if (t.current_latitude or t.home_latitude) is not None
		],
		"routes": routes,
	}


@router.get("/timeline", response_class=HTMLResponse)
async def timeline_fragment(
	request: Request,
	selected: str = "",
	db: AsyncSession = Depends(get_db),
):
	rows = await _timeline_rows(db)
	if selected:
		try:
			sel_ids = {int(x) for x in selected.split(",") if x.strip()}
			rows = [r for r in rows if r["tech"].id in sel_ids]
		except ValueError:
			pass
	now = clock.now()
	now_offset = (now.hour - TIMELINE_START_HOUR) * 60 + now.minute
	return templates.TemplateResponse(
		"_timeline.html",
		{
			"request": request,
			"rows": rows,
			"now_offset_min": max(0, now_offset),
			"start_hour": TIMELINE_START_HOUR,
			"end_hour": TIMELINE_END_HOUR,
			"total_min": (TIMELINE_END_HOUR - TIMELINE_START_HOUR) * 60,
			"hours": list(range(TIMELINE_START_HOUR, TIMELINE_END_HOUR + 1)),
		},
	)


# ── Sim bar + controls ──────────────────────────────────────────────────────

@router.get("/sim/bar", response_class=HTMLResponse)
async def sim_bar(request: Request):
	return templates.TemplateResponse("_sim_bar.html", {"request": request, "sim": _sim_state()})


@router.post("/sim/start", response_class=HTMLResponse)
async def sim_start(request: Request, speed: float = Form(500.0)):
	_require_demo()
	from backend.database.connection import reset_db, AsyncSessionLocal
	from backend.database.seeds.seed_data import seed_all
	from backend.logic.routing.auto_router import auto_route_jobs

	dispatch_loop.stop()
	await reset_db()
	await seed_all()
	# Pre-route all today's jobs so the demo plays a fully-routed day.
	async with AsyncSessionLocal() as db:
		await auto_route_jobs(db)
	virtual_start = datetime.now(timezone.utc).replace(hour=8, minute=0, second=0, microsecond=0)
	clock.start_simulation(virtual_start, speed=speed)
	dispatch_loop.start(MLStrategy(), on_events=manager.broadcast_events)
	return templates.TemplateResponse("_sim_bar.html", {"request": request, "sim": _sim_state()})


@router.post("/sim/pause", response_class=HTMLResponse)
async def sim_pause(request: Request):
	_require_demo()
	clock.pause()
	return templates.TemplateResponse("_sim_bar.html", {"request": request, "sim": _sim_state()})


@router.post("/sim/resume", response_class=HTMLResponse)
async def sim_resume(request: Request):
	_require_demo()
	clock.resume()
	return templates.TemplateResponse("_sim_bar.html", {"request": request, "sim": _sim_state()})


@router.post("/sim/stop", response_class=HTMLResponse)
async def sim_stop(request: Request):
	_require_demo()
	dispatch_loop.stop()
	clock.use_real_time()
	return templates.TemplateResponse("_sim_bar.html", {"request": request, "sim": _sim_state()})


@router.post("/sim/speed", response_class=HTMLResponse)
async def sim_speed(request: Request, speed: float = Form(...)):
	_require_demo()
	if clock.mode != ClockMode.SIMULATED:
		raise HTTPException(status_code=400, detail="Simulation not running")
	clock.set_speed(speed)
	return templates.TemplateResponse("_sim_bar.html", {"request": request, "sim": _sim_state()})


@router.get("/sim/stream")
async def sim_stream():
	"""SSE stream of clock ticks. One event per wall-second."""

	async def event_gen():
		try:
			while True:
				payload = {
					"hms": clock.now().strftime("%H:%M:%S"),
					"speed": clock.speed,
					"paused": clock.is_paused,
					"mode": clock.mode.value,
				}
				yield f"event: tick\ndata: {json.dumps(payload)}\n\n"
				await asyncio.sleep(1.0)
		except asyncio.CancelledError:
			return

	return StreamingResponse(
		event_gen(),
		media_type="text/event-stream",
		headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
	)
