"""
Simulation tick loop.

Manages the background asyncio task that drives the simulated dispatch day:
  1. Set estimated_arrival on newly-assigned jobs (clock.now + travel_time).
  2. Transition ASSIGNED → IN_PROGRESS when arrival time passes.
  3. Transition IN_PROGRESS → COMPLETED when actual_duration_minutes elapses.
  4. Emit overrun_warning events at estimated_duration and 1.5×.
  5. Run the dispatch strategy to assign pending jobs.

Usage:
    from backend.simulation.loop import dispatch_loop
    from backend.simulation.strategy import HeuristicStrategy

    dispatch_loop.start(HeuristicStrategy(), on_events=broadcast_fn)
    dispatch_loop.stop()
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone
from typing import Callable, Awaitable

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from backend.database.connection import AsyncSessionLocal
from backend.database.models import Assignment, Job, JobStatus, Technician, TechnicianStatus
from backend.simulation.clock import clock, ClockMode
from backend.simulation.strategy import DispatchStrategy, DispatchEvent

logger = logging.getLogger(__name__)

TICK_VIRTUAL_MINUTES = 1    # virtual minutes between ticks — fine grain for live UI
OVERRUN_YELLOW_FACTOR = 1.0 # estimated_duration elapsed → yellow
OVERRUN_RED_FACTOR = 1.5    # 1.5× estimated_duration → red

OnEventsCb = Callable[[list[DispatchEvent]], Awaitable[None]] | None


class DispatchLoop:
	def __init__(self) -> None:
		self._task: asyncio.Task | None = None
		self._strategy: DispatchStrategy | None = None
		self._on_events: OnEventsCb = None
		self._running = False
		self._sim_start: datetime | None = None

	def start(self, strategy: DispatchStrategy, on_events: OnEventsCb = None) -> None:
		from backend.simulation.day_script import reset_beats
		if self._running:
			self.stop()
		self._strategy = strategy
		self._on_events = on_events
		self._running = True
		self._sim_start = clock.now() if clock.mode == ClockMode.SIMULATED else None
		reset_beats()
		self._task = asyncio.create_task(self._run(), name="dispatch_loop")
		logger.info("Dispatch loop started")

	def stop(self) -> None:
		self._running = False
		if self._task and not self._task.done():
			self._task.cancel()
		self._task = None
		logger.info("Dispatch loop stopped")

	@property
	def is_running(self) -> bool:
		return self._running and self._task is not None and not self._task.done()

	async def _run(self) -> None:
		# Tick immediately on start so the user sees motion the moment they
		# hit Start Demo. Sleep happens at end of each iteration.
		while self._running:
			if clock.is_paused:
				speed = clock.speed if clock.mode == ClockMode.SIMULATED else 1.0
				await asyncio.sleep((TICK_VIRTUAL_MINUTES * 60) / speed)
				continue

			try:
				async with AsyncSessionLocal() as db:
					events = await _tick(db, clock.now(), self._strategy, self._sim_start)

				if events and self._on_events:
					await self._on_events(events)
				if any(e.event_type == "day_complete" for e in events):
					logger.info("Day complete — all today's jobs finished. Stopping sim.")
					self._running = False
					# Pause clock at end-of-day so the UI shows the final virtual time
					# instead of snapping back to real wall-clock.
					clock.pause()
					break
			except asyncio.CancelledError:
				raise
			except Exception:
				logger.exception("Error in dispatch loop tick")

			speed = clock.speed if clock.mode == ClockMode.SIMULATED else 1.0
			await asyncio.sleep((TICK_VIRTUAL_MINUTES * 60) / speed)
			if not self._running:
				break


async def _tick(db: AsyncSession, now: datetime, strategy: DispatchStrategy, sim_start: datetime | None = None) -> list[DispatchEvent]:
	events: list[DispatchEvent] = []

	# ── 1. Stamp estimated_arrival sequentially — one job per tech per tick ──
	# Pre-route assigns a whole day's worth of jobs to each tech. We don't want
	# them all firing simultaneously; instead the tech works the queue earliest
	# time_slot first. A tech is ready for the *next* job when:
	#   - status is AVAILABLE or EN_ROUTE, AND
	#   - none of their ASSIGNED jobs already has an arrival pending.
	candidate_techs = (await db.execute(
		select(Technician)
		.distinct()
		.join(Assignment, Assignment.technician_id == Technician.id)
		.join(Job, Assignment.job_id == Job.id)
		.where(
			Technician.status.in_([TechnicianStatus.AVAILABLE, TechnicianStatus.EN_ROUTE]),
			Job.status == JobStatus.ASSIGNED,
			Assignment.estimated_arrival.is_(None),
		)
	)).scalars().all()
	for tech in candidate_techs:
		# Skip if this tech already has an EN_ROUTE assignment ticking down.
		pending = (await db.execute(
			select(Assignment.id).join(Job, Assignment.job_id == Job.id).where(
				Assignment.technician_id == tech.id,
				Job.status == JobStatus.ASSIGNED,
				Assignment.estimated_arrival.is_not(None),
			).limit(1)
		)).scalar_one_or_none()
		if pending is not None:
			continue
		next_a = (await db.execute(
			select(Assignment).join(Job, Assignment.job_id == Job.id).where(
				Assignment.technician_id == tech.id,
				Job.status == JobStatus.ASSIGNED,
				Assignment.estimated_arrival.is_(None),
			).order_by(Job.time_slot_start.nullsfirst(), Job.id).limit(1)
		)).scalar_one_or_none()
		if next_a is None:
			continue
		travel = next_a.estimated_travel_time or 0
		# Honor the customer time slot: don't arrive before slot_start. Tech idles
		# at base (AVAILABLE) until depart_time = slot_start - travel.
		slot_str = next_a.job.time_slot_start
		if slot_str:
			try:
				h, m = int(slot_str[:2]), int(slot_str[3:5])
				slot_dt = now.replace(hour=h, minute=m, second=0, microsecond=0)
				depart_dt = slot_dt - timedelta(minutes=travel)
				if now < depart_dt:
					continue  # too early — wait
				arrival_dt = max(now + timedelta(minutes=travel), slot_dt)
			except (ValueError, IndexError):
				arrival_dt = now + timedelta(minutes=travel)
		else:
			arrival_dt = now + timedelta(minutes=travel)
		next_a.estimated_arrival = arrival_dt
		if tech.status == TechnicianStatus.AVAILABLE:
			tech.status = TechnicianStatus.EN_ROUTE
	await db.commit()

	# ── 2. ASSIGNED → IN_PROGRESS when arrival passes ──────────────────────
	result = await db.execute(
		select(Assignment).join(Job, Assignment.job_id == Job.id).where(
			Job.status == JobStatus.ASSIGNED,
			Assignment.estimated_arrival <= now,
		)
	)
	for assignment in result.scalars().all():
		job = assignment.job
		tech = assignment.technician
		job.status = JobStatus.IN_PROGRESS
		job.started_at = now
		if tech:
			tech.status = TechnicianStatus.ON_JOB
		events.append(DispatchEvent(
			event_type="job_started",
			timestamp=now,
			job_id=job.id,
			tech_id=assignment.technician_id,
			tech_name=tech.name if tech else None,
			customer_name=job.customer_name,
		))
	await db.commit()

	# ── 3. IN_PROGRESS → COMPLETED / overrun checks ────────────────────────
	result = await db.execute(
		select(Assignment).join(Job, Assignment.job_id == Job.id).where(
			Job.status == JobStatus.IN_PROGRESS,
			Job.started_at.is_not(None),
		)
	)
	for assignment in result.scalars().all():
		job = assignment.job
		tech = assignment.technician
		elapsed_min = (now - job.started_at).total_seconds() / 60
		actual = assignment.actual_duration_minutes or job.estimated_duration
		est = job.estimated_duration or actual

		if elapsed_min >= actual:
			job.status = JobStatus.COMPLETED
			job.completed_at = now
			assignment.actual_completion = now
			if tech:
				tech.status = TechnicianStatus.AVAILABLE
			events.append(DispatchEvent(
				event_type="job_completed",
				timestamp=now,
				job_id=job.id,
				tech_id=assignment.technician_id,
				tech_name=tech.name if tech else None,
				customer_name=job.customer_name,
				details={"actual_duration_minutes": int(elapsed_min)},
			))
		elif elapsed_min >= est * OVERRUN_RED_FACTOR:
			events.append(DispatchEvent(
				event_type="overrun_warning",
				timestamp=now,
				job_id=job.id,
				tech_id=assignment.technician_id,
				tech_name=tech.name if tech else None,
				customer_name=job.customer_name,
				details={"severity": "red", "overrun_minutes": int(elapsed_min - est)},
			))
		elif elapsed_min >= est * OVERRUN_YELLOW_FACTOR:
			events.append(DispatchEvent(
				event_type="overrun_warning",
				timestamp=now,
				job_id=job.id,
				tech_id=assignment.technician_id,
				tech_name=tech.name if tech else None,
				customer_name=job.customer_name,
				details={"severity": "yellow", "overrun_minutes": int(elapsed_min - est)},
			))
	await db.commit()

	# ── 3.5. Flip techs to OFF_DUTY once their shift ends ─────────────────
	if sim_start is not None:
		elapsed_min = int((now - sim_start).total_seconds() / 60)
		now_minutes = 8 * 60 + elapsed_min
		from backend.simulation.strategy import _slot_minutes
		off_duty_result = await db.execute(
			select(Technician).where(
				Technician.is_active == True,
				Technician.status.in_([TechnicianStatus.AVAILABLE, TechnicianStatus.EN_ROUTE]),
			)
		)
		for t in off_duty_result.scalars().all():
			end = _slot_minutes(t.shift_end)
			if end and now_minutes >= end and t.status == TechnicianStatus.AVAILABLE:
				t.status = TechnicianStatus.OFF_DUTY
		await db.commit()

	# ── 4. Scripted beats ──────────────────────────────────────────────────
	if sim_start is not None:
		from backend.simulation.day_script import process_beats
		fired = await process_beats(db, now, sim_start)
		for desc in fired:
			events.append(DispatchEvent(event_type="scripted_beat", timestamp=now, details={"description": desc}))

	# ── 5. Strategy assigns pending jobs ───────────────────────────────────
	if strategy is not None:
		strategy_events = await strategy.tick(db, now, sim_date=sim_start)
		events.extend(e for e in strategy_events if e.event_type != "no_ops")

	# ── 6. Auto-stop: check if all today's jobs are in terminal state ───────
	if sim_start is not None:
		day_start = sim_start.replace(hour=0, minute=0, second=0, microsecond=0)
		day_end = day_start + timedelta(days=1)
		count_result = await db.execute(
			select(func.count(Job.id)).where(
				Job.status.in_([JobStatus.PENDING, JobStatus.ASSIGNED, JobStatus.IN_PROGRESS]),
				Job.scheduled_date >= day_start,
				Job.scheduled_date < day_end,
			)
		)
		active_today = count_result.scalar() or 0
		# Day ends when all jobs terminal OR virtual clock passes 18:00 (post-shift).
		# Time-based stop prevents the sim from rolling forever when ML intentionally
		# leaves niche-skill jobs (T. Monk, Sun Ra, Tim Berne) unassigned.
		past_shift = now.hour >= 18
		if active_today == 0 or past_shift:
			# Cancel any still-active jobs so they don't sit pending forever.
			if past_shift and active_today > 0:
				await db.execute(
					Job.__table__.update()
					.where(
						Job.status.in_([JobStatus.PENDING, JobStatus.ASSIGNED]),
						Job.scheduled_date >= day_start,
						Job.scheduled_date < day_end,
					)
					.values(status=JobStatus.CANCELLED)
				)
				await db.commit()
			events.append(DispatchEvent(event_type="day_complete", timestamp=now))

	elapsed_min = int((now - sim_start).total_seconds() / 60) if sim_start else 0
	events.append(DispatchEvent(event_type="clock_tick", timestamp=now, details={"elapsed_minutes": elapsed_min}))
	return events


dispatch_loop = DispatchLoop()
