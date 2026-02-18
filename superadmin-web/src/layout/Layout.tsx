import { useEffect, useState, type CSSProperties } from "react";
import { NavLink, Outlet, useLocation, useNavigate } from "react-router-dom";

type LinkItem = { to: string; label: string };

const navigation: LinkItem[] = [
  { to: "/dashboard", label: "Dashboard" },
  { to: "/companies", label: "Empresas" },
  { to: "/employees", label: "Empleados" },
];

function useIsMobile(breakpoint = 900) {
  const [isMobile, setIsMobile] = useState(
    typeof window !== "undefined" ? window.innerWidth < breakpoint : false,
  );

  useEffect(() => {
    function handleResize() {
      setIsMobile(window.innerWidth < breakpoint);
    }

    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, [breakpoint]);

  return isMobile;
}

function getPageTitle(pathname: string) {
  if (pathname.startsWith("/companies/new")) return "Crear empresa";
  if (pathname.startsWith("/companies/")) return "Onboarding";
  if (pathname.startsWith("/companies")) return "Empresas";
  if (pathname.startsWith("/employees/new")) return "Crear empleado";
  if (pathname.startsWith("/employees/")) return "Detalle de empleado";
  if (pathname.startsWith("/employees")) return "Empleados";
  return "Dashboard";
}

export default function Layout() {
  const navigate = useNavigate();
  const location = useLocation();
  const isMobile = useIsMobile();

  function handleLogout() {
    localStorage.removeItem("token");
    navigate("/login", { replace: true });
  }

  const pageTitle = getPageTitle(location.pathname);

  return (
    <div style={layoutShell(isMobile)}>
      <aside style={sidebarStyle(isMobile)}>
        <div>
          <div style={{ fontSize: "1.2rem", fontWeight: 800 }}>CuentaClara</div>
          <div style={{ fontSize: "0.85rem", opacity: 0.85 }}>Panel SuperAdmin</div>
        </div>

        <nav style={{ display: "flex", flexDirection: isMobile ? "row" : "column", gap: "0.5rem", flexWrap: "wrap" }}>
          {navigation.map((item) => (
            <NavItem key={item.to} to={item.to} label={item.label} mobile={isMobile} />
          ))}
        </nav>
      </aside>

      <section style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", minHeight: "100vh" }}>
        <header style={headerStyle(isMobile)}>
          <div>
            <h1 style={{ margin: 0, fontSize: isMobile ? "1.1rem" : "1.35rem", lineHeight: 1.2 }}>{pageTitle}</h1>
            <p style={{ margin: "0.15rem 0 0", color: "#6b7280", fontSize: "0.85rem" }}>
              Gestioná empresas, empleados y operaciones rápidamente.
            </p>
          </div>

          <div style={{ display: "flex", alignItems: "center", gap: "0.5rem", flexWrap: "wrap", justifyContent: "flex-end" }}>
            <QuickActionButton label="+ Empresa" onClick={() => navigate("/companies/new")} secondary />
            <QuickActionButton label="+ Empleado" onClick={() => navigate("/employees/new")} secondary />
            <QuickActionButton label="Cerrar sesión" onClick={handleLogout} />
          </div>
        </header>

        <main style={{ padding: isMobile ? "1rem" : "1.25rem 1.5rem", flex: 1, width: "100%", boxSizing: "border-box" }}>
          <Outlet />
        </main>
      </section>
    </div>
  );
}

function NavItem({ to, label, mobile }: { to: string; label: string; mobile: boolean }) {
  return (
    <NavLink
      to={to}
      style={({ isActive }) => ({
        display: "inline-block",
        padding: mobile ? "0.35rem 0.7rem" : "0.5rem 0.75rem",
        borderRadius: "0.55rem",
        fontSize: "0.9rem",
        fontWeight: 600,
        textDecoration: "none",
        backgroundColor: isActive ? "#1f2937" : "transparent",
        color: "white",
        opacity: isActive ? 1 : 0.9,
      })}
    >
      {label}
    </NavLink>
  );
}

function QuickActionButton({ label, onClick, secondary = false }: { label: string; onClick: () => void; secondary?: boolean }) {
  return (
    <button
      onClick={onClick}
      style={{
        borderRadius: "9999px",
        border: secondary ? "1px solid #d1d5db" : "1px solid #1d4ed8",
        background: secondary ? "white" : "#2563eb",
        color: secondary ? "#111827" : "white",
        padding: "0.45rem 0.8rem",
        fontSize: "0.85rem",
        fontWeight: 600,
        cursor: "pointer",
      }}
    >
      {label}
    </button>
  );
}

const headerStyle = (isMobile: boolean): CSSProperties => ({
  minHeight: "72px",
  background: "white",
  borderBottom: "1px solid #e5e7eb",
  display: "flex",
  alignItems: "center",
  justifyContent: "space-between",
  gap: "1rem",
  padding: isMobile ? "0.8rem 1rem" : "1rem 1.5rem",
  position: "sticky",
  top: 0,
  zIndex: 3,
});

const layoutShell = (isMobile: boolean): CSSProperties => ({
  minHeight: "100vh",
  width: "100%",
  display: "flex",
  flexDirection: isMobile ? "column" : "row",
  background: "#f3f4f6",
  color: "#111827",
  fontFamily: "Inter, system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
});

const sidebarStyle = (isMobile: boolean): CSSProperties => ({
  width: isMobile ? "100%" : "245px",
  background: "#111827",
  color: "white",
  padding: isMobile ? "0.75rem 1rem" : "1.25rem 1rem",
  display: "flex",
  flexDirection: isMobile ? "row" : "column",
  justifyContent: isMobile ? "space-between" : "flex-start",
  gap: "1rem",
  boxSizing: "border-box",
  position: isMobile ? "relative" : "sticky",
  top: 0,
  alignSelf: isMobile ? "stretch" : "flex-start",
  minHeight: isMobile ? "auto" : "100vh",
});
