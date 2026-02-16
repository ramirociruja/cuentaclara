export function extractApiErrorMessage(err: any): string {
  // 1) si ya viene “bonito”
  if (typeof err === "string") return err;

  // 2) axios-style
  const data = err?.response?.data;
  if (data) {
    const d = data?.detail ?? data;
    if (typeof d === "string") return d;
    if (d && typeof d === "object") {
      // casos típicos FastAPI custom
      if (typeof d.message === "string") return d.message;
      if (typeof d.reason === "string" && d.reason) return d.reason;
      if (typeof d.code === "string") return d.code;
      return JSON.stringify(d);
    }
  }

  // 3) tu httpClient wrapper suele retornar err.body / err.json / err.data
  const maybe = err?.json ?? err?.body ?? err?.data;
  if (maybe) {
    const d = maybe?.detail ?? maybe;
    if (typeof d === "string") return d;
    if (d && typeof d === "object") {
      if (typeof d.message === "string") return d.message;
      if (typeof d.reason === "string" && d.reason) return d.reason;
      if (typeof d.code === "string") return d.code;
      return JSON.stringify(d);
    }
  }

  // 4) fallback genérico
  const msg = err?.message;
  if (typeof msg === "string" && msg.trim()) return msg;

  return "Error inesperado";
}
