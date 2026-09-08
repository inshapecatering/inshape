// Catering Control · Edge Function: resolve-maps-link
// ============================================================================
// Objetivo 2 del prompt de direcciones múltiples: los links cortos de Google
// Maps (https://maps.app.goo.gl/xxxx o https://goo.gl/maps/xxxx) no traen
// coordenadas en el texto del link, y el navegador NO puede seguir la
// redirección para descubrir la URL larga (CORS lo bloquea). Esta función
// corre en el servidor de Supabase, donde sí se puede seguir la redirección
// sin problema de CORS, y devuelve las coordenadas ya extraídas.
//
// Cómo se despliega (una sola vez por proyecto de Supabase):
//   1) Instala la CLI de Supabase si no la tienes: https://supabase.com/docs/guides/cli
//   2) Desde la carpeta del proyecto (donde está la carpeta supabase-functions):
//        supabase login
//        supabase link --project-ref TU_PROJECT_REF   (lo ves en Settings → General)
//        supabase functions deploy resolve-maps-link --no-verify-jwt
//      --no-verify-jwt es necesario porque el portal/panel llaman a la
//      función con la clave "publishable" (anon), no con un JWT de usuario.
//   3) Listo. index.js/driver.js ya están preparados para llamarla sola,
//      en silencio, cuando detectan un link corto sin coordenadas (ver
//      resolveShortMapsLinksForClient() en esos archivos). Si esta función
//      no está desplegada, simplemente no pasa nada: el link se guarda tal
//      cual y el geocoding por texto (Nominatim) sigue de respaldo.
//
// Entrada (POST body JSON):  { "url": "https://maps.app.goo.gl/xxxx" }
// Salida (200 JSON):         { "lat": -16.5, "lng": -68.15, "resolvedUrl": "..." } en éxito
//                             { "error": "mensaje", "resolvedUrl": "..." } si no se pudo resolver
//                             (resolvedUrl es la URL larga a la que redirigió el link corto,
//                             solo para diagnóstico manual — el frontend la ignora)
// ============================================================================

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Mismo patrón de coordenadas "sueltas" que ya usa el frontend
// (extractLatLngFromMapsField en index.js/driver.js), para que el resultado
// sea consistente sin importar si el link se resolvió acá o en el navegador.
function extractLatLng(text: string): { lat: number; lng: number } | null {
  if (!text) return null;
  // Orden importa: primero los patrones más precisos. "!3d..!4d.." es la
  // coordenada EXACTA del pin dentro de un link de "lugar" de Google Maps —
  // por eso necesita su PROPIO patrón (no comparte uno con "@lat,lng": ese
  // formato no lleva coma entre los dos números, van separados por "!4d",
  // así que un patrón que exige coma nunca lo matchea, y en la práctica
  // siempre terminaba cayendo al "@lat,lng" de más abajo). "@lat,lng" es
  // solo el centro de la cámara del mapa al compartir y puede venir corrido
  // de la ubicación real, así que se prueba último entre los que sí tienen
  // coordenadas explícitas en la URL.
  const patterns = [
    /!3d(-?\d{1,3}\.\d+)!4d(-?\d{1,3}\.\d+)/,   // .../data=!...!3d-16.5233!4d-68.0889...
    /q=(-?\d+\.\d+),(-?\d+\.\d+)/,              // ?q=-16.54,-68.05
    /ll=(-?\d+\.\d+),(-?\d+\.\d+)/,             // ?ll=-16.54,-68.05
    /@(-?\d{1,3}\.\d+),\s*(-?\d{1,3}\.\d+)/,    // .../@-16.54,-68.05,17z
    /(-?\d{1,3}\.\d{3,}),\s*(-?\d{1,3}\.\d{3,})/, // "-16.54, -68.05" sueltos
  ];
  for (const re of patterns) {
    const m = text.match(re);
    if (m) {
      const lat = parseFloat(m[1]);
      const lng = parseFloat(m[2]);
      if (!isNaN(lat) && !isNaN(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180) {
        return { lat, lng };
      }
    }
  }
  return null;
}

async function resolveShortLink(url: string): Promise<string | null> {
  try {
    // "follow" deja que fetch siga TODAS las redirecciones (los links
    // cortos de Google suelen encadenar 2-3 saltos) y res.url termina
    // siendo la URL larga y final.
    const res = await fetch(url, { redirect: 'follow', headers: { 'User-Agent': 'Mozilla/5.0' } });
    return res.url || null;
  } catch (_) {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Método no soportado, usa POST.' }), {
      status: 405,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }

  try {
    const { url } = await req.json();
    if (!url || typeof url !== 'string') {
      return new Response(JSON.stringify({ error: 'Falta el campo "url".' }), {
        status: 400,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    // Si el link ya trae coordenadas (algunos links "cortos" en realidad no
    // lo son), ni siquiera hace falta seguir la redirección.
    let coords = extractLatLng(url);
    let resolvedUrl: string | null = null;

    if (!coords) {
      resolvedUrl = await resolveShortLink(url);
      if (resolvedUrl) coords = extractLatLng(resolvedUrl);
      // Si el link resuelto tampoco trae coordenadas en la URL (a veces
      // Google Maps arma la URL larga solo con el nombre del lugar, sin
      // lat/lng visibles), no hay más nada que hacer del lado del link:
      // el geocoding por texto (Nominatim) en el frontend sigue de respaldo.
    }

    if (!coords) {
      return new Response(JSON.stringify({ error: 'No se pudieron extraer coordenadas de ese link.', resolvedUrl }), {
        status: 200, // no es un error de la función, simplemente no se pudo
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ ...coords, resolvedUrl }), {
      status: 200,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: 'Error interno resolviendo el link.' }), {
      status: 200,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }
});
