import { useEffect, useMemo, useState, type CSSProperties } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../api/client";

interface Company {
  id: number;
  name: string;
  service_status?: string | null;
  license_expires_at?: string | null;
}

export default function CompaniesPage() {
  const navigate = useNavigate();
  const [companies, setCompanies] = useState<Company[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");

  async function fetchCompanies() {
    try {
      setLoading(true);
      setError(null);
      const resp = await api.get<Company[]>("/superadmin/companies");
      setCompanies(resp.data);
    } catch (err: any) {
      console.error(err);
      setError("No se pudo cargar el listado de empresas.");
    } finally {
      setLoading(false);
    }
  }

  async function handleExtendLicense(id: number) {
    const confirmExtend = window.confirm(
      "¿Extender 30 días la licencia de esta empresa?",
    );
    if (!confirmExtend) return;

    try {
      await api.post(`/superadmin/companies/${id}/extend-license`, {
        days: 30,
      });
      fetchCompanies();
    } catch (err: any) {
      console.error(err);
      alert("No se pudo extender la licencia.");
    }
  }

  async function handleExtendLicenseCustom(id: number) {
    const raw = window.prompt(
      "¿Cuántos días querés extender la licencia? (1 a 90)",
      "3",
    );
    if (raw === null) return;

    const days = Number(raw);

    if (!Number.isFinite(days) || !Number.isInteger(days)) {
      alert("Ingresá un número entero de días (ej: 3).");
      return;
    }

    if (days < 1 || days > 90) {
      alert("El número de días debe estar entre 1 y 90.");
      return;
    }

    const confirmExtend = window.confirm(
      `¿Extender ${days} día(s) la licencia de esta empresa?`,
    );
    if (!confirmExtend) return;

    try {
      await api.post(`/superadmin/companies/${id}/extend-license`, { days });
      fetchCompanies();
    } catch (err: any) {
      console.error(err);
      alert("No se pudo extender la licencia.");
    }
  }

  async function handleSuspend(id: number) {
    const reason = window.prompt(
      "Motivo de la suspensión (opcional):",
      "Suspensión manual desde panel SuperAdmin",
    );
    if (reason === null) return;

    try {
      await api.post(`/superadmin/companies/${id}/suspend`, {
        reason: reason || null,
      });
      fetchCompanies();
    } catch (err: any) {
      console.error(err);
      alert(err?.response?.data?.detail || "No se pudo suspender la empresa.");
    }
  }

  async function handleReactivate(id: number) {
    const confirmReactivate = window.confirm(
      "¿Seguro que querés reactivar esta empresa?",
    );
    if (!confirmReactivate) return;

    try {
      await api.post(`/superadmin/companies/${id}/reactivate`);
      fetchCompanies();
    } catch (err: any) {
      console.error(err);
      alert(err?.response?.data?.detail || "No se pudo reactivar la empresa.");
    }
  }

  useEffect(() => {
    fetchCompanies();
  }, []);

  const filteredCompanies = useMemo(() => {
    const term = search.trim().toLowerCase();
    if (!term) return companies;

    return companies.filter((company) => {
      return (
        company.name.toLowerCase().includes(term) ||
        String(company.id).includes(term) ||
        (company.service_status || "").toLowerCase().includes(term)
      );
    });
  }, [companies, search]);

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "1rem" }}>
      <header
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          gap: "0.75rem",
          flexWrap: "wrap",
        }}
      >
        <h2 style={{ margin: 0, fontSize: "1.45rem", fontWeight: 700 }}>Empresas</h2>

        <div style={{ display: "flex", gap: "0.6rem", flexWrap: "wrap" }}>
          <button onClick={fetchCompanies} style={secondaryButton}>
            Recargar
          </button>
          <button onClick={() => navigate("/companies/new")} style={primaryButton}>
            Nueva empresa
          </button>
        </div>
      </header>

      <section style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "0.75rem" }}>
        <StatCard label="Total" value={companies.length} />
        <StatCard label="Activas" value={companies.filter((c) => (c.service_status || "").toLowerCase() === "active").length} />
        <StatCard label="Suspendidas" value={companies.filter((c) => (c.service_status || "").toLowerCase() === "suspended").length} />
      </section>

      <div style={panelStyle}>
        <input
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Buscar por nombre, estado o ID"
          style={searchInputStyle}
        />
      </div>

      {loading && <p>Cargando empresas...</p>}
      {error && <p style={{ color: "#b91c1c", marginBottom: "1rem" }}>{error}</p>}

      {!loading && !error && (
        <div style={{ ...panelStyle, overflowX: "auto" }}>
          <table
            style={{
              width: "100%",
              minWidth: "800px",
              borderCollapse: "collapse",
              background: "white",
            }}
          >
            <thead>
              <tr style={{ background: "#f9fafb" }}>
                <th style={thStyle}>ID</th>
                <th style={thStyle}>Nombre</th>
                <th style={thStyle}>Estado</th>
                <th style={thStyle}>Licencia vence</th>
                <th style={thStyle}>Acciones</th>
              </tr>
            </thead>
            <tbody>
              {filteredCompanies.map((company) => {
                const status = (company.service_status || "").toLowerCase();
                const isActive = status === "active";
                const isSuspended = status === "suspended";

                return (
                  <tr key={company.id}>
                    <td style={tdStyle}>{company.id}</td>
                    <td style={tdStyle}>{company.name}</td>
                    <td style={tdStyle}>
                      <StatusBadge status={status || "-"} />
                    </td>
                    <td style={tdStyle}>
                      {company.license_expires_at
                        ? new Date(company.license_expires_at).toLocaleDateString("es-AR")
                        : "-"}
                    </td>
                    <td style={{ ...tdStyle, whiteSpace: "nowrap" }}>
                      <ActionButton
                        title="Importar clientes/préstamos/pagos"
                        label="Onboarding"
                        onClick={() => navigate(`/companies/${company.id}/onboarding-import`)}
                      />
                      <ActionButton
                        title="Extiende 30 días"
                        label="+30 días"
                        color="#16a34a"
                        onClick={() => handleExtendLicense(company.id)}
                      />
                      <ActionButton
                        title="Extensión personalizada"
                        label="+X días"
                        outlined
                        color="#166534"
                        onClick={() => handleExtendLicenseCustom(company.id)}
                      />

                      {isActive && (
                        <ActionButton
                          label="Suspender"
                          color="#f97316"
                          onClick={() => handleSuspend(company.id)}
                        />
                      )}

                      {isSuspended && (
                        <ActionButton
                          label="Reactivar"
                          color="#2563eb"
                          onClick={() => handleReactivate(company.id)}
                        />
                      )}
                    </td>
                  </tr>
                );
              })}

              {filteredCompanies.length === 0 && (
                <tr>
                  <td style={tdStyle} colSpan={5}>
                    No hay empresas para mostrar con ese filtro.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function StatCard({ label, value }: { label: string; value: number }) {
  return (
    <div style={{ ...panelStyle, padding: "0.85rem 0.95rem" }}>
      <div style={{ fontSize: "0.82rem", color: "#6b7280" }}>{label}</div>
      <strong style={{ fontSize: "1.3rem" }}>{value}</strong>
    </div>
  );
}

function ActionButton({
  label,
  onClick,
  title,
  color,
  outlined = false,
}: {
  label: string;
  onClick: () => void;
  title?: string;
  color?: string;
  outlined?: boolean;
}) {
  const tone = color || "#111827";

  return (
    <button
      onClick={onClick}
      title={title}
      style={{
        padding: "0.3rem 0.65rem",
        borderRadius: "0.5rem",
        border: outlined ? `1px solid ${tone}` : "none",
        background: outlined ? "white" : tone,
        color: outlined ? tone : "white",
        cursor: "pointer",
        fontSize: "0.78rem",
        marginRight: "0.4rem",
      }}
    >
      {label}
    </button>
  );
}

const panelStyle: CSSProperties = {
  background: "white",
  borderRadius: "0.75rem",
  boxShadow: "0 10px 25px rgba(0,0,0,0.05)",
  border: "1px solid #f3f4f6",
  padding: "0.9rem",
};

const thStyle: CSSProperties = {
  padding: "0.75rem",
  textAlign: "left",
  borderBottom: "1px solid #e5e7eb",
  fontSize: "0.9rem",
};

const tdStyle: CSSProperties = {
  padding: "0.6rem 0.75rem",
  borderBottom: "1px solid #f3f4f6",
  fontSize: "0.9rem",
};

const primaryButton: CSSProperties = {
  padding: "0.45rem 0.9rem",
  borderRadius: "9999px",
  border: "none",
  background: "#2563eb",
  color: "white",
  fontSize: "0.9rem",
  fontWeight: 600,
  cursor: "pointer",
};

const secondaryButton: CSSProperties = {
  ...primaryButton,
  border: "1px solid #d1d5db",
  background: "white",
  color: "#111827",
};

const searchInputStyle: CSSProperties = {
  width: "100%",
  border: "1px solid #d1d5db",
  borderRadius: "0.6rem",
  padding: "0.6rem 0.75rem",
  fontSize: "0.9rem",
};

function StatusBadge({ status }: { status: string }) {
  const normalized = status.toLowerCase();

  let bg = "#e5e7eb";
  let color = "#374151";
  let label = status;

  if (normalized === "active") {
    bg = "#dcfce7";
    color = "#166534";
    label = "activa";
  } else if (normalized === "suspended") {
    bg = "#fef3c7";
    color = "#92400e";
    label = "suspendida";
  } else if (normalized === "expired") {
    bg = "#fee2e2";
    color = "#991b1b";
    label = "vencida";
  }

  return (
    <span
      style={{
        display: "inline-block",
        padding: "0.15rem 0.6rem",
        borderRadius: "9999px",
        fontSize: "0.8rem",
        backgroundColor: bg,
        color,
        textTransform: "capitalize",
      }}
    >
      {label}
    </span>
  );
}
