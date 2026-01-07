import { fetchUtils } from "react-admin";

const API_URL = import.meta.env.VITE_API_URL as string;

function authHeader() {
  const token = localStorage.getItem("access_token");
  return token ? { Authorization: `Bearer ${token}` } : {};
}

async function refreshTokens(): Promise<boolean> {
  const refresh_token = localStorage.getItem("refresh_token");
  if (!refresh_token) return false;

  try {
    const resp = await fetchUtils.fetchJson(`${API_URL}/refresh`, {
      method: "POST",
      body: JSON.stringify({ refresh_token }),
      headers: new Headers({
        Accept: "application/json",
        "Content-Type": "application/json",
      }),
    });

    const data = resp.json as {
      access_token: string;
      refresh_token: string;
      token_type: string;
      employee_id: number;
      company_id: number;
      name: string;
      email: string;
    };

    if (!data?.access_token || !data?.refresh_token) return false;

    localStorage.setItem("access_token", data.access_token);
    localStorage.setItem("refresh_token", data.refresh_token);
    localStorage.setItem("employee_id", String(data.employee_id));
    localStorage.setItem("company_id", String(data.company_id));
    localStorage.setItem("name", data.name ?? "");
    localStorage.setItem("email", data.email ?? "");

    return true;
  } catch {
    return false;
  }
}

export const httpClient = async (
  url: string,
  options: fetchUtils.Options = {}
) => {
  const finalUrl = url.startsWith("http") ? url : `${API_URL}${url}`;

  const opts: fetchUtils.Options = { ...options };
  opts.headers = new Headers(opts.headers || { Accept: "application/json" });

  // Set Content-Type si corresponde
  if (opts.method && opts.method !== "GET" && !opts.headers.has("Content-Type")) {
    opts.headers.set("Content-Type", "application/json");
  }

  // Agregar bearer (excepto si no hay token, ej login)
  const h = authHeader();
  if (h.Authorization) opts.headers.set("Authorization", h.Authorization);

  try {
    return await fetchUtils.fetchJson(finalUrl, opts);
  } catch (err: any) {
    const status = err?.status;

    // Solo intentamos refresh en 401
    if (status !== 401) throw err;

    const refreshed = await refreshTokens();
    if (!refreshed) {
      // limpia todo si refresh falla
      localStorage.removeItem("access_token");
      localStorage.removeItem("refresh_token");
      throw err;
    }

    // Reintentar UNA VEZ el request original con token nuevo
    const h2 = authHeader();
    if (h2.Authorization) opts.headers.set("Authorization", h2.Authorization);
    return await fetchUtils.fetchJson(finalUrl, opts);
  }
};
