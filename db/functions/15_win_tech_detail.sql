-- Port of backend/templates/_win_tech_detail.html — Tech Detail floating window.
-- Mirrors FastAPI /window/tech/{tech_id}: one tech + today's assignments (this tech),
-- ordered by estimated_arrival nulls first. Missing tech -> the not-found body (FastAPI
-- sends it with 404; PostgREST returns 200 + same body — status handled at the proxy).
-- Chips render each element, or a "None" span when the jsonb array is empty.
-- Lat/Lon use Python "%.4f" -> to_char FM9990.0000 (coords are |x|>=1, no leading-zero gap).
create or replace function api.tech_detail(p_tech_id integer)
returns "text/html" language sql stable as $$
	select coalesce(
		(select
			'<div class="jd-content">'
			|| '<div class="jd-header-row">'
			|| '<span class="pill pill--' || lower(t.status::text) || '">'
				|| replace(t.status::text, '_', ' ') || '</span>'
			|| '<span class="jd-type mono">'
				|| api.html_escape(coalesce(nullif(t.employee_id, ''), '#' || t.id)) || '</span>'
			|| '</div>'
			-- Identity
			|| '<div class="jd-section"><div class="jd-section-title">Identity</div>'
			|| '<div class="jd-field"><span class="jd-label">Name</span><span class="jd-value">'
				|| api.html_escape(t.name) || '</span></div>'
			|| case when nullif(t.phone, '') is not null then
				'<div class="jd-field"><span class="jd-label">Phone</span><span class="jd-value mono">'
				|| api.html_escape(t.phone) || '</span></div>' else '' end
			|| case when nullif(t.email, '') is not null then
				'<div class="jd-field"><span class="jd-label">Email</span><span class="jd-value mono">'
				|| api.html_escape(t.email) || '</span></div>' else '' end
			|| '</div>'
			-- Schedule
			|| '<div class="jd-section"><div class="jd-section-title">Schedule</div>'
			|| '<div class="jd-field"><span class="jd-label">Shift</span><span class="jd-value mono">'
				|| coalesce(t.shift_start, '') || '–' || coalesce(t.shift_end, '') || '</span></div>'
			|| '<div class="jd-field"><span class="jd-label">Max jobs/day</span><span class="jd-value mono">'
				|| t.max_jobs_per_day || '</span></div>'
			|| '</div>'
			-- Home Base
			|| '<div class="jd-section"><div class="jd-section-title">Home Base</div>'
			|| '<div class="jd-field"><span class="jd-label">Address</span><span class="jd-value">'
				|| coalesce(api.html_escape(nullif(t.home_address, '')), '—') || '</span></div>'
			|| '<div class="jd-field"><span class="jd-label">Lat / Lon</span><span class="jd-value mono">'
				|| to_char(t.home_latitude, 'FM9990.0000') || ', '
				|| to_char(t.home_longitude, 'FM9990.0000') || '</span></div>'
			|| '</div>'
			-- Skills
			|| '<div class="jd-section"><div class="jd-section-title">Skills</div><div class="jd-skills">'
			|| coalesce((select string_agg('<span class="skill-chip">' || api.html_escape(value) || '</span>', '' order by ord)
				from jsonb_array_elements_text(t.skills) with ordinality x(value, ord)),
				'<span class="muted">None</span>')
			|| '</div></div>'
			-- Assigned Routes
			|| '<div class="jd-section"><div class="jd-section-title">Assigned Routes</div><div class="jd-skills">'
			|| coalesce((select string_agg('<span class="skill-chip">' || api.html_escape(value) || '</span>', '' order by ord)
				from jsonb_array_elements_text(t.assigned_routes) with ordinality x(value, ord)),
				'<span class="muted">None</span>')
			|| '</div></div>'
			-- Today's Assignments
			|| '<div class="jd-section"><div class="jd-section-title">Today''s Assignments ('
				|| asg.cnt || ')</div>'
			|| case when asg.cnt > 0 then
				'<table class="grid" style="font-size:var(--font-size-xs);">'
				|| '<thead><tr><th>JOB</th><th>ETA</th><th>STATUS</th><th>CUST</th></tr></thead><tbody>'
				|| asg.rows || '</tbody></table>'
			else '<span class="muted">None today.</span>' end
			|| '</div>'
			|| '</div>'
		from technicians t
		cross join lateral (
			select
				count(*) as cnt,
				string_agg(
					'<tr class="grid-row" ondblclick="openWindow(''job/' || j.id || ''', ''Job #'
						|| api.html_escape(coalesce(nullif(j.job_number, ''), j.id::text)) || ''')">'
					|| '<td class="num mono">' || api.html_escape(coalesce(nullif(j.job_number, ''), j.id::text)) || '</td>'
					|| '<td class="mono">' || coalesce(to_char(a.estimated_arrival at time zone 'UTC', 'HH24:MI'), '—') || '</td>'
					|| '<td><span class="pill pill--' || lower(j.status::text) || '">'
						|| replace(j.status::text, '_', ' ') || '</span></td>'
					|| '<td>' || api.html_escape(j.customer_name) || '</td>'
					|| '</tr>',
					'' order by a.estimated_arrival asc nulls first) as rows
			from assignments a
			join jobs j on j.id = a.job_id
			cross join (select date_trunc('day', api.sim_now()) as day_start) dd
			where a.technician_id = t.id
			  and j.scheduled_date >= dd.day_start
			  and j.scheduled_date <  dd.day_start + interval '1 day'
		) asg
		where t.id = p_tech_id),
		'<div class="win-empty">Tech not found.</div>');
$$;

grant execute on function api.tech_detail(integer) to web_anon;
