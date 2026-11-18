-- Run in Supabase SQL Editor AFTER the migration. Success: completes with ROLLBACK.
-- Uses two temporary Auth users within a transaction; no test data persists.
begin;
insert into auth.users(id) values ('78b8f211-c7ad-41d0-9276-dff295910001'), ('78b8f211-c7ad-41d0-9276-dff295910002');
set local role authenticated;
select set_config('request.jwt.claim.sub', '78b8f211-c7ad-41d0-9276-dff295910001', true);
select public.import_cards('{"version":1,"folder":"Test A","decks":[{"title":"Kapitel","cards":[{"question":"Q","answer":"A"}]}]}'::jsonb, '78b8f211-c7ad-41d0-9276-dff295910003');
-- Retry same import must not duplicate content.
select public.import_cards('{"version":1,"folder":"Test A","decks":[{"title":"Kapitel","cards":[{"question":"Q","answer":"A"}]}]}'::jsonb, '78b8f211-c7ad-41d0-9276-dff295910003');
do $$
declare c uuid; s integer;
begin
  if (select count(*) from public.folders) <> 1 or (select count(*) from public.cards) <> 1 then raise exception 'FAIL: import duplicate'; end if;
  select id into c from public.cards limit 1;
  perform public.review_card(c, true, '78b8f211-c7ad-41d0-9276-dff295910004');
  perform public.review_card(c, true, '78b8f211-c7ad-41d0-9276-dff295910004');
  select streak into s from public.cards where id = c;
  if s <> 1 then raise exception 'FAIL: review counted twice'; end if;
  perform public.review_card(c, false, '78b8f211-c7ad-41d0-9276-dff295910005');
  if not exists(select 1 from public.cards where id = c and status = 'uncertain' and streak = 0) then raise exception 'FAIL: uncertain state'; end if;
  begin
    perform public.import_cards('{"version":1,"folder":"Invalid","decks":[{"title":"Valid","cards":[{"question":"Q","answer":"A"}]},{"title":"Invalid","cards":[{"question":"","answer":"A"}]}]}'::jsonb, '78b8f211-c7ad-41d0-9276-dff295910006');
    raise exception 'FAIL: invalid import accepted';
  exception when check_violation then null;
  end;
  if exists(select 1 from public.folders where id = '78b8f211-c7ad-41d0-9276-dff295910006') then raise exception 'FAIL: partial import'; end if;
end;
$$;
-- Bulk changes and reset stay within the chosen deck and are absolute states.
do $$
declare
  target uuid;
  first_card uuid;
  second_card uuid;
  other_deck uuid;
  other_card uuid;
  rejected boolean := false;
begin
  select id into target from public.decks limit 1;
  select id into first_card from public.cards where deck_id = target limit 1;
  insert into public.cards(deck_id, question, answer) values (target, 'Second', 'Answer') returning id into second_card;
  insert into public.decks(folder_id, title) values ('78b8f211-c7ad-41d0-9276-dff295910003', 'Other chapter') returning id into other_deck;
  insert into public.cards(deck_id, question, answer, status, streak) values (other_deck, 'Other', 'Keep me', 'secure', 7) returning id into other_card;
  perform public.set_cards_status(target, array[first_card], 'secure');
  perform public.set_cards_status(target, array[first_card], 'secure');
  if not exists(select 1 from public.cards where id = first_card and status = 'secure' and streak = 1) then raise exception 'FAIL: absolute status'; end if;
  if not exists(select 1 from public.cards where id = second_card and status = 'new') then raise exception 'FAIL: unselected card changed'; end if;
  begin
    perform public.set_cards_status(target, array[first_card, other_card], 'uncertain');
  exception when raise_exception then
    if sqlerrm <> 'Auswahl enthält fehlende oder fremde Karten' then raise; end if;
    rejected := true;
  end;
  if not rejected then raise exception 'FAIL: cross-deck selection accepted'; end if;
  if not exists(select 1 from public.cards where id = first_card and status = 'secure') then raise exception 'FAIL: partial update'; end if;
  perform public.set_cards_status(target, array[first_card, second_card], 'uncertain');
  if exists(select 1 from public.cards where deck_id = target and (status <> 'uncertain' or streak <> 0)) then raise exception 'FAIL: bulk uncertain'; end if;
  perform public.reset_deck_progress(target);
  if exists(select 1 from public.cards where deck_id = target and (status <> 'new' or streak <> 0 or due_at > now())) then raise exception 'FAIL: reset'; end if;
  if not exists(select 1 from public.cards where id = other_card and status = 'secure' and streak = 7) then raise exception 'FAIL: another deck changed'; end if;
end;
$$;
select set_config('study.test.deck_id', (select id::text from public.decks limit 1), true);
-- Switch to account B; all of A's rows must disappear under RLS.
select set_config('request.jwt.claim.sub', '78b8f211-c7ad-41d0-9276-dff295910002', true);
do $$
begin
  if exists(select 1 from public.folders) or exists(select 1 from public.cards) or exists(select 1 from public.decks) or exists(select 1 from public.review_events) then raise exception 'FAIL: account isolation'; end if;
  begin
    insert into public.decks(folder_id, title) values ('78b8f211-c7ad-41d0-9276-dff295910003', 'Foreign folder');
    raise exception 'FAIL: cross-owner reference accepted';
  exception when foreign_key_violation then null;
  end;
end;
$$;
-- Account B cannot reset or update a deck owned by A.
do $$
declare rejected boolean := false;
begin
  begin
    perform public.reset_deck_progress(current_setting('study.test.deck_id')::uuid);
  exception when raise_exception then
    if sqlerrm <> 'Stapel nicht gefunden' then raise; end if;
    rejected := true;
  end;
  if not rejected then raise exception 'FAIL: foreign reset accepted'; end if;
end;
$$;
-- An anonymous client must not have access.
set local role anon;
do $$
begin
  begin
    perform count(*) from public.cards;
    raise exception 'FAIL: anonymous table access';
  exception when insufficient_privilege then null;
  end;
end;
$$;
rollback;
