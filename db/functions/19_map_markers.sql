-- Port of FastAPI /map/markers — native JSON (no text/html domain). Consumed by the
-- Leaflet map JS, so the contract is the JSON STRUCTURE/VALUES, not byte layout.
-- Uses json (not jsonb) to keep float8 shortest-repr for coords.
-- jobs: today's jobs (ordered like _todays_jobs). techs: active techs, lat/lng =
-- current_* or home_* (Python `or` -> non-null AND non-zero, else home; home is NOT NULL).
-- routes: per active tech WITH assignments, path = [tech point] + job points ordered by ETA;
-- done_count = completed/cancelled legs. job_number is str when set else the int id (mixed type).
create or replace function api.map_markers()
returns json language sql stable as $$
	with d as (select date_trunc('day', api.sim_now()) as day_start),
	tj as (
		select j.* from jobs j, d
		where j.scheduled_date >= d.day_start
		  and j.scheduled_date <  d.day_start + interval '1 day'
	),
	active as (select * from technicians where is_active),
	asg as (
		select a.technician_id, a.estimated_arrival,
			j2.latitude as jlat, j2.longitude as jlng, j2.scheduled_date as jsd, j2.status as jstatus
		from assignments a join jobs j2 on j2.id = a.job_id, d
		where j2.scheduled_date >= d.day_start
		  and j2.scheduled_date <  d.day_start + interval '1 day'
	)
	select json_build_object(
		'jobs', coalesce((
			select json_agg(json_build_object(
				'id', j.id,
				'job_number', case when nullif(j.job_number, '') is not null
					then to_json(j.job_number) else to_json(j.id) end,
				'customer', j.customer_name,
				'address', j.service_address,
				'status', lower(j.status::text),
				'lat', j.latitude,
				'lng', j.longitude
			) order by j.time_slot_start asc nulls first, j.id)
			from tj j), '[]'::json),
		'techs', coalesce((
			select json_agg(json_build_object(
				'id', t.id,
				'name', t.name,
				'status', lower(t.status::text),
				'lat', case when t.current_latitude is not null and t.current_latitude <> 0
					then t.current_latitude else t.home_latitude end,
				'lng', case when t.current_longitude is not null and t.current_longitude <> 0
					then t.current_longitude else t.home_longitude end
			))
			from active t
			where (case when t.current_latitude is not null and t.current_latitude <> 0
				then t.current_latitude else t.home_latitude end) is not null), '[]'::json),
		'routes', coalesce((
			select json_agg(json_build_object(
				'tech_id', t.id,
				'tech_name', t.name,
				'path', (
					select json_agg(pt order by ord)
					from (
						select 0 as ord, json_build_array(
							case when t.current_latitude is not null and t.current_latitude <> 0
								then t.current_latitude else t.home_latitude end,
							case when t.current_longitude is not null and t.current_longitude <> 0
								then t.current_longitude else t.home_longitude end) as pt
						union all
						select row_number() over (order by coalesce(a.estimated_arrival, a.jsd)) as ord,
							json_build_array(a.jlat, a.jlng) as pt
						from asg a where a.technician_id = t.id
					) pts
				),
				'done_count', (select count(*) from asg a
					where a.technician_id = t.id and lower(a.jstatus::text) in ('completed', 'cancelled'))
			))
			from active t
			where exists (select 1 from asg a where a.technician_id = t.id)), '[]'::json)
	);
$$;

grant execute on function api.map_markers() to web_anon;
