-- Port of backend/templates/_win_search.html — Search floating window.
-- Mirrors FastAPI /window/search: a criteria form (echoes the 9 params back into inputs/
-- selects) + a results table shown only when any criterion is set. Query filters mirror
-- search_window(): q -> ilike over job_number/customer/address; date_from/to; job_id/tech_id
-- (non-int -> no filter, matching Python's ValueError pass); status/job_type via enum upper;
-- route exact. Order scheduled_date desc nulls last, id desc, limit 200.
create or replace function api.search_window(
	p_q         text default '',
	p_date_from text default '',
	p_date_to   text default '',
	p_job_id    text default '',
	p_tech_id   text default '',
	p_customer  text default '',
	p_status    text default '',
	p_job_type  text default '',
	p_route     text default ''
)
returns "text/html" language sql stable as $$
	with flags as (
		select (p_q <> '' or p_date_from <> '' or p_date_to <> '' or p_job_id <> ''
			or p_tech_id <> '' or p_customer <> '' or p_status <> '' or p_job_type <> ''
			or p_route <> '') as anyc
	),
	res as (
		select j.scheduled_date as sd, j.id as jid,
			'<tr class="grid-row job-row search-result-row" data-job-id="' || j.id || '"'
			|| ' ondblclick="openWindow(''job/' || j.id || ''', ''Job #'
				|| api.html_escape(coalesce(nullif(j.job_number, ''), j.id::text)) || ''')"'
			|| ' oncontextmenu="event.preventDefault(); showJobMenu(event, this)"'
			|| ' data-job-number="' || api.html_escape(coalesce(nullif(j.job_number, ''), j.id::text)) || '"'
			|| ' data-job-status="' || lower(j.status::text) || '"'
			|| ' data-job-customer="' || api.html_escape(j.customer_name) || '">'
			|| '<td class="num mono">' || j.id || '</td>'
			|| '<td class="mono">' || coalesce(to_char(j.scheduled_date at time zone 'UTC', 'YYYY-MM-DD'), '—') || '</td>'
			|| '<td><span class="pill pill--' || lower(j.status::text) || '">'
				|| replace(j.status::text, '_', ' ') || '</span></td>'
			|| '<td>' || lower(j.job_type::text) || '</td>'
			|| '<td class="num mono pri pri--' || j.priority || '">' || j.priority || '</td>'
			|| '<td>' || api.html_escape(j.customer_name) || '</td>'
			|| '<td class="mono">' || coalesce(api.html_escape(nullif(j.route_criteria, '')), '—') || '</td>'
			|| '<td class="addr">' || api.html_escape(j.service_address) || '</td>'
			|| '</tr>' as row_html
		from jobs j, flags
		where flags.anyc
		  and (p_q = '' or (j.job_number ilike '%' || p_q || '%'
				or j.customer_name ilike '%' || p_q || '%'
				or j.service_address ilike '%' || p_q || '%'))
		  and (p_date_from = '' or j.scheduled_date >= (p_date_from::timestamp at time zone 'UTC'))
		  and (p_date_to   = '' or j.scheduled_date <  (p_date_to::timestamp at time zone 'UTC') + interval '1 day')
		  and (p_job_id = '' or p_job_id !~ '^[0-9]+$' or j.id = p_job_id::int)
		  and (p_customer = '' or j.customer_name ilike '%' || p_customer || '%')
		  and (p_status = '' or j.status::text = upper(p_status))
		  and (p_job_type = '' or j.job_type::text = upper(p_job_type))
		  and (p_route = '' or j.route_criteria = p_route)
		  and (p_tech_id = '' or p_tech_id !~ '^[0-9]+$'
				or j.id in (select a.job_id from assignments a where a.technician_id = p_tech_id::int))
		order by j.scheduled_date desc nulls last, j.id desc
		limit 200
	),
	agg as (
		select count(*)::int as cnt,
			coalesce(string_agg(row_html, '' order by sd desc nulls last, jid desc), '') as rows_html
		from res
	)
	select
		'<form class="search-criteria"'
		|| ' hx-get="/window/search" hx-target=".float-win[data-key=''search''] .float-win-body" hx-swap="innerHTML"'
		|| ' hx-trigger="submit, input changed delay:400ms from:input, change from:select">'
		|| '<div class="cr-row">'
		|| '<label>Job #<input type="text" name="job_id" value="' || api.html_escape(p_job_id) || '"></label>'
		|| '<label>Customer<input type="text" name="customer" value="' || api.html_escape(p_customer) || '"></label>'
		|| '<label>Address / Q<input type="text" name="q" value="' || api.html_escape(p_q) || '"></label>'
		|| '</div>'
		|| '<div class="cr-row">'
		|| '<label>Date from<input type="date" name="date_from" value="' || api.html_escape(p_date_from) || '"></label>'
		|| '<label>Date to<input type="date" name="date_to" value="' || api.html_escape(p_date_to) || '"></label>'
		|| '<label>Status<select name="status"><option value="">Any</option>'
		|| (select string_agg('<option value="' || v || '" '
				|| case when p_status = v then 'selected' else '' end || '>' || v || '</option>', '' order by ord)
			from unnest(enum_range(null::public.jobstatus)) with ordinality e(s, ord), lateral (select lower(s::text) v) lv)
		|| '</select></label>'
		|| '</div>'
		|| '<div class="cr-row">'
		|| '<label>Type<select name="job_type"><option value="">Any</option>'
		|| (select string_agg('<option value="' || v || '" '
				|| case when p_job_type = v then 'selected' else '' end || '>' || v || '</option>', '' order by ord)
			from unnest(enum_range(null::public.jobtype)) with ordinality e(t, ord), lateral (select lower(t::text) v) lv)
		|| '</select></label>'
		|| '<label>Tech<select name="tech_id"><option value="">Any</option>'
		|| coalesce((select string_agg('<option value="' || tk.id || '" '
				|| case when p_tech_id = tk.id::text then 'selected' else '' end || '>'
				|| api.html_escape(tk.name) || '</option>', '' order by tk.name)
			from technicians tk), '')
		|| '</select></label>'
		|| '<label>Route<input type="text" name="route" value="' || api.html_escape(p_route) || '"></label>'
		|| '</div>'
		|| '<div class="cr-actions">'
		|| '<button class="btn" type="submit">Search</button>'
		|| '<button class="btn" type="button" onclick="clearSearchForm(this)">Clear</button>'
		|| case when flags.anyc then
			'<span class="muted mono">' || agg.cnt || ' result'
			|| case when agg.cnt <> 1 then 's' else '' end
			|| case when agg.cnt = 200 then ' (limit)' else '' end || '</span>'
		else '' end
		|| '</div>'
		|| '</form>'
		|| '<div class="win-body" style="border-top:1px solid var(--border-light);">'
		|| case
			when agg.cnt > 0 then
				'<table class="grid"><thead><tr><th>JOB ID</th><th>DATE</th><th>STATUS</th><th>TYPE</th>'
				|| '<th>PRI</th><th>CUSTOMER</th><th>RTEC</th><th>ADDRESS</th></tr></thead><tbody>'
				|| agg.rows_html || '</tbody></table>'
			when flags.anyc then '<div class="win-empty">No matches.</div>'
			else '<div class="win-empty">Enter criteria above and click Search.<br>Searches across all dates (limit 200).</div>'
		end
		|| '</div>'
	from flags, agg;
$$;

grant execute on function api.search_window(text, text, text, text, text, text, text, text, text) to web_anon;
