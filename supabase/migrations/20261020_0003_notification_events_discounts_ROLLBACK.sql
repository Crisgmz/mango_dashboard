-- =============================================================================
-- ROLLBACK de 20261020_0003 — Avisos de cortesías y descuentos
-- =============================================================================
-- Deja todo como 20261007_0001: sin trigger de descuentos, sin los avisos de
-- cortesía/descuento ya creados, fn_notif_is_rewrite y
-- fn_notification_event_refresh con su cuerpo original.
-- OJO: vuelven los avisos falsos de «producto eliminado» al dividir la cuenta.
-- Las preferencias item_courtesy / item_discount guardadas se quedan (no
-- estorban: nadie las lee).
-- =============================================================================

begin;

set local lock_timeout = '5s';

drop trigger if exists trg_zz_notif_item_discount on public.order_items;
drop function if exists public.fn_notif_on_item_discount();
drop function if exists private.fn_notif_add_discounted_item(uuid, uuid, text, jsonb, uuid);
drop function if exists private.fn_notif_discount_text(text, uuid, uuid, jsonb, uuid);

delete from public.notification_events
 where kind in ('items_courtesy', 'items_discounted');

do $$
declare
  v_con text;
begin
  for v_con in
    select c.conname
    from pg_constraint c
    where c.conrelid = 'public.notification_events'::regclass
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid) like '%kind%'
  loop
    execute format('alter table public.notification_events drop constraint %I', v_con);
  end loop;
  alter table public.notification_events
    add constraint notification_events_kind_check check (kind in (
      'items_removed', 'order_voided', 'sale_annulled',
      'sale_partially_annulled'));
end;
$$;

comment on table public.notification_events is
  'Avisos del dashboard (20261007_0001): producto quitado después de cocina, '
  'orden anulada, venta anulada. Los crean triggers; el dashboard los escucha '
  'por Realtime y su INSERT dispara push-notify.';

create or replace function private.fn_notif_is_rewrite()
returns boolean
language sql
stable
as $$
  select coalesce(current_setting('request.path', true), '') ~
    '/rpc/(fn_split_items_equally|fn_explode_items_to_units|fn_consolidate_order_to_integer|fn_consolidate_keeper_atomic|fn_move_item_to_check|fn_move_items_to_check_batch|fn_transfer_table_session)/?$'
$$;
revoke all on function private.fn_notif_is_rewrite() from public;

drop function if exists private.fn_notif_called_from(text);

create or replace function public.fn_notification_event_refresh(p_event_id uuid)
returns table (
  id          uuid,
  business_id uuid,
  event_type  text,
  kind        text,
  title       text,
  body        text,
  created_at  timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_e     public.notification_events;
  v_role  text;
  v_title text;
  v_body  text;
begin
  select * into v_e from public.notification_events n where n.id = p_event_id;
  if not found then
    return;
  end if;

  v_role := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    ''
  );
  if v_role <> 'service_role'
     and v_e.business_id not in (select public.current_user_business_ids()) then
    return;
  end if;

  begin
    select t.title, t.body
      into v_title, v_body
    from private.fn_notif_text(
           v_e.kind, v_e.business_id, v_e.order_id, v_e.items,
           v_e.payment_ids, v_e.actor_user_id, v_e.created_at) t;
    if v_title is not null
       and (v_title, v_body) is distinct from (v_e.title, v_e.body) then
      update public.notification_events n
         set title = v_title,
             body = v_body
       where n.id = v_e.id;
      v_e.title := v_title;
      v_e.body := v_body;
    end if;
  exception when others then
    raise warning 'fn_notification_event_refresh: % (%)', sqlerrm, sqlstate;
  end;

  return query
    select v_e.id, v_e.business_id, v_e.event_type, v_e.kind, v_e.title,
           v_e.body, v_e.created_at;
end;
$$;

revoke all on function public.fn_notification_event_refresh(uuid) from public, anon;
grant execute on function public.fn_notification_event_refresh(uuid)
  to authenticated, service_role;

commit;
