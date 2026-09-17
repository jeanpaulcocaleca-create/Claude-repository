-- Garden Guide chatbox: stores every question visitors ask on the website,
-- so the team can see what people want to know (and improve the answers).
-- Run ONCE in Supabase: SQL Editor -> New query -> paste -> Run.

create table if not exists public.chat_questions (
  id uuid primary key default gen_random_uuid(),
  asked_at timestamptz not null default now(),
  message text not null,
  lang text,
  matched text,          -- which answer the guide used (null = it had no answer)
  answered boolean not null default false,
  session text           -- random per-visit id, groups one visitor's questions
);

alter table public.chat_questions enable row level security;

-- Anyone browsing the website may ask (insert). Nobody anonymous can read.
drop policy if exists "visitors can ask" on public.chat_questions;
create policy "visitors can ask" on public.chat_questions
  for insert to anon, authenticated with check (true);

-- Only signed-in café accounts can read the questions.
drop policy if exists "cafe reads questions" on public.chat_questions;
create policy "cafe reads questions" on public.chat_questions
  for select to authenticated using (true);
