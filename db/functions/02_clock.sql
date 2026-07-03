-- Pg-native virtual clock (replaces backend/simulation/clock.py singleton).
-- Path C REDESIGNS the clock: the Python continuous wall*speed interpolation is dropped
-- for a DISCRETE stepped clock — a stored virtual_now that api.sim_tick() advances.
-- The tick is SCHEDULER-AGNOSTIC (pg_cron OR external cron OR sidecar just CALL it), because
-- pg_cron isn't in postgres:15-alpine and managed PG may lack it (see release-packaging plan).

-- Single-row clock state. Seeded with one row (defaults = REAL mode).
create table if not exists api.sim_state (
	id boolean primary key default true check (id),   -- enforces at most one row
	virtual_now timestamptz
);
-- Phase 4 columns (idempotent add for existing deployments).
alter table api.sim_state add column if not exists mode      text             not null default 'real';   -- 'real'|'simulated'
alter table api.sim_state add column if not exists is_paused boolean          not null default false;
alter table api.sim_state add column if not exists speed     double precision not null default 1.0;      -- virtual seconds per wall second
insert into api.sim_state (id) values (true) on conflict do nothing;

-- Current virtual time. REAL mode -> wall clock; SIMULATED -> stored virtual_now.
-- Falls back to now() when no row / no virtual_now (keeps render ports diffing clean in real mode).
create or replace function api.sim_now()
returns timestamptz language sql stable as $$
	select coalesce(
		(select case when mode = 'simulated' then virtual_now else now() end from api.sim_state limit 1),
		now());
$$;

-- Advance the virtual clock by (speed * elapsed-wall-seconds). Called by whatever scheduler
-- is wired (pg_cron every ~10s -> sim_tick(10)); no-op unless simulated and not paused.
-- SECURITY DEFINER so an unprivileged scheduler role can drive it.
create or replace function api.sim_tick(p_wall_seconds double precision default 10)
returns void language sql volatile security definer set search_path = api, public as $$
	update api.sim_state
	set virtual_now = virtual_now + make_interval(secs => speed * p_wall_seconds)
	where mode = 'simulated' and not is_paused and virtual_now is not null;
$$;

-- Deploy config (NOT runtime state): whether this is a demo build. GUC set per-deploy via
-- `ALTER DATABASE <db> SET app.is_demo = 'true'` (raw + docker share the same mechanism).
-- Runtime clock state lives in sim_state; this constant governs whether the sim UI exists.
create or replace function api.is_demo()
returns boolean language sql stable as $$
	select coalesce(current_setting('app.is_demo', true)::boolean, false);
$$;

grant select on api.sim_state to web_anon;
grant execute on function api.sim_now() to web_anon;
grant execute on function api.sim_tick(double precision) to web_anon;
grant execute on function api.is_demo() to web_anon;
