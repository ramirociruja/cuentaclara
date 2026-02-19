import { fetchUtils, HttpError } from "react-admin";

const API_URL = import.meta.env.VITE_API_URL as string;

let authBroken = false;

function authHeader() {
  const token = localStorage.getItem("access_token");
  return token ? { Authorization: `Bearer ${token}` } : {};
}

// ✅ Lock global: un solo refresh a la vez
let refreshInFlight: Promise<boolean> | null = null;

async function _refreshTokensOnce(): Promise<boolean> {
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

    authBroken = false;
    return true;
  } catch {
    return false;
  }
}

function refreshTokens(): Promise<boolean> {
  // Si ya hay un refresh corriendo, esperamos ese mismo
  if (refreshInFlight) return refreshInFlight;

  refreshInFlight = (async () => {
    try {
      return await _refreshTokensOnce();
    } finally {
      refreshInFlight = null;
    }
  })();

  return refreshInFlight;
}

/**
 * Convierte FastAPI 422:
 * { detail: [{ loc: ["body","field"], msg: "...", type: "..." }, ...] }
 * a un body que React-Admin entiende:
 * { errors: { field: "..." } }
 */
function fastApi422ToRaBody(json: any): { message?: string; errors: Record<string, string> } | null {
  const detail = json?.detail;
  if (!Array.isArray(detail)) return null;

  const errors: Record<string, string> = {};
  for (const it of detail) {
    const loc = it?.loc;
    const msg = it?.msg ?? "Valor inválido";
    const field =
      Array.isArray(loc) && loc.length ? String(loc[loc.length - 1]) : "_error";
    if (!errors[field]) errors[field] = String(msg);
  }

  return { message: "Formulario inválido", errors };
}

/**
 * Asegura que el error que llega a React-Admin siempre tenga:
 * - status (number)
 * - message (string)
 * - body (object) (NUNCA null/undefined)
 */
function normalizeToHttpError(err: any): HttpError {
  // err de fetchUtils suele ser HttpError con: message/status/body
  const status = Number(err?.status ?? err?.response?.status ?? 0) || 0;
  const rawBody = err?.body ?? err?.response?.body ?? err?.json ?? err?.response?.data;

  // Si el backend devolvió JSON
  const json = rawBody && typeof rawBody === "object" ? rawBody : undefined;

  // Si es FastAPI 422, lo convertimos a errores por campo
  const ra422 = json ? fastApi422ToRaBody(json) : null;

  // message razonable
  const message =
    (typeof json?.detail === "string" && json.detail) ||
    (typeof json?.message === "string" && json.message) ||
    (typeof err?.message === "string" && err.message) ||
    "Error";

  // body SIEMPRE definido para evitar setSubmissionErrors(Object.entries(null))
  const body =
    ra422 ??
    (json ?? (typeof rawBody === "string" ? { message: rawBody, errors: {} } : { message, errors: {} }));

  // Garantía extra: errors siempre objeto
  if (body && typeof body === "object" && body.errors == null) {
    body.errors = {};
  }

  return new HttpError(message, status || 500, body);
}


function isServiceSuspendedError(err: any): boolean {
  const body = err?.body ?? err?.json ?? err?.response?.body ?? err?.response?.data;
  return body?.detail?.code === "SERVICE_SUSPENDED";
}

function redirectToServiceSuspended(err: any) {
  const body = err?.body ?? err?.json ?? {};
  const detail = body?.detail ?? {};

  localStorage.setItem("service_suspended", "1");
  localStorage.setItem("service_suspended_status", String(detail?.status ?? ""));
  localStorage.setItem("service_suspended_reason", String(detail?.reason ?? ""));

}



export const httpClient = async (
  url: string,
  options: fetchUtils.Options = {}
) => {
  const finalUrl = url.startsWith("http") ? url : `${API_URL}${url}`;

  if (authBroken) {
  throw new HttpError("No autorizado", 401, {});
  }

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
    const res = await fetchUtils.fetchJson(finalUrl, opts);

    // ✅ si volvió a estar ok, limpiamos
    authBroken = false;
    localStorage.removeItem("service_suspended");
    localStorage.removeItem("service_suspended_status");
    localStorage.removeItem("service_suspended_reason");

    return res;

  } catch (err: any) {
    const status = Number(err?.status ?? 0);
    console.log("[httpClient catch]", {
  url,
  status,
  errKeys: Object.keys(err ?? {}),
  body: err?.body,
  json: err?.json,
});

    // ✅ SERVICE SUSPENDED -> guardar flag y REDIRIGIR YA MISMO
    if (status === 403 && isServiceSuspendedError(err)) {
      const body = err?.body ?? err?.json ?? {};
      const detail = body?.detail ?? {};

      localStorage.setItem("service_suspended", "1");
      localStorage.setItem("service_suspended_status", String(detail?.status ?? ""));
      localStorage.setItem("service_suspended_reason", String(detail?.reason ?? ""));

      const path = window.location.pathname;
      if (path !== "/service-suspended") {
        window.location.replace("/service-suspended");
      }

      throw normalizeToHttpError(err);
    }

    // Solo intentamos refresh en 401
    if (status === 401) {
      const refreshed = await refreshTokens();
      if (!refreshed) {
        authBroken = true;
        localStorage.removeItem("access_token");
        localStorage.removeItem("refresh_token");
        throw normalizeToHttpError(err);
      }

      // Reintentar UNA VEZ el request original con token nuevo
      const h2 = authHeader();
      if (h2.Authorization) opts.headers.set("Authorization", h2.Authorization);

      try {
        return await fetchUtils.fetchJson(finalUrl, opts);
      } catch (err2: any) {
        const status2 = Number(err2?.status ?? 0);

        console.log("[httpClient catch]", {
  url,
  status,
  errKeys: Object.keys(err ?? {}),
  body: err?.body,
  json: err?.json,
});

        // ✅ IMPORTANTE: si el retry devuelve SERVICE_SUSPENDED, redirigir acá también
        if (status2 === 403 && isServiceSuspendedError(err2)) {
          redirectToServiceSuspended(err2);
        }

        throw normalizeToHttpError(err2);
      }
    }

    // Cualquier otro error: normalizar para React-Admin
    throw normalizeToHttpError(err);
  }
};
