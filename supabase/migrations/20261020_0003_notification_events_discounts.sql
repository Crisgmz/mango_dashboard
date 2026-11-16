-- =============================================================================
-- 20261020_0003 — Avisos del dashboard: cortesías y descuentos (y arreglo de
--                 avisos falsos de «producto eliminado» al dividir la cuenta)
-- =============================================================================
--
-- POR QUÉ. Pedido del dueño (2026-10-20): push de borrado, reducción,
-- cortesía y descuento. Borrar y reducir lo enviado a cocina ya avisan
-- (20261007_0001, clave item_voided). Faltaban cortesías y descuentos.
--
-- QUÉ AVISA. Cuando una PERSONA le sube el descuento a un producto:
--   * Cortesía (clave item_courtesy): la línea queda regalada. Misma regla
--     que los reportes (20260531_0002): etiqueta [CORTESIA:motivo] o
--     descuento >= subtotal + impuesto. El motivo es opcional en el POS.
--   * Descuento (clave item_discount): cualquier otra subida del porcentaje.
--   Solo cuenta lo que pasa por las RPC con que el POS aplica descuentos:
--   fn_update_item_discount_and_notes (barra: % o monto, por línea, repartido
--   en la cuenta, y cortesía), fn_update_item_details (modal del producto) y
--   fn_update_item_discount. Se detectan por la pila (PG_CONTEXT), así que da
--   igual si llegan solas o dentro de fn_apply_order_edit /
--   fn_apply_order_item_group, en línea o desde la cola offline.
--
-- QUÉ NO AVISA.
--   * Promociones automáticas ([PROMO_AUTO:]) y ofertas ([DEAL:],
--     [DEAL_RULE:]): las pone el sistema, no una persona.
--   * Quitar o bajar un descuento, o pasar de cortesía a descuento parcial.
--   * Subir la cantidad de una línea con descuento: el monto sube, pero el
--     porcentaje es el mismo (se compara descuento / (qty × precio)).
--   * Las ofertas que se crean por REST ([DEAL:]) ni lo que reparte
--     cantidades: no pasan por esas RPC.
--
-- AGRUPA. Un descuento repartido en la cuenta es una llamada por línea: lo de
-- la misma orden, la misma cuenta y el mismo tipo dentro de 5 s (y aún sin
-- enviar) es UN aviso, igual que los productos quitados. Si el mismo producto
-- cambia dos veces en ese lapso, queda una sola línea con el último valor.
--
-- QUIÉN. auth.uid(): la cuenta logueada en el equipo (en una tablet
-- compartida, la de la tablet). El POS no guarda quién autorizó un descuento
-- con PIN (pin_verification_modal solo devuelve sí/no).
--
-- ARREGLO (productos quitados, 20261007_0001). private.fn_notif_is_rewrite no
-- conocía las RPC de división de cuenta de 20261014/15, y dividir mandaba
-- «Producto eliminado / Cantidad reducida» falsos:
--   * fn_explode_items_for_split (qty N → 1 y N−1 copias) y
--     fn_apply_bill_split (con personas, llama a fn_split_items_equally): se
--     agregan a la lista por request.path.
--   * fn_apply_order_edit 'consolidate_check' llama a
--     fn_consolidate_keeper_atomic por dentro (request.path es el de
--     fn_apply_order_edit): ahora también se mira la pila. Quitar o reducir
--     de verdad (delete / qty / details) sigue avisando.
--
-- PUSH. Sin cambios en push-notify: toma título, cuerpo y clave de la fila.
--
-- REQUIERE 20261007_0001. IDEMPOTENTE.
-- ROLLBACK: 20261020_0003_notification_events_discounts_ROLLBACK.sql
-- Prueba: supabase/tests/notification_events_discounts_local_test.sh
-- Aplicar en horario de poca venta (el trigger nuevo espera el candado de
-- order_items; lock_timeout 5 s, si vence se vuelve a correr).
-- =============================================================================

begin;

set local lock_timeout = '5s';

do $$
begin
  if to_regclass('public.notification_events') is null
     or to_regprocedure('public.fn_notification_event_refresh(uuid)') is null then
    raise exception 'Falta 20261007_0001_notification_events.sql';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Tipos de aviso nuevos
-- ---------------------------------------------------------------------------
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
      'sale_partially_annulled', 'items_courtesy', 'items_discounted'));
end;
$$;

comment on table public.notification_events is
  'Avisos del dashboard (20261007_0001, 20261020_0003): producto quitado o '
  'reducido después de cocina, cortesía, descuento, orden anulada, venta '
  'anulada. Los crean triggers; el dashboard los escucha por Realtime y su '
  'INSERT dispara push-notify.';

-- ---------------------------------------------------------------------------
-- 2. ¿La llamada viene de esta función? (pila de PG_CONTEXT)
-- ---------------------------------------------------------------------------
create or replace function private.fn_notif_called_from(p_regex text)
returns boolean
language plpgsql
stable
as $$
declare
  v_ctx text;
begin
  get diagnostics v_ctx = pg_context;
  return v_ctx ~ ('function (public\.)?(' || p_regex || ')\(');
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Arreglo: lo que solo redistribuye cantidades no es quitar
-- ---------------------------------------------------------------------------
-- Por request.path (la RPC que llamó la app) o por la pila (la misma
-- redistribución dentro de otra RPC, como fn_apply_order_edit
-- 'consolidate_check'). Si se agrega otra RPC que redistribuya, va aquí.
create or replace function private.fn_notif_is_rewrite()
returns boolean
language plpgsql
stable
as $$
begin
  if coalesce(current_setting('request.path', true), '') ~
       '/rpc/(fn_split_items_equally|fn_explode_items_to_units|fn_explode_items_for_split|fn_apply_bill_split|fn_consolidate_order_to_integer|fn_consolidate_keeper_atomic|fn_move_item_to_check|fn_move_items_to_check_batch|fn_transfer_table_session)/?$' then
    return true;
  end if;
  return private.fn_notif_called_from(
    'fn_split_items_equally|fn_explode_items_to_units|fn_consolidate_order_to_integer|fn_consolidate_keeper_atomic');
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Texto
-- ---------------------------------------------------------------------------
-- p_items: item_id, product_name, qty, gross (subtotal + impuesto), before y
-- after (descuento antes y después), reason (etiqueta [CORTESIA:]).
create or replace function private.fn_notif_discount_text(
  p_kind     text,
  p_business uuid,
  p_order    uuid,
  p_items    jsonb,
  p_actor    uuid,
  out title  text,
  out body   text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_place  text;
  v_count  integer;
  v_after  numeric;
  v_gross  numeric;
  v_reason text;
  v_lines  text;
  v_pct    text;
  v_who    text;
begin
  select pl.place into v_place from private.fn_notif_place(p_order) pl;

  select count(*)::int,
         coalesce(sum((i.value ->> 'after')::numeric), 0),
         coalesce(sum((i.value ->> 'gross')::numeric), 0),
         (array_agg(nullif(trim(i.value ->> 'reason'), '') order by i.ord)
            filter (where nullif(trim(i.value ->> 'reason'), '') is not null))[1]
    into v_count, v_after, v_gross, v_reason
  from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
         with ordinality as i(value, ord);
  if v_count = 0 then
    return;
  end if;

  select string_agg(l.line, ', ' order by l.ord)
    into v_lines
  from (
    select i.ord,
           private.fn_notif_qty((i.value ->> 'qty')::numeric) || ' x '
             || coalesce(i.value ->> 'product_name', 'Producto') as line
    from jsonb_array_elements(p_items) with ordinality as i(value, ord)
  ) l
  where l.ord <= 4;
  if v_count > 4 then
    v_lines := v_lines || ' y ' || (v_count - 4) || ' más';
  end if;

  v_who := private.fn_notif_person(p_business, null, p_actor);

  if p_kind = 'items_courtesy' then
    title := case when v_count = 1 then 'Cortesía' else 'Cortesías' end;
    body := coalesce(v_place, 'Venta') || ' · ' || v_lines || ' · '
      || private.fn_notif_money(v_after) || ' regalados.'
      || coalesce(' Motivo: ' || v_reason || '.', '')
      || coalesce(' Por: ' || v_who || '.', '');
    return;
  end if;

  if p_kind = 'items_discounted' then
    if v_gross > 0 then
      v_pct := ' (' || private.fn_notif_qty(round(v_after / v_gross * 100, 1)) || '%)';
    end if;
    title := 'Descuento aplicado';
    body := coalesce(v_place, 'Venta') || ' · ' || private.fn_notif_money(v_after)
      || coalesce(v_pct, '') || ' de descuento en ' || v_lines || '.'
      || coalesce(' Por: ' || v_who || '.', '');
    return;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Agrupar en el aviso abierto de la orden o crear uno
-- ---------------------------------------------------------------------------
create or replace function private.fn_notif_add_discounted_item(
  p_order    uuid,
  p_business uuid,
  p_kind     text,
  p_item     jsonb,
  p_actor    uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business uuid;
  v_id       uuid;
  v_items    jsonb;
  v_before   jsonb;
  v_title    text;
  v_body     text;
begin
  select ts.business_id
    into v_business
  from public.orders o
  join public.table_sessions ts on ts.id = o.session_id
  where o.id = p_order;
  v_business := coalesce(v_business, p_business);
  if v_business is null then
    raise warning 'fn_notif_add_discounted_item: sin negocio para la orden %', p_order;
    return;
  end if;

  select e.id, e.items
    into v_id, v_items
  from public.notification_events e
  where e.kind = p_kind
    and e.business_id = v_business
    and e.order_id is not distinct from p_order
    and e.actor_user_id is not distinct from p_actor
    and e.pushed_at is null
    and (e.source_txid = txid_current()
         or e.created_at > clock_timestamp() - interval '5 seconds')
  order by e.created_at desc
  limit 1
  for update;

  -- El mismo producto otra vez: una sola línea, con el descuento de antes
  -- del primer cambio.
  select i.value -> 'before'
    into v_before
  from jsonb_array_elements(coalesce(v_items, '[]'::jsonb)) i
  where i.value ->> 'item_id' = p_item ->> 'item_id'
  limit 1;
  select coalesce(jsonb_agg(i.value order by i.ord), '[]'::jsonb)
    into v_items
  from jsonb_array_elements(coalesce(v_items, '[]'::jsonb))
         with ordinality as i(value, ord)
  where i.value ->> 'item_id' is distinct from p_item ->> 'item_id';
  v_items := v_items || jsonb_build_array(
    case when v_before is null then p_item
         else p_item || jsonb_build_object('before', v_before) end);

  select t.title, t.body
    into v_title, v_body
  from private.fn_notif_discount_text(p_kind, v_business, p_order, v_items, p_actor) t;

  if v_id is null then
    insert into public.notification_events (
      business_id, event_type, kind, order_id, items, actor_user_id,
      title, body
    )
    values (
      v_business,
      case p_kind when 'items_courtesy' then 'item_courtesy' else 'item_discount' end,
      p_kind, p_order, v_items, p_actor,
      coalesce(v_title, 'Descuento aplicado'), coalesce(v_body, '')
    );
  else
    update public.notification_events e
       set items = v_items,
           title = coalesce(v_title, e.title),
           body = coalesce(v_body, e.body)
     where e.id = v_id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Trigger: subida del descuento de un producto
-- ---------------------------------------------------------------------------
create or replace function public.fn_notif_on_item_discount()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before      numeric := coalesce(old.discounts, 0);
  v_after       numeric := coalesce(new.discounts, 0);
  v_notes       text := coalesce(new.notes, '');
  v_old_base    numeric;
  v_new_base    numeric;
  v_gross       numeric;
  v_qty         numeric;
  v_kind        text;
begin
  begin
    if v_after <= v_before + 0.009 then
      return null;
    end if;
    if v_notes ~ '\[(PROMO_AUTO|DEAL|DEAL_RULE):' then
      return null;
    end if;

    -- Con descuento previo, solo avisa si sube el porcentaje (subir la
    -- cantidad de una línea con 10 % sube el monto, no el descuento).
    v_old_base := coalesce(old.qty, 0) * coalesce(old.unit_price, 0);
    v_new_base := coalesce(new.qty, 0) * coalesce(new.unit_price, 0);
    if v_before > 0.009 and v_old_base > 0 and v_new_base > 0
       and v_after / v_new_base <= v_before / v_old_base + 0.0005 then
      return null;
    end if;

    if not private.fn_notif_called_from(
         'fn_update_item_discount|fn_update_item_discount_and_notes|fn_update_item_details') then
      return null;
    end if;

    v_gross := coalesce(new.subtotal, 0) + coalesce(new.tax, 0);
    v_kind := case
      when v_notes like '%[CORTESIA:%' or (v_gross > 0 and v_after >= v_gross - 0.01)
        then 'items_courtesy'
      else 'items_discounted'
    end;
    v_qty := coalesce(nullif(new.qty, 0), (to_jsonb(new) ->> 'quantity')::numeric, 1);

    perform private.fn_notif_add_discounted_item(
      new.order_id,
      (to_jsonb(new) ->> 'business_id')::uuid,
      v_kind,
      jsonb_build_object(
        'item_id', new.id,
        'product_name', new.product_name,
        'qty', v_qty,
        'gross', v_gross,
        'before', v_before,
        'after', v_after,
        'reason', nullif(trim((regexp_match(v_notes, '\[CORTESIA:([^\]]*)\]'))[1]), '')
      ),
      auth.uid()
    );
  exception when others then
    raise warning 'fn_notif_on_item_discount: % (%)', sqlerrm, sqlstate;
  end;
  return null;
end;
$$;

drop trigger if exists trg_zz_notif_item_discount on public.order_items;
create trigger trg_zz_notif_item_discount
  after update of discounts on public.order_items
  for each row
  when (new.discounts is distinct from old.discounts)
  execute function public.fn_notif_on_item_discount();

-- ---------------------------------------------------------------------------
-- 7. Texto final: cortesías y descuentos con su propio armado
-- ---------------------------------------------------------------------------
-- Igual que 20261007_0001, salvo la rama de items_courtesy/items_discounted.
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
    if v_e.kind in ('items_courtesy', 'items_discounted') then
      select t.title, t.body
        into v_title, v_body
      from private.fn_notif_discount_text(
             v_e.kind, v_e.business_id, v_e.order_id, v_e.items,
             v_e.actor_user_id) t;
    else
      select t.title, t.body
        into v_title, v_body
      from private.fn_notif_text(
             v_e.kind, v_e.business_id, v_e.order_id, v_e.items,
             v_e.payment_ids, v_e.actor_user_id, v_e.created_at) t;
    end if;
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

revoke all on function private.fn_notif_called_from(text) from public;
revoke all on function private.fn_notif_is_rewrite() from public;
revoke all on function private.fn_notif_discount_text(text, uuid, uuid, jsonb, uuid) from public;
revoke all on function private.fn_notif_add_discounted_item(uuid, uuid, text, jsonb, uuid) from public;
revoke all on function public.fn_notif_on_item_discount() from public, anon, authenticated;

commit;

-- Verificación (correr aparte):
--   select tgname from pg_trigger where tgname = 'trg_zz_notif_item_discount';
--   select kind, title, body, created_at from public.notification_events
--    where kind in ('items_courtesy', 'items_discounted')
--    order by created_at desc limit 20;
