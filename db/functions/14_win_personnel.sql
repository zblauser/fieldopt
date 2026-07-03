-- Port of backend/templates/_win_personnel.html — the Personnel floating window.
-- Mirrors FastAPI /window/personnel: all technicians ordered by name, read-only.
-- DB enum columns UPPERCASE; template emits lowercase .value for pill class + data attrs.
-- Jinja autoescape ON -> html_escape mirrors it. skills/assigned_routes are jsonb arrays
-- joined with ', ' (array order preserved by jsonb_array_elements_text).
create or replace function api.personnel_window()
returns "text/html" language sql stable as $$
	with rows as (
		select
			t.name,
			'<tr class="grid-row personnel-row"'
			|| ' data-tech-id="' || t.id || '" data-tech-name="' || api.html_escape(t.name) || '"'
			|| ' data-search="' || api.html_escape(
				lower(coalesce(t.employee_id, '')) || ' ' || lower(t.name) || ' ' || t.id) || '"'
			|| ' ondblclick="locateTech(' || t.id || ')"'
			|| ' oncontextmenu="event.preventDefault(); showTechMenu(event, this)">'
			|| '<td class="num mono">' || api.html_escape(coalesce(nullif(t.employee_id, ''), t.id::text)) || '</td>'
			|| '<td>' || api.html_escape(t.name) || '</td>'
			|| '<td><span class="pill pill--' || lower(t.status::text) || '">'
				|| replace(t.status::text, '_', ' ') || '</span></td>'
			|| '<td class="mono">' || coalesce(t.shift_start, '') || '–' || coalesce(t.shift_end, '') || '</td>'
			|| '<td class="mono muted" style="max-width:180px; overflow:hidden; text-overflow:ellipsis;">'
				|| coalesce((select string_agg(api.html_escape(value), ', ')
					from jsonb_array_elements_text(t.skills) value), '') || '</td>'
			|| '<td class="mono muted" style="max-width:180px; overflow:hidden; text-overflow:ellipsis;">'
				|| coalesce((select string_agg(api.html_escape(value), ', ')
					from jsonb_array_elements_text(t.assigned_routes) value), '') || '</td>'
			|| '</tr>' as row_html
		from technicians t
	),
	c as (select count(*) as cnt from technicians)
	select
		'<div class="win-toolbar">'
		|| '<input type="text" class="win-input" placeholder="Search by name or ID…"'
			|| ' oninput="filterPersonnel(this.value)" id="personnel-search" autofocus>'
		|| '<span class="muted mono" id="personnel-count">' || c.cnt || ' / ' || c.cnt || '</span>'
		|| '</div>'
		|| '<div class="win-body"><table class="grid" id="personnel-table"><thead><tr>'
		|| '<th>ID</th><th>NAME</th><th>STATUS</th><th>SHIFT</th><th>SKILLS</th><th>ROUTES</th>'
		|| '</tr></thead><tbody>'
		|| coalesce((select string_agg(row_html, '' order by name) from rows), '')
		|| '</tbody></table></div>'
	from c;
$$;

grant execute on function api.personnel_window() to web_anon;
