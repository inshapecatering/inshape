const CACHE_NAME = 'catering-control-v1.4'; 

const PRECACHE_URLS = [
  './index.html',
  './login.html',
  './panel.html',
  './cliente.html',
  './terminos.html',
  './privacidad.html',
  './config.js',
  './app.js',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable-192.png',
  './icons/icon-maskable-512.png',
  './icons/apple-touch-icon.png',
  './icons/favicon-32.png'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache =>
      // {cache:'reload'} salta el caché HTTP del navegador y fuerza a pedir
      // el archivo de verdad por red. Sin esto, si el servidor no manda
      // cabeceras de no-cache, el navegador podía servirle a cache.add()
      // una copia vieja que ya tenía guardada por su cuenta, y entonces el
      // precache "nuevo" terminaba con contenido viejo igual.
      Promise.allSettled(PRECACHE_URLS.map(url =>
        fetch(url, { cache: 'reload' }).then(res => { if (res.ok) return cache.put(url, res); })
      ))
    )
  );
});

self.addEventListener('message', event => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// Guarda una respuesta en caché de forma segura. Clave del arreglo: quien
// llama a esta función debe pasar SIEMPRE una copia (res.clone()) sacada
// en el mismo instante en que llegó la respuesta, nunca una copia hecha
// más tarde dentro de un .then() -- para entonces el body ya pudo haber
// empezado a leerse y clone() truena con "Response body is already used".
function safeCachePut(req, resCopy) {
  if (!resCopy || resCopy.status !== 200 || resCopy.type === 'opaqueredirect') return;
  caches.open(CACHE_NAME)
    .then(cache => cache.put(req, resCopy))
    .catch(err => console.warn('[SW] No se pudo guardar en caché:', req.url, err));
}

self.addEventListener('fetch', event => {
  const req = event.request;
  const url = new URL(req.url);

  if (url.hostname.endsWith('supabase.co')) return;

  if (req.method !== 'GET') return;

  // El documento HTML (login/index/cliente) va por RED PRIMERO, no por
  // caché. Motivo: cuando tocás "Actualizar ahora", el Service Worker
  // nuevo toma control (skipWaiting + clients.claim) y la página se
  // recarga sola (ver pwa-register.js, controllerchange). Si en ese mismo
  // instante la recarga pedía el HTML del caché (cache-first), podía
  // toparse con el caché todavía a medio escribir o con una entrada
  // inconsistente justo después del cambio de versión — eso es lo que
  // dejaba la app en blanco y obligaba a borrar datos y volver a entrar.
  // Yendo por red primero, la recarga siempre trae el HTML fresco de
  // verdad (que además ya está tibio: se acaba de descargar en install()),
  // y solo si no hay conexión cae al caché como respaldo. El resto de los
  // archivos (CSS/JS/íconos) sigue siendo caché-primero más abajo, que es
  // donde de verdad se ahorra la mayoría de los datos/tiempo de carga.
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req).then(res => {
        // Un 404 acá es una respuesta VÁLIDA del servidor (no una falla de
        // red), así que el .catch() de más abajo nunca se entera -- por
        // eso una URL vieja/rota bajo este sitio (ej. un ícono de "Añadir a
        // pantalla de inicio" guardado cuando el login se llamaba
        // login.html, antes de renombrarse a index.html) terminaba
        // mostrando la pantalla de error del navegador en vez de la app.
        // Igual que el router de una SPA: cualquier URL desconocida cae a
        // index.html en vez de romperse.
        if (res.status === 404) return caches.match('./index.html').then(cached => cached || fetch('./index.html'));
        const resCopy = res.clone(); // clonar YA, antes de devolver res a la página
        safeCachePut(req, resCopy);
        return res;
      }).catch(() => caches.match(req).then(cached => cached || caches.match('./index.html')))
    );
    return;
  }

  // Cache-primero para el resto (CSS/JS/íconos): si ya está guardado en
  // esta versión del caché (CACHE_NAME), se sirve directo, sin tocar la
  // red — así se ahorran los megas de volver a descargar lo mismo en cada
  // apertura. La actualización llega sola cuando subes una versión nueva
  // (ver readme.txt: subir el número de CACHE_NAME antes de cada
  // despliegue), porque activate() borra los cachés de versiones viejas y
  // pwa-register.js ya avisa "Actualización disponible" cuando eso pasa.

  event.respondWith(
    caches.match(req).then(cached => {
      if (cached) return cached; // ya está en esta versión del caché: no hace falta red
      return fetch(req).then(res => {
        const resCopy = res.clone(); // idem: clonar de inmediato
        safeCachePut(req, resCopy);
        return res;
      });
    })
  );
});