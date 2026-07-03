-- Port of backend/templates/_timeline.html + _timeline_rows/timeline_fragment.
-- Pure-SVG per-tech assignment timeline. Constants mirror the template exactly:
--   row_h=22, name_w=140, px_per_min=1.2 -> chart_w=540*1.2=648, svg_w=800.0 (const).
-- Coordinates are floats -> api.py_float() reproduces Python's str(float) '.0' repr.
-- Blocks: eta = estimated_arrival or scheduled_date; offset from 08:00; width>=15;
--   ordered by offset_min within a tech; techs ordered by name.
-- p_selected: optional comma-separated tech ids to keep (mirrors ?selected=).
create or replace function api.timeline(p_selected text default '')
returns "text/html" language sql stable as $$
	with clk as (
		select api.sim_now() as t
	),
	d as (
		select
			date_trunc('day', t) as day_start,
			greatest(0,
				(extract(hour from (t at time zone 'UTC'))::int - 8) * 60
				+ extract(minute from (t at time zone 'UTC'))::int) as now_off
		from clk
	),
	techs as (
		select id, name, (row_number() over (order by name) - 1)::int as idx
		from technicians
		where is_active
		  and (p_selected = '' or id = any (
				string_to_array(p_selected, ',')::int[]))
	),
	nrows as (
		select count(*)::int as n, count(*)::int * 22 + 28 as svg_h from techs
	),
	-- per-block html, keyed to its tech row's y-position (needs techs.idx)
	blk as (
		select
			tk.idx,
			bo.offset_min,
			'<g class="tl-block tl-block--' || lower(j.status::text) || '">'
			|| '<title>#' || api.html_escape(coalesce(nullif(j.job_number, ''), j.id::text))
				|| ' ' || api.html_escape(j.customer_name)
				|| ' — ETA ' || to_char(bo.eta at time zone 'UTC', 'HH24:MI')
				|| ' (' || trunc(bo.width_min)::bigint || 'm)</title>'
			|| '<rect x="' || api.py_float(140 + bo.offset_min * 1.2) || '"'
				|| ' y="' || (24 + tk.idx * 22 + 3) || '"'
				|| ' width="' || api.py_float(bo.width_min * 1.2) || '"'
				|| ' height="15" rx="2"/>'
			|| case when bo.width_min * 1.2 > 36 then
				'<text x="' || api.py_float(140 + bo.offset_min * 1.2 + 4) || '"'
				|| ' y="' || (24 + tk.idx * 22 + 14) || '" class="tl-block-label">#'
				|| api.html_escape(coalesce(nullif(j.job_number, ''), j.id::text)) || '</text>'
			else '' end
			|| '</g>' as block_html
		from assignments a
		join jobs j on j.id = a.job_id
		join techs tk on tk.id = a.technician_id
		cross join d
		cross join lateral (
			select
				coalesce(a.estimated_arrival, j.scheduled_date) as eta,
				greatest(0, extract(epoch from
					(coalesce(a.estimated_arrival, j.scheduled_date) - d.day_start)) / 60.0 - 480) as offset_min,
				greatest(15, coalesce(a.actual_duration_minutes, j.estimated_duration, 60)::float8) as width_min
		) bo
		where j.scheduled_date >= d.day_start
		  and j.scheduled_date <  d.day_start + interval '1 day'
		  and coalesce(a.estimated_arrival, j.scheduled_date) is not null
	)
	select
		'<div class="timeline-wrap">'
		|| '<svg class="timeline" width="800.0" height="' || nrows.svg_h || '"'
			|| ' viewBox="0 0 800.0 ' || nrows.svg_h || '" preserveAspectRatio="xMinYMin meet">'
		|| '<!-- Hour grid -->'
		|| (select string_agg(
				'<line x1="' || api.py_float(140 + g.i * 72.0) || '" y1="20"'
					|| ' x2="' || api.py_float(140 + g.i * 72.0) || '" y2="' || nrows.svg_h || '" class="tl-grid"/>'
				|| '<text x="' || api.py_float(140 + g.i * 72.0 + 2) || '" y="14" class="tl-hour">'
					|| to_char(8 + g.i, 'FM00') || ':00</text>',
				'' order by g.i)
			from generate_series(0, 9) as g(i))
		|| '<!-- Rows -->'
		|| coalesce((select string_agg(
				'<text x="6" y="' || (24 + tk.idx * 22 + 14) || '" class="tl-name">'
					|| api.html_escape(tk.name) || '</text>'
				|| '<line x1="140" y1="' || (24 + tk.idx * 22 + 21) || '"'
					|| ' x2="800.0" y2="' || (24 + tk.idx * 22 + 21) || '" class="tl-rowline"/>'
				|| coalesce((select string_agg(b.block_html, '' order by b.offset_min)
							 from blk b where b.idx = tk.idx), ''),
				'' order by tk.idx)
			from techs tk), '')
		|| '<!-- Now marker -->'
		|| case when d.now_off < 540 then
			'<line x1="' || api.py_float(140 + d.now_off * 1.2) || '" y1="18"'
			|| ' x2="' || api.py_float(140 + d.now_off * 1.2) || '" y2="' || nrows.svg_h || '" class="tl-now"/>'
		else '' end
		|| '</svg></div>'
	from nrows, d;
$$;

grant execute on function api.timeline(text) to web_anon;
