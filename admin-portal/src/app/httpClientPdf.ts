const API_URL = import.meta.env.VITE_API_URL ?? "";

function authHeader(): Record<string, string> {
  const token = localStorage.getItem("access_token");
  return token ? { Authorization: `Bearer ${token}` } : {};
}


function headersToRecord(h?: HeadersInit): Record<string, string> {
  if (!h) return {};
  if (h instanceof Headers) return Object.fromEntries(h.entries());
  if (Array.isArray(h)) return Object.fromEntries(h);
  return h;
}

async function refreshTokens(): Promise<boolean> {
  const refresh_token = localStorage.getItem("refresh_token");
  if (!refresh_token) return false;

  try {
    const res = await fetch(`${API_URL}/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ refresh_token }),
    });

    if (!res.ok) return false;

    const data = await res.json();
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

export async function httpPdf(path: string, init?: RequestInit): Promise<Blob> {
  const doFetch = async () => {
    const headers: Record<string, string> = {
      ...headersToRecord(init?.headers),
      ...(authHeader()),
    };

    return fetch(`${API_URL}${path}`, {
      ...init,
      headers,
      credentials: "omit",
    });
  };

  let res = await doFetch();

  if (res.status === 401) {
    const refreshed = await refreshTokens();
    if (refreshed) res = await doFetch();
  }

  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(text || `HTTP ${res.status}`);
  }

  const ct = res.headers.get("content-type") || "";
  if (!ct.includes("application/pdf")) {
    const text = await res.text().catch(() => "");
    throw new Error(text || "Respuesta inesperada (no PDF).");
  }

  return await res.blob();
}

export function openBlobInNewTab(blob: Blob) {
  const url = URL.createObjectURL(blob);
  window.open(url, "_blank", "noopener,noreferrer");
}
