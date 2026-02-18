import { useEffect, useMemo, useState, type CSSProperties } from "react";
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
  const [search, setSearch] = useState("");

  const [sortField, setSortField] = useState<SortField>("id");
  const [sortDirection, setSortDirection] = useState<SortDirection>("asc");

  const companyNameById = useMemo(() => {
    const map = new Map<number, string>();
    companies.forEach((company) => {
      map.set(company.id, company.name);
    });
    return map;
  }, [companies]);

  function getCompanyName(id: number) {
    return companyNameById.get(id) || `#${id}`;
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

  async function loadData() {
    try {
      setLoading(true);
      setError(null);
      const [empResp, compResp] = await Promise.all([
        api.get<Employee[]>("/superadmin/employees"),
        api.get<Company[]>("/superadmin/companies"),
      ]);

      setEmployees(empResp.data);
      setCompanies(compResp.data);
    } catch (err) {
      console.error(err);
      setError("No se pudo cargar empleados o empresas.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadData();
  }, []);

  const filteredAndSorted = useMemo(() => {
    let list = [...employees];

    if (filterCompanyId !== "all") {
      list = list.filter((employee) => employee.company_id === filterCompanyId);
    }

    if (filterRole !== "all") {
      list = list.filter((employee) => employee.role === filterRole);
    }

    const term = search.trim().toLowerCase();
    if (term) {
      list = list.filter((employee) => {
        return (
          employee.name.toLowerCase().includes(term) ||
          employee.email.toLowerCase().includes(term) ||
          String(employee.id).includes(term) ||
          getCompanyName(employee.company_id).toLowerCase().includes(term)
        );
      });
    }

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
  }, [employees, filterCompanyId, filterRole, sortField, sortDirection, search, companyNameById]);

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "1rem" }}>
      <header
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          marginBottom: "0.5rem",
          flexWrap: "wrap",
          gap: "0.75rem",
        }}
      >
        <h2 style={{ margin: 0, fontSize: "1.45rem", fontWeight: 700 }}>Empleados</h2>

        <div style={{ display: "flex", gap: "0.6rem" }}>
          <button onClick={loadData} style={secondaryButton}>Recargar</button>
          <button onClick={() => navigate("/employees/new")} style={primaryButton}>
            Nuevo empleado
          </button>
        </div>
      </header>

      <div style={panelStyle}>
        <div style={{ display: "flex", gap: "0.75rem", flexWrap: "wrap" }}>
          <div>
            <label style={labelStyle}>Empresa</label>
            <select
              value={filterCompanyId}
              onChange={(event) =>
                setFilterCompanyId(
                  event.target.value === "all" ? "all" : Number(event.target.value),
                )
              }
              style={selectStyle}
            >
              <option value="all">Todas</option>
              {companies.map((company) => (
                <option key={company.id} value={company.id}>
                  {company.name}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label style={labelStyle}>Rol</label>
            <select
              value={filterRole}
              onChange={(event) => setFilterRole(event.target.value)}
              style={selectStyle}
            >
              <option value="all">Todos</option>
              <option value="admin">Admin</option>
              <option value="collector">Cobrador</option>
              <option value="superadmin">SuperAdmin</option>
            </select>
          </div>

          <div style={{ minWidth: "220px", flex: 1 }}>
            <label style={labelStyle}>Buscar</label>
            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              style={selectStyle}
              placeholder="Nombre, email, empresa o ID"
            />
          </div>
        </div>
      </div>

      {loading && <p>Cargando...</p>}
      {error && <p style={{ color: "#b91c1c" }}>{error}</p>}

      {!loading && !error && (
        <div style={{ ...panelStyle, overflowX: "auto" }}>
          <table
            style={{
              width: "100%",
              minWidth: "920px",
              borderCollapse: "collapse",
              background: "white",
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
                <th style={thStyle}>Acciones</th>
              </tr>
            </thead>

            <tbody>
              {filteredAndSorted.map((employee) => (
                <tr key={employee.id}>
                  <td style={tdStyle}>{employee.id}</td>
                  <td style={tdStyle}>{employee.name}</td>
                  <td style={tdStyle}>{employee.email}</td>
                  <td style={tdStyle}>{employee.role}</td>
                  <td style={tdStyle}>{getCompanyName(employee.company_id)}</td>
                  <td style={tdStyle}>{employee.phone || "-"}</td>
                  <td style={{ ...tdStyle, whiteSpace: "nowrap" }}>
                    <button
                      onClick={() => navigate(`/employees/${employee.id}`)}
                      style={secondaryButton}
                    >
                      Ver / editar
                    </button>
                  </td>
                </tr>
              ))}

              {filteredAndSorted.length === 0 && (
                <tr>
                  <td colSpan={7} style={tdStyle}>
                    No hay empleados con los filtros seleccionados.
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

const panelStyle: CSSProperties = {
  background: "white",
  borderRadius: "0.75rem",
  boxShadow: "0 10px 25px rgba(0, 0, 0, 0.05)",
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

const selectStyle: CSSProperties = {
  width: "100%",
  padding: "0.5rem 0.6rem",
  borderRadius: "0.5rem",
  border: "1px solid #d1d5db",
  fontSize: "0.9rem",
};

const labelStyle: CSSProperties = {
  display: "block",
  marginBottom: "0.25rem",
  fontSize: "0.82rem",
  color: "#6b7280",
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
