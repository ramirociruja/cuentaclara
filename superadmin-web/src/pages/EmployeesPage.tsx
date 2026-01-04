// src/pages/EmployeesPage.tsx
import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
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

type SortField = "id" | "name" | "email" | "role" | "company";
type SortDirection = "asc" | "desc";

export default function EmployeesPage() {
  const navigate = useNavigate();

  const [employees, setEmployees] = useState<Employee[]>([]);
  const [companies, setCompanies] = useState<Company[]>([]);

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [filterCompanyId, setFilterCompanyId] = useState<number | "all">("all");
  const [filterRole, setFilterRole] = useState<string>("all");

  const [sortField, setSortField] = useState<SortField>("id");
  const [sortDirection, setSortDirection] = useState<SortDirection>("asc");

  // -----------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------
  function getCompanyName(id: number) {
    const c = companies.find((x) => x.id === id);
    return c ? c.name : `#${id}`;
  }

  function toggleSort(field: SortField) {
    if (sortField === field) {
      setSortDirection((prev) => (prev === "asc" ? "desc" : "asc"));
    } else {
      setSortField(field);
      setSortDirection("asc");
    }
  }

  function sortIcon(field: SortField) {
    if (sortField !== field) return "↕";
    return sortDirection === "asc" ? "▲" : "▼";
  }

  // -----------------------------------------------------------
  // Fetch inicial (una sola vez)
  // -----------------------------------------------------------
  useEffect(() => {
    async function load() {
      try {
        setLoading(true);
        const [empResp, compResp] = await Promise.all([
          api.get<Employee[]>("/superadmin/employees"),
          api.get<Company[]>("/superadmin/companies"),
        ]);

        setEmployees(empResp.data);
        setCompanies(compResp.data);
        setError(null);
      } catch (err) {
        console.error(err);
        setError("No se pudo cargar empleados o empresas.");
      } finally {
        setLoading(false);
      }
    }

    load();
  }, []);

  // -----------------------------------------------------------
  // Filtrado + ordenamiento SOLO EN EL FRONT
  // -----------------------------------------------------------
  const filteredAndSorted = useMemo(() => {
    let list = [...employees];

    // 1) Filtrar empresa
    if (filterCompanyId !== "all") {
      list = list.filter((e) => e.company_id === filterCompanyId);
    }

    // 2) Filtrar rol
    if (filterRole !== "all") {
      list = list.filter((e) => e.role === filterRole);
    }

    // 3) Ordenar
    list.sort((a, b) => {
      let aVal: string | number = "";
      let bVal: string | number = "";

      switch (sortField) {
        case "id":
          aVal = a.id;
          bVal = b.id;
          break;
        case "name":
          aVal = a.name.toLowerCase();
          bVal = b.name.toLowerCase();
          break;
        case "email":
          aVal = a.email.toLowerCase();
          bVal = b.email.toLowerCase();
          break;
        case "role":
          aVal = a.role.toLowerCase();
          bVal = b.role.toLowerCase();
          break;
        case "company":
          aVal = getCompanyName(a.company_id).toLowerCase();
          bVal = getCompanyName(b.company_id).toLowerCase();
          break;
      }

      if (aVal < bVal) return sortDirection === "asc" ? -1 : 1;
      if (aVal > bVal) return sortDirection === "asc" ? 1 : -1;
      return 0;
    });

    return list;
  }, [employees, filterCompanyId, filterRole, sortField, sortDirection, companies]);

  function handleNewEmployee() {
    navigate("/employees/new");
  }

  // -----------------------------------------------------------
  // UI
  // -----------------------------------------------------------
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
        <h1 style={{ fontSize: "1.5rem", fontWeight: 600 }}>Empleados</h1>
        <button
          onClick={handleNewEmployee}
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
          Nuevo empleado
        </button>
      </header>

      {/* FILTROS */}
      <div style={{ display: "flex", gap: "0.75rem", marginBottom: "1rem" }}>
        <div>
          <label style={labelStyle}>Empresa</label>
          <select
            value={filterCompanyId}
            onChange={(e) =>
              setFilterCompanyId(
                e.target.value === "all" ? "all" : Number(e.target.value)
              )
            }
            style={selectStyle}
          >
            <option value="all">Todas</option>
            {companies.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label style={labelStyle}>Rol</label>
          <select
            value={filterRole}
            onChange={(e) => setFilterRole(e.target.value)}
            style={selectStyle}
          >
            <option value="all">Todos</option>
            <option value="admin">Admin</option>
            <option value="collector">Cobrador</option>
            <option value="superadmin">SuperAdmin</option>
          </select>
        </div>
      </div>

      {loading && <p>Cargando...</p>}
      {error && <p style={{ color: "#b91c1c" }}>{error}</p>}

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
              <SortableTh label="ID" icon={sortIcon("id")} onClick={() => toggleSort("id")} />
              <SortableTh label="Nombre" icon={sortIcon("name")} onClick={() => toggleSort("name")} />
              <SortableTh label="Email" icon={sortIcon("email")} onClick={() => toggleSort("email")} />
              <SortableTh label="Rol" icon={sortIcon("role")} onClick={() => toggleSort("role")} />
              <SortableTh label="Empresa" icon={sortIcon("company")} onClick={() => toggleSort("company")} />
              <th style={thStyle}>Teléfono</th>
              <th style={thStyle}>Acciones</th> {/* 👈 NUEVA */}
            </tr>
          </thead>

          <tbody>
            {filteredAndSorted.map((e) => (
              <tr key={e.id}>
                <td style={tdStyle}>{e.id}</td>
                <td style={tdStyle}>{e.name}</td>
                <td style={tdStyle}>{e.email}</td>
                <td style={tdStyle}>{e.role}</td>
                <td style={tdStyle}>{getCompanyName(e.company_id)}</td>
                <td style={tdStyle}>{e.phone || "-"}</td>
                <td style={{ ...tdStyle, whiteSpace: "nowrap" }}>
                  <button
                    onClick={() => navigate(`/employees/${e.id}`)}
                    style={{
                      padding: "0.3rem 0.7rem",
                      borderRadius: "0.5rem",
                      border: "1px solid #d1d5db",
                      background: "white",
                      cursor: "pointer",
                      fontSize: "0.8rem",
                    }}
                  >
                    Ver / editar
                  </button>
                </td>
              </tr>
            ))}

            {filteredAndSorted.length === 0 && (
              <tr>
                <td colSpan={6} style={tdStyle}>
                  No hay empleados con los filtros seleccionados.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      )}
    </div>
  );
}

function SortableTh({
  label,
  icon,
  onClick,
}: {
  label: string;
  icon: string;
  onClick: () => void;
}) {
  return (
    <th
      onClick={onClick}
      style={{
        ...thStyle,
        cursor: "pointer",
        userSelect: "none",
        whiteSpace: "nowrap",
      }}
    >
      {label} <span style={{ fontSize: "0.7rem", opacity: 0.7 }}>{icon}</span>
    </th>
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

const selectStyle: React.CSSProperties = {
  padding: "0.4rem 0.6rem",
  borderRadius: "0.5rem",
  border: "1px solid #d1d5db",
};

const labelStyle: React.CSSProperties = {
  display: "block",
  marginBottom: "0.25rem",
  fontSize: "0.85rem",
};
