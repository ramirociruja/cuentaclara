// src/App.tsx
import type { ReactElement } from "react";
import { Navigate, Route, Routes } from "react-router-dom";
import LoginPage from "./pages/LoginPage";
import CompaniesPage from "./pages/CompaniesPage";
import DashboardPage from "./pages/DashboardPage";
import EmployeesPage from "./pages/EmployeesPage";
import CreateCompanyPage from "./pages/CreateCompanyPage";
import Layout from "./layout/Layout";
import CreateEmployeePage from "./pages/CreateEmployeePage";
import EmployeeDetailPage from "./pages/EmployeeDetailPage";
import OnboardingImportPage from "./pages/OnboardingImportPage";

function isAuthenticated(): boolean {
  const token = localStorage.getItem("token");
  return !!token;
}

function PrivateRoute({ children }: { children: ReactElement }) {
  if (!isAuthenticated()) {
    return <Navigate to="/login" replace />;
  }
  return children;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />

      {/* Rutas protegidas con layout */}
      <Route
        path="/"
        element={
          <PrivateRoute>
            <Layout />
          </PrivateRoute>
        }
      >
        <Route index element={<Navigate to="/dashboard" replace />} />
        <Route path="dashboard" element={<DashboardPage />} />
        <Route path="companies" element={<CompaniesPage />} />
        <Route path="companies/new" element={<CreateCompanyPage />} /> {/* 👈 NUEVA */}
        <Route
          path="companies/:id/onboarding-import"
          element={<OnboardingImportPage />}
        />
        <Route path="employees" element={<EmployeesPage />} />
        <Route path="employees/new" element={<CreateEmployeePage />} />
        <Route path="employees/:id" element={<EmployeeDetailPage />} />
      </Route>

      {/* Fallback */}
      <Route path="*" element={<Navigate to="/dashboard" replace />} />
    </Routes>
  );
}
