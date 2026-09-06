// Roles y permisos del Panel. Se separa en su propio archivo porque lo va
// a necesitar tanto el menú lateral (para saber qué botones mostrar) como
// cada pantalla (para saber si el usuario puede editar o solo mirar).

export const ROLE_LABELS = {
  admin: 'Administrador',
  editor: 'Editor',
  kitchen: 'Cocina',
  driver: 'Driver',
  superadmin: 'Super Administrador',
};

// Qué roles built-in pueden VER cada pantalla. Un "rol personalizado"
// (creado desde Usuarios) no aparece acá — sus permisos por página se
// guardan aparte y se consultan cuando se construya la pantalla Usuarios.
export const NAV_PERMS = {
  dispatch: ['admin', 'editor', 'kitchen', 'driver', 'superadmin'],
  delivery: ['admin', 'editor', 'driver', 'superadmin'],
  clients: ['admin', 'editor', 'driver', 'superadmin'],
  drivers: ['admin', 'editor', 'superadmin'],
  routes: ['admin', 'editor', 'superadmin'],
  plans: ['admin', 'editor', 'superadmin'],
  payroll: ['admin', 'editor', 'driver', 'superadmin'],
  metrics: ['admin', 'editor', 'superadmin'],
  inventory: ['admin', 'editor', 'kitchen', 'superadmin'],
  users: ['admin', 'superadmin'],
  audit: ['admin', 'superadmin'],
  notes: ['admin', 'editor', 'superadmin'],
  settings: ['admin', 'editor', 'kitchen', 'driver', 'superadmin'],
};

// Qué páginas puede desbloquear el plan Premium, y si por defecto (sin
// configurar nada) están bloqueadas para el plan Básico.
export const PREMIUM_DEFAULT_LOCKED = {
  notes: true,
  payroll: true,
  inventory: true,
  audit: true,
  metrics: true,
  delivery: false,
  clientPortal: true,
};

export function isBuiltinRole(role) {
  return !!ROLE_LABELS[role];
}

export function roleLabel(role, customRoles = []) {
  return ROLE_LABELS[role] || customRoles.find((r) => r.id === role)?.label || role || 'Usuario';
}

export function isAdmin(role) {
  return role === 'admin' || role === 'superadmin';
}

// Permisos "de edición" para los roles built-in: quién puede modificar
// datos (no solo mirarlos) en cada pantalla.
export const canManage = (role) => ['admin', 'editor', 'superadmin'].includes(role);
export const canManageInventory = (role) => ['admin', 'editor', 'kitchen', 'superadmin'].includes(role);
export const canManageDelivery = (role) => ['admin', 'editor', 'driver', 'superadmin'].includes(role);

export function canAccessPage(page, role, customRoles = []) {
  if (page === 'users') return isAdmin(role);
  if (isBuiltinRole(role)) return (NAV_PERMS[page] || []).includes(role);
  return !!customRoles.find((r) => r.id === role)?.pages?.[page]?.view;
}

export function isPagePremiumLocked(page, premiumLockedPagesConfig) {
  if (!premiumLockedPagesConfig || !(page in premiumLockedPagesConfig)) return !!PREMIUM_DEFAULT_LOCKED[page];
  return !!premiumLockedPagesConfig[page];
}
