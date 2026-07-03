-- Port of backend/templates/_win_job_detail.html — Job Detail floating window.
-- Mirrors FastAPI /window/job/{job_id}: one job + its (0..1) assignment/tech.
-- Missing job -> not-found body (FastAPI 404 / PostgREST 200+body; status is proxy-layer).
-- Conditional sections render only when the field is truthy (non-null AND non-empty/non-zero,
-- matching Jinja truthiness): phone/email/desc/notes/timestamps, travel-time `or '—'` (0 -> '—').
-- Python "%.4f"/"%.1f" -> to_char FM990.0000/FM990.0 (the forced 0 before '.' keeps leading zero).
create or replace function api.job_detail(p_job_id integer)
returns "text/html" language sql stable as $$
	select coalesce(
		(select
			'<div class="jd-content">'
			|| '<div class="jd-header-row">'
			|| '<span class="pill pill--' || lower(j.status::text) || '">'
				|| replace(j.status::text, '_', ' ') || '</span>'
			|| '<span class="jd-type">' || lower(j.job_type::text) || '</span>'
			|| '<span class="jd-priority pri pri--' || j.priority || '">Priority ' || j.priority || '</span>'
			|| '</div>'
			-- Customer
			|| '<div class="jd-section"><div class="jd-section-title">Customer</div>'
			|| '<div class="jd-field"><span class="jd-label">Name</span><span class="jd-value">'
				|| api.html_escape(j.customer_name) || '</span></div>'
			|| case when nullif(j.customer_phone, '') is not null then
				'<div class="jd-field"><span class="jd-label">Phone</span><span class="jd-value mono">'
				|| api.html_escape(j.customer_phone) || '</span></div>' else '' end
			|| case when nullif(j.customer_email, '') is not null then
				'<div class="jd-field"><span class="jd-label">Email</span><span class="jd-value mono">'
				|| api.html_escape(j.customer_email) || '</span></div>' else '' end
			|| '</div>'
			-- Service Location
			|| '<div class="jd-section"><div class="jd-section-title">Service Location</div>'
			|| '<div class="jd-field"><span class="jd-label">Address</span><span class="jd-value">'
				|| api.html_escape(j.service_address) || '</span></div>'
			|| '<div class="jd-field"><span class="jd-label">City / Zip</span><span class="jd-value">'
				|| api.html_escape(coalesce(j.service_city, '')) || ' ' || api.html_escape(coalesce(j.service_zip, '')) || '</span></div>'
			|| '<div class="jd-field"><span class="jd-label">Route</span><span class="jd-value mono">'
				|| coalesce(api.html_escape(nullif(j.route_criteria, '')), '—') || '</span></div>'
			|| '<div class="jd-field"><span class="jd-label">Lat / Lon</span><span class="jd-value mono">'
				|| to_char(j.latitude, 'FM9990.0000') || ', ' || to_char(j.longitude, 'FM9990.0000') || '</span></div>'
			|| '</div>'
			-- Schedule
			|| '<div class="jd-section"><div class="jd-section-title">Schedule</div>'
			|| '<div class="jd-field"><span class="jd-label">Date</span><span class="jd-value">'
				|| coalesce(to_char(j.scheduled_date at time zone 'UTC', 'YYYY-MM-DD'), '—') || '</span></div>'
			|| '<div class="jd-field"><span class="jd-label">Time Slot</span><span class="jd-value mono">'
				|| case when nullif(j.time_slot_start, '') is not null and nullif(j.time_slot_end, '') is not null
					then j.time_slot_start || '–' || j.time_slot_end else '—' end || '</span></div>'
			|| '<div class="jd-field"><span class="jd-label">Duration</span><span class="jd-value">'
				|| j.estimated_duration || ' min</span></div>'
			|| '</div>'
			-- Assignment
			|| '<div class="jd-section"><div class="jd-section-title">Assignment</div>'
			|| '<div class="jd-field"><span class="jd-label">Tech</span><span class="jd-value">'
				|| case when a.id is null then 'Unassigned' else api.html_escape(tk.name) end || '</span></div>'
			|| case when a.id is not null then
				'<div class="jd-field"><span class="jd-label">ETA</span><span class="jd-value mono">'
				|| coalesce(to_char(a.estimated_arrival at time zone 'UTC', 'HH24:MI'), '—') || '</span></div>'
				|| '<div class="jd-field"><span class="jd-label">Travel</span><span class="jd-value">'
				|| case when coalesce(a.estimated_travel_time, 0) = 0 then '—' else a.estimated_travel_time::text end
				|| ' min · ' || to_char(coalesce(a.estimated_distance, 0), 'FM990.0') || ' mi</span></div>'
				|| case when coalesce(a.actual_duration_minutes, 0) <> 0 then
					'<div class="jd-field"><span class="jd-label">Sim duration</span><span class="jd-value">'
					|| a.actual_duration_minutes || ' min</span></div>' else '' end
			else '' end
			|| '</div>'
			-- Required Skills
			|| '<div class="jd-section"><div class="jd-section-title">Required Skills</div><div class="jd-skills">'
			|| coalesce((select string_agg('<span class="skill-chip">' || api.html_escape(value) || '</span>', '' order by ord)
				from jsonb_array_elements_text(j.required_skills) with ordinality x(value, ord)),
				'<span class="muted">None</span>')
			|| '</div></div>'
			-- Optional free-text sections
			|| case when nullif(j.description, '') is not null then
				'<div class="jd-section"><div class="jd-section-title">Description</div><div class="jd-text">'
				|| api.html_escape(j.description) || '</div></div>' else '' end
			|| case when nullif(j.special_instructions, '') is not null then
				'<div class="jd-section"><div class="jd-section-title">Special Instructions</div>'
				|| '<div class="jd-text jd-text--warning">' || api.html_escape(j.special_instructions) || '</div></div>' else '' end
			|| case when nullif(j.notes, '') is not null then
				'<div class="jd-section"><div class="jd-section-title">Notes</div><div class="jd-text">'
				|| api.html_escape(j.notes) || '</div></div>' else '' end
			-- Timestamps
			|| '<div class="jd-section jd-timestamps">'
			|| '<div class="jd-field"><span class="jd-label">Created</span><span class="jd-value mono">'
				|| coalesce(to_char(j.created_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI'), '—') || '</span></div>'
			|| case when j.started_at is not null then
				'<div class="jd-field"><span class="jd-label">Started</span><span class="jd-value mono">'
				|| to_char(j.started_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || '</span></div>' else '' end
			|| case when j.completed_at is not null then
				'<div class="jd-field"><span class="jd-label">Completed</span><span class="jd-value mono">'
				|| to_char(j.completed_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || '</span></div>' else '' end
			|| '</div>'
			|| '</div>'
		from jobs j
		left join assignments a on a.job_id = j.id
		left join technicians tk on tk.id = a.technician_id
		where j.id = p_job_id),
		'<div class="win-empty">Job not found.</div>');
$$;

grant execute on function api.job_detail(integer) to web_anon;
