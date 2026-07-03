-- Media type handler: a domain named after a media type makes PostgREST serve a
-- function's scalar result raw with that Content-Type (when the request Accepts it).
-- The HTMX UI must send `Accept: text/html` (htmx:configRequest hook) — its default
-- `*/*` negotiates to JSON.
do $$
begin
	create domain "text/html" as text;
exception
	when duplicate_object then null;
end
$$;
