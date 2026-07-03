-- Port of backend/templates/_job_table.html — the polled jobs grid.
-- Mirrors FastAPI /jobs (jobs_fragment + _todays_jobs in api/routes/htmx.py):
--   today's jobs (sim-clock day) with optional status/job_type/tech_id/route filters,
--   ordered by time_slot_start (nulls first), id. One assignment per job (job_id UNIQUE).
--   `overdue` row flag: slot_end passed vs sim now-minutes, unless completed/cancelled.
-- DB enum columns are UPPERCASE; template emits lowercase .value for classes/attrs and
-- upper+space for the status pill text. Jinja autoescape is ON -> html_escape mirrors it.
create or replace function api.job_table(
	p_status   text default '',
	p_job_type text default '',
	p_tech_id  text default '',
	p_route    text default ''
)
returns "text/html" language sql stable as $$
	with clk as (
		select api.sim_now() as t
	),
	d as (
		select
			date_trunc('day', t) as day_start,
			extract(hour   from (t at time zone 'UTC')) * 60
			+ extract(minute from (t at time zone 'UTC')) as now_min
		from clk
	),
	rows as (
		select
			j.time_slot_start as ord_slot,
			j.id as ord_id,
			'<tr class="grid-row job-row '
			|| case when
				j.time_slot_end ~ '^[0-9]{2}:[0-9]{2}$'
				and d.now_min > (split_part(j.time_slot_end, ':', 1)::int * 60
				                 + split_part(j.time_slot_end, ':', 2)::int)
				and j.status::text not in ('COMPLETED', 'CANCELLED')
			then 'job-row--overdue' else '' end
			|| '"'
			|| ' data-job-id="' || j.id || '"'
			|| ' data-job-number="' || api.html_escape(coalesce(nullif(j.job_number, ''), j.id::text)) || '"'
			|| ' data-job-status="' || lower(j.status::text) || '"'
			|| ' data-job-customer="' || api.html_escape(j.customer_name) || '"'
			|| ' ondblclick="openWindow(''job/' || j.id || ''', ''Job #'
				|| api.html_escape(coalesce(nullif(j.job_number, ''), j.id::text)) || ''')"'
			|| ' oncontextmenu="event.preventDefault(); showJobMenu(event, this)">'
			|| '<td class="num mono">' || j.id || '</td>'
			|| '<td>' || lower(j.job_type::text) || '</td>'
			|| '<td><span class="pill pill--' || lower(j.status::text) || '">'
				|| replace(j.status::text, '_', ' ') || '</span></td>'
			|| '<td>' || case when a.id is null then '—' else api.html_escape(t.name) end || '</td>'
			|| '<td class="num mono pri pri--' || j.priority || '">' || j.priority || '</td>'
			|| '<td>' || api.html_escape(j.customer_name) || '</td>'
			|| '<td class="mono">' || coalesce(api.html_escape(nullif(j.route_criteria, '')), '—') || '</td>'
			|| '<td class="addr">' || api.html_escape(j.service_address) || '</td>'
			|| '<td class="mono">' || coalesce(nullif(j.time_slot_start, ''), '—')
				|| case when nullif(j.time_slot_end, '') is not null
				        then '–' || j.time_slot_end else '' end || '</td>'
			|| '</tr>' as row_html
		from jobs j
		cross join d
		left join assignments a on a.job_id = j.id
		left join technicians t on t.id = a.technician_id
		where j.scheduled_date >= d.day_start
		  and j.scheduled_date <  d.day_start + interval '1 day'
		  and (p_status   = '' or j.status::text   = upper(p_status))
		  and (p_job_type = '' or j.job_type::text = upper(p_job_type))
		  and (p_route    = '' or j.route_criteria = p_route)
		  and (
			p_tech_id = ''
			or (p_tech_id = 'unassigned' and a.id is null)
			or (p_tech_id ~ '^[0-9]+$' and a.technician_id = p_tech_id::int)
			or (p_tech_id <> 'unassigned' and p_tech_id !~ '^[0-9]+$')
		  )
	)
	select
		'<table class="grid job-grid"><thead><tr>'
		|| '<th class="num">JOB ID</th><th>TYPE</th><th>STATUS</th><th>TECH</th>'
		|| '<th class="num">PRI</th><th>CUSTOMER</th><th>RTEC</th><th>ADDRESS</th><th>SLOT</th>'
		|| '</tr></thead><tbody>'
		|| coalesce(
			string_agg(row_html, '' order by ord_slot asc nulls first, ord_id),
			'<tr><td colspan="9" class="empty">No jobs for today.</td></tr>')
		|| '</tbody></table>'
	from rows;
$$;

grant execute on function api.job_table(text, text, text, text) to web_anon;
