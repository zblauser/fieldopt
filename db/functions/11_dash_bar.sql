-- Port of backend/templates/_dash_bar.html — the polled counts fragment.
-- Mirrors FastAPI /counts (_counts + counts_fragment in api/routes/htmx.py):
--   job counts are over TODAY's jobs (scheduled_date within the sim-clock day);
--   tech counts are over active techs by status.
-- DB enum columns are UPPERCASE (status='PENDING'); template labels/filters lowercase.
create or replace function api.dash_bar()
returns "text/html" language sql stable as $$
	with day as (
		select date_trunc('day', api.sim_now()) as start
	),
	jc as (
		select
			count(*) filter (where j.status = 'PENDING')     as pending,
			count(*) filter (where j.status = 'ASSIGNED')    as assigned,
			count(*) filter (where j.status = 'IN_PROGRESS') as in_progress,
			count(*) filter (where j.status = 'COMPLETED')   as completed,
			count(*) filter (where j.status = 'ON_HOLD')     as on_hold,
			count(*) filter (where j.status = 'CANCELLED')   as cancelled
		from jobs j, day
		where j.scheduled_date >= day.start
		  and j.scheduled_date <  day.start + interval '1 day'
	),
	tc as (
		select
			count(*) filter (where t.status = 'AVAILABLE')                 as tech_available,
			count(*) filter (where t.status in ('OFF_DUTY', 'ON_BREAK'))   as tech_off
		from technicians t
		where t.is_active
	)
	select
		  '<div class="dash-cell" data-filter="status=pending" onclick="toggleDashFilter(this)">'
		|| '<div class="dash-count dash-count--danger">' || jc.pending || '</div><div class="dash-label">Unassigned</div>'
		|| '</div>'
		|| '<div class="dash-cell" data-filter="status=assigned" onclick="toggleDashFilter(this)">'
		|| '<div class="dash-count dash-count--info">' || jc.assigned || '</div><div class="dash-label">Assigned</div>'
		|| '</div>'
		|| '<div class="dash-cell" data-filter="status=in_progress" onclick="toggleDashFilter(this)">'
		|| '<div class="dash-count dash-count--warning">' || jc.in_progress || '</div><div class="dash-label">In Progress</div>'
		|| '</div>'
		|| '<div class="dash-cell" data-filter="status=completed" onclick="toggleDashFilter(this)">'
		|| '<div class="dash-count dash-count--success">' || jc.completed || '</div><div class="dash-label">Completed</div>'
		|| '</div>'
		|| '<div class="dash-cell" data-filter="status=on_hold" onclick="toggleDashFilter(this)">'
		|| '<div class="dash-count dash-count--muted">' || jc.on_hold || '</div><div class="dash-label">On Hold</div>'
		|| '</div>'
		|| '<div class="dash-cell" data-filter="status=cancelled" onclick="toggleDashFilter(this)">'
		|| '<div class="dash-count dash-count--danger">' || jc.cancelled || '</div><div class="dash-label">Failed</div>'
		|| '</div>'
		|| '<div class="header-divider"></div>'
		|| '<div class="dash-cell">'
		|| '<div class="dash-count dash-count--success">' || tc.tech_available || '</div><div class="dash-label">Techs Active</div>'
		|| '</div>'
		|| '<div class="dash-cell">'
		|| '<div class="dash-count dash-count--muted">' || tc.tech_off || '</div><div class="dash-label">Off Duty</div>'
		|| '</div>'
	from jc, tc;
$$;

grant execute on function api.dash_bar() to web_anon;
