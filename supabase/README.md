# supabase/ (Member A)

- `migrations/` one SQL file per schema change (`YYYYMMDDHHMMSS_name.sql`); tables, PostGIS, RLS, storage
- `seed.sql` demo data for local development

Set up: install the Supabase CLI, run `supabase init` here, then `supabase db reset` to apply migrations and seed.
