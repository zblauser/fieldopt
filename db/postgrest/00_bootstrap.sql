-- PostgREST bootstrap: exposed schema + anonymous web role.
-- Additive only — does not touch the app's existing tables.
-- The `api` schema holds RPC functions (HTML fragments + JSON) that PostgREST exposes.
-- Functions read the app-owned `public` tables; nothing here writes.

create schema if not exists api;

-- Anonymous role PostgREST authenticates as for unauthenticated requests.
do $$
begin
	if not exists (select from pg_roles where rolname = 'web_anon') then
		create role web_anon nologin;
	end if;
end
$$;

grant usage on schema api to web_anon;
grant usage on schema public to web_anon;
grant select on all tables in schema public to web_anon;
alter default privileges in schema public grant select on tables to web_anon;
