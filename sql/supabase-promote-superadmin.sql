-- ============================================================================
-- PROMOVER A SUPER ADMINISTRADOR
-- ============================================================================
-- staffUsers vive dentro de db_personal.payload (es un JSON, no una tabla de
-- columnas), así que para "editarlo" hay que reemplazar ese array completo
-- cambiando el rol del usuario que coincida con el correo indicado.
--
-- 1) Reemplaza 'tu_correo@ejemplo.com' por el CORREO (el mismo con el que
--    entras en la pestaña "Soy del equipo" del login) del usuario que quieres
--    volver Super Administrador.
-- 2) Supabase → SQL Editor → New query → pega esto → Run.
-- 3) Solo puede haber un Super Administrador: si ya hay otro, primero bájale
--    el rol a él (repite este mismo script apuntando a su correo, cambiando
--    'superadmin' por 'admin' en la línea del jsonb_build_object).
-- ============================================================================

update db_personal
set payload = jsonb_set(
  payload,
  '{staffUsers}',
  (
    select jsonb_agg(
      case
        when lower(elem->>'email') = lower('tu_correo@ejemplo.com')
          then elem || jsonb_build_object('role','superadmin')
        else elem
      end
    )
    from jsonb_array_elements(payload->'staffUsers') elem
  )
)
where id = 'main';

-- Verifica que quedó bien (debe aparecer tu usuario con role = "superadmin"):
select jsonb_pretty(payload->'staffUsers') from db_personal where id = 'main';
