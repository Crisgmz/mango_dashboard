-- 20260616_0001_resolve_user_names_rpc.sql
-- Scope:
--   Resolver nombres de usuarios (cajeros / meseros) para el dashboard admin.
--
-- Problema:
--   La tabla `profiles` solo tiene la politica RLS `profiles_select_own`
--   (id = auth.uid()), por lo que un admin/owner SOLO puede leer su propio
--   perfil. Al construir los cierres de caja, el rendimiento de cajeros/meseros
--   y la atribucion de descuentos, el dashboard intenta resolver el nombre de
--   OTROS usuarios y no obtiene filas -> se muestra "Desconocido" (cierres) o
--   se cae a etiquetas genericas ("Cajero" / "Mesero").
--
-- Solucion:
--   Un RPC SECURITY DEFINER que resuelve user_id -> nombre legible tomando el
--   mejor dato disponible (employees.first_name+last_name, luego
--   profiles.full_name y por ultimo la parte local del email), limitado a
--   usuarios que pertenecen a alguno de los negocios del llamante. Esto evita
--   ampliar la RLS de `profiles` (no expone toda la tabla a todo el personal)
--   y maneja tanto usuarios creados por el sistema de empleados como los
--   creados por el flujo legacy de `profiles`.

begin;

create or replace function public.fn_resolve_user_names(p_user_ids uuid[])
returns table(user_id uuid, display_name text)
language sql
stable
security definer
set search_path = public
as $$
  select
    i.uid as user_id,
    coalesce(
      -- 1) Sistema actual: empleados (nombre + apellido).
      nullif(btrim(concat_ws(' ', e.first_name, e.last_name)), ''),
      -- 2) Legacy: profiles.full_name.
      nullif(btrim(p.full_name), ''),
      -- 3) Ultimo recurso: parte local del correo (antes de la @).
      nullif(split_part(coalesce(p.email, e.email), '@', 1), '')
    ) as display_name
  from (select distinct unnest(p_user_ids) as uid) i
  left join lateral (
    select e.first_name, e.last_name, e.email
    from public.employees e
    where e.user_id = i.uid
      and e.business_id in (select public.current_user_business_ids())
    limit 1
  ) e on true
  left join lateral (
    select p.full_name, p.email
    from public.profiles p
    where p.id = i.uid
    limit 1
  ) p on true
  where
    -- Solo se resuelven usuarios que comparten un negocio con el llamante.
    exists (
      select 1 from public.employees e2
      where e2.user_id = i.uid
        and e2.business_id in (select public.current_user_business_ids())
    )
    or exists (
      select 1 from public.user_businesses ub
      where ub.user_id = i.uid
        and ub.business_id in (select public.current_user_business_ids())
    )
    or exists (
      select 1 from public.memberships m
      where m.user_id = i.uid
        and m.business_id in (select public.current_user_business_ids())
    );
$$;

comment on function public.fn_resolve_user_names(uuid[])
  is 'Resuelve user_id -> nombre legible (employees -> profiles.full_name -> email), limitado a usuarios del/los negocio(s) del llamante. Usado por el dashboard para cierres de caja, rendimiento de cajeros/meseros y atribucion de descuentos.';

grant execute on function public.fn_resolve_user_names(uuid[]) to authenticated;

commit;
