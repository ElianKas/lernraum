-- Atomic status changes for an explicit selection, without long URL filters.
begin;
create function public.set_cards_status(target_deck uuid, selected_ids uuid[], new_status text)
returns integer language plpgsql security invoker set search_path = '' as $$
declare
  expected integer;
  affected integer;
begin
  if auth.uid() is null then raise exception 'Anmeldung erforderlich'; end if;
  if new_status is null or new_status not in ('secure', 'uncertain') then raise exception 'Ungültiger Kartenstatus'; end if;
  if selected_ids is null or cardinality(selected_ids) = 0 or array_position(selected_ids, null) is not null then
    raise exception 'Wähle mindestens eine gültige Karte aus';
  end if;
  if not exists(select 1 from public.decks d where d.id = target_deck and d.user_id = auth.uid()) then
    raise exception 'Stapel nicht gefunden';
  end if;
  select count(distinct value) into expected from unnest(selected_ids) as value;
  -- Lock in consistent order; validation and update stay in one transaction.
  perform c.id from public.cards c
    where c.deck_id = target_deck and c.user_id = auth.uid() and c.id = any(selected_ids)
    order by c.id for update;
  if (select count(*) from public.cards c where c.deck_id = target_deck and c.user_id = auth.uid() and c.id = any(selected_ids)) <> expected then
    raise exception 'Auswahl enthält fehlende oder fremde Karten';
  end if;
  update public.cards c set
    status = new_status,
    streak = case when new_status = 'secure' then 1 else 0 end,
    due_at = now() + case when new_status = 'secure' then interval '1 day' else interval '10 minutes' end
    where c.deck_id = target_deck and c.user_id = auth.uid() and c.id = any(selected_ids);
  get diagnostics affected = row_count;
  return affected;
end;
$$;

create function public.reset_deck_progress(target_deck uuid)
returns integer language plpgsql security invoker set search_path = '' as $$
declare affected integer;
begin
  if auth.uid() is null then raise exception 'Anmeldung erforderlich'; end if;
  if not exists(select 1 from public.decks d where d.id = target_deck and d.user_id = auth.uid()) then raise exception 'Stapel nicht gefunden'; end if;
  update public.cards c set status = 'new', streak = 0, due_at = now()
    where c.deck_id = target_deck and c.user_id = auth.uid();
  get diagnostics affected = row_count;
  return affected;
end;
$$;
revoke all on function public.set_cards_status(uuid, uuid[], text), public.reset_deck_progress(uuid) from public, anon;
grant execute on function public.set_cards_status(uuid, uuid[], text), public.reset_deck_progress(uuid) to authenticated;
commit;
