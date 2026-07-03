-- Port of POST /assign (backend/api/routes/htmx.py:260) — the assignment write path.
-- SLICE 1 (this file, current): candoo skill/route checks + override modal (deterministic,
--   byte-verifiable) AND the mutation (reassign/create + toast + HX-Trigger refreshAll).
-- Deferred (Phase 4, flagged): demo-lock (needs sim clock mode/paused) — skipped = real mode,
--   matches non-demo app; actual_duration_minutes = sample_duration (numpy PCG64 lognormal on
--   Python tuple-hash seed) is NOT reproducible in SQL and is sim-internal -> stored NULL here,
--   Phase 4 sim owns duration. estimated_arrival uses api.sim_now() (live -> not byte-comparable,
--   but not in any response). haversine + travel_time are deterministic and match Python.
-- _candoo_issues: skill missing = required_skills not in tech.skills (order preserved);
--   route pass = job has NO route_criteria (advisory-permissive, mirrors Slice-6 backend).
-- Toast msg is raw (FastAPI f-string, NOT autoescaped); modal IS autoescaped (template).
-- SECURITY DEFINER: the write runs as the function owner (owns the tables); web_anon gets
-- only EXECUTE, never direct table writes. search_path pinned to avoid definer hijack.
create or replace function api.assign(p_job_id integer, p_tech_id integer, p_override integer default 0)
returns "text/html" language plpgsql volatile
security definer set search_path = api, public as $fn$
declare
	j            jobs%rowtype;
	t            technicians%rowtype;
	missing      text[];
	skill_pass   boolean;
	route_pass   boolean;
	skill_label  text;
	route_label  text;
	num          text;
	existing_tid integer;
	olat         double precision;
	olon         double precision;
	dist         double precision;
	travel       integer;
begin
	select * into j from jobs where id = p_job_id;
	if not found then raise exception 'Job or tech not found' using errcode = 'P0002'; end if;
	select * into t from technicians where id = p_tech_id;
	if not found then raise exception 'Job or tech not found' using errcode = 'P0002'; end if;

	num := coalesce(nullif(j.job_number, ''), j.id::text);

	-- ── CanDo checks ────────────────────────────────────────────────────────
	missing := array(
		select s from jsonb_array_elements_text(coalesce(j.required_skills, '[]'::jsonb)) s
		where s not in (select jsonb_array_elements_text(coalesce(t.skills, '[]'::jsonb)))
	);
	skill_pass := array_length(missing, 1) is null;
	skill_label := 'Skill' || case when not skill_pass
		then ' (missing: ' || array_to_string(missing, ', ') || ')' else '' end;
	route_pass := nullif(j.route_criteria, '') is null;
	route_label := 'Route' || case when route_pass then '' else ' (' || j.route_criteria || ')' end;

	-- ── Not overriding + issues -> return override modal (no write) ──────────
	if p_override = 0 and (not skill_pass or not route_pass) then
		return
			$html$<div id="modal-host" hx-swap-oob="true"><div class="modal-backdrop" onclick="document.getElementById('modal-host').innerHTML=''"><div class="modal" onclick="event.stopPropagation()"><h3>Override CanDo check?</h3><p>Job <strong>#$html$
			|| api.html_escape(num) || $html$</strong> ($html$ || api.html_escape(j.customer_name)
			|| $html$) → <strong>$html$ || api.html_escape(t.name) || $html$</strong></p><ul class="issues">$html$
			|| '<li class="' || case when skill_pass then 'ok' else 'fail' end || '">'
				|| case when skill_pass then '✓' else '✗' end || ' ' || api.html_escape(skill_label) || '</li>'
			|| '<li class="' || case when route_pass then 'ok' else 'fail' end || '">'
				|| case when route_pass then '✓' else '✗' end || ' ' || api.html_escape(route_label) || '</li>'
			|| $html$</ul><div class="modal-actions"><button class="btn" onclick="document.getElementById('modal-host').innerHTML=''">Cancel</button><form hx-post="/assign" hx-target="#toast-host" hx-swap="innerHTML" style="display:inline"><input type="hidden" name="job_id" value="$html$
			|| j.id || $html$"><input type="hidden" name="tech_id" value="$html$ || t.id
			|| $html$"><input type="hidden" name="override" value="1"><button class="btn btn--stop" onclick="document.getElementById('modal-host').innerHTML=''">Override</button></form></div></div></div></div>$html$;
	end if;

	-- ── Mutation ────────────────────────────────────────────────────────────
	select technician_id into existing_tid from assignments where job_id = p_job_id;
	if found then
		if existing_tid = p_tech_id then
			return api.toast('Already on ' || t.name, 'warning');
		else
			-- unassign_job: delete + revert to PENDING (re-set to ASSIGNED below)
			delete from assignments where job_id = p_job_id;
			update jobs set status = 'PENDING' where id = p_job_id;
		end if;
	end if;

	olat := coalesce(t.current_latitude, t.home_latitude);
	olon := coalesce(t.current_longitude, t.home_longitude);
	dist := 3959.0 * 2 * asin(sqrt(
		sin(radians(j.latitude - olat) / 2) ^ 2
		+ cos(radians(olat)) * cos(radians(j.latitude)) * sin(radians(j.longitude - olon) / 2) ^ 2));
	travel := trunc(dist / 30.0 * 60)::int;

	insert into assignments (job_id, technician_id, sequence, estimated_distance,
		estimated_travel_time, actual_duration_minutes, estimated_arrival, assigned_at, created_at, updated_at)
	values (p_job_id, p_tech_id, null, dist, travel, null,
		api.sim_now() + make_interval(mins => travel), now(), now(), now());

	update jobs set status = 'ASSIGNED' where id = p_job_id;
	update technicians set status = 'EN_ROUTE' where id = p_tech_id and status = 'AVAILABLE';

	-- htmx: re-fetch dependent panels (mirrors HX-Trigger: refreshAll)
	perform set_config('response.headers', '[{"HX-Trigger": "refreshAll"}]', true);
	return api.toast('Job #' || num || ' → ' || t.name, 'success');
end;
$fn$;

-- OOB toast helper (raw msg — FastAPI builds it via f-string, not autoescaped).
create or replace function api.toast(msg text, kind text default 'success')
returns "text/html" language sql immutable as $$
	select '<div id="toast" hx-swap-oob="true" class="toast toast--' || kind || '">' || msg || '</div>';
$$;

-- Port of POST /unassign (htmx.py:313) — unassign_job + toast. Note the toast uses the
-- job_id param (NOT job_number, unlike assign's success toast). Demo-lock deferred (Phase 4).
create or replace function api.unassign(p_job_id integer)
returns "text/html" language plpgsql volatile
security definer set search_path = api, public as $fn$
begin
	delete from assignments where job_id = p_job_id;
	if not found then
		return api.toast('Job not assigned', 'warning');
	end if;
	update jobs set status = 'PENDING' where id = p_job_id;
	perform set_config('response.headers', '[{"HX-Trigger": "refreshAll"}]', true);
	return api.toast('Job #' || p_job_id || ' unassigned', 'success');
end;
$fn$;

grant execute on function api.assign(integer, integer, integer) to web_anon;
grant execute on function api.unassign(integer) to web_anon;
grant execute on function api.toast(text, text) to web_anon;
