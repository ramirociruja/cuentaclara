import * as React from "react";
import { httpClient } from "../../app/httpClient";
import {
  Box,
  Paper,
  Typography,
  TextField,
  Button,
  Stack,
  Divider,
} from "@mui/material";
import { useVirtualizer } from "@tanstack/react-virtual";

type CollectableRow = {
  loan_id?: number | null;
  purchase_id?: number | null;

  installment_id: number;

  collector_id?: number | null;
  collector_name?: string | null;

  customer_id?: number | null;
  customer_name?: string | null;
  customer_phone?: string | null;

  installment_number?: number | null;
  due_date?: string | null;

  installment_amount?: number | null;
  installment_balance?: number | null;

  loan_balance?: number | null;
  purchase_balance?: number | null;
};

// 👇 ahora el draft guarda el string visible del input (para formato dinero)
type DraftPayment = {
  amount: string; // ej: "1.234,56"
};

type SortState = {
  key: SortKey;
  dir: "asc" | "desc";
} | null;

type SortKey =
  | "collector_name"
  | "customer_name"
  | "debt_label"
  | "installment_number"
  | "due_date"
  | "installment_amount"
  | "installment_balance"
  | "debt_balance";

function n(v: any): number {
  const x = Number(v);
  return Number.isFinite(x) ? x : 0;
}

const moneyFmt = new Intl.NumberFormat("es-AR", {
  style: "currency",
  currency: "ARS",
  maximumFractionDigits: 2,
});

function fmtMoney(v: number): string {
  return moneyFmt.format(v || 0);
}

const inputMoneyFmt = new Intl.NumberFormat("es-AR", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 2,
});

// Soporta: "1.234,56" "1234,56" "1,234.56" "1234.56" "1.234"
function parseMoneyInput(s: string): number {
  const raw = (s ?? "").trim();
  if (!raw) return 0;

  const hasDot = raw.includes(".");
  const hasComma = raw.includes(",");

  let normalized = raw;

  if (hasDot && hasComma) {
    const lastDot = raw.lastIndexOf(".");
    const lastComma = raw.lastIndexOf(",");
    const decIsComma = lastComma > lastDot;

    if (decIsComma) {
      // miles: ".", decimal: ","
      normalized = raw.replace(/\./g, "").replace(",", ".");
    } else {
      // miles: ",", decimal: "."
      normalized = raw.replace(/,/g, "");
    }
  } else if (hasComma && !hasDot) {
    // decimal coma
    normalized = raw.replace(/\./g, "").replace(",", ".");
  } else {
    // si termina en .### asumimos miles
    if (/\.(\d{3})$/.test(raw)) normalized = raw.replace(/\./g, "");
  }

  const num = Number(normalized);
  return Number.isFinite(num) ? num : 0;
}

function formatMoneyInput(num: number): string {
  return inputMoneyFmt.format(num || 0);
}

function debtLabel(r: CollectableRow): string {
  if (r.loan_id) return `Préstamo #${r.loan_id}`;
  if (r.purchase_id) return `Compra #${r.purchase_id}`;
  return "-";
}

function debtBalance(r: CollectableRow): number {
  return n(r.loan_balance ?? r.purchase_balance);
}

function compare(a: any, b: any): number {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;

  if (typeof a === "number" && typeof b === "number") return a - b;

  const sa = String(a);
  const sb = String(b);
  return sa.localeCompare(sb, "es", { numeric: true, sensitivity: "base" });
}

function sortRows(rows: CollectableRow[], sort: SortState): CollectableRow[] {
  if (!sort) return rows;

  const factor = sort.dir === "asc" ? 1 : -1;

  const getVal = (r: CollectableRow) => {
    switch (sort.key) {
      case "collector_name":
        return r.collector_name ?? "";
      case "customer_name":
        return r.customer_name ?? "";
      case "debt_label":
        return debtLabel(r);
      case "installment_number":
        return n(r.installment_number);
      case "due_date":
        return r.due_date ?? "";
      case "installment_amount":
        return n(r.installment_amount);
      case "installment_balance":
        return n(r.installment_balance);
      case "debt_balance":
        return debtBalance(r);
      default:
        return "";
    }
  };

  return [...rows].sort((ra, rb) => factor * compare(getVal(ra), getVal(rb)));
}

export default function BulkPaymentsScreen() {
  const [loading, setLoading] = React.useState(false);
  const [rows, setRows] = React.useState<CollectableRow[]>([]);
  const [total, setTotal] = React.useState<number>(0);

  const [q, setQ] = React.useState<string>("");
  const [limit] = React.useState<number>(500);
  const [offset, setOffset] = React.useState<number>(0);

  const [draft, setDraft] = React.useState<Record<number, DraftPayment>>({});

  const [sort, setSort] = React.useState<SortState>({
    key: "due_date",
    dir: "asc",
  });

  const endpoint = "/installments/collectable-per-loan";

  const load = React.useCallback(async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams();
      if (q.trim()) params.set("q", q.trim());
      params.set("limit", String(limit));
      params.set("offset", String(offset));
      params.set("tz", "America/Argentina/Tucuman");

      const resp = await httpClient(`${endpoint}?${params.toString()}`, {
        method: "GET",
      });
      const json = resp.json as { data: CollectableRow[]; total: number };

      const data = Array.isArray(json?.data) ? json.data : [];
      setRows(data);
      setTotal(Number(json?.total ?? data.length ?? 0));
    } finally {
      setLoading(false);
    }
  }, [endpoint, q, limit, offset]);

  React.useEffect(() => {
    load();
  }, [load]);

  const totals = React.useMemo(() => {
    let count = 0;
    let sum = 0;

    for (const [k, v] of Object.entries(draft)) {
      const installmentId = Number(k);
      if (!installmentId) continue;

      const amt = v?.amount ? parseMoneyInput(v.amount) : 0;
      if (amt > 0) {
        count += 1;
        sum += amt;
      }
    }

    return { count, sum };
  }, [draft]);

  // 👇 ahora solo guardamos el texto tal cual (sin convertir a number acá)
  const setAmount = React.useCallback((installmentId: number, value: string) => {
    const trimmed = value.trim();

    if (trimmed === "") {
      setDraft((prev) => {
        const next = { ...prev };
        delete next[installmentId];
        return next;
      });
      return;
    }

    setDraft((prev) => ({
      ...prev,
      [installmentId]: { amount: trimmed },
    }));
  }, []);

  const clearAll = React.useCallback(() => {
    setDraft({});
  }, []);

  const sortedRows = React.useMemo(() => sortRows(rows, sort), [rows, sort]);

  const toggleSort = React.useCallback((key: SortKey) => {
    setSort((prev) => {
      if (!prev || prev.key !== key) return { key, dir: "asc" };
      return { key, dir: prev.dir === "asc" ? "desc" : "asc" };
    });
  }, []);

  const sortIcon = React.useCallback(
    (key: SortKey) => {
      if (!sort || sort.key !== key) return "";
      return sort.dir === "asc" ? " ▲" : " ▼";
    },
    [sort]
  );

  return (
    <Box sx={{ p: 2 }}>
      <Typography variant="h5" sx={{ mb: 1 }}>
        Carga masiva de pagos
      </Typography>

      <Paper variant="outlined" sx={{ p: 2, mb: 2 }}>
        <Stack
          direction={{ xs: "column", md: "row" }}
          spacing={2}
          alignItems="center"
        >
          <TextField
            label="Buscar cliente / teléfono"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            size="small"
            sx={{ width: { xs: "100%", md: 360 } }}
          />

          <Button
            variant="contained"
            onClick={() => {
              setOffset(0);
              load();
            }}
            disabled={loading}
          >
            {loading ? "Cargando..." : "Buscar"}
          </Button>

          <Button variant="outlined" onClick={clearAll} disabled={loading}>
            Limpiar pagos
          </Button>

          <Box sx={{ flex: 1 }} />

          <Typography variant="body2">
            Filas: {rows.length} / Total: {total}
          </Typography>
        </Stack>

        <Divider sx={{ my: 2 }} />

        <Stack direction={{ xs: "column", md: "row" }} spacing={2}>
          <Metric label="Pagos cargados" value={String(totals.count)} />
          <Metric label="Total ingresado" value={fmtMoney(totals.sum)} />
          <Metric
            label="Regla"
            value="Se permite sobrepago por cuota; se bloquea si supera saldo total de la deuda."
          />
        </Stack>
      </Paper>

      {/* 👇 Wrapper con scroll horizontal y la tabla con ancho fijo (evita “columna vacía”) */}
      
        <Box sx={tableSx}>
          {/* Header */}
          <Box sx={{ ...rowSx, ...headerSx }}>
            <HCell onClick={() => toggleSort("collector_name")}>
              Cobrador{sortIcon("collector_name")}
            </HCell>
            <HCell onClick={() => toggleSort("customer_name")}>
              Cliente{sortIcon("customer_name")}
            </HCell>
            <HCell onClick={() => toggleSort("debt_label")}>
              Deuda{sortIcon("debt_label")}
            </HCell>
            <HCell align="right" onClick={() => toggleSort("installment_number")}>
              Cuota{sortIcon("installment_number")}
            </HCell>
            <HCell onClick={() => toggleSort("due_date")}>
              Vence{sortIcon("due_date")}
            </HCell>
            <HCell align="right" onClick={() => toggleSort("installment_amount")}>
              Monto{sortIcon("installment_amount")}
            </HCell>
            <HCell align="right" onClick={() => toggleSort("installment_balance")}>
              Saldo Cuota{sortIcon("installment_balance")}
            </HCell>
            <HCell align="right">Pago</HCell>
            <HCell align="right" onClick={() => toggleSort("debt_balance")}>
              Saldo Deuda{sortIcon("debt_balance")}
            </HCell>
            <HCell align="right" onClick={() => toggleSort("debt_balance")}>
              Saldo Post{sortIcon("debt_balance")}
            </HCell>
          </Box>

          {/* Body */}
          <VirtualTable rows={sortedRows} draft={draft} setAmount={setAmount} setDraft={setDraft} />
        </Box>

      {/* Paginación mínima (MVP) */}
      <Stack direction="row" spacing={2} sx={{ mt: 2 }} alignItems="center">
        <Button
          variant="outlined"
          disabled={loading || offset === 0}
          onClick={() => setOffset((prev) => Math.max(0, prev - limit))}
        >
          Anterior
        </Button>
        <Button
          variant="outlined"
          disabled={loading || offset + limit >= total}
          onClick={() => setOffset((prev) => prev + limit)}
        >
          Siguiente
        </Button>
        <Typography variant="body2">
          Offset: {offset} — Limit: {limit}
        </Typography>
      </Stack>
    </Box>
  );
}

function VirtualTable({
  rows,
  draft,
  setAmount,
  setDraft,
}: {
  rows: CollectableRow[];
  draft: Record<number, DraftPayment>;
  setAmount: (installmentId: number, value: string) => void;
  setDraft: React.Dispatch<React.SetStateAction<Record<number, DraftPayment>>>;
}) {
  const parentRef = React.useRef<HTMLDivElement | null>(null);

  const rowVirtualizer = useVirtualizer({
    count: rows.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 40,
    overscan: 12,
  });

  const virtualItems = rowVirtualizer.getVirtualItems();

  return (
    <Box
      ref={parentRef}
      sx={{
        height: 520,
        overflow: "auto",
        position: "relative",
      }}
    >
      <Box sx={{ height: rowVirtualizer.getTotalSize(), position: "relative" }}>
        {virtualItems.map((vi) => {
          const r = rows[vi.index];
          if (!r) return null;

          const installmentId = r.installment_id;
          const draftAmt = draft[installmentId]?.amount ?? "";

          const montoCuota = n(r.installment_amount);
          const saldoCuota = n(r.installment_balance);

          const saldoDeuda = debtBalance(r);
          const pago = draftAmt ? parseMoneyInput(draftAmt) : 0;

          const exceedsDebt = pago > 0 && pago - saldoDeuda > 1e-9;
          const saldoDeudaPost = Math.max(0, saldoDeuda - pago);

          return (
            <Box
              key={installmentId}
              sx={{
                ...rowSx,
                position: "absolute",
                top: 0,
                left: 0,
                width: "100%",
                transform: `translateY(${vi.start}px)`,
                borderBottom: "1px solid rgba(255,255,255,0.10)",
              }}
            >
              <CellText title={r.collector_name ?? "Sin asignar"}>
                {r.collector_name ?? "Sin asignar"}
              </CellText>

              <CellText title={r.customer_name ?? ""}>
                {r.customer_name ?? ""}
              </CellText>

              <CellText title={debtLabel(r)}>{debtLabel(r)}</CellText>

              <CellText align="right">{r.installment_number ?? "-"}</CellText>

              <CellText>{r.due_date ?? "-"}</CellText>

              <CellText align="right">{fmtMoney(montoCuota)}</CellText>

              <CellText align="right">{fmtMoney(saldoCuota)}</CellText>

              <Box
                sx={{
                  px: 0.5,
                  borderRight: "1px solid rgba(255,255,255,0.10)",
                  display: "flex",
                  justifyContent: "flex-end",
                  alignItems: "center",
                  height: "100%",
                }}
              >
                <TextField
                  value={draftAmt}
                  onChange={(e) => setAmount(installmentId, e.target.value)}
                  onBlur={() => {
                    if (!draftAmt) return;
                    const num = parseMoneyInput(draftAmt);
                    const formatted = formatMoneyInput(num);
                    setDraft((prev) => ({
                      ...prev,
                      [installmentId]: { amount: formatted },
                    }));
                  }}
                  placeholder="0"
                  size="small"
                  variant="outlined"
                  error={exceedsDebt}
                  sx={{
                    width: 130,
                    "& .MuiInputBase-root": { height: 34 },
                    "& input": {
                      textAlign: "right",
                      py: 0.5,
                      fontSize: 15,
                      fontWeight: 600,
                    },
                  }}
                  inputProps={{ inputMode: "decimal" }}
                />
              </Box>

              <CellText align="right">{fmtMoney(saldoDeuda)}</CellText>

              <CellText align="right">{fmtMoney(saldoDeudaPost)}</CellText>
            </Box>
          );
        })}
      </Box>
    </Box>
  );
}

/** ---------- Styles / Cells ---------- */

// 👇 ancho fijo = suma de columnas, así no queda “columna vacía” a la derecha

const tableSx = {
  border: "1px solid rgba(255,255,255,0.12)",
  borderRadius: 1,
  overflow: "hidden",
  backgroundColor: "rgba(255,255,255,0.02)",
  width: "100%", // 👈 vuelve a ocupar todo el contenedor
};

const rowSx = {
  height: 40,
  display: "grid",
  alignItems: "center",
  gridTemplateColumns:
    "170px 220px 140px 80px 110px 110px 120px 140px 130px 130px",
  columnGap: 0,
  px: 1,
  width: "100%", // 👈 importante
};


const headerSx = {
  position: "sticky" as const,
  top: 0,
  zIndex: 2,
  height: 40,
  fontWeight: 700,
  backgroundColor: "rgba(0,0,0,0.35)",
  borderBottom: "1px solid rgba(255,255,255,0.12)",
};

function HCell({
  children,
  align,
  onClick,
}: {
  children: React.ReactNode;
  align?: "left" | "right";
  onClick?: () => void;
}) {
  return (
    <Box
      onClick={onClick}
      sx={{
        px: 0.5,
        overflow: "hidden",
        whiteSpace: "nowrap",
        textOverflow: "ellipsis",
        textAlign: align ?? "left",
        fontSize: 13,
        cursor: onClick ? "pointer" : "default",
        userSelect: "none",
        borderRight: "1px solid rgba(255,255,255,0.10)",
        height: "100%",
        display: "flex",
        alignItems: "center",
        ...(align === "right" ? { justifyContent: "flex-end" } : {}),
        "&:hover": onClick ? { backgroundColor: "rgba(255,255,255,0.04)" } : {},
      }}
    >
      {children}
    </Box>
  );
}

function CellText({
  children,
  title,
  align,
}: {
  children: React.ReactNode;
  title?: string;
  align?: "left" | "right";
}) {
  return (
    <Box
      title={title}
      sx={{
        px: 0.5,
        overflow: "hidden",
        whiteSpace: "nowrap",
        textOverflow: "ellipsis",
        textAlign: align ?? "left",
        fontSize: 14,
        borderRight: "1px solid rgba(255,255,255,0.10)",
        height: "100%",
        display: "flex",
        alignItems: "center",
        letterSpacing: 0.2,
        ...(align === "right" ? { justifyContent: "flex-end" } : {}),
      }}
    >
      {children}
    </Box>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <Box>
      <Typography variant="caption" color="text.secondary">
        {label}
      </Typography>
      <Typography variant="body2">{value}</Typography>
    </Box>
  );
}
