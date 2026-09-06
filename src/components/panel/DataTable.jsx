// Tabla simple con buscador arriba. `columns`: [{key,label,render(row)}].
// No incluye reordenar/ocultar columnas (eso queda para una pasada
// posterior, igual que en Día de trabajo) — acá el orden es siempre el
// que viene en `columns`.
export default function DataTable({ columns, rows, getRowId = (r) => r.id, search, onSearchChange, searchPlaceholder, emptyText = 'Sin registros.' }) {
  return (
    <>
      {onSearchChange && (
        <div className="toolbar">
          <input className="search" placeholder={searchPlaceholder || 'Buscar…'} value={search} onChange={(e) => onSearchChange(e.target.value)} />
        </div>
      )}
      <div className="sheet">
        <table>
          <thead><tr>{columns.map((c) => <th key={c.key}>{c.label}</th>)}</tr></thead>
          <tbody>
            {rows.length ? rows.map((row) => (
              <tr key={getRowId(row)}>{columns.map((col) => <td key={col.key}>{col.render(row)}</td>)}</tr>
            )) : (
              <tr><td colSpan={columns.length} className="empty">{emptyText}</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}
