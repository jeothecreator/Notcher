-- Optional global leaderboards for Notcher.
-- 1. Create a Supabase project and run this in the SQL editor.
-- 2. In Notcher → Settings → Global leaderboards, paste the project URL and
--    the public (anon / publishable) API key.

create table if not exists public.scores (
  id          bigint generated always as identity primary key,
  board       text        not null check (char_length(board) between 1 and 40),
  player_id   text        not null check (player_id ~ '^PLAYER-[2-9A-HJ-NP-Z]{4}$'),
  name        text        not null check (char_length(name) between 1 and 24),
  value       integer     not null check (value >= 0 and value < 100000000),
  created_at  timestamptz not null default now()
);

create index if not exists scores_board_value on public.scores (board, value desc);
create index if not exists scores_board_created on public.scores (board, created_at desc);

alter table public.scores enable row level security;

-- Anyone may read the boards.
drop policy if exists "scores are public" on public.scores;
create policy "scores are public" on public.scores
  for select to anon, authenticated using (true);

-- Anyone may submit a score; rows can never be edited or deleted by clients.
drop policy if exists "anyone can submit" on public.scores;
create policy "anyone can submit" on public.scores
  for insert to anon, authenticated with check (true);
