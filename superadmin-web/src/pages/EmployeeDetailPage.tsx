// src/pages/EmployeeDetailPage.tsx
import { type FormEvent, useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { api } from "../api/client";

interface Company {
  id: number;
  name: string;
}

interface Employee {
  id: number;
  name: string;
  email: string;
  role: string;
  phone?: string | null;
  company_id: number;
}

export default function EmployeeDetailPage() {
  const { id } = useParams();
  const navigate = useNavigate();
  const employeeId = Number(id);

  const [employee, setEmployee] = useState<Employee | null>(null);
  const [companies, setCompanies] = useState<Company[]>([]);

  // campos editables
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [role, setRole] = useState("collector");
  const [phone, setPhone] = useState("");
  const [companyId, setCompanyId] = useState<number | "">("");

  // reset password
  const [newPassword, setNewPassword] = useState("");
  const [newPassword2, setNewPassword2] = useState("");

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [resetting, setResetting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!employeeId) return;

    async function load() {
      try {
        setLoading(true);
        const [empResp, compResp] = await Promise.all([
          api.get<Employee>(`/superadmin/employees/${employeeId}`),
          api.get<Company[]>("/superadmin/companies"),
        ]);

        const emp = empResp.data;
        setEmployee(emp);
        setName(emp.name);
        setEmail(emp.email);
        setRole(emp.role);
        setPhone(emp.phone || "");
        setCompanyId(emp.company_id);
        setCompanies(compResp.data);
        setError(null);
      } catch (err: any) {
        console.error(err);
        setError(
          err?.response?.data?.detail ||
            "No se pudo cargar la información del empleado."
        );
      } finally {
        setLoading(false);
      }
    }

    load();
  }, [employeeId]);

  async function handleSave(e: FormEvent) {
    e.preventDefault();
    if (!employeeId) return;
    setError(null);
    setSuccessMessage(null);

    if (!name.trim() || !email.trim() || !companyId) {
      setError("Completá nombre, email y empresa.");
      return;
    }

    try {
      setSaving(true);
      const resp = await api.put<Employee>(`/superadmin/employees/${employeeId}`, {
        name: name.trim(),
        email: email.trim(),
        role,
        phone: phone.trim() || null,
        company_id: companyId,
      });

      setEmployee(resp.data);
      setSuccessMessage("Cambios guardados correctamente.");
    } catch (err: any) {
      console.error(err);
      const msg =
        err?.response?.data?.detail ||
        "No se pudieron guardar los cambios. Revisá los datos.";
      setError(String(msg));
    } finally {
      setSaving(false);
    }
  }

  async function handleResetPassword(e: FormEvent) {
    e.preventDefault();
    if (!employeeId) return;
    setError(null);
    setSuccessMessage(null);

    if (!newPassword || !newPassword2) {
      setError("Ingresá la nueva contraseña y la confirmación.");
      return;
    }
    if (newPassword !== newPassword2) {
      setError("Las contraseñas no coinciden.");
      return;
    }
    if (newPassword.length < 4) {
      setError("La contraseña debe tener al menos 4 caracteres.");
      return;
    }

    try {
      setResetting(true);
      await api.post(`/superadmin/employees/${employeeId}/reset-password`, {
        new_password: newPassword,
      });
      setNewPassword("");
      setNewPassword2("");
      setSuccessMessage("Contraseña actualizada correctamente.");
    } catch (err: any) {
      console.error(err);
      const msg =
        err?.response?.data?.detail ||
        "No se pudo resetear la contraseña.";
      setError(String(msg));
    } finally {
      setResetting(false);
    }
  }

  if (loading) {
    return <p>Cargando empleado...</p>;
  }

  if (error && !employee) {
    return (
      <div>
        <p style={{ color: "#b91c1c" }}>{error}</p>
        <button
          onClick={() => navigate("/employees")}
          style={{
            marginTop: "0.75rem",
            padding: "0.45rem 0.9rem",
            borderRadius: "9999px",
            border: "1px solid #d1d5db",
            background: "white",
            cursor: "pointer",
          }}
        >
          Volver
        </button>
      </div>
    );
  }

  if (!employee) {
    return null;
  }

  return (
    <div
      style={{
        display: "grid",
        gap: "1.5rem",
        alignItems: "flex-start",
      }}
    >
      {/* Card edición de datos */}
      <div
        style={{
          background: "white",
          padding: "1.5rem 1.75rem",
          borderRadius: "0.75rem",
          boxShadow: "0 10px 25px rgba(0,0,0,0.05)",
        }}
      >
        <h1
          style={{
            fontSize: "1.5rem",
            fontWeight: 600,
            marginBottom: "0.5rem",
          }}
        >
          Empleado #{employee.id}
        </h1>
        <p style={{ fontSize: "0.9rem", color: "#6b7280", marginBottom: "1rem" }}>
          Editá los datos básicos del empleado.
        </p>

        <form
          onSubmit={handleSave}
          style={{ display: "flex", flexDirection: "column", gap: "0.9rem" }}
        >
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
            <label style={labelStyle}>Teléfono (opcional)</label>
            <input
              type="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              style={inputStyle}
            />
          </div>

          {error && (
            <div style={{ color: "#b91c1c", fontSize: "0.9rem" }}>{error}</div>
          )}
          {successMessage && (
            <div style={{ color: "#16a34a", fontSize: "0.9rem" }}>
              {successMessage}
            </div>
          )}

          <div style={{ display: "flex", gap: "0.75rem", marginTop: "0.5rem" }}>
            <button
              type="submit"
              disabled={saving}
              style={{
                padding: "0.55rem 1.2rem",
                borderRadius: "9999px",
                border: "none",
                background: "#2563eb",
                color: "white",
                fontSize: "0.9rem",
                fontWeight: 500,
                cursor: "pointer",
                opacity: saving ? 0.7 : 1,
              }}
            >
              {saving ? "Guardando..." : "Guardar cambios"}
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
              Volver
            </button>
          </div>
        </form>
      </div>

      {/* Card reset password */}
      <div
        style={{
          background: "white",
          padding: "1.5rem 1.75rem",
          borderRadius: "0.75rem",
          boxShadow: "0 10px 25px rgba(0,0,0,0.05)",
        }}
      >
        <h2
          style={{
            fontSize: "1.1rem",
            fontWeight: 600,
            marginBottom: "0.75rem",
          }}
        >
          Resetear contraseña
        </h2>
        <p style={{ fontSize: "0.9rem", color: "#6b7280", marginBottom: "0.75rem" }}>
          Asigná una nueva contraseña para este empleado.
        </p>

        <form
          onSubmit={handleResetPassword}
          style={{ display: "flex", flexDirection: "column", gap: "0.75rem" }}
        >
          <div>
            <label style={labelStyle}>Nueva contraseña</label>
            <input
              type="password"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              style={inputStyle}
            />
          </div>

          <div>
            <label style={labelStyle}>Repetir contraseña</label>
            <input
              type="password"
              value={newPassword2}
              onChange={(e) => setNewPassword2(e.target.value)}
              style={inputStyle}
            />
          </div>

          <button
            type="submit"
            disabled={resetting}
            style={{
              padding: "0.55rem 1.2rem",
              borderRadius: "9999px",
              border: "none",
              background: "#f97316",
              color: "white",
              fontSize: "0.9rem",
              fontWeight: 500,
              cursor: "pointer",
              opacity: resetting ? 0.7 : 1,
            }}
          >
            {resetting ? "Actualizando..." : "Actualizar contraseña"}
          </button>
        </form>
      </div>
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
