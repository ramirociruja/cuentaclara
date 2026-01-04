// src/pages/LoginPage.tsx
import type { FormEvent } from "react";
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../api/client";

export default function LoginPage() {
  const navigate = useNavigate();
  const [email, setEmail] = useState("superadmin@cuentaclara.com");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);

    try {
      // TU backend usa email + password (NO username)
      const resp = await api.post("/login", {
        username: email,
        password: password,
      });

      const token = resp.data.access_token as string | undefined;

      if (!token) {
        throw new Error("No se recibió token");
      }

      localStorage.setItem("token", token);

      navigate("/dashboard");
    } catch (err: any) {
      console.error(err);
      setError("Error al iniciar sesión. Verificá tus datos.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div
      style={{
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "#f3f4f6",
      }}
    >
      <form
        onSubmit={handleSubmit}
        style={{
          background: "white",
          padding: "2rem",
          borderRadius: "0.75rem",
          boxShadow: "0 10px 25px rgba(0,0,0,0.08)",
          minWidth: "320px",
        }}
      >
        <h1 style={{ marginBottom: "1.5rem", fontSize: "1.5rem" }}>
          CuentaClara – SuperAdmin
        </h1>

        <label style={{ display: "block", marginBottom: "0.75rem" }}>
          <span style={{ display: "block", marginBottom: "0.25rem" }}>Email</span>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            style={{
              width: "100%",
              padding: "0.5rem 0.75rem",
              borderRadius: "0.5rem",
              border: "1px solid #d1d5db",
            }}
          />
        </label>

        <label style={{ display: "block", marginBottom: "0.75rem" }}>
          <span style={{ display: "block", marginBottom: "0.25rem" }}>
            Contraseña
          </span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            style={{
              width: "100%",
              padding: "0.5rem 0.75rem",
              borderRadius: "0.5rem",
              border: "1px solid #d1d5db",
            }}
          />
        </label>

        {error && (
          <div
            style={{
              marginBottom: "0.75rem",
              color: "#b91c1c",
              fontSize: "0.9rem",
            }}
          >
            {error}
          </div>
        )}

        <button
          type="submit"
          disabled={loading}
          style={{
            width: "100%",
            padding: "0.6rem 1rem",
            borderRadius: "0.5rem",
            border: "none",
            background: "#2563eb",
            color: "white",
            fontWeight: 600,
            cursor: "pointer",
            opacity: loading ? 0.7 : 1,
          }}
        >
          {loading ? "Ingresando..." : "Ingresar"}
        </button>
      </form>
    </div>
  );
}
