-- Port of backend/templates/_tech_list.html — the polled techs fragment.
-- Mirrors the FastAPI /techs route: all technicians, ordered by name.
-- DB enum columns are UPPERCASE (status='AVAILABLE'); pill class + data attr use lowercase.
create or replace function api.tech_list()
returns "text/html" language sql stable as $$
	select
		'<table class="grid tech-grid"><thead><tr>'
		|| '<th class="num">TECH ID</th><th>NAME</th><th>STATUS</th>'
		|| '<th>SHIFT</th><th class="num">JOBS A:C</th><th>ROUTES</th>'
		|| '</tr></thead><tbody>'
		|| coalesce(
			string_agg(row_html, '' order by name),
			'<tr><td colspan="6" class="empty">No technicians.</td></tr>')
		|| '</tbody></table>'
	from (
		select
			t.name,
			'<tr class="grid-row drop-target"'
			|| ' data-tech-id="' || t.id || '"'
			|| ' data-tech-name="' || api.html_escape(t.name) || '"'
			|| ' data-tech-status="' || lower(t.status::text) || '"'
			|| ' ondblclick="openWindow(''tech/' || t.id || ''', ''' || api.html_escape(t.name) || ''')"'
			|| ' oncontextmenu="event.preventDefault(); showTechMenu(event, this)">'
			|| '<td class="num mono">' || api.html_escape(coalesce(t.employee_id, t.id::text)) || '</td>'
			|| '<td>' || api.html_escape(t.name) || '</td>'
			|| '<td><span class="pill pill--' || lower(t.status::text) || '">'
				|| replace(t.status::text, '_', ' ') || '</span></td>'
			|| '<td class="mono">' || coalesce(t.shift_start, '') || '–' || coalesce(t.shift_end, '') || '</td>'
			|| '<td class="num mono">' || cnt.assigned || ':' || cnt.completed || '</td>'
			|| '<td class="routes mono">' || coalesce(
				(select string_agg(api.html_escape(value), ', ')
				 from jsonb_array_elements_text(t.assigned_routes)), '') || '</td>'
			|| '</tr>' as row_html
		from technicians t
		cross join lateral (
			select
				count(*) filter (where j.status::text in ('ASSIGNED', 'IN_PROGRESS')) as assigned,
				count(*) filter (where j.status::text = 'COMPLETED') as completed
			from assignments a
			join jobs j on j.id = a.job_id
			where a.technician_id = t.id
		) cnt
	) rows;
$$;

grant execute on function api.tech_list() to web_anon;
