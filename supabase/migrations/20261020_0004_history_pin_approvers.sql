-- =============================================================================
-- 20261020_0004 — Historial: quién AUTORIZÓ con su PIN un producto quitado o
--                 una mesa anulada / liberada
-- =============================================================================
--
-- PEDIDO DEL DUEÑO (2026-10-20): «en el historial debe decir quién aprobó un
-- borrado o una mesa liberada, con el PIN de quien lo aprobó».
--
-- CÓMO ESTABA:
--   * Productos quitados: order_item_removals ya guarda al aprobador validado
--     en el servidor (approved_by_employee_id, 20261005_0003), pero el
--     historial lo usaba como AUTOR (coalesce(aprobador, operador)): salía
--     «María quitó la Pizza» cuando la quitó Juan con el PIN de María, y no
--     se veía quién la pidió. Además el aprobador solo se sellaba DESPUÉS
--     (fn_approve_order_item_removal): si el borrado iba por la cola, el
--     sello llegaba antes que el borrado y se perdía. La aprobación de
--     20261020_0002 (token) sí viaja en la cola, pero nadie la copiaba.
--   * Anular / liberar una mesa: el PIN se validaba solo en la app (sí/no).
--     Nadie sabía quién lo autorizó; el historial ponía la cuenta del equipo.
--
-- QUÉ HACE:
--   1. order_item_removals toma al aprobador de la aprobación vigente de ese
--      producto en esa cuenta (order_item_removal_approvals, la que entrega
--      fn_issue_order_item_removal_approval al validar el PIN). Cada
--      aprobación sirve UNA vez por producto (used_item_ids). Sirve igual
--      para borrar y para bajar la cantidad: la app pide la aprobación para
--      los dos.
--   2. order_void_approvals + fn_issue_order_void_approval(orden, PIN,
--      operador): valida el PIN AQUÍ (fn_verify_employee_pin + rol
--      owner/admin/manager, igual que 20261020_0002). La app la llama justo
--      antes de anular o liberar. Vence en 30 minutos y se usa una vez.
--   3. Historial, productos quitados: autor = quien lo hizo (el operador del
--      PIN o la cuenta del equipo); changes.approved_by = quien autorizó (si
--      es otra persona). Las líneas ya escritas con el aprobador como autor
--      se corrigen (no las escribió nadie: el trigger eligió mal el autor).
--   4. Historial, cuenta anulada: si hubo aprobación, autor = el operador que
--      la pidió y changes.approved_by = quien autorizó. Una mesa sin nada
--      enviado ni cobrado se anota SOLO si alguien la autorizó con su PIN
--      (las que se liberan solas siguen sin anotarse: son ruido).
--   El PIN no se guarda en ningún lado.
--
-- SIN RED: la app no puede pedir la aprobación al servidor; esa anulación o
--   ese retiro quedan sin aprobador (como antes). El PIN nunca va a la cola.
--
-- REQUIERE 20261005_0003, 20261013_0001, 20261013_0002 y 20261020_0002.
-- IDEMPOTENTE. ROLLBACK: 20261020_0004_history_pin_approvers_ROLLBACK.sql
-- Prueba: supabase/tests/change_history_pin_approvers_local_test.sh
-- Aplicar en horario de poca venta (el trigger nuevo espera el candado de
-- order_item_removals; lock_timeout 5 s, si vence se vuelve a correr).
-- =============================================================================

begin;

set local lock_timeout = '5s';

do $$
begin
  if to_regclass('public.change_history') is null
     or to_regprocedure('private.fn_change_history_called_from(text)') is null then
    raise exception 'Faltan 20261013_0001 y 20261013_0002 (historial de cambios).';
  end if;
  if to_regclass('public.order_item_removal_approvals') is null then
    raise exception 'Falta 20261020_0002 (order_item_removal_approvals).';
  end if;
  if not exists (
    select 1 from pg_attribute
    where attrelid = 'public.order_item_removals'::regclass
      and attname = 'approved_by_employee_id' and not attisdropped
  ) then
    raise exception 'Falta 20261005_0003 (order_item_removals.approved_by_employee_id).';
  end if;
  if to_regprocedure('public.fn_verify_employee_pin(uuid, text)') is null
     or to_regprocedure('public.user_business_role(uuid, uuid)') is null
     or to_regprocedure('public.is_member_of_business(uuid)') is null then
    raise exception 'Faltan fn_verify_employee_pin / user_business_role / is_member_of_business.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Productos quitados: el aprobador sale de la aprobación vigente
-- ---------------------------------------------------------------------------
alter table public.order_item_removal_approvals
  add column if not exists used_item_ids uuid[] not null default '{}';

create or replace function public.fn_removal_take_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token    uuid;
  v_employee uuid;
  v_user     uuid;
  v_at       timestamptz;
begin
  begin
    if new.approved_by_employee_id is not null
       or new.order_id is null
       or not coalesce(new.is_user_action, false) then
      return new;
    end if;

    select ap.token, ap.approved_by_employee_id, ap.approved_by_user_id, ap.created_at
      into v_token, v_employee, v_user, v_at
    from public.order_item_removal_approvals ap
    where ap.order_id = new.order_id
      and new.item_id = any (ap.item_ids)
      and not (new.item_id = any (ap.used_item_ids))
      and ap.expires_at > now()
    order by ap.created_at desc
    limit 1
    for update;
    if v_token is null then
      return new;
    end if;

    update public.order_item_removal_approvals
       set used_item_ids = used_item_ids || new.item_id
     where token = v_token;

    new.approved_by_employee_id := v_employee;
    new.approved_by_user_id := v_user;
    new.approved_at := v_at;
  exception when others then
    raise warning 'fn_removal_take_approval: % (%)', sqlerrm, sqlstate;
  end;
  return new;
end;
$$;

drop trigger if exists trg_removal_take_approval on public.order_item_removals;
create trigger trg_removal_take_approval
  before insert on public.order_item_removals
  for each row
  execute function public.fn_removal_take_approval();

-- ---------------------------------------------------------------------------
-- 2. Anular / liberar una mesa con el PIN de un supervisor
-- ---------------------------------------------------------------------------
create table if not exists public.order_void_approvals (
  id                       uuid primary key default gen_random_uuid(),
  business_id              uuid not null,
  order_id                 uuid not null,
  approved_by_employee_id  uuid not null,
  approved_by_user_id      uuid,
  -- La cuenta del equipo (auth.uid()) y el operador que pidió anular.
  requested_by             uuid,
  requested_by_employee_id uuid,
  created_at               timestamptz not null default now(),
  expires_at               timestamptz not null default now() + interval '30 minutes',
  -- La anulación que la usó (una sola).
  used_at                  timestamptz
);
create index if not exists order_void_approvals_order_idx
  on public.order_void_approvals (order_id, created_at desc);
-- Solo por las funciones de abajo (security definer).
alter table public.order_void_approvals enable row level security;
revoke all on public.order_void_approvals from public, anon, authenticated;

comment on table public.order_void_approvals is
  'Quién autorizó con su PIN anular o liberar una mesa (20261020_0004). '
  'La crea fn_issue_order_void_approval; la usa el historial. Sin el PIN.';

create or replace function public.fn_issue_order_void_approval(
  p_order_id             uuid,
  p_approver_pin         text,
  p_operator_employee_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_business uuid;
  v_approver jsonb;
  v_employee uuid;
  v_user     uuid;
  v_role     text;
  v_operator uuid;
  v_name     text;
begin
  if v_uid is null then
    return jsonb_build_object('approved', false, 'error_code', 'UNAUTHENTICATED');
  end if;
  if p_order_id is null
     or p_approver_pin is null or btrim(p_approver_pin) = '' then
    return jsonb_build_object('approved', false, 'error_code', 'APPROVAL_REQUIRED');
  end if;

  select coalesce(ts.business_id, z.business_id)
    into v_business
    from public.orders o
    join public.table_sessions ts on ts.id = o.session_id
    left join public.dining_tables dt on dt.id = ts.table_id
    left join public.zones z on z.id = dt.zone_id
   where o.id = p_order_id;
  if v_business is null
     or not coalesce(public.is_member_of_business(v_business), false) then
    return jsonb_build_object('approved', false, 'error_code', 'ORDER_NOT_FOUND');
  end if;

  -- El PIN se valida aquí, no se le cree a la app (como 20261020_0002).
  v_approver := public.fn_verify_employee_pin(v_business, btrim(p_approver_pin));
  v_employee := nullif(v_approver ->> 'employee_id', '')::uuid;
  v_user := nullif(v_approver ->> 'user_id', '')::uuid;
  if v_user is not null then
    v_role := public.user_business_role(v_user, v_business);
  end if;
  if v_employee is null
     or v_role is null
     or v_role not in ('owner', 'admin', 'manager') then
    return jsonb_build_object('approved', false,
      'error_code', 'APPROVAL_DENIED',
      'error', 'PIN inválido o sin jerarquía de Supervisor/Administrador.');
  end if;

  -- El operador lo manda la app (el mesero con PIN): solo si es del negocio.
  select e.id
    into v_operator
    from public.employees e
   where e.id = p_operator_employee_id
     and e.business_id = v_business;

  insert into public.order_void_approvals (
    business_id, order_id, approved_by_employee_id, approved_by_user_id,
    requested_by, requested_by_employee_id
  )
  values (v_business, p_order_id, v_employee, v_user, v_uid, v_operator);

  select nullif(btrim(concat_ws(' ', e.first_name, e.last_name)), '')
    into v_name
    from public.employees e
   where e.id = v_employee;

  return jsonb_build_object('approved', true,
    'approver_employee_id', v_employee, 'approver_name', v_name);
end;
$$;

revoke all on function public.fn_issue_order_void_approval(uuid, text, uuid)
  from public, anon;
grant execute on function public.fn_issue_order_void_approval(uuid, text, uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Historial, productos quitados: quien lo hizo y quien autorizó, aparte
-- ---------------------------------------------------------------------------
-- Igual que 20261013_0001, salvo el autor (ya no es el aprobador) y
-- changes.approved_by.
create or replace function private.fn_change_history_upsert_removal(p jsonb)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_business uuid := (p ->> 'business_id')::uuid;
  v_user     uuid := (p ->> 'removed_by')::uuid;
  v_employee uuid := (p ->> 'reason_employee_id')::uuid;
  v_reduced  boolean := p ->> 'change_type' = 'reduced';
  v_actor    text;
  v_approver text;
  v_author   text;
  v_changes  jsonb;
begin
  if v_business is null or coalesce((p ->> 'is_user_action')::boolean, false) = false then
    return;
  end if;

  v_actor := private.fn_change_history_person(v_business, v_user, v_employee);
  if p ->> 'approved_by_employee_id' is not null then
    v_approver := private.fn_change_history_person(
      v_business, (p ->> 'approved_by_user_id')::uuid,
      (p ->> 'approved_by_employee_id')::uuid);
    -- Lo autorizó él mismo: no se repite.
    if v_approver is not distinct from v_actor then
      v_approver := null;
    end if;
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
    'approved_by', v_approver,
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
    v_user, v_employee, v_actor,
    coalesce((p ->> 'removed_at')::timestamptz, clock_timestamp()),
    v_changes, nullif(p ->> 'request_path', ''), (p ->> 'id')::uuid
  )
  on conflict (ref_id) where ref_id is not null do update
    set actor_employee_id = excluded.actor_employee_id,
        actor_name        = excluded.actor_name,
        changes           = excluded.changes;
end;
$$;

-- Las líneas ya escritas con el aprobador como autor.
do $$
begin
  perform private.fn_change_history_upsert_removal(to_jsonb(r))
  from public.order_item_removals r
  where r.is_user_action
    and r.approved_by_employee_id is not null
    and exists (select 1 from public.change_history h where h.ref_id = r.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Historial, cuenta anulada / mesa liberada: con el PIN de quién
-- ---------------------------------------------------------------------------
-- Igual que 20261013_0002, salvo la aprobación (autor = operador que la
-- pidió, changes.approved_by) y que una mesa vacía se anota si alguien la
-- autorizó.
create or replace function public.fn_change_history_on_order_void()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business    uuid;
  v_table       text;
  v_paid        numeric;
  v_items       integer;
  v_ncf         text;
  v_actor       uuid := auth.uid();
  v_employee    uuid;
  v_approval    uuid;
  v_approver_id uuid;
  v_approver_us uuid;
  v_actor_name  text;
  v_approver    text;
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

    -- ¿La autorizó alguien con su PIN? (la última aprobación sin usar)
    select ap.id, ap.approved_by_employee_id, ap.approved_by_user_id,
           ap.requested_by_employee_id
      into v_approval, v_approver_id, v_approver_us, v_employee
    from public.order_void_approvals ap
    where ap.order_id = new.id
      and ap.used_at is null
      and ap.expires_at > now()
    order by ap.created_at desc
    limit 1
    for update;

    -- Mesa vacía o solo borradores, y nadie la autorizó: no se anota.
    if v_paid = 0 and v_items = 0 and v_approval is null then
      return null;
    end if;

    if v_approval is not null then
      update public.order_void_approvals
         set used_at = now()
       where id = v_approval;
    end if;

    v_actor_name := private.fn_change_history_person(v_business, v_actor, v_employee);
    if v_approver_id is not null then
      v_approver := private.fn_change_history_person(
        v_business, v_approver_us, v_approver_id);
      if v_approver is not distinct from v_actor_name then
        v_approver := null;
      end if;
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
      actor_user_id, actor_employee_id, actor_name, changes, source
    )
    values (
      v_business, 'orders', new.id::text, 'void', coalesce(v_table, 'Venta'),
      coalesce(v_ncf, ''), v_actor, v_employee, v_actor_name,
      jsonb_strip_nulls(jsonb_build_object(
        'total', new.total,
        'paid_total', nullif(v_paid, 0),
        'items_count', v_items,
        'ncf', v_ncf,
        'approved_by', v_approver)),
      nullif(current_setting('request.path', true), '')
    );
  exception when others then
    raise warning 'fn_change_history_on_order_void: % (%)', sqlerrm, sqlstate;
  end;
  return null;
end;
$$;

revoke all on function public.fn_removal_take_approval() from public, anon, authenticated;
revoke all on function private.fn_change_history_upsert_removal(jsonb) from public;
revoke all on function public.fn_change_history_on_order_void() from public, anon, authenticated;

commit;

-- Sin esto la app no ve fn_issue_order_void_approval (PGRST202) hasta que se
-- reinicie el servidor de la API; la anulación sigue, pero sin aprobador.
notify pgrst, 'reload schema';

-- Verificación (correr aparte):
--   select tgname from pg_trigger where tgname = 'trg_removal_take_approval';
--   select changed_at, actor_name, label, changes ->> 'approved_by'
--     from public.change_history
--    where table_name in ('order_items', 'orders')
--    order by changed_at desc limit 20;
