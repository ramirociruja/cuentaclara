// src/pages/DashboardPage.tsx
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../api/client";

interface Summary {
  active_companies: number;
  suspended_companies: number;
  expired_companies: number;
  total_employees: number;
}

export default function DashboardPage() {
  const navigate = useNavigate();
  const [summary, setSummary] = useState<Summary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  async function fetchSummary() {
    try {
      setLoading(true);
      const resp = await api.get<Summary>("/superadmin/summary");
      setSummary(resp.data);
    } catch (err) {
      console.error(err);
      setError("No se pudo cargar el resumen.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    fetchSummary();
  }, []);

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "1.5rem", width: "100%", }}>
      <h1 style={{ fontSize: "1.7rem", fontWeight: 600 }}>Dashboard</h1>

      {loading && <p>Cargando resumen...</p>}
      {error && <p style={{ color: "#b91c1c" }}>{error}</p>}

      {!loading && !error && summary && (
        <>
          {/* Tarjetas de métricas */}
          <section
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
              gap: "1rem",
            }}
          >
            <MetricCard
              label="Empresas activas"
              value={summary.active_companies}
            />
            <MetricCard
              label="Empresas suspendidas"
              value={summary.suspended_companies}
            />
            <MetricCard
              label="Empresas vencidas"
              value={summary.expired_companies}
            />
            <MetricCard
              label="Empleados totales"
              value={summary.total_employees}
            />
          </section>

          {/* Acciones rápidas */}
          <section
            style={{
              marginTop: "0.5rem",
              background: "white",
              padding: "1.25rem 1.5rem",
              borderRadius: "0.75rem",
              boxShadow: "0 10px 25px rgba(0,0,0,0.04)",
              display: "flex",
              flexDirection: "column",
              gap: "0.75rem",
            }}
          >
            <h2 style={{ fontSize: "1.1rem", fontWeight: 600 }}>
              Acciones rápidas
            </h2>
            <div style={{ display: "flex", flexWrap: "wrap", gap: "0.75rem" }}>
              <button
                onClick={() => navigate("/companies")}
                style={primaryButtonStyle}
              >
                Ver empresas
              </button>
              <button
                onClick={() => navigate("/employees")}
                style={secondaryButtonStyle}
              >
                Ver empleados
              </button>
            </div>
          </section>
        </>
      )}
    </div>
  );
}

function MetricCard({ label, value }: { label: string; value: number }) {
  return (
    <div
      style={{
        background: "white",
        borderRadius: "0.75rem",
        padding: "1rem 1.25rem",
        boxShadow: "0 10px 25px rgba(0,0,0,0.04)",
        display: "flex",
        flexDirection: "column",
        gap: "0.25rem",
      }}
    >
      <span style={{ fontSize: "0.85rem", color: "#6b7280" }}>{label}</span>
      <span style={{ fontSize: "1.4rem", fontWeight: 600 }}>{value}</span>
    </div>
  );
}

const primaryButtonStyle: React.CSSProperties = {
  padding: "0.55rem 1rem",
  borderRadius: "9999px",
  border: "none",
  background: "#2563eb",
  color: "white",
  fontSize: "0.9rem",
  fontWeight: 500,
  cursor: "pointer",
};

const secondaryButtonStyle: React.CSSProperties = {
  ...primaryButtonStyle,
  background: "white",
  color: "#111827",
  border: "1px solid #d1d5db",
};
