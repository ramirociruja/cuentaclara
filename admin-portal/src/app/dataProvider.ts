import type { DataProvider } from "react-admin";
import { httpClient } from "./httpClient";

function buildQuery(params: any) {
  const q = new URLSearchParams();

  // pagination
  const page = params?.pagination?.page ?? 1;
  const perPage = params?.pagination?.perPage ?? 25;

  // Convertimos a limit/offset (tu backend suele usar eso mejor)
  const limit = perPage;
  const offset = (page - 1) * perPage;

  q.set("limit", String(limit));
  q.set("offset", String(offset));

  // filters (simple)
  const filter = params?.filter ?? {};
  Object.entries(filter).forEach(([k, v]) => {
    if (v === undefined || v === null || v === "") return;
    q.set(k, String(v));
  });

  // sort (opcional)
  const sort = params?.sort;
  if (sort?.field) {
    q.set("sort", String(sort.field));
    q.set("order", String(sort.order ?? "ASC"));
  }

  return q.toString();
}

export const dataProvider: DataProvider = {
  getList: async (resource, params) => {
    // Mapeo resource->endpoint
    // Por ahora: "collectable" va a pegarle a /installments/collectable-per-loan
    const endpoint =
      resource === "collectable"
        ? "/installments/collectable-per-loan"
        : `/${resource}`;

    const qs = buildQuery(params);
    const url = `${endpoint}?${qs}`;

    const resp = await httpClient(url);
    const json = resp.json as any;

    // Esperamos {data, total}
    if (!json?.data || typeof json?.total !== "number") {
      throw new Error(`getList(${resource}) esperaba {data,total}. Recibió: ${JSON.stringify(json).slice(0, 300)}`);
    }

    // RA necesita que cada item tenga "id"
    const data = json.data.map((row: any) => ({
      ...row,
      id: row.id ?? row.installment_id ?? row.loan_id,
    }));

    return { data, total: json.total };
  },

  getOne: async (resource, params) => {
    const resp = await httpClient(`/${resource}/${params.id}`);
    const row = resp.json as any;
    return { data: { ...row, id: row.id ?? params.id } };
  },

  // De momento, stub para que no reviente si RA llama algo no implementado
  create: async () => {
    throw new Error("create no implementado aún");
  },
  update: async () => {
    throw new Error("update no implementado aún");
  },
  delete: async () => {
    throw new Error("delete no implementado aún");
  },
  getMany: async () => {
    throw new Error("getMany no implementado aún");
  },
  getManyReference: async () => {
    throw new Error("getManyReference no implementado aún");
  },
  updateMany: async () => {
    throw new Error("updateMany no implementado aún");
  },
  deleteMany: async () => {
    throw new Error("deleteMany no implementado aún");
  },
};
