-- Execute once in a new Supabase project's SQL Editor.
begin;

create table public.folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 120),
  created_at timestamptz not null default now(),
  unique (id, user_id)
);
create table public.decks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  folder_id uuid not null,
  title text not null check (length(trim(title)) between 1 and 200),
  created_at timestamptz not null default now(),
  unique (id, user_id),
  foreign key (folder_id, user_id) references public.folders(id, user_id) on delete cascade
);
create table public.cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  deck_id uuid not null,
  question text not null check (length(trim(question)) between 1 and 10000),
  answer text not null check (length(trim(answer)) between 1 and 20000),
  status text not null default 'new' check (status in ('new', 'uncertain', 'secure')),
  streak integer not null default 0 check (streak between 0 and 10000),
  due_at timestamptz not null default now(),
  position integer not null default 0,
  created_at timestamptz not null default now(),
  foreign key (deck_id, user_id) references public.decks(id, user_id) on delete cascade,
  unique (id, user_id)
);
create table public.review_events (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  card_id uuid not null,
  is_secure boolean not null,
  created_at timestamptz not null default now(),
  primary key (id, user_id),
  foreign key (card_id, user_id) references public.cards(id, user_id) on delete cascade
);
create index decks_folder_idx on public.decks(user_id, folder_id);
create index cards_deck_idx on public.cards(user_id, deck_id);
create index cards_due_idx on public.cards(user_id, status, due_at);

alter table public.folders enable row level security;
alter table public.decks enable row level security;
alter table public.cards enable row level security;
alter table public.review_events enable row level security;

create policy own_folders on public.folders for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_decks on public.decks for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_cards on public.cards for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_reviews on public.review_events for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

revoke all on public.folders, public.decks, public.cards, public.review_events from anon, authenticated;
grant select, insert, update, delete on public.folders, public.decks, public.cards to authenticated;
grant select, insert on public.review_events to authenticated;

-- All inserts are one transaction. A retry with the same request_id is a no-op.
-- SECURITY INVOKER preserves RLS throughout, including composite owner foreign keys.
create function public.import_cards(document jsonb, request_id uuid)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare
  chapter jsonb;
  item jsonb;
  new_deck uuid;
  position_index integer;
  card_total integer := 0;
begin
  if auth.uid() is null then raise exception 'Anmeldung erforderlich'; end if;
  if request_id is null then raise exception 'Importkennung fehlt'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text || request_id::text, 0));
  if exists(select 1 from public.folders where id = request_id and user_id = auth.uid()) then return request_id; end if;
  if jsonb_typeof(document) is distinct from 'object'
     or document->>'version' is distinct from '1'
     or jsonb_typeof(document->'folder') is distinct from 'string'
     or jsonb_typeof(document->'decks') is distinct from 'array' then
    raise exception 'Ungültiges Importformat';
  end if;
  if octet_length(document::text) > 5000000 or jsonb_array_length(document->'decks') not between 1 and 100 then
    raise exception 'Import zu groß oder leer';
  end if;
  insert into public.folders(id, name) values (request_id, trim(document->>'folder'));
  for chapter in select value from jsonb_array_elements(document->'decks') loop
    if jsonb_typeof(chapter->'title') is distinct from 'string' or jsonb_typeof(chapter->'cards') is distinct from 'array' then
      raise exception 'Ungültiger Stapel';
    end if;
    if jsonb_array_length(chapter->'cards') = 0 then raise exception 'Leerer Stapel'; end if;
    card_total := card_total + jsonb_array_length(chapter->'cards');
    if card_total > 2000 then raise exception 'Maximal 2000 Karten pro Import'; end if;
    insert into public.decks(folder_id, title) values (request_id, trim(chapter->>'title')) returning id into new_deck;
    position_index := 0;
    for item in select value from jsonb_array_elements(chapter->'cards') loop
      if jsonb_typeof(item->'question') is distinct from 'string' or jsonb_typeof(item->'answer') is distinct from 'string' then
        raise exception 'Frage oder Antwort fehlt';
      end if;
      insert into public.cards(deck_id, question, answer, position)
        values (new_deck, trim(item->>'question'), trim(item->>'answer'), position_index);
      position_index := position_index + 1;
    end loop;
  end loop;
  return request_id;
end;
$$;

-- A row lock serializes concurrent reviews. The event id prevents double counting
-- when the network drops after the transaction committed and the client retries.
create function public.review_card(card_id uuid, is_secure boolean, review_id uuid)
returns setof public.cards language plpgsql security invoker set search_path = '' as $$
declare
  target public.cards;
  previous public.review_events;
begin
  if auth.uid() is null then raise exception 'Anmeldung erforderlich'; end if;
  if review_id is null or is_secure is null then raise exception 'Ungültige Bewertung'; end if;
  select * into target from public.cards c where c.id = card_id and c.user_id = auth.uid() for update;
  if not found then raise exception 'Karte nicht gefunden'; end if;
  select * into previous from public.review_events e where e.id = review_id and e.user_id = auth.uid();
  if found then
    if previous.card_id <> card_id or previous.is_secure <> is_secure then raise exception 'Bewertungskennung bereits verwendet'; end if;
    return next target;
    return;
  end if;
  insert into public.review_events(id, card_id, is_secure) values (review_id, card_id, is_secure);
  update public.cards c set
    status = case when is_secure then 'secure' else 'uncertain' end,
    streak = case when is_secure then least(c.streak + 1, 10000) else 0 end,
    due_at = now() + case when is_secure then make_interval(days => least(power(2, least(c.streak, 5))::integer, 30)) else interval '10 minutes' end
    where c.id = card_id and c.user_id = auth.uid() returning c.* into target;
  return next target;
end;
$$;
revoke all on function public.import_cards(jsonb, uuid), public.review_card(uuid, boolean, uuid) from public, anon;
grant execute on function public.import_cards(jsonb, uuid), public.review_card(uuid, boolean, uuid) to authenticated;
commit;
