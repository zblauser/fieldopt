> ⚠️ **WIP — full-Postgres rewrite branch (Path C).** This branch re-implements FieldOpt as *Postgres-as-platform*: PL/pgSQL functions serve the HTMX fragments and JSON via PostgREST, replacing the FastAPI backend. **Ported & verified:** the render surface (all fragments + map JSON), the assign/unassign write path, and the sim clock + controls (19 endpoints, matched against the FastAPI reference). **In progress:** the sim engine (auto-route + dispatch loop), the `/pg/` browser shell, and packaging (Docker + raw flavors). The docs below still describe the current FastAPI (Path B) app; they'll be rewritten when the rewrite lands.

## Overview
FieldOpt - v0.0.9<br>
An open-source field service management system. FieldOpt is an enterprise-grade dispatch console designed for dispatchers and field service companies to efficiently assign, route, and manage service jobs across a workforce of field technicians.

<table align="center">
	<tr>
		<td colspan="2" align="center">
			<img src="./assets/dashboard.png" alt="Dispatch Console" width="600"/><br/>
			Dispatch Console
		</td>
	</tr>
	<tr>
		<td align="center">
			<img src="./assets/jobsearch.png" alt="Job Search" width="300"/><br/>
			Job Search
		</td>
		<td align="center">
			<img src="./assets/map.png" alt="Map in Second Window" width="300"/><br/>
			Map in Second Window
		</td>
	</tr>
	<tr>
	<td align="center">
			<img src="./assets/filter.png" alt="Route Filter Display" width="300"/><br/>
			Route Filter Display
		</td>
		<td align="center">
			<img src="./assets/personal.png" alt="Personal Display" width="300"/><br/>
			Personal Display
		</td>
	</tr>
</table><br>

**Auto-Router** — Automatically assigns jobs to the best qualified technicians

**Skill-Based Matching** — Ensures technicians only get jobs they're qualified for (manual override capable)

**Capacity Management** — Prevents overbooking by tracking tech workload

**Route Criteria & Management Areas** — Techs are assigned geographic zones; jobs carry route criteria for zone-aware dispatch

**Enterprise Dispatch Console** — AG Grid-powered split-pane layout with right-click context menus, drag-and-drop assignment, multi-select batch operations, tech timeline, day picker, floating filter/search/personnel windows, and a detachable map popup for multi-monitor setups

## Launch FieldOpt

### Requirements

- Docker + Docker Compose

### Run

```bash
make up      # regular (no demo, sim endpoints 404)
make demo    # IS_DEMO=true, simulation engine active
make down    # stop containers (DB volume kept)
make clean   # stop + wipe DB volume (fresh seed next run)
make logs    # tail app logs
```

Single-container build (multi-stage `Dockerfile`: node → python). Compose runs `postgres` + `app` on port 8080.

#### Access

| Service | URL |
|---------|-----|
| Dispatch Console | http://localhost:8080/ |
| API | http://localhost:8080/api/v1 |
| Swagger Docs | http://localhost:8080/docs |
| ReDoc | http://localhost:8080/redoc |

`IS_DEMO=true` (set by `make demo`) enables the simulation engine and a daily 04:00 UTC reseed. Without it, `/simulation/*` returns 404 and the SimBar stays hidden.

## Routing
### Routing Modes

- `standard` — Closest qualified tech
- `load_balance` — Distributes workload across all techs
- `standard_by_timeslot` — Considers time slots (future enhancement)

### How It Works

The routing engine evaluates multiple factors to find the best technician for each job:
1. **Skill** — Technician must have all required skills
2. **Route** — Job's route criteria must match one of the tech's assigned management areas
3. **Time** — Technician must have time available in their shift
4. **Capacity** — Won't exceed configurable max jobs per day
5. **Distance** — Assigns closest qualified tech (haversine calculation)
6. **Priority** — VIP and high-priority jobs routed first

### Job Evaluation

When assigning a job to a technician, the system evaluates three criteria and warns if any fail:
- **Skill** ✓/✕ — Does the tech have the required skills?
- **Route** ✓/✕ — Is the job in the tech's assigned management area?
- **Time** ✓/✕ — Does the tech have enough shift time remaining?
If any check fails, the dispatcher receives a warning with details but can override the assignment.

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `R` | Refresh data |
| `M` | Toggle map |
| `T` | Toggle timeline |
| `F` | Toggle display filter |
| `P` | Open personnel window |
| `J` | Open job search |
| `A` | Auto-route (with confirmation) |
| `Ctrl/Cmd+A` | Select all in focused grid |
| `Esc` | Close windows / context menus |

## API
### Key Endpoints

#### Technicians
- `POST /api/v1/technicians/` — Create technician
- `GET /api/v1/technicians/` — List all (includes assigned/completed job counts, assigned routes)
- `GET /api/v1/technicians/available` — Get available techs
- `PATCH /api/v1/technicians/{id}/status` — Update status
- `PATCH /api/v1/technicians/{id}/location` — Update location
- `GET /api/v1/technicians/{id}/workload` — Get workload
#### Jobs
- `POST /api/v1/jobs/` — Create job (supports route_criteria)
- `GET /api/v1/jobs/` — List all (supports `?scheduled_date=` filter, includes assigned tech)
- `GET /api/v1/jobs/pending` — Get unassigned jobs
- `GET /api/v1/jobs/summary` — Job counts by status (supports `?target_date=`)
- `GET /api/v1/jobs/search/query` — Multi-criteria search (date range, tech, customer, status, type, route)
- `POST /api/v1/jobs/{id}/start` — Start a job
- `POST /api/v1/jobs/{id}/complete` — Complete a job
- `POST /api/v1/jobs/{id}/cancel` — Cancel a job
- `GET /api/v1/jobs/{id}/can-do/{tech_id}` — Full Job evaluation (skill, route, time, distance)
#### Assignments
- `POST /api/v1/assignments/` — Assign job to tech
- `POST /api/v1/assignments/unassign` — Unassign a job
- `POST /api/v1/assignments/reassign` — Reassign to different tech
- `POST /api/v1/assignments/batch-assign` — Assign multiple jobs to one tech
- `POST /api/v1/assignments/batch-unassign` — Unassign multiple jobs
#### Routing
- `POST /api/v1/routing/auto-route` — Auto-assign all pending jobs
- `GET /api/v1/routing/best-tech/{job_id}` — Find best tech for a job

## Change Log

### 0.0.9 (Latest)
HTMX is now the only frontend. React archived. Tighter chrome + slot-aware sim.
- **HTMX at root** — server-rendered Jinja2 dashboard mounted at `/`. All `/htmx/*` paths gone; fragments live under root. Vendored htmx / idiomorph / leaflet (no npm).
- **React archived** — old SPA moved to `archive/frontend/` (gitignored, never built, never served). Dockerfile collapsed to single-stage python. Smaller image, no Vite/npm in build, no t3.micro OOM risk.
- **Pre-route on demo start** — `Start Demo` reseeds and immediately auto-routes every today's job before the dispatch loop kicks off. Demo plays a fully-routed day.
- **Sequential, slot-aware dispatch** — loop dispatches one job per tech per tick, ordered by `time_slot_start`. Tech idles at base (AVAILABLE) until `depart = slot_start − travel`, then EN_ROUTE → ON_JOB → AVAILABLE. Arrivals land inside the customer window; days fill the full shift instead of finishing by 10am.
- **Override-modal flash fixed** — manual fetch handler parses the response and moves `#modal-host` + toasts into place properly (htmx OOB swaps don't fire on raw fetches).
- **Column resize** — vanilla JS injects `<colgroup>` per `.grid`, adds 6px resize handles on each `<th>`, persists widths to localStorage by table key. Re-attaches on every `htmx:afterSwap`.
- **CSS port** — `app.css` is a full lift of the React design tokens + components, adapted to HTMX class names. Mobile `@media (max-width: 768px)` makes floating windows + map fullscreen.
- **SVG icons** — header buttons use the React-source SVGs (filter, personnel, search, settings, timeline, map, refresh, auto-route bolt). Bigger touch targets (34×34 icon, 30px min-height regular).
- **Thicker splitters** — 9px with centered grip bar, accent on hover/drag. Jobs↔Timeline splitter hidden when the timeline pane is collapsed.
- **Grid horizontal scroll** — `.grid { min-width: 720px }` so narrow panes get a horizontal scrollbar instead of column-shrunk-to-nothing.
- **Hidden filter selects** — Jobs pane dropped its inline status/type/tech/route bar; dash-cell clicks drive a single hidden `[name='status']` input, Filter window covers multi-select.
- **Cache-bust** — `app.css?v=<mtime>` query param so CSS edits land without manual hard-refresh after rebuild.

### 0.0.8
ML routing + investor-ready demo day
- **Single-container Docker** — multi-stage build (node → python). FastAPI serves the SPA via `StaticFiles`; no separate nginx. One command brings up Postgres + app: `make up` (or `make demo` to enable the simulation). Browse `http://localhost:8080`.
- **MLStrategy** — default dispatch. Scores `(job, tech)` by `travel_time + what_if_duration(job, tech)` using hidden `speed_factor` / `skill_bonuses` modifiers. Two-pass routing: prefers techs who can arrive within the customer window, falls back to best-available so jobs never sit unrouted. `HeuristicStrategy` kept for A/B.
- **Sim control bar** — DEMO badge, status pill, HH:MM:SS virtual clock that rolls second-by-second via local interpolation re-anchored on each WebSocket `clock_tick`. Start / Pause / Resume / Stop, 10×–500× speed. Hidden when `IS_DEMO` is unset.
- **Demo playback lock** — once the day is running, the dispatcher can still inspect (click techs / jobs, open Map, Refresh, Timeline) but assignment-mutating UI is disabled (Auto-Route, Filter, Personnel, Job Search, drag-drop assign, context-menu assign). "DEMO PLAYING" badge bottom-right.
- **Realistic schedule** — 1-hour job slots redistributed across 8:00-16:00 (lunch hour skipped). Universal staggered breaks (~10:30 mid-morning 15 min, 12:00 lunch 30 min) and `OFF_DUTY` flip at shift end. Tech goes `EN_ROUTE` on assign → `ON_JOB` on arrival → `AVAILABLE` on completion → `OFF_DUTY` past shift end.
- **Tech timeline by ETA** — blocks position by `assignment.estimated_arrival` and width by `actual_duration_minutes` (sampled), not the customer time-slot window. Sequential jobs render side-by-side; manual stacks fall into vertical lanes.
- **Past-timeframe + overrun indicators** — jobs whose `time_slot_end` has passed without completion get a red left-border (`row--overdue`); in-progress jobs past `estimated_duration` go yellow / red (`overrun_warning` WebSocket events).
- **Auto-reseed daily** — when `IS_DEMO=true`, the app spawns a background task that wipes + reseeds Postgres at 04:00 UTC every day. AWS demo box stays fresh with zero manual touch. `/simulation/start` also resets on every click.
- **Day-complete auto-pause** — when no active today's jobs remain, sim emits `day_complete`, halts the loop, and pauses the clock at the final virtual time so the dispatcher sees end-of-day instead of a snap to real time.
- **Simulation engine** — asyncio dispatch loop, 1-min virtual tick. Clock singleton (simulated / real, pause / resume, live speed change without drift). Log-normal duration sampler seeded per `(job, tech)` for deterministic replay.
- **WebSocket broadcaster** — FastAPI WS at `/api/v1/simulation/ws` streams `job_assigned`, `job_started`, `job_completed`, `overrun_warning`, `clock_tick`, `scripted_beat`, `day_complete`. Frontend reconnects with exponential backoff.
- **Scripted beats** — Apollo Theater VIP emergency at 10:47, afternoon job surge at 12:00.
- **Simulation engine** — asyncio dispatch loop drives a time-accelerated demo day (200× default). Clock singleton supports simulated/real modes, pause/resume, live speed changes without drift.
- **Duration sampler** — log-normal sampling seeded per (job, tech) pair. Tech `speed_factor` and `skill_bonuses` modifiers create realistic variance. Same pair always returns the same duration (deterministic replay).
- **WebSocket broadcaster** — FastAPI WebSocket at `/ws` broadcasts `DispatchEvent` payloads: `job_started`, `job_completed`, `overrun_warning`, `clock_tick`, `scripted_beat`. Dead connections auto-pruned.
- **Sim control endpoints** — `IS_DEMO`-gated REST controls: `/simulation/start|pause|resume|stop|speed|status`. All return 404 in production.
- **Day script** — three scripted beats: Dizzy Gillespie on break at 10:00, VIP Apollo Theater emergency injected at 10:47, afternoon job surge released at 12:00.
- **Calendar date picker** — click the date label in the header to open a calendar popup (portal-rendered, escapes overflow clipping). Prev/next month navigation, Today shortcut.
- **Mobile & touch responsive** — `@media (max-width: 768px)`: icons-only header buttons, scrollable dashboard bar, full-screen floating windows, bigger touch targets (40px buttons, 44px titlebars). Touch drag-and-drop: long-press 200ms on a job row → drag ghost → drop on tech row. Haptic feedback on drag start.
- **Ctrl/Cmd+A select all** — selects all rows in the currently focused grid (tech or job pane).
- **Version globalization** — single source of truth in `package.json`, injected at build time via Vite `define`. Version shown in header. Backend reads from `config.py APP_VERSION`.
- **Performance** — drag ghost is direct DOM writes (no React re-render per frame). Selection sync uses AG Grid `getRowNode` O(1) not `forEachNode` O(n). Filter computation in `useMemo`. Tech ID lookup at drop via `useImperativeHandle.getTechIdAtPoint`.
- **Seed data** — 25 jazz musician techs with `speed_factor` and `skill_bonuses` modifiers. 50 jobs across 13 NYC management areas. Miles Davis fast, Sun Ra catastrophic on service changes, Mary Halvorson slow new hire.

### Previous Versions
<details>
<summary>Previous Changes</summary>

***0.0.7***<br>
Windows, search, route criteria, map popup
- Display Filter Window — Multi-select filter by time slot, job type, route criteria, and technician with Select All / None / Reset. Stacks with dashboard bar filters.
- Personnel Window — Searchable list of all technicians regardless of schedule. Right-click for context actions, double-click for detail, locate-in-grid button.
- Job Search Window — Multi-criteria search (date range, job ID, tech #, customer name, status, type, route criteria). Full AG Grid results with all columns matching the main display. Right-click and double-click support. Drag from search results onto a tech in the R&D.
- Job Detail Panel — Double-click any job (main grid or search results) for full detail view: customer, address, route criteria, schedule, assignment, skills, description, notes, timestamps.
- Map as real OS popup — Map opens via `window.open()` as a standalone window for multi-monitor setups. Syncs live data via BroadcastChannel. Falls back to in-page floating window if popup is blocked.
- Route Criteria / Management Areas — `route_criteria` field on jobs, `assigned_routes` on technicians. 13 NYC management areas in seed data. Route criteria column in job grid, routes column in tech grid.
- Job evaluation — Expanded from skill-only to skill + route + time checks with haversine distance calculation. Override warning modal on assign with ✓/✕ indicators for each check.
- Auto-route confirmation — Auto-route now prompts for confirmation before executing.
- Toolbar — Filter, Personnel, Job Search buttons in header bar.
- Keyboard shortcuts — F (filter), P (personnel), J (job search), A (auto-route).
- Backend — `GET /jobs/search/query` endpoint, expanded Job Evaluation endpoint, route_criteria on all job schemas.
- Header and dashboard bar scroll gracefully on narrow windows.

***0.0.6***<br>
Dispatch interactivity + batch operations
- Day picker with date-filtered API calls (navigate days, all views scoped to selected date)
- Multi-select: Cmd/Ctrl+click to toggle, Shift+click for range (respects AG Grid sort order)
- Independent grid selections (select techs for timeline while selecting jobs for assignment)
- Batch assign/unassign via single API call and single DB transaction
- Batch tech status changes (select multiple techs, right-click → set all to available/break/off duty)
- Drag-and-drop job assignment (drag from job grid, drop on tech row)
- Multi-job drag (select multiple jobs, drag one → all selected assign to target tech)
- Tech timeline pane (toggle-able, shows hour blocks with job assignments, stacks overlapping jobs)
- Resizable timeline divider
- Jobs A:C column now shows real assigned/completed counts
- Job grid "Tech" column shows assigned technician name
- API responses now include assignment data (assigned_tech_id/name on jobs, job counts on techs)
- Skill-filtered context menus with multi-select awareness
- Context menu shows batch operations when multiple items selected

***0.0.5***<br>
Complete frontend redesign — enterprise dispatch console
- AG Grid-powered split-pane layout (technicians top, jobs bottom)
- Draggable divider between panes
- Right-click context menus with skill-filtered tech assignment
- Clickable dashboard indicator bar (filters grids by status)
- Floating, draggable, resizable map window (Leaflet)
- Toast notifications on all dispatch actions
- Keyboard shortcuts (R = refresh, M = map, T = timeline, Esc = close)
- Dropped Tailwind — handwritten enterprise CSS with dark theme
- Expanded API client (all endpoints wired)
- Jazz-themed seed data

***0.0.4***<br>
Async backend migration + bug fixes
- SQLAlchemy async engine with asyncpg
- Fixed delete_technician, workload signature, reassign atomicity
- Fixed get_jobs_summary filter bug
- lazy="selectin" on all relationships
- Routing now uses current tech location over home base

***0.0.3***<br>
Project restructuring + frontend
- Fully backend-driven
- PostgreSQL over SQLite
- Map view via OpenStreetMap/Leaflet
- Vite + React + Tailwind frontend

***0.0.2***<br>
Started frontend
- FastAPI + React integration
- Technician + job CRUD via API
- Basic frontend displaying techs/jobs

***0.0.1***<br>
Initial commit
- Basic backend logic
- Proof of concept
</details>

## Roadmap

- [x] Drag-and-drop job assignment
- [x] Day picker with date-filtered views
- [x] Multi-select and batch operations
- [x] Tech timeline pane
- [x] Display filter window (time slot, job type, route criteria, tech)
- [x] Tech/staff search window (personnel)
- [x] Job search window (multi-criteria)
- [x] Map as real popup window (second monitor support)
- [x] Route criteria / management areas
- [x] Job evaluation (skill/route/time + distance)
- [x] Override warning on assignment mismatch
- [x] Automated dispatch (simulation engine with time-accelerated demo day)
- [x] WebSocket real-time updates (backend broadcaster complete)
- [x] Mobile responsive UI + touch drag-and-drop
- [x] Frontend sim control bar (start/pause/resume/stop, speed selector, virtual clock)
- [x] Overrun row highlighting (yellow/red at estimated/1.5× duration)
- [x] ML routing strategy (embedded model — travel + predicted completion time)
- [ ] God View debug overlay (reveal tech modifiers: speed_factor, skill_bonuses)
- [ ] Job visual column (per-job evaluation mode on tech grid)
- [ ] Dark/light theme toggle
- [ ] Account system with role-based access
- [ ] Column state persistence per user
- [ ] Mobile technician PWA
- [ ] Docker compose full stack
- [x] Hosted live demo

## Contributing

If you share the belief that simplicity empowers creativity, feel free to contribute.
- Submit a Pull Request
- Bug reports and feature requests

Please ensure your code follows the existing style.

