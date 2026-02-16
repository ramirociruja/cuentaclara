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
  Snackbar,
  Alert,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Switch,
  FormControlLabel,
  Tooltip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  List,
  ListItem,
  ListItemText,
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
  customer_province?: string | null;

  installment_number?: number | null;
  due_date?: string | null;

  installment_amount?: number | null;
  installment_balance?: number | null;

  loan_balance?: number | null;
  purchase_balance?: number | null;
};

// draft guarda el string visible del input (para formato dinero)
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
  | "customer_province"
  | "debt_label"
  | "installment_number"
  | "due_date"
  | "installment_amount"
  | "installment_balance"
  | "debt_balance";

type PreviewErrorType =
  | "EXCEEDS_DEBT"
  | "PURCHASE_NOT_SUPPORTED"
  | "NO_LOAN"
  | "ROW_NOT_FOUND";

type PreviewErrorBucket = {
  label: string;
  count: number;
  examples: Array<{ ref: string; customer: string }>;
};

type BulkPreview = {
  validCount: number;
  validTotal: number;

  errorTotal: number;
  errorBuckets: Record<PreviewErrorType, PreviewErrorBucket>;

  payoffCount: number;

  outlier:
    | null
    | {
        ratio: number;
        loan_id: number;
        customer: string;
        installment_amount: number;
        amount: number;
      };
};

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
      case "customer_province":
        return r.customer_province ?? "";
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

  // filtros
  const [q, setQ] = React.useState<string>("");
  const [collectorId, setCollectorId] = React.useState<string>("");
  const [province, setProvince] = React.useState<string>("");

  const [collectors, setCollectors] = React.useState<
    Array<{ id: number; name: string }>
  >([]);

  const [limit] = React.useState<number>(500);
  const [offset, setOffset] = React.useState<number>(0);

  // toggles recomendados
  const [showOnlyDraft, setShowOnlyDraft] = React.useState<boolean>(false);
  const [showOnlyErrors, setShowOnlyErrors] = React.useState<boolean>(false);

  const [draft, setDraft] = React.useState<Record<number, DraftPayment>>({});

  const [sort, setSort] = React.useState<SortState>({
    key: "due_date",
    dir: "asc",
  });

  const [submitting, setSubmitting] = React.useState(false);

  // estado por installment_id: ok/error con mensaje opcional
  const [applyStatus, setApplyStatus] = React.useState<
    Record<number, { status: "ok" | "error"; message?: string }>
  >({});

  const [toast, setToast] = React.useState<{
    open: boolean;
    severity: "success" | "error" | "warning" | "info";
    message: string;
  }>({ open: false, severity: "info", message: "" });

  const [confirmOpen, setConfirmOpen] = React.useState(false);
  const [preview, setPreview] = React.useState<BulkPreview | null>(null);

  const showToast = React.useCallback(
    (severity: "success" | "error" | "warning" | "info", message: string) => {
      setToast({ open: true, severity, message });
    },
    []
  );

  const endpoint = "/installments/collectable-per-loan";

  const loadCollectors = React.useCallback(async () => {
    try {
      const resp = await httpClient(`/employees?role=collector`, {
        method: "GET",
      });
      const json = resp.json as any;
      const data = Array.isArray(json?.data)
        ? json.data
        : Array.isArray(json)
        ? json
        : [];
      setCollectors(
        data
          .filter((x: any) => x?.id && x?.name)
          .map((e: any) => ({ id: Number(e.id), name: String(e.name) }))
      );
    } catch {
      setCollectors([]);
    }
  }, []);

  React.useEffect(() => {
    loadCollectors();
  }, [loadCollectors]);

  const load = React.useCallback(async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams();
      if (q.trim()) params.set("q", q.trim());
      if (collectorId) params.set("collector_id", collectorId);
      if (province.trim()) params.set("province", province.trim());
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
  }, [endpoint, q, collectorId, province, limit, offset]);

  React.useEffect(() => {
    load();
  }, [load]);

  // Provincia dropdown: derivarlo del resultado del endpoint (rows)
  // Si tu DB tiene muchos null, igual vas a ver "Todas" solamente (lo cual sería correcto).
  const provinceOptions = React.useMemo(() => {
    const set = new Set<string>();
    for (const r of rows) {
      const p = (r.customer_province || "").trim();
      if (p) set.add(p);
    }
    // fallback: si el usuario ya eligió una provincia que no está en la página actual, mantenela visible
    const pSel = province.trim();
    if (pSel) set.add(pSel);

    return Array.from(set).sort((a, b) => a.localeCompare(b, "es"));
  }, [rows, province]);

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

  const errorCount = React.useMemo(() => {
    return Object.values(applyStatus).filter((x) => x.status === "error").length;
  }, [applyStatus]);

  const setAmount = React.useCallback(
    (installmentId: number, value: string) => {
      const trimmed = value.trim();

      if (trimmed === "") {
        setDraft((prev) => {
          const next = { ...prev };
          delete next[installmentId];
          return next;
        });
        // si el user borra, también limpiamos estado para esa fila
        setApplyStatus((prev) => {
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

      // al editar, limpiamos el status previo (para que no quede “ok/error” viejo)
      setApplyStatus((prev) => {
        if (!prev[installmentId]) return prev;
        const next = { ...prev };
        delete next[installmentId];
        return next;
      });
    },
    []
  );

  const clearAll = React.useCallback(() => {
    setDraft({});
    setApplyStatus({});
    setShowOnlyErrors(false);
    setShowOnlyDraft(false);
  }, []);

  const clearFilters = React.useCallback(() => {
    setQ("");
    setCollectorId("");
    setProvince("");
    setOffset(0);
  }, []);

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

  const displayRows = React.useMemo(() => {
    let base = sortRows(rows, sort);

    if (showOnlyDraft) {
      const ids = new Set<number>();
      for (const [k, v] of Object.entries(draft)) {
        const id = Number(k);
        if (!id) continue;
        const amt = v?.amount ? parseMoneyInput(v.amount) : 0;
        if (amt > 0) ids.add(id);
      }
      base = base.filter((r) => ids.has(r.installment_id));
    }

    if (showOnlyErrors) {
      base = base.filter((r) => applyStatus[r.installment_id]?.status === "error");
    }

    return base;
  }, [rows, sort, showOnlyDraft, showOnlyErrors, draft, applyStatus]);


    const buildPreview = React.useCallback((): BulkPreview => {
    const buckets: Record<PreviewErrorType, PreviewErrorBucket> = {
      EXCEEDS_DEBT: { label: "Pago supera saldo de deuda", count: 0, examples: [] },
      PURCHASE_NOT_SUPPORTED: { label: "Compra no soportada", count: 0, examples: [] },
      NO_LOAN: { label: "Fila no corresponde a un préstamo", count: 0, examples: [] },
      ROW_NOT_FOUND: { label: "Fila no encontrada en la tabla", count: 0, examples: [] },
    };

    const pushExample = (key: PreviewErrorType, ref: string, customer: string) => {
      const b = buckets[key];
      b.count += 1;
      if (b.examples.length < 3) b.examples.push({ ref, customer });
    };

    let validCount = 0;
    let validTotal = 0;
    let payoffCount = 0;

    let bestOutlier: BulkPreview["outlier"] = null;

    const EPS = 0.01;
    const OUTLIER_RATIO = 8;

    for (const [k, v] of Object.entries(draft)) {
      const installmentId = Number(k);
      const amt = v?.amount ? parseMoneyInput(v.amount) : 0;
      if (!installmentId || amt <= 0) continue;

      const r = rows.find((x) => x.installment_id === installmentId);
      const customer = (r?.customer_name || "").trim() || "(Sin nombre)";

      if (!r) {
        pushExample("ROW_NOT_FOUND", `Cuota ${installmentId}`, customer);
        continue;
      }

      if (r.purchase_id) {
        pushExample("PURCHASE_NOT_SUPPORTED", `Compra #${r.purchase_id}`, customer);
        continue;
      }

      if (!r.loan_id) {
        pushExample("NO_LOAN", `Fila ${installmentId}`, customer);
        continue;
      }

      const saldoDeuda = debtBalance(r);
      if (amt - saldoDeuda > EPS) {
        pushExample(
          "EXCEEDS_DEBT",
          `Préstamo #${r.loan_id} — Saldo ${fmtMoney(saldoDeuda)} — Pago ${fmtMoney(amt)}`,
          customer
        );
        continue;
      }

      // válido
      validCount += 1;
      validTotal += amt;

      // cancelación (sin ejemplo, solo conteo)
      if (amt >= saldoDeuda - EPS) payoffCount += 1;

      // outlier: pago >= cuota * 8
      const cuota = n(r.installment_amount);
      if (cuota > 0) {
        const ratio = amt / cuota;
        if (ratio >= OUTLIER_RATIO) {
          if (!bestOutlier || ratio > bestOutlier.ratio) {
            bestOutlier = {
              ratio,
              loan_id: r.loan_id,
              customer,
              installment_amount: cuota,
              amount: amt,
            };
          }
        }
      }
    }

    const errorTotal = Object.values(buckets).reduce((acc, b) => acc + b.count, 0);

    return {
      validCount,
      validTotal,
      errorTotal,
      errorBuckets: buckets,
      payoffCount,
      outlier: bestOutlier,
    };
    }, [draft, rows]);


  const applyBulkPayments = React.useCallback(async () => {
    // construir items desde draft
    const items: Array<{
      loan_id: number;
      amount: number;
      collector_id?: number | null;
      _installment_id: number; // solo para mapear UI
    }> = [];

    const nextStatus: Record<number, { status: "ok" | "error"; message?: string }> =
      {};

    for (const [k, v] of Object.entries(draft)) {
      const installmentId = Number(k);
      const amt = v?.amount ? parseMoneyInput(v.amount) : 0;

      if (!installmentId || amt <= 0) continue;

      const r = rows.find((x) => x.installment_id === installmentId);
      if (!r) {
        nextStatus[installmentId] = {
          status: "error",
          message: "Fila no encontrada en la tabla.",
        };
        continue;
      }

      if (!r.loan_id) {
        nextStatus[installmentId] = {
          status: "error",
          message: "Esta fila no corresponde a un préstamo.",
        };
        continue;
      }
      if (r.purchase_id) {
        nextStatus[installmentId] = {
          status: "error",
          message: "Compras aún no soportadas en este proceso.",
        };
        continue;
      }

      const saldoDeuda = debtBalance(r);
      if (amt - saldoDeuda > 0.01) {
        nextStatus[installmentId] = {
          status: "error",
          message: "El pago supera el saldo total de la deuda.",
        };
        continue;
      }

      items.push({
        loan_id: r.loan_id,
        amount: amt,
        collector_id: r.collector_id ?? null,
        _installment_id: installmentId,
      });
    }

    const invalidCountPreview = Object.keys(nextStatus).length;
    if (invalidCountPreview > 0) {
      showToast(
        "warning",
        `Hay ${invalidCountPreview} fila(s) con errores y no se enviarán.`
      );
    }

    if (items.length === 0) {
      setApplyStatus(nextStatus);

      const invalidCount = Object.keys(nextStatus).length;

      if (invalidCount > 0) {
        showToast(
          "error",
          `No se registró ningún pago: hay ${invalidCount} fila(s) con errores. Revisá los campos marcados en rojo.`
        );
        setShowOnlyErrors(true);
      } else {
        showToast("warning", "No hay pagos cargados para registrar.");
      }
      return;
    }

    setSubmitting(true);
    try {
      // agrupar por loan_id (sumando importes)
      const byLoan = new Map<
        number,
        { loan_id: number; amount: number; collector_id?: number | null }
      >();

      for (const it of items) {
        const prev = byLoan.get(it.loan_id);
        if (!prev)
          byLoan.set(it.loan_id, {
            loan_id: it.loan_id,
            amount: it.amount,
            collector_id: it.collector_id,
          });
        else
          byLoan.set(it.loan_id, {
            ...prev,
            amount: prev.amount + it.amount,
          });
      }

      const payload = {
        all_or_nothing: false,
        items: Array.from(byLoan.values()),
      };

      const resp = await httpClient(`/payments/bulk-apply`, {
        method: "POST",
        body: JSON.stringify(payload),
      });

      const json = resp.json as {
        ok: number;
        failed: number;
        results: Array<{
          index: number;
          loan_id: number;
          payment_id?: number | null;
          applied: boolean;
          error?: string | null;
        }>;
      };

      const resultByLoan = new Map<number, { applied: boolean; error?: string | null }>();
      for (const r of json?.results ?? []) {
        resultByLoan.set(r.loan_id, { applied: !!r.applied, error: r.error ?? null });
      }

      const finalStatus: Record<number, { status: "ok" | "error"; message?: string }> =
        { ...nextStatus };

      // marcar cada fila del draft según resultado del préstamo
      for (const it of items) {
        const res = resultByLoan.get(it.loan_id);
        if (!res) {
          finalStatus[it._installment_id] = {
            status: "error",
            message: "Sin respuesta del servidor.",
          };
          continue;
        }
        if (res.applied) {
          finalStatus[it._installment_id] = { status: "ok" };
        } else {
          finalStatus[it._installment_id] = {
            status: "error",
            message: res.error ?? "Error aplicando pago.",
          };
        }
      }

      setApplyStatus(finalStatus);

      const okCount = Object.values(finalStatus).filter((s) => s.status === "ok").length;
      const errCount = Object.values(finalStatus).filter((s) => s.status === "error").length;

      if (okCount > 0) {
        showToast("success", `Pagos registrados: ${okCount}. Errores: ${errCount}.`);

        await load();

        // limpiar solo los ok
        setDraft((prev) => {
          const next = { ...prev };
          for (const [k, st] of Object.entries(finalStatus)) {
            if (st.status === "ok") delete next[Number(k)];
          }
          return next;
        });

        // si hubo errores, mostrarlos para corregir rápido
        if (errCount > 0) setShowOnlyErrors(true);
      } else {
        showToast("error", `No se pudo registrar ningún pago. Errores: ${errCount}.`);
        setShowOnlyErrors(true);
      }
    } finally {
      setSubmitting(false);
    }
  }, [draft, rows, load, showToast, setShowOnlyErrors]);

  const canClearPayments = totals.count > 0 && !(loading || submitting);

  const registerDisabledReason =
    totals.count === 0
      ? "No hay pagos cargados."
      : loading
      ? "La tabla está cargando."
      : submitting
      ? "Se están registrando pagos."
      : "";

  return (
    <Box sx={{ p: 2 }}>
      <Typography variant="h5" sx={{ mb: 1 }}>
        Carga masiva de pagos
      </Typography>

      <Paper variant="outlined" sx={{ p: 2, mb: 2 }}>
        {/* FILTROS + BUSQUEDA */}
        <Stack
          direction={{ xs: "column", md: "row" }}
          spacing={2}
          alignItems="center"
          sx={{ mb: 2 }}
        >
          <TextField
            label="Buscar (cliente / teléfono)"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            size="small"
            sx={{ width: { xs: "100%", md: 360 } }}
          />

          <FormControl size="small" sx={{ width: { xs: "100%", md: 260 } }}>
            <InputLabel>Cobrador</InputLabel>
            <Select
              label="Cobrador"
              value={collectorId}
              onChange={(e) => setCollectorId(String(e.target.value))}
            >
              <MenuItem value="">Todos</MenuItem>
              {collectors.map((c) => (
                <MenuItem key={c.id} value={String(c.id)}>
                  {c.name}
                </MenuItem>
              ))}
            </Select>
          </FormControl>

          <FormControl size="small" sx={{ width: { xs: "100%", md: 220 } }}>
            <InputLabel>Provincia</InputLabel>
            <Select
              label="Provincia"
              value={province}
              onChange={(e) => setProvince(String(e.target.value))}
            >
              <MenuItem value="">Todas</MenuItem>
              {provinceOptions.map((p) => (
                <MenuItem key={p} value={p}>
                  {p}
                </MenuItem>
              ))}
            </Select>
          </FormControl>

          <Button
            variant="contained"
            onClick={() => {
              setOffset(0);
              load();
            }}
            disabled={loading || submitting}
          >
            {loading ? "Cargando..." : "Buscar"}
          </Button>

          <Button
            variant="text"
            onClick={() => {
              clearFilters();
              // Disparar load con filtros limpios inmediatamente
              // (evita esperar a que el usuario toque Buscar)
              setTimeout(() => load(), 0);
            }}
            disabled={loading || submitting}
          >
            Limpiar filtros
          </Button>

          <Box sx={{ flex: 1 }} />

          <Typography variant="body2">
            Filas: {rows.length} / Total: {total}
          </Typography>
        </Stack>

        {/* REGLA (CLARA) */}
        <Alert severity="info" sx={{ mb: 2 }}>
          Ingresá un monto a cobrar por préstamo (puede ser parcial y no necesita coincidir con el saldo de la cuota).
          El monto no puede superar el saldo total del préstamo. Al registrar, el pago se aplica al préstamo y se recalculan saldos.
          Compras aún no están soportadas en este proceso.
        </Alert>

        {/* RESUMEN + ACCIONES + TOGGLES */}
        <Stack
          direction={{ xs: "column", md: "row" }}
          spacing={2}
          alignItems="center"
        >
          <Metric label="Pagos cargados" value={String(totals.count)} />
          <Metric label="Total ingresado" value={fmtMoney(totals.sum)} />
          <Metric label="Errores" value={String(errorCount)} />

          <FormControlLabel
            control={
              <Switch
                checked={showOnlyDraft}
                onChange={(e) => setShowOnlyDraft(e.target.checked)}
                disabled={loading || submitting}
              />
            }
            label="Solo con pagos cargados"
          />

          <FormControlLabel
            control={
              <Switch
                checked={showOnlyErrors}
                onChange={(e) => setShowOnlyErrors(e.target.checked)}
                disabled={loading || submitting || errorCount === 0}
              />
            }
            label="Ver solo errores"
          />

          <Box sx={{ flex: 1 }} />

          <Button
            variant="outlined"
            color="error"
            onClick={() => {
              if (!canClearPayments) return;
              const ok = window.confirm(
                "¿Seguro que querés limpiar todos los pagos cargados? Esta acción no se puede deshacer."
              );
              if (!ok) return;
              clearAll();
              showToast("info", "Pagos cargados limpiados.");
            }}
            disabled={!canClearPayments}
          >
            Limpiar pagos
          </Button>

          <Tooltip title={registerDisabledReason || ""} disableHoverListener={!registerDisabledReason}>
            <span>
              <Button
                variant="contained"
                color="success"
                onClick={() => {
                  const p = buildPreview();
                  setPreview(p);

                  if (p.validCount === 0) {
                    if (p.errorTotal > 0) {
                      showToast("error", `No hay pagos válidos para registrar. Errores: ${p.errorTotal}.`);
                      setShowOnlyErrors(true);
                    } else {
                      showToast("warning", "No hay pagos cargados para registrar.");
                    }
                    return;
                  }

                  setConfirmOpen(true);
                }}
                disabled={loading || submitting || totals.count === 0}
              >
                {submitting ? "Registrando..." : `Registrar pagos (${totals.count})`}
              </Button>
            </span>
          </Tooltip>
        </Stack>

        <Divider sx={{ mt: 2 }} />
      </Paper>

      <Box sx={tableSx}>
        {/* Header */}
        <Box sx={{ ...rowSx, ...headerSx }}>
          <HCell onClick={() => toggleSort("collector_name")}>
            Cobrador{sortIcon("collector_name")}
          </HCell>
          <HCell onClick={() => toggleSort("customer_name")}>
            Cliente{sortIcon("customer_name")}
          </HCell>
          <HCell onClick={() => toggleSort("customer_province")}>
            Provincia{sortIcon("customer_province")}
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
        <VirtualTable
          rows={displayRows}
          draft={draft}
          setAmount={setAmount}
          setDraft={setDraft}
          applyStatus={applyStatus}
        />
      </Box>

      {/* Paginación mínima (MVP) */}
      <Stack direction="row" spacing={2} sx={{ mt: 2 }} alignItems="center">
        <Button
          variant="outlined"
          disabled={loading || submitting || offset === 0}
          onClick={() => setOffset((prev) => Math.max(0, prev - limit))}
        >
          Anterior
        </Button>
        <Button
          variant="outlined"
          disabled={loading || submitting || offset + limit >= total}
          onClick={() => setOffset((prev) => prev + limit)}
        >
          Siguiente
        </Button>
        <Typography variant="body2">
          Offset: {offset} — Limit: {limit} — Mostrando: {displayRows.length}
        </Typography>
      </Stack>
      <Dialog
        open={confirmOpen}
        onClose={() => setConfirmOpen(false)}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle>Confirmar registro de pagos</DialogTitle>

        <DialogContent dividers>
          {preview && (
            <>
              <Stack spacing={1.1} sx={{ mb: 2 }}>
                <Typography variant="body1">
                  <b>Pagos a registrar:</b> {preview.validCount}
                </Typography>
                <Typography variant="body1">
                  <b>Total a registrar:</b> {fmtMoney(preview.validTotal)}
                </Typography>
              </Stack>

              {preview.errorTotal > 0 && (
                <Box sx={{ mb: 2 }}>
                  <Typography variant="subtitle1" sx={{ mb: 0.5 }}>
                    No se registrarán <b>{preview.errorTotal}</b> fila(s) por errores:
                  </Typography>

                  <List dense sx={{ pt: 0 }}>
                    {(Object.entries(preview.errorBuckets) as Array<
                      [PreviewErrorType, PreviewErrorBucket]
                    >)
                      .filter(([, b]) => b.count > 0)
                      .map(([key, b]) => {
                        const examples = b.examples
                          .map((e) => `${e.ref} — ${e.customer}`)
                          .join("; ");
                        const extra =
                          b.count > b.examples.length
                            ? `; y ${b.count - b.examples.length} más`
                            : "";
                        return (
                          <ListItem key={key} disableGutters>
                            <ListItemText
                              primary={`${b.label} (${b.count})`}
                              secondary={`${examples}${extra}`}
                            />
                          </ListItem>
                        );
                      })}
                  </List>
                </Box>
              )}

              {preview.payoffCount > 0 && (
                <Alert severity="warning" sx={{ mb: 2 }}>
                  Cancelaciones detectadas: <b>{preview.payoffCount}</b>
                </Alert>
              )}

              {preview.outlier && (
                <Alert severity="warning">
                  Posible monto fuera de lo normal: <b>Préstamo #{preview.outlier.loan_id}</b> —{" "}
                  {preview.outlier.customer} — Cuota{" "}
                  <b>{fmtMoney(preview.outlier.installment_amount)}</b> — Pago{" "}
                  <b>{fmtMoney(preview.outlier.amount)}</b> (
                  <b>{preview.outlier.ratio.toFixed(1)}x</b>)
                </Alert>
              )}
            </>
          )}
        </DialogContent>

        <DialogActions>
          <Button onClick={() => setConfirmOpen(false)} disabled={submitting}>
            Cancelar
          </Button>
          <Button
            variant="contained"
            color="success"
            onClick={async () => {
              setConfirmOpen(false);
              await applyBulkPayments();
            }}
            disabled={submitting}
          >
            Confirmar y registrar
          </Button>
        </DialogActions>
      </Dialog>

      <Snackbar
        open={toast.open}
        autoHideDuration={5000}
        onClose={() => setToast((p) => ({ ...p, open: false }))}
        anchorOrigin={{ vertical: "bottom", horizontal: "center" }}
      >
        <Alert
          severity={toast.severity}
          onClose={() => setToast((p) => ({ ...p, open: false }))}
          variant="filled"
          sx={{ width: "100%" }}
        >
          {toast.message}
        </Alert>
      </Snackbar>
    </Box>
  );
}

function VirtualTable({
  rows,
  draft,
  setAmount,
  setDraft,
  applyStatus,
}: {
  rows: CollectableRow[];
  draft: Record<number, DraftPayment>;
  setAmount: (installmentId: number, value: string) => void;
  setDraft: React.Dispatch<React.SetStateAction<Record<number, DraftPayment>>>;
  applyStatus: Record<number, { status: "ok" | "error"; message?: string }>;
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

          const exceedsDebt = pago > 0 && pago - saldoDeuda > 0.01;
          const saldoDeudaPost = Math.max(0, saldoDeuda - pago);

          const st = applyStatus[installmentId];

          const hasDraft = pago > 0;

          const rowBg =
            st?.status === "ok"
              ? "rgba(46, 125, 50, 0.18)"
              : st?.status === "error"
              ? "rgba(211, 47, 47, 0.14)"
              : hasDraft
              ? "rgba(2, 136, 209, 0.08)"
              : "transparent";

          const rowOutline =
            st?.status === "error"
              ? "1px solid rgba(211, 47, 47, 0.35)"
              : hasDraft
              ? "1px solid rgba(2, 136, 209, 0.22)"
              : "1px solid transparent";

          const customerTitleParts = [
            r.customer_name ?? "",
            r.customer_phone ? `Tel: ${r.customer_phone}` : "",
            r.customer_province ? `Prov: ${r.customer_province}` : "",
          ].filter(Boolean);

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
                backgroundColor: rowBg,
                outline: rowOutline,
                outlineOffset: "-1px",
              }}
            >
              <CellText title={r.collector_name ?? "Sin asignar"}>
                {r.collector_name ?? "Sin asignar"}
              </CellText>

              <CellText title={customerTitleParts.join(" — ")}>
                {r.customer_name ?? ""}
              </CellText>

              <CellText title={r.customer_province ?? ""}>
                {r.customer_province ?? "-"}
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
                  title={
                    st?.status === "error"
                      ? st.message
                      : exceedsDebt
                      ? "El pago supera el saldo total de la deuda."
                      : undefined
                  }
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
                  error={exceedsDebt || st?.status === "error"}
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

const tableSx = {
  border: "1px solid rgba(255,255,255,0.12)",
  borderRadius: 1,
  overflow: "hidden",
  backgroundColor: "rgba(255,255,255,0.02)",
  width: "100%",
};

const rowSx = {
  height: 40,
  display: "grid",
  alignItems: "center",
  // Se agrega columna Provincia
  gridTemplateColumns:
    "170px 220px 140px 140px 80px 110px 110px 120px 140px 130px 130px",
  columnGap: 0,
  px: 1,
  width: "100%",
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
