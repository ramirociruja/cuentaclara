// src/pages/CreateCompanyPage.tsx
import { type FormEvent, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../api/client";

export default function CreateCompanyPage() {
  const navigate = useNavigate();

  const [name, setName] = useState("");
  const [licenseDays, setLicenseDays] = useState(30);
  const [adminName, setAdminName] = useState("");
  const [adminEmail, setAdminEmail] = useState("");
  const [adminPhone, setAdminPhone] = useState("");
  const [adminPassword, setAdminPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);

    if (!name.trim() || !adminName.trim() || !adminEmail.trim() || !adminPassword.trim()) {
      setError("Completá al menos nombre de empresa, admin, email y contraseña.");
      return;
    }

    try {
      setLoading(true);
      await api.post("/superadmin/companies", {
        name: name.trim(),
        license_days: licenseDays,
        admin_name: adminName.trim(),
        admin_email: adminEmail.trim(),
        admin_phone: adminPhone.trim() || null,
        admin_password: adminPassword,
      });

      // Si todo sale bien, volvemos al listado
      navigate("/companies");
    } catch (err: any) {
      console.error(err);
      const msg =
        err?.response?.data?.detail ??
        "No se pudo crear la empresa. Revisá los datos.";
      setError(String(msg));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div
      style={{
        maxWidth: "640px",
        margin: "0 auto",
        background: "white",
        padding: "1.5rem 1.75rem",
        borderRadius: "0.75rem",
        boxShadow: "0 10px 25px rgba(0,0,0,0.05)",
      }}
    >
      <h1 style={{ fontSize: "1.5rem", fontWeight: 600, marginBottom: "1rem" }}>
        Nueva empresa
      </h1>

      <p style={{ fontSize: "0.9rem", color: "#4b5563", marginBottom: "1rem" }}>
        Creá una nueva empresa y su usuario administrador inicial.
      </p>

      <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: "0.85rem" }}>
        <div>
          <label style={labelStyle}>Nombre de la empresa</label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            style={inputStyle}
          />
        </div>

        <div>
          <label style={labelStyle}>Días de licencia inicial</label>
          <input
            type="number"
            min={1}
            value={licenseDays}
            onChange={(e) => setLicenseDays(Number(e.target.value) || 0)}
            style={inputStyle}
          />
        </div>

        <hr style={{ border: "none", borderTop: "1px solid #e5e7eb", margin: "0.75rem 0" }} />

        <div>
          <label style={labelStyle}>Nombre del administrador</label>
          <input
            type="text"
            value={adminName}
            onChange={(e) => setAdminName(e.target.value)}
            style={inputStyle}
          />
        </div>

        <div>
          <label style={labelStyle}>Email del administrador</label>
          <input
            type="email"
            value={adminEmail}
            onChange={(e) => setAdminEmail(e.target.value)}
            style={inputStyle}
          />
        </div>

        <div>
          <label style={labelStyle}>Teléfono del administrador (opcional)</label>
          <input
            type="tel"
            value={adminPhone}
            onChange={(e) => setAdminPhone(e.target.value)}
            style={inputStyle}
          />
        </div>

        <div>
          <label style={labelStyle}>Contraseña del administrador</label>
          <input
            type="password"
            value={adminPassword}
            onChange={(e) => setAdminPassword(e.target.value)}
            style={inputStyle}
          />
        </div>

        {error && (
          <div style={{ color: "#b91c1c", fontSize: "0.9rem" }}>{error}</div>
        )}

        <div style={{ display: "flex", gap: "0.75rem", marginTop: "0.5rem" }}>
          <button
            type="submit"
            disabled={loading}
            style={{
              padding: "0.55rem 1.2rem",
              borderRadius: "9999px",
              border: "none",
              background: "#2563eb",
              color: "white",
              fontSize: "0.9rem",
              fontWeight: 500,
              cursor: "pointer",
              opacity: loading ? 0.7 : 1,
            }}
          >
            {loading ? "Creando..." : "Crear empresa"}
          </button>

          <button
            type="button"
            onClick={() => navigate("/companies")}
            style={{
              padding: "0.55rem 1.1rem",
              borderRadius: "9999px",
              border: "1px solid #d1d5db",
              background: "white",
              fontSize: "0.9rem",
              cursor: "pointer",
            }}
          >
            Cancelar
          </button>
        </div>
      </form>
    </div>
  );
}

const labelStyle: React.CSSProperties = {
  display: "block",
  marginBottom: "0.25rem",
  fontSize: "0.9rem",
  color: "#374151",
};

const inputStyle: React.CSSProperties = {
  width: "100%",
  padding: "0.45rem 0.7rem",
  borderRadius: "0.5rem",
  border: "1px solid #d1d5db",
  fontSize: "0.9rem",
};
