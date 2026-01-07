import type { AuthProvider } from "react-admin";
import { httpClient } from "./httpClient";

type TokenPairResponse = {
  access_token: string;
  refresh_token: string;
  token_type: string; // "bearer"
  employee_id: number;
  company_id: number;
  name: string;
  email: string;
};

export const authProvider: AuthProvider = {
  login: async ({ username, password }) => {
    // Tu backend espera username=email
    const body = JSON.stringify({ username, password });

    const resp = await httpClient("/login", {
      method: "POST",
      body,
      // IMPORTANTE: httpClient agrega headers y NO requiere bearer para login
    });

    const data = resp.json as TokenPairResponse;

    if (!data?.access_token || !data?.refresh_token) {
      throw new Error("Login inválido: faltan tokens en la respuesta");
    }

    localStorage.setItem("access_token", data.access_token);
    localStorage.setItem("refresh_token", data.refresh_token);

    // Info útil para UI (opcional)
    localStorage.setItem("employee_id", String(data.employee_id));
    localStorage.setItem("company_id", String(data.company_id));
    localStorage.setItem("name", data.name ?? "");
    localStorage.setItem("email", data.email ?? "");

    return Promise.resolve();
  },

  logout: async () => {
    // Tu backend tiene /logout_all (204). Podríamos llamarlo, pero no es obligatorio para MVP.
    // Si querés invalidar refresh tokens server-side, lo agregamos luego.
    localStorage.removeItem("access_token");
    localStorage.removeItem("refresh_token");
    localStorage.removeItem("employee_id");
    localStorage.removeItem("company_id");
    localStorage.removeItem("name");
    localStorage.removeItem("email");
    return Promise.resolve();
  },

  checkAuth: async () => {
    const token = localStorage.getItem("access_token");
    if (!token) return Promise.reject();
    return Promise.resolve();
  },

  checkError: async (error) => {
    const status = error?.status;
    if (status === 401 || status === 403) {
      // si falla refresh, se limpiará igual en httpClient
      return Promise.reject();
    }
    return Promise.resolve();
  },

  getPermissions: async () => {
    // En tu backend hay roles en Employee, pero no los estoy asumiendo.
    // Luego lo leemos de un endpoint /employees/me si querés.
    return Promise.resolve("company_admin");
  },

  getIdentity: async () => {
    const id = localStorage.getItem("employee_id") ?? "me";
    const fullName = localStorage.getItem("name") ?? "Usuario";
    return Promise.resolve({ id, fullName });
  },
};
