import { useState } from 'react';
import { useOperations } from '../../../context/OperationsContext';
import { n } from '../../../services/planHelpers';
import config from '../../../services/config';
import ImageField from '../ImageField';

const PREMIUM_LOCKABLE_PAGES = [
  ['notes', 'Notas'], ['payroll', 'Sueldos'], ['inventory', 'Inventario'], ['audit', 'Auditoría'],
  ['metrics', 'Métricas'], ['weeklySchedule', 'Horario semanal (Clientes)'], ['returnDate', 'Reactivación automática por fecha'],
  ['clientPortal', 'Portal de clientes'],
];

function themeKey(userId) {
  return `staff-theme-${userId}`;
}

export default function SettingsPage({ user, theme, onThemeChange }) {
  const { settings, saveSettings, serverToday } = useOperations();
  const isSuperAdmin = user?.role === 'superadmin';
  const isAdmin = ['admin', 'superadmin'].includes(user?.role);
  const [premiumDays, setPremiumDays] = useState('');

  function handleThemeChange(value) {
    localStorage.setItem(themeKey(user.id), value);
    onThemeChange(value);
  }

  function field(key, transform = (v) => v) {
    return {
      value: settings[key] ?? '',
      onBlur: (e) => saveSettings({ ...settings, [key]: transform(e.target.value) }),
    };
  }

  function activatePremium(untilDate) {
    saveSettings({ ...settings, plan: 'premium', premiumUntil: untilDate || '' });
  }
  function activateBasic() {
    if (!confirm('¿Volver al plan Básico? El equipo perderá acceso a las funciones Premium.')) return;
    saveSettings({ ...settings, plan: 'basico', premiumUntil: '' });
  }
  function activatePremiumDays() {
    const days = n(premiumDays);
    if (days <= 0) return;
    const until = new Date(serverToday + 'T00:00:00Z');
    until.setUTCDate(until.getUTCDate() + days);
    activatePremium(until.toISOString().slice(0, 10));
  }
  function togglePremiumPage(key, checked) {
    saveSettings({ ...settings, premiumLockedPages: { ...settings.premiumLockedPages, [key]: checked } });
  }

  const isPremium = settings.plan === 'premium';
  const daysLeft = isPremium && settings.premiumUntil ? Math.max(0, Math.ceil((new Date(settings.premiumUntil) - new Date(serverToday)) / 86400000)) : null;

  return (
    <section className="page active">
      <div className="page-head"><div><h1>Configuración</h1><p>Preferencias visuales y datos de la empresa.</p></div></div>

      <div className="two-col">
        <div className="card card-pad stack">
          <h3>Tu tema</h3>
          <p className="muted">Solo afecta a tu navegador, no a los demás usuarios.</p>
          <label>Tema
            <select value={theme} onChange={(e) => handleThemeChange(e.target.value)}>
              <option value="light">Claro</option>
              <option value="night">Nocturno</option>
              <option value="forest">Bosque</option>
            </select>
          </label>
          <p className="muted" style={{ fontSize: 12 }}>Elegir qué columnas ver en Día de trabajo queda pendiente para una próxima parte.</p>
        </div>

        {isAdmin && (
          <div className="card card-pad stack">
            <h3>Empresa</h3>
            <label>Nombre de la empresa<input defaultValue={settings.companyName} placeholder={config.companyName} onBlur={(e) => saveSettings({ ...settings, companyName: e.target.value })} /></label>
            <ImageField label="Logo" name="_logo" value={settings.logoUrl} onChange={(url) => saveSettings({ ...settings, logoUrl: url })} folder="branding" maxDim={300} />
            <label>Número de WhatsApp<input defaultValue={settings.whatsappNumber} placeholder="Ej: 59171234567" onBlur={(e) => saveSettings({ ...settings, whatsappNumber: e.target.value.replace(/\D/g, '') })} /></label>
            <p className="muted" style={{ marginTop: -6 }}>Solo números, con código de país. Se usa en los botones de contacto del portal del cliente.</p>
            <label>Link de Instagram<input defaultValue={settings.instagramUrl} placeholder="https://instagram.com/tu_empresa" onBlur={(e) => saveSettings({ ...settings, instagramUrl: e.target.value.trim() })} /></label>
            <label>Usuario de Instagram (@handle)<input defaultValue={settings.instagramHandle} placeholder="@tu_empresa" onBlur={(e) => saveSettings({ ...settings, instagramHandle: e.target.value.trim() })} /></label>
            <ImageField label="Imagen publicitaria (banner del portal de clientes)" name="_ad" value={settings.adImageUrl} onChange={(url) => saveSettings({ ...settings, adImageUrl: url })} folder="branding" maxDim={800} />
          </div>
        )}

        {isAdmin && (
          <div className="card card-pad stack">
            <h3>Aviso de renovación</h3>
            <p className="muted">Cuando a un cliente le queden estos días o menos, verá un cartel invitándolo a renovar su plan.</p>
            <label>Días restantes para mostrar el aviso<input type="number" min="0" max="30" defaultValue={n(settings.renewalWarningDays)} onBlur={(e) => saveSettings({ ...settings, renewalWarningDays: Math.max(0, n(e.target.value)) })} /></label>
          </div>
        )}

        {isSuperAdmin && (
          <div className="card card-pad stack">
            <h3>Plan de la cuenta</h3>
            <p className="muted">En Básico, algunas pantallas quedan bloqueadas (lista abajo). Elegí una opción:</p>
            <div className="plan-options">
              <button
                type="button"
                className={`plan-option ${isPremium && !settings.premiumUntil ? 'is-active' : 'is-inactive'}`}
                onClick={() => activatePremium('')}
                disabled={isPremium && !settings.premiumUntil}
              >
                <span>Premium sin vencimiento</span>
                {isPremium && !settings.premiumUntil && <span className="plan-option-tag">Activo</span>}
              </button>

              <div className={`plan-option plan-option-days ${isPremium && settings.premiumUntil ? 'is-active' : 'is-inactive'}`}>
                <span>Premium por días</span>
                <input type="number" min="1" placeholder="Días" value={premiumDays} onChange={(e) => setPremiumDays(e.target.value)} />
                <button type="button" onClick={activatePremiumDays}>Activar</button>
                {isPremium && settings.premiumUntil && <span className="plan-option-tag">Vence {settings.premiumUntil.split('-').reverse().join('/')} · {daysLeft}d</span>}
              </div>

              <button type="button" className={`plan-option ${!isPremium ? 'is-active' : 'is-inactive'}`} onClick={activateBasic} disabled={!isPremium}>
                <span>Básico</span>
                {!isPremium && <span className="plan-option-tag">Activo</span>}
              </button>
            </div>
            <h3 style={{ marginTop: 10 }}>Qué menús requieren Premium</h3>
            <div className="toggle-list-col">
              {PREMIUM_LOCKABLE_PAGES.map(([key, label]) => (
                <label key={key}><input type="checkbox" checked={!!settings.premiumLockedPages?.[key]} onChange={(e) => togglePremiumPage(key, e.target.checked)} /> {label}</label>
              ))}
            </div>
          </div>
        )}
      </div>

      <p className="muted" style={{ fontSize: 12.5, marginTop: 18 }}>
        Pendiente para una próxima parte: personas conectadas ahora (con detalle de quién), exportar/importar respaldo en JSON.
      </p>
    </section>
  );
}
