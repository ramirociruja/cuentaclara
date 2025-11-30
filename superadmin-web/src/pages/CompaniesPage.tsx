// src/pages/CompaniesPage.tsx
import { useEffect, useState } from "react";
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
      fetchCompanies(); // refrescar
    } catch (err: any) {
      console.error(err);
      alert("No se pudo extender la licencia.");
    }
  }

  function handleLogout() {
    localStorage.removeItem("token");
    navigate("/login");
  }

  useEffect(() => {
    fetchCompanies();
  }, []);

  return (
    <div style={{ padding: "1.5rem" }}>
      <header
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          marginBottom: "1.5rem",
        }}
      >
        <h1 style={{ fontSize: "1.5rem" }}>Empresas</h1>
        <button
          onClick={handleLogout}
          style={{
            padding: "0.4rem 0.75rem",
            borderRadius: "0.5rem",
            border: "1px solid #d1d5db",
            background: "white",
            cursor: "pointer",
          }}
        >
          Cerrar sesión
        </button>
      </header>

      {loading && <p>Cargando empresas...</p>}
      {error && (
        <p style={{ color: "#b91c1c", marginBottom: "1rem" }}>{error}</p>
      )}

      {!loading && !error && (
        <table
          style={{
            width: "100%",
            borderCollapse: "collapse",
            background: "white",
            borderRadius: "0.75rem",
            overflow: "hidden",
            boxShadow: "0 10px 25px rgba(0,0,0,0.05)",
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
            {companies.map((c) => (
              <tr key={c.id}>
                <td style={tdStyle}>{c.id}</td>
                <td style={tdStyle}>{c.name}</td>
                <td style={tdStyle}>{c.service_status ?? "-"}</td>
                <td style={tdStyle}>
                  {c.license_expires_at
                    ? new Date(c.license_expires_at).toLocaleDateString(
                        "es-AR"
                      )
                    : "-"}
                </td>
                <td style={tdStyle}>
                  <button
                    onClick={() => handleExtendLicense(c.id)}
                    style={{
                      padding: "0.3rem 0.7rem",
                      borderRadius: "0.5rem",
                      border: "none",
                      background: "#22c55e",
                      color: "white",
                      cursor: "pointer",
                      fontSize: "0.85rem",
                    }}
                  >
                    +30 días
                  </button>
                </td>
              </tr>
            ))}

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
