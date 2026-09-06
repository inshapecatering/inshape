-- #############################################################################
-- CATERING CONTROL · SQL COMPLETO PARA UN PROYECTO DE SUPABASE NUEVO
-- #############################################################################
-- Este archivo une, EN EL ORDEN CORRECTO, los 4 scripts que antes estaban
-- separados. Corré este archivo COMPLETO una sola vez, en una consulta
-- nueva del SQL Editor de Supabase, y ya queda todo instalado:
--
--   PARTE 1 — Tablas base + funciones de login sin candado de cliente
--             (archivo original: supabase-setup-completo.sql)
--   PARTE 2 — Cierre de seguridad: tokens de sesión + RLS cerrado en
--             todas las tablas (archivo original: supabase-security-lockdown.sql)
--   PARTE 3 — Candado de 3 intentos para el login de cliente, YA
--             CORREGIDO para que no rompa el token de sesión de la
--             Parte 2 (archivo original tenía este bug -- ver nota abajo)
--   PARTE 4 — Espacio de almacenamiento para imágenes (logo, fotos de
--             planes/choferes) por fuera de la base de datos
--             (archivo original: supabase-storage-setup.sql)
--
-- NOTA IMPORTANTE sobre la Parte 3: el archivo original
-- "supabase-login-cliente-lockout-migration.sql" se escribió ANTES que
-- el de la Parte 2. Si se corre en ese orden, la Parte 3 original
-- reemplaza la función de login de cliente por una versión que ya NO
-- devuelve el token de sesión que la Parte 2 dejó preparado -- es decir,
-- el login de cliente se vería exitoso pero nada después funcionaría.
-- Este archivo ya usa la versión corregida, que combina candado + token
-- correctamente, así que no tenés que preocuparte por esto: simplemente
-- corriendo TODO este archivo de una sola vez, en este orden, queda bien.
--
-- Los siguientes archivos NO forman parte de la instalación inicial y
-- NO están incluidos acá a propósito -- son scripts de mantenimiento que
-- se usan por separado, solo si hacen falta más adelante:
--   - reset-admin-password.sql      (si te quedás sin poder entrar)
--   - supabase-promote-superadmin.sql (para ascender a un usuario)
-- #############################################################################


-- #############################################################################
-- PARTE 1 de 4 — Tablas base y funciones de login
-- (contenido original de supabase-setup-completo.sql, sin cambios)
-- #############################################################################

-- =============================================================================
-- CATERING CONTROL · SETUP COMPLETO PARA UNA EMPRESA NUEVA (un solo archivo)
-- =============================================================================
-- Ejecuta este script UNA VEZ, completo, en el SQL Editor de un proyecto de
-- Supabase NUEVO (recién creado, vacío) cada vez que des de alta una empresa.
-- Es seguro volver a correrlo si algo falla a mitad de camino (todo usa
-- IF NOT EXISTS / OR REPLACE / DROP POLICY IF EXISTS).
--
-- Reemplaza, en un solo paso, a correr uno por uno:
--   supabase-setup-full.sql + supabase-clients-migration.sql +
--   supabase-audit-log-migration.sql + supabase-delivery-status-migration.sql +
--   supabase-dispatch-snapshots-migration.sql + supabase-notas-migration.sql +
--   supabase-premium-plan-migration.sql + supabase-public-branding-migration.sql +
--   supabase-address-override-migration.sql + migracion-retencion-auditoria.sql
--
-- Incluye:
--   · Tablas: db_clientes (legado), db_clientes_rows, db_personal,
--             db_inventario, db_audit_log, db_delivery_status,
--             db_dispatch_snapshots, db_notas_rows
--   · Funciones: login_cliente, login_staff, hash_password, get_branding,
--                get_plan_status, get_server_date, crear_nota_cliente,
--                set_client_address_override
--   · Políticas RLS de acceso público (anon/authenticated) + permisos de
--     secuencias
--   · Migración de clientes existentes (db_clientes → db_clientes_rows),
--     no rompe nada si el proyecto está vacío
--   · Limpieza automática con pg_cron: 7 días para delivery_status (fotos
--     de entrega), 1 año para dispatch_snapshots (historial de días
--     procesados), 15 días para audit_log
--
-- NO incluidos a propósito (llevan un dato tuyo, van aparte):
--   · reset-admin-password.sql   → fija la contraseña del admin inicial
--   · supabase-promote-superadmin.sql → vuelve Super Admin a un correo puntual
--
-- Después de correrlo, copia la URL y la "publishable key" del proyecto
-- (Project Settings → API) a config.js (supabaseUrl / supabaseKey).
-- =============================================================================

set search_path = public, extensions;

-- --------------------------------------------------------------------------
-- 1. Extensiones necesarias
-- --------------------------------------------------------------------------
create extension if not exists pgcrypto;
create extension if not exists pg_cron;  -- si da error de permisos, actívala
                                          -- desde Database → Extensions → pg_cron

-- --------------------------------------------------------------------------
-- 2. Tablas principales
-- --------------------------------------------------------------------------

-- Legado/respaldo: ya no se usa para la lista de clientes (ver
-- db_clientes_rows), se deja creada por compatibilidad.
create table if not exists db_clientes (
  id text primary key default 'main',
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- Clientes: UNA FILA POR CLIENTE.
create table if not exists db_clientes_rows (
  id text primary key,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- Personal: staffUsers, drivers, rutas y Configuración (settings).
create table if not exists db_personal (
  id text primary key default 'main',
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists db_inventario (
  id text primary key default 'main',
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- Historial de auditoría: solo se agregan filas, nunca se pisan.
create table if not exists db_audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor_id text,
  actor_name text,
  actor_role text,
  action text not null,
  entity_type text,
  entity_label text,
  entity_id text,
  details jsonb not null default '{}'::jsonb
);

-- Estado de entrega por (fecha, cliente) — menú "Despacho".
create table if not exists public.db_delivery_status (
  id          text primary key,          -- `${date}_${clientId}`
  date        date not null,
  client_id   text not null,
  payload     jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);

-- Snapshots (foto congelada) de cada "Procesar día".
create table if not exists public.db_dispatch_snapshots (
  date       date primary key,
  payload    jsonb not null,
  created_at timestamptz not null default now()
);

-- Notas (recordatorios del staff + mensajes de clientes) — una fila por nota.
create table if not exists db_notas_rows (
  id text primary key,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

-- Bloqueo por fuerza bruta del login de staff (ver login_staff más abajo).
create table if not exists public.db_login_attempts (
  email text primary key,
  fail_count int not null default 0,
  locked_until timestamptz,
  last_attempt timestamptz not null default now()
);

-- --------------------------------------------------------------------------
-- 3. Índices para rendimiento
-- --------------------------------------------------------------------------
create index if not exists db_audit_log_at_idx on db_audit_log (at desc);
create index if not exists db_delivery_status_date_idx on public.db_delivery_status (date);
create index if not exists db_delivery_status_client_idx on public.db_delivery_status (client_id);

-- --------------------------------------------------------------------------
-- 4. RLS y políticas de acceso público (con la clave "publishable"/anon,
--    tal como está armada la app hoy: login propio vía RPC, no Supabase Auth)
-- --------------------------------------------------------------------------
alter table db_clientes                  enable row level security;
alter table db_clientes_rows             enable row level security;
alter table db_personal                  enable row level security;
alter table db_inventario                enable row level security;
alter table db_audit_log                 enable row level security;
alter table public.db_delivery_status    enable row level security;
alter table public.db_dispatch_snapshots enable row level security;
alter table db_notas_rows                enable row level security;
alter table public.db_login_attempts     enable row level security;

drop policy if exists "public access clientes" on db_clientes;
create policy "public access clientes" on db_clientes for all using (true) with check (true);

drop policy if exists "public access clientes filas" on db_clientes_rows;
create policy "public access clientes filas" on db_clientes_rows for all using (true) with check (true);

drop policy if exists "public access personal" on db_personal;
create policy "public access personal" on db_personal for all using (true) with check (true);

drop policy if exists "public access inventario" on db_inventario;
create policy "public access inventario" on db_inventario for all using (true) with check (true);

drop policy if exists "public access audit log" on db_audit_log;
create policy "public access audit log" on db_audit_log for all using (true) with check (true);

drop policy if exists "delivery_status_select" on public.db_delivery_status;
create policy "delivery_status_select" on public.db_delivery_status for select to anon, authenticated using (true);
drop policy if exists "delivery_status_upsert" on public.db_delivery_status;
create policy "delivery_status_upsert" on public.db_delivery_status for insert to anon, authenticated with check (true);
drop policy if exists "delivery_status_update" on public.db_delivery_status;
create policy "delivery_status_update" on public.db_delivery_status for update to anon, authenticated using (true) with check (true);

drop policy if exists "dispatch_snapshots_all" on public.db_dispatch_snapshots;
create policy "dispatch_snapshots_all" on public.db_dispatch_snapshots for all using (true) with check (true);

drop policy if exists "notas_select" on db_notas_rows;
create policy "notas_select" on db_notas_rows for select using (true);
drop policy if exists "notas_insert" on db_notas_rows;
create policy "notas_insert" on db_notas_rows for insert with check (true);
drop policy if exists "notas_update" on db_notas_rows;
create policy "notas_update" on db_notas_rows for update using (true) with check (true);
drop policy if exists "notas_delete" on db_notas_rows;
create policy "notas_delete" on db_notas_rows for delete using (true);

-- db_login_attempts: SIN acceso público — solo la toca login_staff() del
-- lado del servidor (SECURITY DEFINER). A diferencia de las demás tablas,
-- acá no se le da nada a anon/authenticated a propósito.
drop policy if exists "no public access login attempts" on public.db_login_attempts;
create policy "no public access login attempts" on public.db_login_attempts for all using (false) with check (false);

-- RLS no alcanza si el rol no tiene permiso a nivel de tabla/secuencia:
grant select, insert on db_audit_log to anon, authenticated;
grant usage, select on sequence db_audit_log_id_seq to anon, authenticated;

-- --------------------------------------------------------------------------
-- 5. Funciones de login, hash, branding, plan y fecha de servidor
-- --------------------------------------------------------------------------

create or replace function login_cliente(p_carnet text, p_phone text)
returns table(id text, name text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_phone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
begin
  return query
  select db_clientes_rows.id, payload ->> 'name'
  from db_clientes_rows
  where lower(trim(coalesce(payload ->> 'carnet', ''))) = lower(trim(coalesce(p_carnet, '')))
    and (
      regexp_replace(coalesce(payload ->> 'phone1', ''), '\D', '', 'g') = v_phone
      or regexp_replace(coalesce(payload ->> 'phone2', ''), '\D', '', 'g') = v_phone
    )
  limit 1;
end;
$$;
revoke all on function login_cliente(text, text) from public;
grant execute on function login_cliente(text, text) to anon, authenticated;

drop function if exists login_staff(text, text);
create or replace function login_staff(p_email text, p_password text)
returns table(id text, name text, role text, "routeId" text, "driverId" text, locked_seconds int)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_users jsonb;
  v_email text := lower(trim(coalesce(p_email, '')));
  v_attempt db_login_attempts%rowtype;
  v_matched boolean := false;
  v_new_fail_count int;
  v_remaining int;
begin
  -- Bloqueo por fuerza bruta: 3 intentos fallidos seguidos con el mismo
  -- correo lo bloquean 1 minuto (ver punto 5 del pedido original). El
  -- conteo vive en la base de datos (db_login_attempts), no en el
  -- navegador, porque cualquiera que llame a esta función directo se
  -- saltaría un contador hecho solo en JavaScript.
  select * into v_attempt from db_login_attempts where email = v_email;
  if found and v_attempt.locked_until is not null and v_attempt.locked_until > now() then
    v_remaining := ceil(extract(epoch from (v_attempt.locked_until - now())));
    return query select null::text, null::text, null::text, null::text, null::text, greatest(v_remaining, 1);
    return;
  end if;

  select coalesce(payload -> 'staffUsers', '[]'::jsonb) into v_users from db_personal where db_personal.id = 'main';

  if v_users is null or jsonb_array_length(v_users) = 0 then
    if v_email = 'admin@catering.local' and p_password = 'admin123' then
      v_matched := true;
    end if;
  else
    v_matched := exists(
      select 1 from jsonb_array_elements(v_users) as u
      where lower(u ->> 'email') = v_email
        and u ->> 'passwordHash' is not null
        and crypt(p_password, u ->> 'passwordHash') = (u ->> 'passwordHash')
    );
  end if;

  if v_matched then
    delete from db_login_attempts where email = v_email;
    if v_users is null or jsonb_array_length(v_users) = 0 then
      return query select 'staff_admin'::text, 'Administrador'::text, 'admin'::text, ''::text, ''::text, 0;
    else
      return query
      select u ->> 'id', u ->> 'name', u ->> 'role', u ->> 'routeId', u ->> 'driverId', 0
      from jsonb_array_elements(v_users) as u
      where lower(u ->> 'email') = v_email
        and u ->> 'passwordHash' is not null
        and crypt(p_password, u ->> 'passwordHash') = (u ->> 'passwordHash')
      limit 1;
    end if;
    return;
  end if;

  v_new_fail_count := coalesce(v_attempt.fail_count, 0) + 1;
  if v_new_fail_count >= 3 then
    insert into db_login_attempts (email, fail_count, locked_until, last_attempt)
      values (v_email, 0, now() + interval '1 minute', now())
    on conflict (email) do update
      set fail_count = 0, locked_until = now() + interval '1 minute', last_attempt = now();
  else
    insert into db_login_attempts (email, fail_count, locked_until, last_attempt)
      values (v_email, v_new_fail_count, null, now())
    on conflict (email) do update
      set fail_count = v_new_fail_count, locked_until = null, last_attempt = now();
  end if;

  return;
end;
$$;
revoke all on function login_staff(text, text) from public;
grant execute on function login_staff(text, text) to anon, authenticated;

create or replace function hash_password(p_password text)
returns text
language sql
security definer
set search_path = public, extensions
as $$
  select crypt(p_password, gen_salt('bf', 10));
$$;
revoke all on function hash_password(text) from public;
grant execute on function hash_password(text) to anon, authenticated;

create or replace function get_branding()
returns jsonb
language sql
security definer
set search_path = public, extensions
as $$
  select coalesce(payload -> 'settings', '{}'::jsonb)
  from db_personal
  where id = 'main';
$$;
revoke all on function get_branding() from public;
grant execute on function get_branding() to anon, authenticated;

create or replace function public.get_plan_status()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'plan', coalesce(payload->'settings'->>'plan', 'basico')
  )
  from db_personal
  where id = 'main';
$$;
grant execute on function public.get_plan_status() to anon, authenticated;

create or replace function get_server_date()
returns text
language sql
security definer
stable
as $$
  select to_char(now() at time zone 'utc', 'YYYY-MM-DD');
$$;
grant execute on function get_server_date() to anon, authenticated;

-- --------------------------------------------------------------------------
-- 6. Notas creadas por el cliente desde su portal (sin darle acceso directo
--    a la tabla db_notas_rows)
-- --------------------------------------------------------------------------
create or replace function crear_nota_cliente(p_client_id text, p_texto text)
returns text
language plpgsql
security definer
as $$
declare
  v_id text := 'n_' || substr(md5(random()::text || clock_timestamp()::text), 1, 12);
  v_client_name text;
begin
  if p_texto is null or length(trim(p_texto)) = 0 then
    raise exception 'El mensaje no puede estar vacío';
  end if;

  select payload->>'name' into v_client_name
  from db_clientes_rows where id = p_client_id;

  insert into db_notas_rows (id, payload, updated_at)
  values (
    v_id,
    jsonb_build_object(
      'text', trim(p_texto),
      'dueDate', to_char(current_date, 'YYYY-MM-DD'),
      'status', 'pendiente',
      'source', 'cliente',
      'clientId', p_client_id,
      'clientName', coalesce(v_client_name, ''),
      'createdAt', now(),
      'read', false
    ),
    now()
  );

  return v_id;
end;
$$;
grant execute on function crear_nota_cliente(text, text) to anon;

-- --------------------------------------------------------------------------
-- 7. Cambio de dirección de mañana desde el portal de cliente (direcciones
--    múltiples). Toda la validación ocurre en el servidor: no confía en el
--    reloj del navegador del cliente.
-- --------------------------------------------------------------------------
create or replace function public.set_client_address_override(
  p_client_id text,
  p_address_id text,
  p_date text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_row db_clientes_rows%rowtype;
  v_now_bo timestamptz := now() at time zone 'America/La_Paz';
  v_addr_exists boolean;
  v_overrides jsonb;
begin
  if extract(hour from v_now_bo) >= 22 then
    raise exception 'Ya pasó el horario para cambiar la dirección (22:00 hora Bolivia).';
  end if;

  select * into v_row from db_clientes_rows where id = p_client_id;
  if not found then
    raise exception 'Cliente no encontrado.';
  end if;

  select exists(
    select 1 from jsonb_array_elements(coalesce(v_row.payload->'addresses', '[]'::jsonb)) a
    where a->>'id' = p_address_id
  ) into v_addr_exists;
  if not v_addr_exists then
    raise exception 'Esa dirección no pertenece a este cliente.';
  end if;

  select coalesce(
    (select jsonb_agg(o) from jsonb_array_elements(coalesce(v_row.payload->'addressOverrides', '[]'::jsonb)) o
     where o->>'date' <> p_date),
    '[]'::jsonb
  ) into v_overrides;
  v_overrides := v_overrides || jsonb_build_array(jsonb_build_object('date', p_date, 'addressId', p_address_id));

  update db_clientes_rows
    set payload = jsonb_set(payload, '{addressOverrides}', v_overrides, true),
        updated_at = now()
    where id = p_client_id;

  return v_overrides;
end;
$$;
revoke all on function public.set_client_address_override(text, text, text) from public;
grant execute on function public.set_client_address_override(text, text, text) to anon, authenticated;

-- --------------------------------------------------------------------------
-- 8. Datos iniciales (filas "main" — la app las crea sola igual si faltan)
-- --------------------------------------------------------------------------
insert into db_clientes (id, payload) values ('main', '{}'::jsonb) on conflict (id) do nothing;
insert into db_personal (id, payload) values ('main', '{}'::jsonb) on conflict (id) do nothing;
insert into db_inventario (id, payload) values ('main', '{}'::jsonb) on conflict (id) do nothing;

-- --------------------------------------------------------------------------
-- 9. Migración de clientes existentes (si el proyecto ya tenía datos en
--    db_clientes; en un proyecto nuevo/vacío esto simplemente no copia nada)
-- --------------------------------------------------------------------------
insert into db_clientes_rows (id, payload)
select
  coalesce(c ->> 'id', gen_random_uuid()::text) as id,
  c as payload
from db_clientes, jsonb_array_elements(coalesce(payload -> 'clients', '[]'::jsonb)) as c
where db_clientes.id = 'main'
on conflict (id) do update set payload = excluded.payload, updated_at = now();

-- --------------------------------------------------------------------------
-- 10. Limpieza automática con pg_cron
-- --------------------------------------------------------------------------

-- delivery_status: 7 días (son fotos de respaldo de entrega — solo hacen
-- falta para reclamos de los últimos días, no para siempre), todos los días
-- a la 1 AM UTC.
do $do$
begin
  perform cron.schedule(
    'delivery-status-cleanup',
    '0 1 * * *',
    $cron$ delete from public.db_delivery_status where date < (now() - interval '7 days')::date; $cron$
  );
exception when others then
  raise notice 'No se pudo programar el cron de delivery_status (revisa permisos/pg_cron).';
end $do$;

-- dispatch_snapshots: 1 año (son el historial congelado de "Día de
-- trabajo" ya procesado — mucho más valioso que las fotos, se guarda bastante
-- más tiempo), todos los días a la 1 AM UTC.
do $do$
begin
  perform cron.schedule(
    'delete-old-dispatch-snapshots',
    '0 1 * * *',
    $cron$ delete from public.db_dispatch_snapshots where date < (current_date - interval '1 year'); $cron$
  );
exception when others then
  raise notice 'No se pudo programar el cron de dispatch_snapshots (revisa permisos/pg_cron).';
end $do$;

-- audit_log: 15 días, todos los días a las 04:00 UTC (00:00 hora Bolivia).
do $do$
begin
  perform cron.unschedule('borrar-auditoria-vieja')
  where exists (select 1 from cron.job where jobname = 'borrar-auditoria-vieja');

  perform cron.schedule(
    'borrar-auditoria-vieja',
    '0 4 * * *',
    $cron$ delete from db_audit_log where at < now() - interval '15 days'; $cron$
  );
exception when others then
  raise notice 'No se pudo programar el cron de audit_log (revisa permisos/pg_cron).';
end $do$;

-- db_login_attempts: borra correos que ya no insisten (probados por bots),
-- todos los días a las 04:30 UTC.
do $do$
begin
  perform cron.schedule(
    'limpiar-intentos-login-viejos',
    '30 4 * * *',
    $cron$ delete from public.db_login_attempts where last_attempt < now() - interval '1 day'; $cron$
  );
exception when others then
  raise notice 'No se pudo programar el cron de limpieza de intentos de login (revisa permisos/pg_cron).';
end $do$;

-- =============================================================================
-- FIN DEL SCRIPT. Verificaciones útiles después de correrlo:
--   select * from db_personal;                 -- debe existir la fila 'main'
--   select * from db_clientes_rows limit 5;
--   select get_branding();
--   select get_plan_status();
--   select * from cron.job;                    -- los 4 jobs de limpieza programados
--
-- Después de esto, corre por separado (llevan un dato tuyo):
--   reset-admin-password.sql       → contraseña del admin inicial
--   supabase-promote-superadmin.sql → vuelve Super Admin a un correo puntual
-- =============================================================================


-- #############################################################################
-- PARTE 2 de 4 — Cierre de seguridad: tokens de sesión + RLS cerrado
-- (contenido original de supabase-security-lockdown.sql, sin cambios)
-- #############################################################################

-- =============================================================================
-- CATERING CONTROL · CIERRE DE SEGURIDAD (sesiones + RPCs + RLS real)
-- =============================================================================
-- Por qué: hoy TODAS las tablas db_* (menos db_login_attempts) tienen
-- políticas "for all using (true) with check (true)". Eso significa que
-- cualquiera con la clave publishable de config.js -- que es pública por
-- diseño, viaja en el HTML -- puede leer, escribir Y BORRAR esas tablas
-- directo por REST, sin loguearse nunca. Se comprobó en la práctica:
--   .../rest/v1/db_personal?select=*&apikey=<publishable key>
-- devuelve el JSON completo, incluidos los passwordHash de staffUsers.
-- Peor todavía: db_clientes_rows guarda carnet/phone1/phone2 en texto
-- plano -- son literalmente las credenciales del portal cliente.
--
-- La causa raíz: login_staff/login_cliente autentican bien, pero nunca
-- emitieron nada verificable server-side después -- el navegador solo
-- guardaba {id, role} en sessionStorage. Sin eso, ninguna política RLS
-- puede distinguir "admin ya logueado" de "cualquiera con la anon key".
--
-- La solución: una tabla de sesiones (db_sessions) con un token random de
-- 256 bits que login_staff/login_cliente emiten al autenticar bien, y que
-- el navegador manda de ahí en más en cada operación. Todas las tablas
-- sensibles pasan a RLS `using (false)` (nadie entra por REST directo, ni
-- con la anon key) y el acceso real ocurre exclusivamente a través de
-- funciones RPC `security definer` que validan ese token antes de tocar
-- la tabla -- mismo patrón que ya usan login_staff/login_cliente/
-- crear_nota_cliente hoy, solo que ahora se aplica a TODO.
--
-- Cómo correr esto: Supabase Dashboard → SQL Editor → pegar y ejecutar
-- completo, una sola vez, DESPUÉS de supabase-setup-completo.sql. Es
-- seguro volver a correrlo (todo usa IF NOT EXISTS / OR REPLACE / DROP
-- POLICY IF EXISTS / DROP FUNCTION IF EXISTS).
--
-- IMPORTANTE: este script tiene que desplegarse JUNTO con el
-- supabase-client.js / login.html / index.html / cliente.html nuevos que
-- lo acompañan -- las funciones viejas login_staff(text,text) y
-- login_cliente(text,text) (2 parámetros) se BORRAN acá, y las páginas
-- viejas que todavía las llamen con la firma vieja van a fallar. No lo
-- corras contra el sitio en producción sin subir los archivos nuevos casi
-- al mismo tiempo.
--
-- Lo que NO se toca en este script (alcance separado, ver nota al final):
--   · Storage (bucket app-images): sigue con subir/reemplazar/borrar
--     abiertos a la anon key. Es un riesgo menor (imágenes, no datos de
--     clientes/contraseñas) pero queda pendiente.
--   · Permisos por rol dentro del staff (hoy cualquier sesión de staff
--     válida -- admin, editor, cocina o driver -- puede llamar cualquier
--     RPC staff_*; la app ya oculta en el front lo que cada rol no debería
--     ver/tocar, pero el backend no lo vuelve a chequear todavía). Es una
--     mejora aparte si la querés más adelante.
-- =============================================================================

set search_path = public, extensions;

-- --------------------------------------------------------------------------
-- 1. Tabla de sesiones
-- --------------------------------------------------------------------------
create table if not exists public.db_sessions (
  token         text primary key,
  subject_type  text not null check (subject_type in ('staff','cliente')),
  subject_id    text not null,
  subject_name  text,
  role          text,                 -- solo aplica a subject_type='staff'
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default now() + interval '30 days'
);
create index if not exists db_sessions_subject_idx on public.db_sessions (subject_type, subject_id);

alter table public.db_sessions enable row level security;
drop policy if exists "no public access sessions" on public.db_sessions;
create policy "no public access sessions" on public.db_sessions for all using (false) with check (false);
-- (a propósito: nadie entra por REST directo, ni para leer ni para escribir
-- sesiones -- solo las funciones de abajo, que son security definer y por
-- lo tanto corren como dueñas de la tabla, sin pasar por RLS)

-- --------------------------------------------------------------------------
-- 2. Funciones internas de validación de sesión (NO se exponen a anon)
-- --------------------------------------------------------------------------
create or replace function public._staff_session(p_token text)
returns table(subject_id text, subject_name text, role text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id text; v_name text; v_role text;
begin
  select s.subject_id, s.subject_name, s.role into v_id, v_name, v_role
  from db_sessions s
  where s.token = p_token and s.subject_type = 'staff' and s.expires_at > now();

  if not found then
    raise exception 'Sesión inválida o expirada. Vuelve a iniciar sesión.';
  end if;

  update db_sessions set expires_at = now() + interval '30 days' where token = p_token;
  return query select v_id, v_name, v_role;
end;
$$;
revoke all on function public._staff_session(text) from public;

create or replace function public._require_staff(p_token text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform public._staff_session(p_token);
end;
$$;
revoke all on function public._require_staff(text) from public;

create or replace function public._cliente_session(p_token text)
returns table(subject_id text, subject_name text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id text; v_name text;
begin
  select s.subject_id, s.subject_name into v_id, v_name
  from db_sessions s
  where s.token = p_token and s.subject_type = 'cliente' and s.expires_at > now();

  if not found then
    raise exception 'Sesión inválida o expirada. Vuelve a iniciar sesión.';
  end if;

  update db_sessions set expires_at = now() + interval '30 days' where token = p_token;
  return query select v_id, v_name;
end;
$$;
revoke all on function public._cliente_session(text) from public;

create or replace function public._require_cliente_owns(p_token text, p_client_id text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_id text;
begin
  select subject_id into v_id from public._cliente_session(p_token);
  if v_id is distinct from p_client_id then
    raise exception 'No autorizado.';
  end if;
end;
$$;
revoke all on function public._require_cliente_owns(text, text) from public;

-- --------------------------------------------------------------------------
-- 3. Logout real (borra la sesión del lado del servidor)
-- --------------------------------------------------------------------------
create or replace function public.revoke_session(p_token text)
returns void
language sql
security definer
set search_path = public, extensions
as $$
  delete from db_sessions where token = p_token;
$$;
grant execute on function public.revoke_session(text) to anon, authenticated;

-- --------------------------------------------------------------------------
-- 4. login_staff / login_cliente: ahora emiten session_token
--    (misma lógica de siempre -- bloqueo por fuerza bruta, bcrypt, admin
--    por defecto si todavía no hay staffUsers -- solo se agrega el token)
-- --------------------------------------------------------------------------
drop function if exists login_cliente(text, text);
create or replace function login_cliente(p_carnet text, p_phone text)
returns table(id text, name text, session_token text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_id text; v_name text; v_token text;
begin
  select db_clientes_rows.id, payload ->> 'name' into v_id, v_name
  from db_clientes_rows
  where lower(trim(coalesce(payload ->> 'carnet', ''))) = lower(trim(coalesce(p_carnet, '')))
    and (
      regexp_replace(coalesce(payload ->> 'phone1', ''), '\D', '', 'g') = v_phone
      or regexp_replace(coalesce(payload ->> 'phone2', ''), '\D', '', 'g') = v_phone
    )
  limit 1;

  if v_id is null then
    return;
  end if;

  v_token := encode(gen_random_bytes(32), 'hex');
  insert into db_sessions (token, subject_type, subject_id, subject_name, role)
  values (v_token, 'cliente', v_id, v_name, null);

  return query select v_id, v_name, v_token;
end;
$$;
revoke all on function login_cliente(text, text) from public;
grant execute on function login_cliente(text, text) to anon, authenticated;

drop function if exists login_staff(text, text);
create or replace function login_staff(p_email text, p_password text)
returns table(id text, name text, role text, "routeId" text, "driverId" text, locked_seconds int, session_token text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_users jsonb;
  v_email text := lower(trim(coalesce(p_email, '')));
  v_attempt db_login_attempts%rowtype;
  v_new_fail_count int;
  v_remaining int;
  v_id text; v_name text; v_role text; v_routeId text; v_driverId text;
  v_token text;
begin
  select * into v_attempt from db_login_attempts where email = v_email;
  if found and v_attempt.locked_until is not null and v_attempt.locked_until > now() then
    v_remaining := ceil(extract(epoch from (v_attempt.locked_until - now())));
    return query select null::text, null::text, null::text, null::text, null::text, greatest(v_remaining, 1), null::text;
    return;
  end if;

  select coalesce(payload -> 'staffUsers', '[]'::jsonb) into v_users from db_personal where db_personal.id = 'main';

  if v_users is null or jsonb_array_length(v_users) = 0 then
    if v_email = 'admin@catering.local' and p_password = 'admin123' then
      v_id := 'staff_admin'; v_name := 'Administrador'; v_role := 'admin'; v_routeId := ''; v_driverId := '';
    end if;
  else
    select u ->> 'id', u ->> 'name', u ->> 'role', u ->> 'routeId', u ->> 'driverId'
      into v_id, v_name, v_role, v_routeId, v_driverId
    from jsonb_array_elements(v_users) as u
    where lower(u ->> 'email') = v_email
      and u ->> 'passwordHash' is not null
      and crypt(p_password, u ->> 'passwordHash') = (u ->> 'passwordHash')
    limit 1;
  end if;

  if v_id is not null then
    delete from db_login_attempts where email = v_email;
    v_token := encode(gen_random_bytes(32), 'hex');
    insert into db_sessions (token, subject_type, subject_id, subject_name, role)
    values (v_token, 'staff', v_id, v_name, v_role);
    return query select v_id, v_name, v_role, v_routeId, v_driverId, 0, v_token;
    return;
  end if;

  v_new_fail_count := coalesce(v_attempt.fail_count, 0) + 1;
  if v_new_fail_count >= 3 then
    insert into db_login_attempts (email, fail_count, locked_until, last_attempt)
      values (v_email, 0, now() + interval '1 minute', now())
    on conflict (email) do update
      set fail_count = 0, locked_until = now() + interval '1 minute', last_attempt = now();
  else
    insert into db_login_attempts (email, fail_count, locked_until, last_attempt)
      values (v_email, v_new_fail_count, null, now())
    on conflict (email) do update
      set fail_count = v_new_fail_count, locked_until = null, last_attempt = now();
  end if;

  return;
end;
$$;
revoke all on function login_staff(text, text) from public;
grant execute on function login_staff(text, text) to anon, authenticated;

-- --------------------------------------------------------------------------
-- 5. Catálogo público del portal (plans/days/currentDate) -- lo necesita
--    cliente.html SIN sesión de staff (no es información sensible, es el
--    mismo criterio que ya tiene get_branding()).
-- --------------------------------------------------------------------------
create or replace function public.get_portal_catalog()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_result jsonb;
begin
  select coalesce(jsonb_object_agg(id, payload), '{}'::jsonb) into v_result
  from db_clientes where id in ('plans','days','currentDate');

  if v_result = '{}'::jsonb then
    select payload into v_result from db_clientes where id = 'main';
  end if;

  return coalesce(v_result, '{}'::jsonb);
end;
$$;
grant execute on function public.get_portal_catalog() to anon, authenticated;

-- --------------------------------------------------------------------------
-- 6. RPCs de staff (cualquier sesión de staff válida -- admin/editor/
--    cocina/driver; el front ya oculta lo que cada rol no debería usar)
-- --------------------------------------------------------------------------

-- clientes / personal / inventario: bloque completo (id='main', legado)
create or replace function public.staff_get_block(p_token text, p_table_key text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_payload jsonb;
begin
  perform public._require_staff(p_token);
  if p_table_key = 'clientes' then
    select payload into v_payload from db_clientes where id = 'main';
  elsif p_table_key = 'personal' then
    select payload into v_payload from db_personal where id = 'main';
  elsif p_table_key = 'inventario' then
    select payload into v_payload from db_inventario where id = 'main';
  else
    raise exception 'Tabla no permitida.';
  end if;
  return v_payload;
end;
$$;
revoke all on function public.staff_get_block(text, text) from public;
grant execute on function public.staff_get_block(text, text) to anon, authenticated;

create or replace function public.staff_set_block(p_token text, p_table_key text, p_payload jsonb)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform public._require_staff(p_token);
  if p_table_key = 'clientes' then
    insert into db_clientes (id, payload, updated_at) values ('main', p_payload, now())
      on conflict (id) do update set payload = excluded.payload, updated_at = now();
  elsif p_table_key = 'personal' then
    insert into db_personal (id, payload, updated_at) values ('main', p_payload, now())
      on conflict (id) do update set payload = excluded.payload, updated_at = now();
  elsif p_table_key = 'inventario' then
    insert into db_inventario (id, payload, updated_at) values ('main', p_payload, now())
      on conflict (id) do update set payload = excluded.payload, updated_at = now();
  else
    raise exception 'Tabla no permitida.';
  end if;
  return true;
end;
$$;
revoke all on function public.staff_set_block(text, text, jsonb) from public;
grant execute on function public.staff_set_block(text, text, jsonb) to anon, authenticated;

-- clientes / personal / inventario: por campo (settings, staffUsers,
-- drivers, routes, plans, days, currentDate, inventory...)
create or replace function public.staff_get_fields(p_token text, p_table_key text, p_ids text[])
returns table(id text, payload jsonb)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform public._require_staff(p_token);
  if p_ids is null or array_length(p_ids, 1) is null then return; end if;
  if p_table_key = 'clientes' then
    return query select r.id, r.payload from db_clientes r where r.id = any(p_ids);
  elsif p_table_key = 'personal' then
    return query select r.id, r.payload from db_personal r where r.id = any(p_ids);
  elsif p_table_key = 'inventario' then
    return query select r.id, r.payload from db_inventario r where r.id = any(p_ids);
  else
    raise exception 'Tabla no permitida.';
  end if;
end;
$$;
revoke all on function public.staff_get_fields(text, text, text[]) from public;
grant execute on function public.staff_get_fields(text, text, text[]) to anon, authenticated;

create or replace function public.staff_set_fields(p_token text, p_table_key text, p_fields jsonb)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_key text; v_val jsonb;
begin
  perform public._require_staff(p_token);
  if p_table_key not in ('clientes','personal','inventario') then
    raise exception 'Tabla no permitida.';
  end if;
  for v_key, v_val in select * from jsonb_each(coalesce(p_fields, '{}'::jsonb)) loop
    if p_table_key = 'clientes' then
      insert into db_clientes (id, payload, updated_at) values (v_key, v_val, now())
        on conflict (id) do update set payload = excluded.payload, updated_at = now();
    elsif p_table_key = 'personal' then
      insert into db_personal (id, payload, updated_at) values (v_key, v_val, now())
        on conflict (id) do update set payload = excluded.payload, updated_at = now();
    elsif p_table_key = 'inventario' then
      insert into db_inventario (id, payload, updated_at) values (v_key, v_val, now())
        on conflict (id) do update set payload = excluded.payload, updated_at = now();
    end if;
  end loop;
  return true;
end;
$$;
revoke all on function public.staff_set_fields(text, text, jsonb) from public;
grant execute on function public.staff_set_fields(text, text, jsonb) to anon, authenticated;

-- clientes (una fila por cliente)
create or replace function public.staff_get_client_rows(p_token text)
returns table(id text, payload jsonb)
language plpgsql security definer set search_path = public, extensions
as $$ begin perform public._require_staff(p_token); return query select r.id, r.payload from db_clientes_rows r; end; $$;
revoke all on function public.staff_get_client_rows(text) from public;
grant execute on function public.staff_get_client_rows(text) to anon, authenticated;

create or replace function public.staff_get_client_row_ids(p_token text)
returns table(id text)
language plpgsql security definer set search_path = public, extensions
as $$ begin perform public._require_staff(p_token); return query select r.id from db_clientes_rows r; end; $$;
revoke all on function public.staff_get_client_row_ids(text) from public;
grant execute on function public.staff_get_client_row_ids(text) to anon, authenticated;

create or replace function public.staff_get_client_rows_since(p_token text, p_since timestamptz)
returns table(id text, payload jsonb)
language plpgsql security definer set search_path = public, extensions
as $$ begin perform public._require_staff(p_token); return query select r.id, r.payload from db_clientes_rows r where r.updated_at >= p_since; end; $$;
revoke all on function public.staff_get_client_rows_since(text, timestamptz) from public;
grant execute on function public.staff_get_client_rows_since(text, timestamptz) to anon, authenticated;

create or replace function public.staff_get_client_row(p_token text, p_id text)
returns table(id text, payload jsonb)
language plpgsql security definer set search_path = public, extensions
as $$ begin perform public._require_staff(p_token); return query select r.id, r.payload from db_clientes_rows r where r.id = p_id; end; $$;
revoke all on function public.staff_get_client_row(text, text) from public;
grant execute on function public.staff_get_client_row(text, text) to anon, authenticated;

create or replace function public.staff_upsert_client_rows(p_token text, p_rows jsonb)
returns boolean
language plpgsql security definer set search_path = public, extensions
as $$
declare v_row jsonb;
begin
  perform public._require_staff(p_token);
  for v_row in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    insert into db_clientes_rows (id, payload, updated_at) values (v_row ->> 'id', v_row, now())
    on conflict (id) do update set payload = excluded.payload, updated_at = now();
  end loop;
  return true;
end; $$;
revoke all on function public.staff_upsert_client_rows(text, jsonb) from public;
grant execute on function public.staff_upsert_client_rows(text, jsonb) to anon, authenticated;

create or replace function public.staff_delete_client_rows(p_token text, p_ids text[])
returns boolean
language plpgsql security definer set search_path = public, extensions
as $$ begin perform public._require_staff(p_token); delete from db_clientes_rows where id = any(p_ids); return true; end; $$;
revoke all on function public.staff_delete_client_rows(text, text[]) from public;
grant execute on function public.staff_delete_client_rows(text, text[]) to anon, authenticated;

-- notas (recordatorios + mensajes de clientes)
create or replace function public.staff_get_note_rows(p_token text)
returns table(id text, payload jsonb)
language plpgsql security definer set search_path = public, extensions
as $$ begin perform public._require_staff(p_token); return query select r.id, r.payload from db_notas_rows r; end; $$;
revoke all on function public.staff_get_note_rows(text) from public;
grant execute on function public.staff_get_note_rows(text) to anon, authenticated;

create or replace function public.staff_upsert_note_rows(p_token text, p_rows jsonb)
returns boolean
language plpgsql security definer set search_path = public, extensions
as $$
declare v_row jsonb;
begin
  perform public._require_staff(p_token);
  for v_row in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    insert into db_notas_rows (id, payload, updated_at) values (v_row ->> 'id', v_row, now())
    on conflict (id) do update set payload = excluded.payload, updated_at = now();
  end loop;
  return true;
end; $$;
revoke all on function public.staff_upsert_note_rows(text, jsonb) from public;
grant execute on function public.staff_upsert_note_rows(text, jsonb) to anon, authenticated;

create or replace function public.staff_delete_note_rows(p_token text, p_ids text[])
returns boolean
language plpgsql security definer set search_path = public, extensions
as $$ begin perform public._require_staff(p_token); delete from db_notas_rows where id = any(p_ids); return true; end; $$;
revoke all on function public.staff_delete_note_rows(text, text[]) from public;
grant execute on function public.staff_delete_note_rows(text, text[]) to anon, authenticated;

-- auditoría (actor forzado desde la sesión, nunca desde lo que mande el
-- navegador -- así nadie puede insertar una entrada haciéndose pasar por
-- otro usuario)
create or replace function public.staff_insert_audit(p_token text, p_entry jsonb)
returns boolean
language plpgsql security definer set search_path = public, extensions
as $$
declare v_id text; v_name text; v_role text;
begin
  select subject_id, subject_name, role into v_id, v_name, v_role from public._staff_session(p_token);
  insert into db_audit_log (actor_id, actor_name, actor_role, action, entity_type, entity_label, entity_id, details)
  values (v_id, v_name, v_role,
    coalesce(p_entry->>'action', ''),
    p_entry->>'entity_type', p_entry->>'entity_label', p_entry->>'entity_id',
    coalesce(p_entry->'details', '{}'::jsonb));
  return true;
end; $$;
revoke all on function public.staff_insert_audit(text, jsonb) from public;
grant execute on function public.staff_insert_audit(text, jsonb) to anon, authenticated;

create or replace function public.staff_get_audit_log(p_token text, p_limit int default 200)
returns setof db_audit_log
language plpgsql security definer set search_path = public, extensions
as $$ begin perform public._require_staff(p_token); return query select * from db_audit_log order by at desc limit p_limit; end; $$;
revoke all on function public.staff_get_audit_log(text, int) from public;
grant execute on function public.staff_get_audit_log(text, int) to anon, authenticated;

create or replace function public.staff_get_all_audit_log(p_token text, p_since timestamptz default null)
returns setof db_audit_log
language plpgsql security definer set search_path = public, extensions
as $$
begin
  perform public._require_staff(p_token);
  if p_since is null then
    return query select * from db_audit_log order by at desc;
  else
    return query select * from db_audit_log where at >= p_since order by at desc;
  end if;
end; $$;
revoke all on function public.staff_get_all_audit_log(text, timestamptz) from public;
grant execute on function public.staff_get_all_audit_log(text, timestamptz) to anon, authenticated;

-- restauración desde backup: acá SÍ se respetan los actor_* del archivo
-- (son historial ya ocurrido, no tiene sentido reetiquetarlo con quien
-- restaura)
create or replace function public.staff_insert_audit_bulk(p_token text, p_entries jsonb)
returns boolean
language plpgsql security definer set search_path = public, extensions
as $$
declare v_e jsonb;
begin
  perform public._require_staff(p_token);
  for v_e in select * from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb)) loop
    insert into db_audit_log (at, actor_id, actor_name, actor_role, action, entity_type, entity_label, entity_id, details)
    values (
      coalesce((v_e->>'at')::timestamptz, now()),
      v_e->>'actor_id', v_e->>'actor_name', v_e->>'actor_role',
      coalesce(v_e->>'action', ''), v_e->>'entity_type', v_e->>'entity_label', v_e->>'entity_id',
      coalesce(v_e->'details', '{}'::jsonb)
    );
  end loop;
  return true;
end; $$;
revoke all on function public.staff_insert_audit_bulk(text, jsonb) from public;
grant execute on function public.staff_insert_audit_bulk(text, jsonb) to anon, authenticated;

-- snapshots ("Procesar día")
create or replace function public.staff_upsert_snapshot(p_token text, p_date date, p_payload jsonb)
returns boolean
language plpgsql security definer set search_path = public, extensions
as $$
begin
  perform public._require_staff(p_token);
  insert into db_dispatch_snapshots (date, payload, created_at) values (p_date, p_payload, now())
  on conflict (date) do update set payload = excluded.payload, created_at = now();
  return true;
end; $$;
revoke all on function public.staff_upsert_snapshot(text, date, jsonb) from public;
grant execute on function public.staff_upsert_snapshot(text, date, jsonb) to anon, authenticated;

create or replace function public.staff_get_snapshot(p_token text, p_date date)
returns table(date date, payload jsonb, created_at timestamptz)
language plpgsql security definer set search_path = public, extensions
as $$ begin perform public._require_staff(p_token); return query select s.date, s.payload, s.created_at from db_dispatch_snapshots s where s.date = p_date; end; $$;
revoke all on function public.staff_get_snapshot(text, date) from public;
grant execute on function public.staff_get_snapshot(text, date) to anon, authenticated;

create or replace function public.staff_list_snapshot_dates(p_token text)
returns table(date date, created_at timestamptz)
language plpgsql security definer set search_path = public, extensions
as $$ begin perform public._require_staff(p_token); return query select s.date, s.created_at from db_dispatch_snapshots s order by s.date desc; end; $$;
revoke all on function public.staff_list_snapshot_dates(text) from public;
grant execute on function public.staff_list_snapshot_dates(text) to anon, authenticated;

create or replace function public.staff_get_all_snapshots(p_token text, p_since date default null)
returns table(date date, payload jsonb)
language plpgsql security definer set search_path = public, extensions
as $$
begin
  perform public._require_staff(p_token);
  if p_since is null then
    return query select s.date, s.payload from db_dispatch_snapshots s;
  else
    return query select s.date, s.payload from db_dispatch_snapshots s where s.date >= p_since;
  end if;
end; $$;
revoke all on function public.staff_get_all_snapshots(text, date) from public;
grant execute on function public.staff_get_all_snapshots(text, date) to anon, authenticated;

create or replace function public.staff_upsert_snapshots_bulk(p_token text, p_snapshots jsonb)
returns boolean
language plpgsql security definer set search_path = public, extensions
as $$
declare v_s jsonb;
begin
  perform public._require_staff(p_token);
  for v_s in select * from jsonb_array_elements(coalesce(p_snapshots, '[]'::jsonb)) loop
    insert into db_dispatch_snapshots (date, payload, created_at)
    values ((v_s->>'date')::date, v_s->'payload', now())
    on conflict (date) do update set payload = excluded.payload, created_at = now();
  end loop;
  return true;
end; $$;
revoke all on function public.staff_upsert_snapshots_bulk(text, jsonb) from public;
grant execute on function public.staff_upsert_snapshots_bulk(text, jsonb) to anon, authenticated;

-- despacho (estado de entrega por fecha+cliente)
create or replace function public.staff_get_delivery_rows(p_token text, p_date date)
returns table(id text, client_id text, payload jsonb)
language plpgsql security definer set search_path = public, extensions
as $$ begin perform public._require_staff(p_token); return query select r.id, r.client_id, r.payload from db_delivery_status r where r.date = p_date; end; $$;
revoke all on function public.staff_get_delivery_rows(text, date) from public;
grant execute on function public.staff_get_delivery_rows(text, date) to anon, authenticated;

create or replace function public.staff_upsert_delivery_rows(p_token text, p_rows jsonb)
returns boolean
language plpgsql security definer set search_path = public, extensions
as $$
declare v_r jsonb;
begin
  perform public._require_staff(p_token);
  for v_r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    insert into db_delivery_status (id, date, client_id, payload, updated_at)
    values ((v_r->>'date') || '_' || (v_r->>'clientId'), (v_r->>'date')::date, v_r->>'clientId', v_r->'payload', now())
    on conflict (id) do update set payload = excluded.payload, updated_at = now();
  end loop;
  return true;
end; $$;
revoke all on function public.staff_upsert_delivery_rows(text, jsonb) from public;
grant execute on function public.staff_upsert_delivery_rows(text, jsonb) to anon, authenticated;

create or replace function public.staff_get_all_delivery_status(p_token text, p_since date default null)
returns table(date date, client_id text, payload jsonb)
language plpgsql security definer set search_path = public, extensions
as $$
begin
  perform public._require_staff(p_token);
  if p_since is null then
    return query select r.date, r.client_id, r.payload from db_delivery_status r;
  else
    return query select r.date, r.client_id, r.payload from db_delivery_status r where r.date >= p_since;
  end if;
end; $$;
revoke all on function public.staff_get_all_delivery_status(text, date) from public;
grant execute on function public.staff_get_all_delivery_status(text, date) to anon, authenticated;

-- --------------------------------------------------------------------------
-- 7. RPCs del portal cliente (sesión propia, SOLO su propia fila, y con
--    lista blanca de campos editables -- nunca puede tocar carnet/phone/
--    price/plan/deliveryOrder aunque los mande en el payload)
-- --------------------------------------------------------------------------
create or replace function public.cliente_get_own_profile(p_token text, p_client_id text)
returns table(id text, payload jsonb)
language plpgsql security definer set search_path = public, extensions
as $$
begin
  perform public._require_cliente_owns(p_token, p_client_id);
  return query select r.id, r.payload from db_clientes_rows r where r.id = p_client_id;
end; $$;
revoke all on function public.cliente_get_own_profile(text, text) from public;
grant execute on function public.cliente_get_own_profile(text, text) to anon, authenticated;

create or replace function public.cliente_save_profile(p_token text, p_client_id text, p_updates jsonb)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_row db_clientes_rows%rowtype;
  v_new jsonb;
  v_allowed text[] := array['pauseStart','returnDate','status','pauseDates','activeAddressId'];
  v_key text;
begin
  perform public._require_cliente_owns(p_token, p_client_id);

  select * into v_row from db_clientes_rows where id = p_client_id;
  if not found then
    raise exception 'Cliente no encontrado.';
  end if;

  v_new := v_row.payload;
  foreach v_key in array v_allowed loop
    if p_updates ? v_key then
      v_new := jsonb_set(v_new, array[v_key], coalesce(p_updates -> v_key, 'null'::jsonb), true);
    end if;
  end loop;

  -- "status" solo puede ser uno de estos 3 valores -- si mandan cualquier
  -- otra cosa se ignora y se conserva el valor que ya había.
  if p_updates ? 'status' and not (p_updates->>'status' in ('Programado','Pausado','Activo')) then
    v_new := jsonb_set(v_new, '{status}', coalesce(v_row.payload->'status', 'null'::jsonb), true);
  end if;

  update db_clientes_rows set payload = v_new, updated_at = now() where id = p_client_id;
  return true;
end;
$$;
revoke all on function public.cliente_save_profile(text, text, jsonb) from public;
grant execute on function public.cliente_save_profile(text, text, jsonb) to anon, authenticated;

create or replace function public.cliente_insert_audit(p_token text, p_client_id text, p_entry jsonb)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_name text;
begin
  perform public._require_cliente_owns(p_token, p_client_id);
  select subject_name into v_name from public._cliente_session(p_token);
  insert into db_audit_log (actor_id, actor_name, actor_role, action, entity_type, entity_label, entity_id, details)
  values (p_client_id, coalesce(v_name, ''), 'cliente',
    coalesce(p_entry->>'action', ''), p_entry->>'entity_type', p_entry->>'entity_label', p_client_id,
    coalesce(p_entry->'details', '{}'::jsonb));
  return true;
end;
$$;
revoke all on function public.cliente_insert_audit(text, text, jsonb) from public;
grant execute on function public.cliente_insert_audit(text, text, jsonb) to anon, authenticated;

-- --------------------------------------------------------------------------
-- 8. Se le agrega sesión a crear_nota_cliente y set_client_address_override
--    (antes cualquiera podía llamarlas con CUALQUIER p_client_id sin
--    loguearse -- spam de notas falsas o cambiar la dirección de mañana de
--    un cliente que no es el suyo)
-- --------------------------------------------------------------------------
drop function if exists crear_nota_cliente(text, text);
create or replace function crear_nota_cliente(p_token text, p_client_id text, p_texto text)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id text := 'n_' || substr(md5(random()::text || clock_timestamp()::text), 1, 12);
  v_client_name text;
begin
  perform public._require_cliente_owns(p_token, p_client_id);

  if p_texto is null or length(trim(p_texto)) = 0 then
    raise exception 'El mensaje no puede estar vacío';
  end if;

  select payload->>'name' into v_client_name from db_clientes_rows where id = p_client_id;

  insert into db_notas_rows (id, payload, updated_at)
  values (
    v_id,
    jsonb_build_object(
      'text', trim(p_texto), 'dueDate', to_char(current_date, 'YYYY-MM-DD'),
      'status', 'pendiente', 'source', 'cliente', 'clientId', p_client_id,
      'clientName', coalesce(v_client_name, ''), 'createdAt', now(), 'read', false
    ),
    now()
  );

  return v_id;
end;
$$;
revoke all on function crear_nota_cliente(text, text, text) from public;
grant execute on function crear_nota_cliente(text, text, text) to anon;

drop function if exists public.set_client_address_override(text, text, text);
create or replace function public.set_client_address_override(
  p_token text,
  p_client_id text,
  p_address_id text,
  p_date text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_row db_clientes_rows%rowtype;
  v_now_bo timestamptz := now() at time zone 'America/La_Paz';
  v_addr_exists boolean;
  v_overrides jsonb;
begin
  perform public._require_cliente_owns(p_token, p_client_id);

  if extract(hour from v_now_bo) >= 22 then
    raise exception 'Ya pasó el horario para cambiar la dirección (22:00 hora Bolivia).';
  end if;

  select * into v_row from db_clientes_rows where id = p_client_id;
  if not found then
    raise exception 'Cliente no encontrado.';
  end if;

  select exists(
    select 1 from jsonb_array_elements(coalesce(v_row.payload->'addresses', '[]'::jsonb)) a
    where a->>'id' = p_address_id
  ) into v_addr_exists;
  if not v_addr_exists then
    raise exception 'Esa dirección no pertenece a este cliente.';
  end if;

  select coalesce(
    (select jsonb_agg(o) from jsonb_array_elements(coalesce(v_row.payload->'addressOverrides', '[]'::jsonb)) o
     where o->>'date' <> p_date),
    '[]'::jsonb
  ) into v_overrides;
  v_overrides := v_overrides || jsonb_build_array(jsonb_build_object('date', p_date, 'addressId', p_address_id));

  update db_clientes_rows
    set payload = jsonb_set(payload, '{addressOverrides}', v_overrides, true),
        updated_at = now()
    where id = p_client_id;

  return v_overrides;
end;
$$;
revoke all on function public.set_client_address_override(text, text, text, text) from public;
grant execute on function public.set_client_address_override(text, text, text, text) to anon, authenticated;

-- --------------------------------------------------------------------------
-- 9. CIERRE DE RLS: se hace al final, después de que ya existen todas las
--    funciones de reemplazo. De acá en más, NADA de esto se lee/escribe
--    por REST directo con la anon key -- solo por las funciones de arriba.
-- --------------------------------------------------------------------------
drop policy if exists "public access clientes" on db_clientes;
create policy "no direct access clientes" on db_clientes for all using (false) with check (false);

drop policy if exists "public access clientes filas" on db_clientes_rows;
create policy "no direct access clientes filas" on db_clientes_rows for all using (false) with check (false);

drop policy if exists "public access personal" on db_personal;
create policy "no direct access personal" on db_personal for all using (false) with check (false);

drop policy if exists "public access inventario" on db_inventario;
create policy "no direct access inventario" on db_inventario for all using (false) with check (false);

drop policy if exists "public access audit log" on db_audit_log;
create policy "no direct access audit log" on db_audit_log for all using (false) with check (false);
revoke select, insert on db_audit_log from anon, authenticated;

drop policy if exists "delivery_status_select" on public.db_delivery_status;
drop policy if exists "delivery_status_upsert" on public.db_delivery_status;
drop policy if exists "delivery_status_update" on public.db_delivery_status;
drop policy if exists "no direct access delivery status" on public.db_delivery_status;
create policy "no direct access delivery status" on public.db_delivery_status for all using (false) with check (false);

drop policy if exists "dispatch_snapshots_all" on public.db_dispatch_snapshots;
create policy "no direct access dispatch snapshots" on public.db_dispatch_snapshots for all using (false) with check (false);

drop policy if exists "notas_select" on db_notas_rows;
drop policy if exists "notas_insert" on db_notas_rows;
drop policy if exists "notas_update" on db_notas_rows;
drop policy if exists "notas_delete" on db_notas_rows;
create policy "no direct access notas" on db_notas_rows for all using (false) with check (false);

-- =============================================================================
-- FIN. Verificaciones útiles después de correrlo:
--   select * from login_staff('admin@catering.local','admin123');  -- debe
--     traer session_token
--   select public.staff_get_block(
--     (select session_token from login_staff('admin@catering.local','admin123')),
--     'personal'
--   );  -- debe traer el payload
--
-- Y para confirmar que el hueco se tapó, probá SIN sesión (esto ahora
-- tiene que devolver un array vacío, no el JSON con los passwordHash):
--   curl "https://<tu-proyecto>.supabase.co/rest/v1/db_personal?select=*&apikey=<publishable key>"
-- =============================================================================


-- #############################################################################
-- PARTE 3 de 4 — Candado de 3 intentos para login de cliente (CORREGIDO
-- para incluir el session_token que dejó preparado la Parte 2 -- ver la
-- nota grande al principio de este archivo)
-- #############################################################################

-- ============================================================================
-- Catering Control · Candado de fuerza bruta para login_cliente + token de
-- sesión (VERSIÓN CORREGIDA)
-- ----------------------------------------------------------------------------
-- Por qué existe esta versión: el archivo original
-- "supabase-login-cliente-lockout-migration.sql" se escribió ANTES que
-- "supabase-security-lockdown.sql". Si se corre el lockdown primero (que
-- hace que login_cliente devuelva un session_token) y DESPUÉS se corre el
-- archivo original del candado, ese archivo reemplaza login_cliente por una
-- versión que ya no devuelve session_token — el login de cliente deja de
-- funcionar (no hay token que guardar ni que mandar en las llamadas
-- siguientes). Esta versión une las dos cosas: candado de 3 intentos +
-- token de sesión.
--
-- Cuándo correr esto: SIEMPRE después de supabase-security-lockdown.sql
-- (este archivo asume que la tabla db_sessions ya existe).
--
-- Cómo correr esto: Supabase Dashboard → SQL Editor → pegar y ejecutar
-- completo, una sola vez. Es seguro volver a correrlo.
-- ============================================================================

set search_path = public, extensions;

-- --------------------------------------------------------------------------
-- 1. Tabla de intentos por carnet (igual que en el archivo original).
-- --------------------------------------------------------------------------
create table if not exists public.db_client_login_attempts (
  carnet       text primary key,
  fail_count   int not null default 0,
  locked_until timestamptz,
  last_attempt timestamptz not null default now()
);

alter table public.db_client_login_attempts enable row level security;

drop policy if exists "no public access client login attempts" on public.db_client_login_attempts;
create policy "no public access client login attempts"
  on public.db_client_login_attempts for all using (false) with check (false);

-- --------------------------------------------------------------------------
-- 2. login_cliente con candado Y session_token.
-- --------------------------------------------------------------------------
drop function if exists login_cliente(text, text);
create or replace function login_cliente(p_carnet text, p_phone text)
returns table(id text, name text, locked_seconds int, session_token text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_carnet text := lower(trim(coalesce(p_carnet, '')));
  v_phone  text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_attempt public.db_client_login_attempts%rowtype;
  v_matched_id text;
  v_matched_name text;
  v_new_fail_count int;
  v_remaining int;
  v_token text;
begin
  select * into v_attempt from public.db_client_login_attempts where carnet = v_carnet;
  if found and v_attempt.locked_until is not null and v_attempt.locked_until > now() then
    v_remaining := ceil(extract(epoch from (v_attempt.locked_until - now())));
    return query select null::text, null::text, greatest(v_remaining, 1), null::text;
    return;
  end if;

  select db_clientes_rows.id, payload ->> 'name'
    into v_matched_id, v_matched_name
  from db_clientes_rows
  where lower(trim(coalesce(payload ->> 'carnet', ''))) = v_carnet
    and (
      regexp_replace(coalesce(payload ->> 'phone1', ''), '\D', '', 'g') = v_phone
      or regexp_replace(coalesce(payload ->> 'phone2', ''), '\D', '', 'g') = v_phone
    )
  limit 1;

  if v_matched_id is not null then
    delete from public.db_client_login_attempts where carnet = v_carnet;
    v_token := encode(gen_random_bytes(32), 'hex');
    insert into db_sessions (token, subject_type, subject_id, subject_name, role)
    values (v_token, 'cliente', v_matched_id, v_matched_name, null);
    return query select v_matched_id, v_matched_name, 0, v_token;
    return;
  end if;

  v_new_fail_count := coalesce(v_attempt.fail_count, 0) + 1;
  if v_new_fail_count >= 3 then
    insert into public.db_client_login_attempts (carnet, fail_count, locked_until, last_attempt)
      values (v_carnet, 0, now() + interval '1 minute', now())
    on conflict (carnet) do update
      set fail_count = 0, locked_until = now() + interval '1 minute', last_attempt = now();
  else
    insert into public.db_client_login_attempts (carnet, fail_count, locked_until, last_attempt)
      values (v_carnet, v_new_fail_count, null, now())
    on conflict (carnet) do update
      set fail_count = v_new_fail_count, locked_until = null, last_attempt = now();
  end if;

  return;
end;
$$;
revoke all on function login_cliente(text, text) from public;
grant execute on function login_cliente(text, text) to anon, authenticated;

-- --------------------------------------------------------------------------
-- 3. Limpieza automática de intentos viejos (igual que el archivo original).
-- --------------------------------------------------------------------------
do $do$
begin
  perform cron.unschedule('limpiar-intentos-login-cliente-viejos')
  where exists (select 1 from cron.job where jobname = 'limpiar-intentos-login-cliente-viejos');

  perform cron.schedule(
    'limpiar-intentos-login-cliente-viejos',
    '30 4 * * *',
    $cron$ delete from public.db_client_login_attempts where last_attempt < now() - interval '1 day'; $cron$
  );
exception when others then
  raise notice 'No se pudo programar el cron de limpieza de intentos de login de cliente (revisa permisos/pg_cron).';
end $do$;

-- ============================================================================
-- FIN. Verificación después de correrlo:
--   select * from login_cliente('carnet_de_prueba', 'telefono_de_prueba');
--   -- debe devolver una fila con id, name y un session_token (texto largo).
--   select login_cliente('carnet_de_prueba', '00000000'); -- 3 veces seguidas
--   -- la 3ra debe devolver locked_seconds > 0.
-- ============================================================================


-- #############################################################################
-- PARTE 4 de 4 — Almacenamiento de imágenes
-- (contenido original de supabase-storage-setup.sql, sin cambios)
-- #############################################################################

-- ============================================================================
-- Catering Control · Storage para imágenes (logo, foto publicitaria, fotos de
-- drivers/planes, íconos de menú, fotos de respaldo de entrega)
-- ============================================================================
-- Por qué: hoy esas imágenes viven como base64 DENTRO de las filas de
-- Postgres (db_personal, db_clientes, db_delivery_status). Eso significa que
-- CADA VEZ que la app lee esas filas -- que pasa muy seguido: al iniciar
-- sesión, en cada guardado, y cada 12s mientras Despacho está abierto -- se
-- vuelve a bajar el peso completo de todas esas imágenes juntas, aunque no
-- hayan cambiado. Eso es lo que está inflando la "Salida" (egress) del plan
-- gratuito de Supabase.
--
-- La solución: guardar las imágenes en un bucket de Storage y dejar en la
-- fila de Postgres solo la URL pública (un texto cortito). Las imágenes
-- entonces se sirven como cualquier archivo estático -- el navegador las
-- cachea normal -- y ya no viajan pegadas al JSON cada vez que se lee/graba
-- clientes/personal/delivery_status.
--
-- Cómo correr esto: Supabase Dashboard → SQL Editor → pegar y ejecutar
-- completo, una sola vez por proyecto (o por cliente, si administrás varios
-- tenants -- cada uno tiene su propio proyecto de Supabase con este mismo
-- script).
-- ============================================================================

-- 1) Crear el bucket (público: cualquiera con la URL puede VER la imagen,
--    igual que hoy con el base64 embebido -- no es información sensible).
insert into storage.buckets (id, name, public)
values ('app-images', 'app-images', true)
on conflict (id) do nothing;

-- 2) Policies del bucket.
-- Mismo criterio de seguridad que ya tiene el resto de la base (RLS abierto,
-- decisión tuya de prototipo sin autenticación real de Supabase todavía):
-- se permite subir/reemplazar/borrar con la clave publishable (anon), igual
-- que hoy se puede leer/escribir cualquier tabla db_* sin restricción.

drop policy if exists "app-images: lectura pública" on storage.objects;
create policy "app-images: lectura pública"
  on storage.objects for select
  using (bucket_id = 'app-images');

drop policy if exists "app-images: subir" on storage.objects;
create policy "app-images: subir"
  on storage.objects for insert
  with check (bucket_id = 'app-images');

drop policy if exists "app-images: reemplazar" on storage.objects;
create policy "app-images: reemplazar"
  on storage.objects for update
  using (bucket_id = 'app-images');

drop policy if exists "app-images: borrar" on storage.objects;
create policy "app-images: borrar"
  on storage.objects for delete
  using (bucket_id = 'app-images');

-- ============================================================================
-- Nota para cuando más adelante se agregue autenticación real de Supabase
-- (hoy el login es con usuarios propios en db_personal, no con Supabase Auth):
-- estas policies habría que endurecerlas a auth.role() = 'authenticated' en
-- vez de dejarlas abiertas a cualquiera con la clave publishable, igual que
-- el resto de las tablas db_*.
-- ============================================================================


-- #############################################################################
-- FIN DEL ARCHIVO COMPLETO. Verificaciones sugeridas después de correrlo:
--   select * from login_staff('admin@catering.local', 'admin123');
--     -- debe traer una fila con session_token.
--   select * from login_cliente('carnet_de_prueba', 'telefono_de_prueba');
--     -- debe traer una fila con id, name, locked_seconds=0 y session_token.
-- #############################################################################
