-- Shared render helpers for the api.* HTML fragment functions.

-- Escape a string for safe interpolation into HTML text/attributes.
-- Ampersand first so later entities aren't double-escaped.
create or replace function api.html_escape(s text)
returns text language sql immutable as $$
	select replace(replace(replace(replace(replace(
		coalesce(s, ''),
		'&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;');
$$;

-- Render a double as Python's str(float) does. The only divergence from
-- Postgres float8out is integer-valued floats: Python str(140.0) = '140.0',
-- Postgres 140.0::text = '140'. Both use shortest round-trip repr otherwise,
-- so non-integers pass through unchanged. Needed for SVG coord parity with
-- Jinja-rendered templates (e.g. _timeline.html).
create or replace function api.py_float(x double precision)
returns text language sql immutable as $$
	select case
		when x = trunc(x) and abs(x) < 1e16 then trunc(x)::bigint::text || '.0'
		else x::text
	end;
$$;
