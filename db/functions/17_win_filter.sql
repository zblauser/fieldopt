-- Port of backend/templates/_win_filter.html — Filter floating window.
-- Mirrors FastAPI /window/filter: status/job_type from enum .value lists (enum_range gives
-- definition order == Python enum iteration order; lower() == .value), routes = distinct
-- route_criteria over TODAY's jobs sorted asc, techs all by name. All checkboxes checked.
create or replace function api.filter_window()
returns "text/html" language sql stable as $$
	with d as (select date_trunc('day', api.sim_now()) as day_start)
	select
		'<div class="win-body" style="padding:14px;">'
		|| '<p class="muted" style="margin-bottom:12px;font-size:var(--font-size-sm);">'
			|| 'Filters apply live to the Jobs grid. Multi-select with checkboxes.</p>'
		-- Status
		|| '<div class="filter-section"><div class="filter-section-head"><span>Status</span>'
		|| '<span class="filter-section-actions"><button onclick="filterCheckAll(''status'', true)">All</button>'
			|| '<button onclick="filterCheckAll(''status'', false)">None</button></span></div>'
		|| '<div class="filter-checks">'
		|| (select string_agg(
				'<label><input type="checkbox" name="f-status" value="' || v || '" checked onchange="applyFilterMulti()">' || v || '</label>',
				'' order by ord)
			from unnest(enum_range(null::public.jobstatus)) with ordinality e(s, ord),
				 lateral (select lower(s::text) as v) lv)
		|| '</div></div>'
		-- Job type
		|| '<div class="filter-section"><div class="filter-section-head"><span>Job type</span>'
		|| '<span class="filter-section-actions"><button onclick="filterCheckAll(''job_type'', true)">All</button>'
			|| '<button onclick="filterCheckAll(''job_type'', false)">None</button></span></div>'
		|| '<div class="filter-checks">'
		|| (select string_agg(
				'<label><input type="checkbox" name="f-job_type" value="' || v || '" checked onchange="applyFilterMulti()">' || v || '</label>',
				'' order by ord)
			from unnest(enum_range(null::public.jobtype)) with ordinality e(t, ord),
				 lateral (select lower(t::text) as v) lv)
		|| '</div></div>'
		-- Route
		|| '<div class="filter-section"><div class="filter-section-head"><span>Route</span>'
		|| '<span class="filter-section-actions"><button onclick="filterCheckAll(''route'', true)">All</button>'
			|| '<button onclick="filterCheckAll(''route'', false)">None</button></span></div>'
		|| '<div class="filter-checks">'
		|| coalesce((select string_agg(
				'<label><input type="checkbox" name="f-route" value="' || api.html_escape(rc) || '" checked onchange="applyFilterMulti()">' || api.html_escape(rc) || '</label>',
				'' order by rc)
			from (
				select distinct j.route_criteria as rc
				from jobs j, d
				where j.scheduled_date >= d.day_start
				  and j.scheduled_date <  d.day_start + interval '1 day'
				  and nullif(j.route_criteria, '') is not null
			) r), '')
		|| '</div></div>'
		-- Technician
		|| '<div class="filter-section"><div class="filter-section-head"><span>Technician</span>'
		|| '<span class="filter-section-actions"><button onclick="filterCheckAll(''tech_id'', true)">All</button>'
			|| '<button onclick="filterCheckAll(''tech_id'', false)">None</button></span></div>'
		|| '<div class="filter-checks">'
		|| '<label><input type="checkbox" name="f-tech_id" value="unassigned" checked onchange="applyFilterMulti()">— Unassigned —</label>'
		|| coalesce((select string_agg(
				'<label><input type="checkbox" name="f-tech_id" value="' || tk.id || '" checked onchange="applyFilterMulti()">' || api.html_escape(tk.name) || '</label>',
				'' order by tk.name)
			from technicians tk), '')
		|| '</div></div>'
		-- Footer buttons
		|| '<div style="display:flex;gap:8px;margin-top:12px;">'
		|| '<button class="btn" onclick="filterResetAll()">Reset all</button>'
		|| '<button class="btn btn--primary" onclick="filterClearAll()">Clear (show all)</button>'
		|| '</div>'
		|| '</div>';
$$;

grant execute on function api.filter_window() to web_anon;
