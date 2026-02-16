// src/pages/CompaniesPage.tsx
import React, { useEffect, useState } from "react";
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

  async function fetchCompanies() {
    try {
      setLoading(true);
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
      "¿Extender 30 días la licencia de esta empresa?"
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

  // ✅ NUEVO: extensión personalizada
  async function handleExtendLicenseCustom(id: number) {
    const raw = window.prompt(
      "¿Cuántos días querés extender la licencia? (1 a 90)",
      "3"
    );
    if (raw === null) return; // canceló

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
      `¿Extender ${days} día(s) la licencia de esta empresa?`
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
      "Suspensión manual desde panel SuperAdmin"
    );
    if (reason === null) return; // canceló

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
      "¿Seguro que querés reactivar esta empresa?"
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

  function handleNewCompany() {
    navigate("/companies/new");
  }

  function handleOnboardingImport(id: number) {
    navigate(`/companies/${id}/onboarding-import`);
  }

  useEffect(() => {
    fetchCompanies();
  }, []);

  return (
    <div style={{ padding: "0.5rem" }}>
      <header
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          marginBottom: "1.5rem",
        }}
      >
        <h1 style={{ fontSize: "1.5rem", fontWeight: 600 }}>Empresas</h1>
        <button
          onClick={handleNewCompany}
          style={{
            padding: "0.45rem 0.9rem",
            borderRadius: "9999px",
            border: "none",
            background: "#2563eb",
            color: "white",
            fontSize: "0.9rem",
            fontWeight: 500,
            cursor: "pointer",
          }}
        >
          Nueva empresa
        </button>
      </header>

      {loading && <p>Cargando empresas...</p>}
      {error && <p style={{ color: "#b91c1c", marginBottom: "1rem" }}>{error}</p>}

      {!loading && !error && (
        <table
          style={{
            width: "100%",
            borderCollapse: "collapse",
            background: "white",
            borderRadius: "0.75rem",
            overflow: "hidden",
            boxShadow: "0 10px 25px rgba(0, 0, 0, 0.05)",
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
            {companies.map((c) => {
              const status = (c.service_status || "").toLowerCase();
              const isActive = status === "active";
              const isSuspended = status === "suspended";

              return (
                <tr key={c.id}>
                  <td style={tdStyle}>{c.id}</td>
                  <td style={tdStyle}>{c.name}</td>
                  <td style={tdStyle}>
                    <StatusBadge status={status || "-"} />
                  </td>
                  <td style={tdStyle}>
                    {c.license_expires_at
                      ? new Date(c.license_expires_at).toLocaleDateString("es-AR")
                      : "-"}
                  </td>
                  <td style={{ ...tdStyle, whiteSpace: "nowrap" }}>
                    <button
                      onClick={() => handleOnboardingImport(c.id)}
                      style={{
                        padding: "0.3rem 0.7rem",
                        borderRadius: "0.5rem",
                        border: "1px solid #d1d5db",
                        background: "white",
                        color: "#111827",
                        cursor: "pointer",
                        fontSize: "0.8rem",
                        marginRight: "0.4rem",
                      }}
                      title="Importar clientes/préstamos/pagos"
                    >
                      Onboarding
                    </button>

                    <button
                      onClick={() => handleExtendLicense(c.id)}
                      style={{
                        padding: "0.3rem 0.7rem",
                        borderRadius: "0.5rem",
                        border: "none",
                        background: "#22c55e",
                        color: "white",
                        cursor: "pointer",
                        fontSize: "0.8rem",
                        marginRight: "0.4rem",
                      }}
                      title="Extiende 30 días"
                    >
                      +30 días
                    </button>

                    {/* ✅ NUEVO botón */}
                    <button
                      onClick={() => handleExtendLicenseCustom(c.id)}
                      style={{
                        padding: "0.3rem 0.7rem",
                        borderRadius: "0.5rem",
                        border: "1px solid #16a34a",
                        background: "white",
                        color: "#166534",
                        cursor: "pointer",
                        fontSize: "0.8rem",
                        marginRight: "0.4rem",
                      }}
                      title="Extiende una cantidad de días personalizada"
                    >
                      +X días
                    </button>

                    {isActive && (
                      <button
                        onClick={() => handleSuspend(c.id)}
                        style={{
                          padding: "0.3rem 0.7rem",
                          borderRadius: "0.5rem",
                          border: "none",
                          background: "#f97316",
                          color: "white",
                          cursor: "pointer",
                          fontSize: "0.8rem",
                        }}
                      >
                        Suspender
                      </button>
                    )}

                    {isSuspended && (
                      <button
                        onClick={() => handleReactivate(c.id)}
                        style={{
                          padding: "0.3rem 0.7rem",
                          borderRadius: "0.5rem",
                          border: "none",
                          background: "#3b82f6",
                          color: "white",
                          cursor: "pointer",
                          fontSize: "0.8rem",
                        }}
                      >
                        Reactivar
                      </button>
                    )}
                  </td>
                </tr>
              );
            })}

            {companies.length === 0 && (
              <tr>
                <td style={tdStyle} colSpan={5}>
                  No hay empresas.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      )}
    </div>
  );
}

const thStyle: React.CSSProperties = {
  padding: "0.75rem",
  textAlign: "left",
  borderBottom: "1px solid #e5e7eb",
  fontSize: "0.9rem",
};

const tdStyle: React.CSSProperties = {
  padding: "0.6rem 0.75rem",
  borderBottom: "1px solid #f3f4f6",
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
        color: color,
        textTransform: "capitalize",
      }}
    >
      {label}
    </span>
  );
}
