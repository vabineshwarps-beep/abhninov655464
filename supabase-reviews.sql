-- Run once in Supabase Dashboard -> SQL Editor.
-- Customer reviews: public can submit (goes to 'pending'), public can read only 'approved', admins manage.

create table if not exists public.customer_reviews (
  id uuid primary key default gen_random_uuid(),
  reviewer_name text not null check (char_length(btrim(reviewer_name)) between 2 and 60 and reviewer_name !~* '(https?://|www\.)'),
  area text check (area is null or (char_length(area) <= 60 and area !~* '(https?://|www\.)')),
  rating smallint not null check (rating between 1 and 5),
  review_text text not null check (char_length(btrim(review_text)) between 20 and 600 and review_text !~* '(https?://|www\.)'),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  approved_at timestamptz
);

create index if not exists customer_reviews_status_created_idx
  on public.customer_reviews (status, created_at desc);

alter table public.customer_reviews enable row level security;

drop policy if exists "public can submit pending reviews" on public.customer_reviews;
create policy "public can submit pending reviews" on public.customer_reviews
  for insert to anon, authenticated
  with check (status = 'pending' and approved_at is null);

drop policy if exists "public can read approved reviews" on public.customer_reviews;
create policy "public can read approved reviews" on public.customer_reviews
  for select to anon, authenticated
  using (status = 'approved');

drop policy if exists "admins manage reviews" on public.customer_reviews;
create policy "admins manage reviews" on public.customer_reviews
  for all to authenticated
  using (exists (select 1 from public.admin_users a where a.user_id = auth.uid()))
  with check (exists (select 1 from public.admin_users a where a.user_id = auth.uid()));

revoke all on public.customer_reviews from anon, authenticated;
grant select on public.customer_reviews to anon, authenticated;
grant insert (reviewer_name, area, rating, review_text) on public.customer_reviews to anon, authenticated;
grant update, delete on public.customer_reviews to authenticated;

create or replace function public.customer_reviews_set_approved_at() returns trigger
language plpgsql as $$
begin
  if new.status = 'approved' and (old.status is distinct from 'approved') then
    new.approved_at := now();
  end if;
  return new;
end $$;

drop trigger if exists customer_reviews_approved_at on public.customer_reviews;
create trigger customer_reviews_approved_at before update on public.customer_reviews
  for each row execute function public.customer_reviews_set_approved_at();

-- To approve a review: Table Editor -> customer_reviews -> change status from 'pending' to 'approved'.
