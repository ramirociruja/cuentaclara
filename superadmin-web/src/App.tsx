// src/App.tsx
import { Navigate, Route, Routes } from "react-router-dom";
import LoginPage from "./pages/LoginPage";
import CompaniesPage from "./pages/CompaniesPage";

function isAuthenticated(): boolean {
  const token = localStorage.getItem("token");
  return !!token;
}

function PrivateRoute({ children }: { children: React.ReactNode }) {
  if (!isAuthenticated()) {
    return <Navigate to="/login" replace />;
  }
  return <>{children}</>;
}


export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/companies"
        element={
          <PrivateRoute>
            <CompaniesPage />
          </PrivateRoute>
        }
      />
      {/* default: si entras a / te manda a /companies si hay token, sino a /login */}
      <Route
        path="*"
        element={
          isAuthenticated() ? (
            <Navigate to="/companies" replace />
          ) : (
            <Navigate to="/login" replace />
          )
        }
      />
    </Routes>
  );
}
