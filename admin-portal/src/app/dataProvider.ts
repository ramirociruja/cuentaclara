import type { DataProvider } from "react-admin";
import { httpClient } from "./httpClient";

type BuildQueryOptions = {
  includePagination?: boolean;
  includeSort?: boolean;
};

/**
 * OJO: varios endpoints actuales NO aceptan limit/offset (si los mandás, FastAPI responde 422).
 * Por eso buildQuery recibe flags para decidir qué incluir por recurso.
 */
function buildQuery(params: any, opts: BuildQueryOptions = {}) {
  const q = new URLSearchParams();
  const includePagination = opts.includePagination ?? false;
  const includeSort = opts.includeSort ?? false;

  if (includePagination) {
    const page = params?.pagination?.page ?? 1;
    const perPage = params?.pagination?.perPage ?? 25;
    const limit = perPage;
    const offset = (page - 1) * perPage;
    q.set("limit", String(limit));
    q.set("offset", String(offset));
  }

  const filter = params?.filter ?? {};
  Object.entries(filter).forEach(([k, v]) => {
    if (v === undefined || v === null || v === "") return;
    q.set(k, String(v));
  });

  if (includeSort) {
    const sort = params?.sort;
    if (sort?.field) {
      q.set("sort", String(sort.field));
      q.set("order", String(sort.order ?? "ASC"));
    }
  }

  return q.toString();
}

function sortLocal(rows: any[], params: any) {
  const field = params?.sort?.field;
  const order = String(params?.sort?.order ?? "ASC").toUpperCase();

  if (!field) return rows;

  const dir = order === "DESC" ? -1 : 1;

  const getVal = (r: any) => {
    const v = r?.[field];
    if (v === undefined || v === null) return null;

    // fechas ISO -> timestamp
    if (typeof v === "string") {
      const t = Date.parse(v);
      if (!Number.isNaN(t)) return t;
      return v.toLowerCase();
    }

    return v;
  };

  return [...rows].sort((a, b) => {
    const av = getVal(a);
    const bv = getVal(b);

    if (av === null && bv === null) return 0;
    if (av === null) return 1;   // nulls al final
    if (bv === null) return -1;

    // números
    if (typeof av === "number" && typeof bv === "number") return (av - bv) * dir;

    // fallback string
    return String(av).localeCompare(String(bv), "es", { sensitivity: "base" }) * dir;
  });
}


function withId(row: any, fallbackId?: any) {
  const id =
    row?.id ??
    row?.payment_id ??
    row?.installment_id ??
    row?.loan_id ??
    row?.customer_id ??
    row?.employee_id ??
    fallbackId;

  return { ...row, id };
}

const SERVER_PAGINATED_RESOURCES = new Set<string>([
  // backend: /installments/collectable-per-loan -> {data,total} con limit/offset
  "collectable",
  "payments",
]);

function listEndpoint(resource: string) {
  if (resource === "collectable") return "/installments/collectable-per-loan";
  
  if (resource === "loans") return "/loans/all";

  if (resource === "payments") return "/payments/all";

  if (resource === "loans_effective") return "/loans/";
  
  return `/${resource}/`;
}

function createEndpoint(resource: string, params?: any) {
  // backend: /loans/createLoan/ (no estándar)
  if (resource === "loans") return "/loans/createLoan/";

   // NUEVO: registrar pago de cuota
  if (resource === "installment_payments") {
    const installmentId = params?.meta?.installment_id;
    if (!installmentId) {
      throw new Error("create(installment_payments) requiere meta.installment_id");
    }
    return `/installments/${installmentId}/pay`;
  }

    // NUEVO: registrar pago directo a un préstamo (crea Payment)
  if (resource === "loan_payments") {
    const loanId = params?.meta?.loan_id;
    if (!loanId) {
      throw new Error("create(loan_payments) requiere meta.loan_id");
    }
    return `/loans/${loanId}/pay`;
  }


  return `/${resource}`;
}

function updateEndpoint(resource: string, id: any) {
  return `/${resource}/${id}`;
}

export const dataProvider: DataProvider = {
  getList: async (resource, params) => {
  const endpoint = listEndpoint(resource);

  const serverPaginated = SERVER_PAGINATED_RESOURCES.has(resource);

  // ===============================
  // PAYMENTS: incluir voided por defecto (solo admin-portal)
  // ===============================
  let nextParams = params;

  if (resource === "payments") {
    const currentFilter = (params?.filter ?? {}) as any;
    const filter = { ...currentFilter } as any;

    // Si el UI NO especifica is_voided, traemos ambos (active + voided)
    if (typeof filter.is_voided === "undefined") {
      filter.include_voided = true;
    } else {
      // Si viene is_voided, no hace falta include_voided
      delete filter.include_voided;
    }

    // Re-armamos params sin mutar el objeto original
    nextParams = { ...params, filter };
  }

  const qs = buildQuery(nextParams, {
    includePagination: serverPaginated,
    includeSort: serverPaginated,
  });

  const url = qs ? `${endpoint}?${qs}` : endpoint;
  const resp = await httpClient(url);
  const json = resp.json as any;

  // Caso A: backend devuelve {data,total}
  if (json && Array.isArray(json.data) && typeof json.total === "number") {
    const data = json.data.map((row: any) => withId(row));
    return { data, total: json.total };
  }

  // Caso B: backend devuelve lista simple []
  if (Array.isArray(json)) {
    const all = json.map((row: any) => withId(row));
    const sorted = sortLocal(all, params);
    const total = sorted.length;

    // Paginación en frontend
    const page = params?.pagination?.page ?? 1;
    const perPage = params?.pagination?.perPage ?? 25;
    const start = (page - 1) * perPage;
    const end = start + perPage;

    return { data: sorted.slice(start, end), total };
  }

  throw new Error(
    `getList(${resource}) no soporta el formato de respuesta recibido: ${JSON.stringify(json).slice(0, 400)}`
  );
},


  getOne: async (resource, params) => {
    const resp = await httpClient(`/${resource}/${params.id}`);
    const row = resp.json as any;
    return { data: withId(row, params.id) };
  },

  create: async (resource, params) => {
    const endpoint = createEndpoint(resource, params);

    const resp = await httpClient(endpoint, {
      method: "POST",
      body: JSON.stringify(params.data),
    });

    const row = resp.json as any;
    return { data: withId(row) };
  },

  update: async (resource, params) => {
    const endpoint = updateEndpoint(resource, params.id);

    const resp = await httpClient(endpoint, {
      method: "PUT",
      body: JSON.stringify(params.data),
    });

    const row = resp.json as any;
    return { data: withId(row, params.id) };
  },

  /**
   * Importante:
   * - Payments: NO borramos; anulamos via POST /payments/void/{id} (soft-delete contable).
   * - Employees: backend sí tiene DELETE /employees/{id}.
   * - Otros: no implementamos delete todavía.
   */
  delete: async (resource, params) => {
    if (resource === "payments") {
      const reason = (params as any)?.meta?.reason ?? null;

      await httpClient(`/payments/void/${params.id}`, {
        method: "POST",
        body: reason ? JSON.stringify({ reason }) : undefined,
      });

      // React-Admin espera devolver el registro borrado
      return { data: withId(params.previousData ?? { id: params.id }) };
    }

    if (resource === "employees") {
      await httpClient(`/employees/${params.id}`, { method: "DELETE" });
      return { data: withId(params.previousData ?? { id: params.id }) };
    }

    throw new Error(`delete(${resource}) no está habilitado en el backend (o no es recomendable).`);
  },

  /**
   * Backends típicos no tienen GET /resource?ids=...
   * Implementación simple: múltiples getOne.
   */
  getMany: async (resource, params) => {
    const rows = await Promise.all(
      params.ids.map((id: any) =>
        httpClient(`/${resource}/${id}`).then((r) => withId(r.json as any, id))
      )
    );
    return { data: rows };
  },

  /**
   * Implementación base: trae lista y filtra en frontend.
   * (Suficiente para arrancar; si lo usamos intensivamente, agregamos endpoint dedicado en backend)
   */
  getManyReference: async (resource, params) => {
    const filter = { ...(params.filter ?? {}), [params.target]: params.id };
    const resp = await dataProvider.getList(resource, {
      ...params,
      filter,
    } as any);

    return resp;
  },

  updateMany: async (resource, params) => {
    const results = await Promise.all(
      params.ids.map((id: any) =>
        dataProvider.update(resource, { id, data: params.data, previousData: undefined } as any)
      )
    );
    return { data: results.map((r) => r.data.id) };
  },

  deleteMany: async (resource, params) => {
    const results = await Promise.all(
      params.ids.map((id: any) =>
        dataProvider.delete(resource, { id, previousData: undefined } as any)
      )
    );
    return { data: results.map((r) => r.data.id) };
  },
};
