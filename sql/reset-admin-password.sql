-- ==========================================================================
-- Catering Control · Restablecer el usuario administrador
-- Úsalo si quedaste sin poder entrar porque el usuario admin ya existía
-- en la base con la contraseña antigua (sin hash).
--
-- 1) Cambia el texto 'PON-AQUI-TU-CONTRASEÑA-NUEVA' de abajo por la
--    contraseña que quieras usar para entrar como Administrador.
-- 2) Pega TODO este script en el SQL Editor de tu proyecto de Supabase
--    y dale Run.
-- 3) Entra en login.html con:
--      Correo:      admin@catering.local
--      Contraseña:  la que hayas puesto abajo
-- 4) Una vez adentro, ve a Usuarios y crea tu(s) usuario(s) real(es) con
--    su propio correo (puedes dejar este admin@catering.local como
--    respaldo, o editarlo después con otra contraseña).
-- ==========================================================================

set search_path = public, extensions;

do $$
declare
  v_password text := 'PON-AQUI-TU-CONTRASEÑA-NUEVA';
  v_payload  jsonb;
  v_users    jsonb;
begin
  select payload into v_payload from db_personal where id = 'main';

  if v_payload is null then
    insert into db_personal (id, payload) values ('main', '{}'::jsonb);
    v_payload := '{}'::jsonb;
  end if;

  v_users := coalesce(v_payload -> 'staffUsers', '[]'::jsonb);

  -- Quita cualquier usuario anterior con este correo (con o sin contraseña
  -- hasheada), para no dejar dos copias.
  select coalesce(jsonb_agg(u), '[]'::jsonb) into v_users
  from jsonb_array_elements(v_users) as u
  where lower(u ->> 'email') <> 'admin@catering.local';

  -- Agrega el admin de nuevo, ya con la contraseña hasheada.
  v_users := v_users || jsonb_build_array(jsonb_build_object(
    'id', 'staff_admin',
    'username', 'admin',
    'email', 'admin@catering.local',
    'name', 'Administrador',
    'role', 'admin',
    'routeId', '',
    'driverId', '',
    'passwordHash', crypt(v_password, gen_salt('bf', 10))
  ));

  update db_personal
  set payload = jsonb_set(v_payload, '{staffUsers}', v_users, true)
  where id = 'main';
end $$;
