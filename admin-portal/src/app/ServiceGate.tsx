import * as React from "react";
import { Navigate, useLocation } from "react-router-dom";

export function ServiceGate({ children }: { children: React.ReactNode }) {
  const location = useLocation();
  const suspended = localStorage.getItem("service_suspended") === "1";

  if (suspended && location.pathname !== "/service-suspended") {
    return <Navigate to="/service-suspended" replace />;
  }

  return <>{children}</>;
}
