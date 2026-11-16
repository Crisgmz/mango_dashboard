-- =============================================================================
-- ROLLBACK de 20261020_0004 — Historial con el PIN de quién autorizó
-- =============================================================================
-- Deja todo como antes: sin aprobaciones de anulación, el registro de
-- retiros sin tomar el aprobador de la aprobación, y el historial con sus
-- funciones de 20261013_0001 (productos quitados: el aprobador vuelve a ser
-- el autor) y 20261013_0002 (cuenta anulada). Las líneas de productos
-- quitados con aprobador se vuelven a escribir como estaban.
-- Las líneas de «mesa vacía autorizada» ya escritas se quedan (el historial
-- no se borra).
-- =============================================================================

begin;

set local lock_timeout = '5s';

drop trigger if exists trg_removal_take_approval on public.order_item_removals;
drop function if exists public.fn_removal_take_approval();
alter table public.order_item_removal_approvals drop column if exists used_item_ids;

drop function if exists public.fn_issue_order_void_approval(uuid, text, uuid);
drop table if exists public.order_void_approvals;

-- 20261013_0001, textual.
create or replace function private.fn_change_history_upsert_removal(p jsonb)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_business uuid := (p ->> 'business_id')::uuid;
  v_user     uuid := (p ->> 'removed_by')::uuid;
  v_employee uuid := coalesce((p ->> 'approved_by_employee_id')::uuid,
                              (p ->> 'reason_employee_id')::uuid);
  v_reduced  boolean := p ->> 'change_type' = 'reduced';
  v_author   text;
  v_changes  jsonb;
begin
  if v_business is null or coalesce((p ->> 'is_user_action')::boolean, false) = false then
    return;
  end if;

  if p ->> 'author_employee_id' is not null then
    v_author := private.fn_change_history_person(
      v_business, null, (p ->> 'author_employee_id')::uuid);
  end if;

  v_changes := jsonb_strip_nulls(jsonb_build_object(
    'quantity', case
                  when v_reduced then jsonb_build_array(
                    (p -> 'qty_before'), (p -> 'qty_after'))
                  else p -> 'quantity'
                end,
    'unit_price', p -> 'unit_price',
    'amount', to_jsonb(round(coalesce((p ->> 'quantity')::numeric, 0)
                             * coalesce((p ->> 'unit_price')::numeric, 0), 2)),
    'reason', nullif(p ->> 'reason', ''),
    'kitchen_sent', to_jsonb(p ->> 'kitchen_sent_at' is not null),
    'added_by', v_author,
    'notes', nullif(p ->> 'notes', '')));

  insert into public.change_history (
    business_id, table_name, row_id, action, label, context,
    actor_user_id, actor_employee_id, actor_name, changed_at, changes,
    source, ref_id
  )
  values (
    v_business, 'order_items', coalesce(p ->> 'item_id', p ->> 'id'),
    case when v_reduced then 'update' else 'delete' end,
    coalesce(nullif(p ->> 'product_name', ''), 'Producto'),
    coalesce(nullif(p ->> 'table_name', ''), ''),
    v_user, v_employee,
    private.fn_change_history_person(v_business, v_user, v_employee),
    coalesce((p ->> 'removed_at')::timestamptz, clock_timestamp()),
    v_changes, nullif(p ->> 'request_path', ''), (p ->> 'id')::uuid
  )
  on conflict (ref_id) where ref_id is not null do update
    set actor_employee_id = excluded.actor_employee_id,
        actor_name        = excluded.actor_name,
        changes           = excluded.changes;
end;
$$;

do $$
begin
  perform private.fn_change_history_upsert_removal(to_jsonb(r))
  from public.order_item_removals r
  where r.is_user_action
    and r.approved_by_employee_id is not null
    and exists (select 1 from public.change_history h where h.ref_id = r.id);
end;
$$;

-- 20261013_0002, textual.
create or replace function public.fn_change_history_on_order_void()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business uuid;
  v_table    text;
  v_paid     numeric;
  v_items    integer;
  v_ncf      text;
  v_actor    uuid := auth.uid();
begin
  begin
    if private.fn_change_history_called_from('fn_transfer_table_session') then
      return null;
    end if;

    select ts.business_id,
           case
             when dt.id is not null then coalesce(dt.label, dt.code, 'Mesa')
             when ts.origin::text = 'manual' then 'Venta manual'
             when ts.origin::text in ('quick', 'quick_sale') then 'Venta rápida'
             else 'Venta'
           end
      into v_business, v_table
    from public.table_sessions ts
    left join public.dining_tables dt on dt.id = ts.table_id
    where ts.id = new.session_id;
    v_business := coalesce((to_jsonb(new) ->> 'business_id')::uuid, v_business);
    if v_business is null then
      return null;
    end if;

    if exists (
      select 1 from public.change_history h
      where h.business_id = v_business
        and h.table_name = 'orders'
        and h.row_id = new.id::text
        and h.action = 'void'
    ) then
      return null;
    end if;

    -- La anulación pasa la orden a 'void' ANTES de cancelar los pagos y los
    -- ítems: aquí todavía se ven como estaban.
    select coalesce(sum(p.amount), 0)
      into v_paid
    from public.payments p
    where p.order_id = new.id
      and p.status = 'completed';

    select count(*)
      into v_items
    from public.order_items i
    where i.order_id = new.id
      and coalesce(i.status::text, 'draft') <> 'void'
      and (coalesce(i.status::text, 'draft') <> 'draft'
           or to_jsonb(i) ->> 'kitchen_sent_at' is not null);

    -- Mesa vacía o solo borradores: no salió nada ni se cobró nada.
    if v_paid = 0 and v_items = 0 then
      return null;
    end if;

    select string_agg(distinct coalesce(to_jsonb(fd) ->> 'ncf',
                                        to_jsonb(fd) ->> 'ncf_number'), ', ')
      into v_ncf
    from public.payments p
    join public.fiscal_documents fd on fd.id = p.fiscal_document_id
    where p.order_id = new.id
      and p.status = 'completed';

    insert into public.change_history (
      business_id, table_name, row_id, action, label, context,
      actor_user_id, actor_name, changes, source
    )
    values (
      v_business, 'orders', new.id::text, 'void', coalesce(v_table, 'Venta'),
      coalesce(v_ncf, ''), v_actor,
      private.fn_change_history_person(v_business, v_actor),
      jsonb_strip_nulls(jsonb_build_object(
        'total', new.total,
        'paid_total', nullif(v_paid, 0),
        'items_count', v_items,
        'ncf', v_ncf)),
      nullif(current_setting('request.path', true), '')
    );
  exception when others then
    raise warning 'fn_change_history_on_order_void: % (%)', sqlerrm, sqlstate;
  end;
  return null;
end;
$$;

revoke all on function private.fn_change_history_upsert_removal(jsonb) from public;
revoke all on function public.fn_change_history_on_order_void() from public, anon, authenticated;

commit;

notify pgrst, 'reload schema';
