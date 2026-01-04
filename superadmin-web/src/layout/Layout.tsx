// src/layout/Layout.tsx
import { useEffect, useState } from "react";
import { NavLink, Outlet, useNavigate } from "react-router-dom";

function useIsMobile(breakpoint = 768) {
  const [isMobile, setIsMobile] = useState(
    typeof window !== "undefined" ? window.innerWidth < breakpoint : false
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

export default function Layout() {
  const navigate = useNavigate();
  const isMobile = useIsMobile();

  function handleLogout() {
    localStorage.removeItem("token");
    navigate("/login");
  }

  // 🔹 Layout MOBILE: sin sidebar, tabs arriba
  if (isMobile) {
    return (
      <div
        style={{
          minHeight: "100vh",
          width: "100%",
          display: "flex",
          flexDirection: "column",
          background: "#f3f4f6",
          color: "#111827",
          fontFamily: "system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
        }}
      >
        {/* Topbar */}
        <header
          style={{
            background: "#111827",
            color: "white",
            padding: "0.75rem 1rem",
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
          }}
        >
          <div>
            <div style={{ fontSize: "1rem", fontWeight: 700 }}>
              CuentaClara
            </div>
            <div style={{ fontSize: "0.8rem", opacity: 0.8 }}>SuperAdmin</div>
          </div>
          <button
            onClick={handleLogout}
            style={{
              padding: "0.3rem 0.7rem",
              borderRadius: "9999px",
              border: "1px solid #4b5563",
              background: "#111827",
              color: "white",
              fontSize: "0.8rem",
              cursor: "pointer",
            }}
          >
            Cerrar sesión
          </button>
        </header>

        {/* Nav tabs */}
        <nav
          style={{
            background: "white",
            borderBottom: "1px solid #e5e7eb",
            display: "flex",
            justifyContent: "space-around",
            padding: "0.4rem 0.5rem",
          }}
        >
          <TopNavLink to="/dashboard" label="Dashboard" />
          <TopNavLink to="/companies" label="Empresas" />
          <TopNavLink to="/employees" label="Empleados" />
        </nav>

        {/* Contenido */}
        <main
          style={{
            flex: 1,
            padding: "1rem",
            width: "100%",
          }}
        >
          <Outlet />
        </main>
      </div>
    );
  }

  // 🔹 Layout DESKTOP: sidebar + contenido que ocupa TODO el ancho restante
  return (
    <div
      style={{
        minHeight: "100vh",
        display: "flex",
        background: "#f3f4f6",
        color: "#111827",
        fontFamily: "system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
      }}
    >
      {/* Sidebar */}
      <aside
        style={{
          width: "220px",
          background: "#111827",
          color: "white",
          padding: "1.25rem 1rem",
          display: "flex",
          flexDirection: "column",
          gap: "1.5rem",
        }}
      >
        <div>
          <div style={{ fontSize: "1.2rem", fontWeight: 700 }}>CuentaClara</div>
          <div style={{ fontSize: "0.85rem", opacity: 0.8 }}>SuperAdmin</div>
        </div>

        <nav
          style={{ display: "flex", flexDirection: "column", gap: "0.4rem" }}
        >
          <SidebarLink to="/dashboard" label="Dashboard" />
          <SidebarLink to="/companies" label="Empresas" />
          <SidebarLink to="/employees" label="Empleados" />
        </nav>
      </aside>

      {/* Contenido */}
      <div style={{ flex: 1, display: "flex", flexDirection: "column" }}>
        {/* Topbar */}
        <header
          style={{
            height: "64px",
            background: "white",
            borderBottom: "1px solid #e5e7eb",
            display: "flex",
            alignItems: "center",
            justifyContent: "flex-end",
            padding: "0 1.5rem",
          }}
        >
          <button
            onClick={handleLogout}
            style={{
              padding: "0.4rem 0.9rem",
              borderRadius: "9999px",
              border: "1px solid #d1d5db",
              background: "white",
              cursor: "pointer",
              fontSize: "0.9rem",
            }}
          >
            Cerrar sesión
          </button>
        </header>

        {/* Página actual */}
        <main
          style={{
            padding: "1.5rem",
            flex: 1,              // ocupa todo el alto
            // 👇 sin justifyContent, sin maxWidth: el contenido ocupa todo el ancho
          }}
        >
          <Outlet />
        </main>
      </div>
    </div>
  );
}

type SidebarLinkProps = {
  to: string;
  label: string;
};

function SidebarLink({ to, label }: SidebarLinkProps) {
  return (
    <NavLink
      to={to}
      style={({ isActive }) => ({
        display: "block",
        padding: "0.45rem 0.75rem",
        borderRadius: "0.5rem",
        fontSize: "0.9rem",
        textDecoration: "none",
        color: "white",
        backgroundColor: isActive ? "#1f2937" : "transparent",
        opacity: isActive ? 1 : 0.9,
      })}
    >
      {label}
    </NavLink>
  );
}

function TopNavLink({ to, label }: { to: string; label: string }) {
  return (
    <NavLink
      to={to}
      style={({ isActive }) => ({
        padding: "0.35rem 0.75rem",
        borderRadius: "9999px",
        fontSize: "0.85rem",
        textDecoration: "none",
        color: isActive ? "#111827" : "#6b7280",
        backgroundColor: isActive ? "#e5e7eb" : "transparent",
      })}
    >
      {label}
    </NavLink>
  );
}
