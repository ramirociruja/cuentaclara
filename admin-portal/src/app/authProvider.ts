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
    localStorage.clear();
    return Promise.resolve();
  },

    checkAuth: async () => {
    const access = localStorage.getItem("access_token");
    if (access) return Promise.resolve();

    // Si no hay access, intentamos recuperar con refresh (si existe)
    const refresh = localStorage.getItem("refresh_token");
    if (!refresh) return Promise.reject();

    try {
      // Esto dispara el flujo del httpClient:
      // - 401 inicial
      // - refresh (si corresponde)
      // - reintento
      await httpClient("/health", { method: "GET" }); 
      // 🔁 IMPORTANTE: /health debe ser un endpoint protegido (requiere get_current_user)
      // Si no tenés uno así, reemplazalo por cualquier endpoint protegido barato.
      return Promise.resolve();
    } catch {
      // si no pudo revalidar sesión -> limpiar y mandar login
      localStorage.removeItem("access_token");
      localStorage.removeItem("refresh_token");
      localStorage.removeItem("employee_id");
      localStorage.removeItem("company_id");
      localStorage.removeItem("name");
      localStorage.removeItem("email");
      return Promise.reject();
    }
  },

  checkError: async (error) => {
    const status = error?.status;

    // 401 = no autenticado / token inválido -> forzar login
    if (status === 401) return Promise.reject();

    // 403 = autenticado pero sin permisos -> NO desloguear
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
