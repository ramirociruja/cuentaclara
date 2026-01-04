// src/pages/CreateEmployeePage.tsx
import { type FormEvent, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../api/client";

interface Company {
  id: number;
  name: string;
}

export default function CreateEmployeePage() {
  const navigate = useNavigate();

  const [companies, setCompanies] = useState<Company[]>([]);
  const [companyId, setCompanyId] = useState<number | "">("");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [role, setRole] = useState("collector");
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function loadCompanies() {
      try {
        const resp = await api.get<Company[]>("/superadmin/companies");
        setCompanies(resp.data);
      } catch (err) {
        console.error(err);
      }
    }
    loadCompanies();
  }, []);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);

    if (!companyId || !name.trim() || !email.trim() || !password.trim()) {
      setError("Completá empresa, nombre, email y contraseña.");
      return;
    }

    try {
      setLoading(true);
      await api.post("/superadmin/employees", {
        company_id: companyId,
        name: name.trim(),
        email: email.trim(),
        role,
        phone: phone.trim() || null,
        password,
      });

      navigate("/employees");
    } catch (err: any) {
      console.error(err);
      const msg =
        err?.response?.data?.detail ??
        "No se pudo crear el empleado. Revisá los datos.";
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
        Nuevo empleado
      </h1>

      <form
        onSubmit={handleSubmit}
        style={{ display: "flex", flexDirection: "column", gap: "0.9rem" }}
      >
        <div>
          <label style={labelStyle}>Empresa</label>
          <select
            value={companyId}
            onChange={(e) =>
              setCompanyId(e.target.value ? Number(e.target.value) : "")
            }
            style={inputStyle}
          >
            <option value="">Seleccioná una empresa...</option>
            {companies.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label style={labelStyle}>Nombre</label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            style={inputStyle}
          />
        </div>

        <div>
          <label style={labelStyle}>Email</label>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            style={inputStyle}
          />
        </div>

        <div>
          <label style={labelStyle}>Rol</label>
          <select
            value={role}
            onChange={(e) => setRole(e.target.value)}
            style={inputStyle}
          >
            <option value="admin">Admin</option>
            <option value="collector">Cobrador</option>
            <option value="superadmin">SuperAdmin</option>
          </select>
        </div>

        <div>
          <label style={labelStyle}>Teléfono (opcional)</label>
          <input
            type="tel"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            style={inputStyle}
          />
        </div>

        <div>
          <label style={labelStyle}>Contraseña</label>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
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
            {loading ? "Creando..." : "Crear empleado"}
          </button>

          <button
            type="button"
            onClick={() => navigate("/employees")}
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
