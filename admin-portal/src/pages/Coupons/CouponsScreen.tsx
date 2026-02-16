// src/pages/Coupons/CouponsScreen.tsx
import * as React from "react";
import {
  Box,
  Paper,
  Typography,
  TextField,
  Button,
  Stack,
  Divider,
  Checkbox,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Snackbar,
  Alert,
} from "@mui/material";
import { httpClient } from "../../app/httpClient";
import { httpPdf, openBlobInNewTab } from "../../app/httpClientPdf";

type LoanRow = {
  id: number;
  customer_name: string;
  customer_province?: string | null;
  collector_id?: number | null;
  collector_name?: string | null;

  // Montos préstamo
  total_due?: number | null;
  remaining?: number | null;

  // ✅ Info de la cuota que se va a imprimir (primera impaga)
  installment_id?: number | null;
  installment_number?: number | null;
  installments_count?: number | null;
  due_date?: string | null; // ISO yyyy-mm-dd (ya la devolvés así)
  installment_amount?: number | null; // ✅ total de cuota (NUEVO EN TABLA)
  installment_paid_amount?: number | null; // pagado en esa cuota
  installment_balance?: number | null; // saldo de cuota (lo que se imprime)
};

type CollectorOption = { id: number; name: string };

type ToastState = {
  open: boolean;
  msg: string;
  severity: "success" | "error" | "info";
};

function extractErrorMessage(e: any): string {
  if (typeof e?.message === "string" && e.message.trim()) return e.message;

  const detail = e?.detail ?? e?.response?.detail ?? e?.data?.detail;
  if (typeof detail === "string") return detail;

  if (detail && typeof detail === "object") {
    if (typeof detail?.message === "string") return detail.message;
    if (typeof detail?.code === "string")
      return `${detail.code}${detail.reason ? `: ${detail.reason}` : ""}`;
  }

  const status = e?.status ?? e?.response?.status;
  if (status === 401)
    return "No autorizado. Iniciá sesión nuevamente (token vencido) y reintentá.";
  if (status === 403) return "Sin permisos para esta acción.";
  if (status) return `Error HTTP ${status}.`;

  return "Ocurrió un error inesperado.";
}

function normalizeLoanRow(x: any): LoanRow {
  const idRaw = x?.id ?? x?.loan_id ?? x?.loanId;

  const collectorName =
    x?.collector_name ??
    x?.collectorName ??
    x?.employee_name ??
    x?.employeeName ??
    x?.collector?.name ??
    null;

  const collectorId =
    x?.collector_id ??
    x?.collectorId ??
    x?.employee_id ??
    x?.employeeId ??
    x?.collector?.id ??
    null;

  return {
    id: Number(idRaw),
    customer_name: String(x?.customer_name ?? x?.customerName ?? "-"),
    customer_province: (x?.customer_province ?? x?.customerProvince ?? null) as any,
    collector_id: collectorId != null ? Number(collectorId) : null,
    collector_name: collectorName != null ? String(collectorName) : null,

    // préstamo
    total_due: x?.total_due ?? x?.amount ?? x?.totalDue ?? null,
    remaining: x?.remaining ?? x?.total_due ?? x?.totalDue ?? null,

    // cuota imprimible (viene de /loans/printables)
    installment_id: x?.installment_id ?? null,
    installment_number: x?.installment_number ?? null,
    installments_count: x?.installments_count ?? null,
    due_date: x?.due_date ?? null,
    installment_amount: x?.installment_amount ?? null, // ✅
    installment_paid_amount: x?.installment_paid_amount ?? null,
    installment_balance: x?.installment_balance ?? null,
  };
}

function formatMoney(n: number | null | undefined): string {
  if (n == null || !Number.isFinite(Number(n))) return "-";
  return Number(n).toLocaleString("es-AR", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function formatDateISO(iso: string | null | undefined): string {
  if (!iso) return "-";
  // Esperamos yyyy-mm-dd
  const s = String(iso).trim();
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return s;
  const [, y, mo, d] = m;
  return `${d}/${mo}/${y}`;
}

export default function CouponsScreen() {
  const [loading, setLoading] = React.useState(false);
  const [baseRows, setBaseRows] = React.useState<LoanRow[]>([]);
  const [rows, setRows] = React.useState<LoanRow[]>([]);

  // filtros
  const [collectorId, setCollectorId] = React.useState<string>("");
  const [province, setProvince] = React.useState<string>("");
  const [q, setQ] = React.useState("");

  // opciones cobrador
  const [collectors, setCollectors] = React.useState<CollectorOption[]>([]);

  // selección
  const [selected, setSelected] = React.useState<Record<number, boolean>>({});

  // ui
  const [toast, setToast] = React.useState<ToastState>({
    open: false,
    msg: "",
    severity: "info",
  });

  const showToast = React.useCallback(
    (msg: string, severity: ToastState["severity"]) => {
      setToast({ open: true, msg, severity });
    },
    []
  );

  const closeToast = React.useCallback(() => {
    setToast((p) => ({ ...p, open: false }));
  }, []);

  const loadCollectors = React.useCallback(async () => {
    try {
      const resp = await httpClient(`/employees?role=collector`, { method: "GET" });
      const json = resp.json as any;
      const data = Array.isArray(json?.data) ? json.data : Array.isArray(json) ? json : [];

      setCollectors(
        data
          .filter((x: any) => x?.id && x?.name)
          .map((e: any) => ({ id: Number(e.id), name: String(e.name) }))
      );
    } catch {
      setCollectors([]);
    }
  }, []);

  const loadLoans = React.useCallback(async () => {
    setLoading(true);
    try {
      const paramsBase = new URLSearchParams();
      if (q.trim()) paramsBase.set("q", q.trim());
      if (collectorId) paramsBase.set("collector_id", collectorId);
      paramsBase.set("tz", "America/Argentina/Tucuman");

      // 1) Base: sin province (para opciones del dropdown)
      const respBase = await httpClient(`/loans/printables?${paramsBase.toString()}`, { method: "GET" });
      const jsonBase = respBase.json as any;
      const rawBase = Array.isArray(jsonBase?.data) ? jsonBase.data : Array.isArray(jsonBase) ? jsonBase : [];
      const dataBase: LoanRow[] = rawBase
        .map(normalizeLoanRow)
        .filter((r: { id: unknown; customer_name: any }) => Number.isFinite(r.id) && r.customer_name);

      setBaseRows(dataBase);

      // Si no hay province, tabla = base
      if (!province.trim()) {
        setRows(dataBase);

        setSelected((prev) => {
          const allowed = new Set(dataBase.map((r) => r.id));
          const next: Record<number, boolean> = {};
          for (const [k, v] of Object.entries(prev)) {
            const id = Number(k);
            if (allowed.has(id) && v) next[id] = true;
          }
          return next;
        });

        return;
      }

      // 2) Tabla: con province (¡también en /loans/printables!)
      const params = new URLSearchParams(paramsBase);
      params.set("province", province.trim());

      const resp = await httpClient(`/loans/printables?${params.toString()}`, { method: "GET" });
      const json = resp.json as any;
      const raw = Array.isArray(json?.data) ? json.data : Array.isArray(json) ? json : [];
      const data: LoanRow[] = raw
        .map(normalizeLoanRow)
        .filter((r: { id: unknown; customer_name: any }) => Number.isFinite(r.id) && r.customer_name);

      setRows(data);

      setSelected((prev) => {
        const allowed = new Set(data.map((r) => r.id));
        const next: Record<number, boolean> = {};
        for (const [k, v] of Object.entries(prev)) {
          const id = Number(k);
          if (allowed.has(id) && v) next[id] = true;
        }
        return next;
      });
    } catch (e: any) {
      showToast(extractErrorMessage(e) || "Error cargando préstamos", "error");
    } finally {
      setLoading(false);
    }
  }, [q, province, collectorId, showToast]);

  const provinceOptions = React.useMemo(() => {
    const set = new Set<string>();
    for (const r of baseRows) {
      const p = (r.customer_province || "").trim();
      if (p) set.add(p);
    }
    return Array.from(set).sort((a, b) => a.localeCompare(b, "es"));
  }, [baseRows]);

  const provinceMenuOptions = React.useMemo(() => {
    const current = (province || "").trim();
    if (!current) return provinceOptions;
    return provinceOptions.includes(current) ? provinceOptions : [current, ...provinceOptions];
  }, [province, provinceOptions]);

  React.useEffect(() => {
    loadCollectors();
    loadLoans();
  }, [loadCollectors, loadLoans]);

  const selectedIds = React.useMemo(() => {
    return rows.filter((r) => selected[r.id]).map((r) => r.id);
  }, [rows, selected]);

  const allSelected = React.useMemo(() => {
    return rows.length > 0 && rows.every((r) => !!selected[r.id]);
  }, [rows, selected]);

  const toggleAll = React.useCallback(() => {
    if (allSelected) {
      setSelected({});
      return;
    }
    const next: Record<number, boolean> = {};
    for (const r of rows) next[r.id] = true;
    setSelected(next);
  }, [rows, allSelected]);

  const toggleOne = React.useCallback((loanId: number, checked: boolean) => {
    setSelected((prev) => ({ ...prev, [loanId]: checked }));
  }, []);

  const printOne = React.useCallback(
    async (loanId: number) => {
      try {
        const blob = await httpPdf(`/loans/${loanId}/coupon.pdf?tz=America/Argentina/Tucuman`, {
          method: "GET",
        });
        openBlobInNewTab(blob);
      } catch (e: any) {
        showToast(extractErrorMessage(e) || "Error generando cupón", "error");
      }
    },
    [showToast]
  );

  const printBatch = React.useCallback(async () => {
    if (selectedIds.length === 0) return;

    try {
      const blob = await httpPdf(`/loans/coupons.pdf`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          loan_ids: selectedIds,
          tz: "America/Argentina/Tucuman",
        }),
      });

      openBlobInNewTab(blob);
      showToast(`PDF generado (${selectedIds.length} préstamos)`, "success");
    } catch (e: any) {
      showToast(extractErrorMessage(e) || "Error generando cupones", "error");
    }
  }, [selectedIds, showToast]);

  return (
    <Box sx={{ p: 2 }}>
      <Typography variant="h5" sx={{ mb: 1 }}>
        Impresión de cupones
      </Typography>

      <Paper variant="outlined" sx={{ p: 2, mb: 2 }}>
        <Stack direction={{ xs: "column", md: "row" }} spacing={2} alignItems="center">
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

          <FormControl size="small" sx={{ width: { xs: "100%", md: 240 } }}>
            <InputLabel>Provincia</InputLabel>
            <Select
              label="Provincia"
              value={province}
              onChange={(e) => setProvince(String(e.target.value))}
            >
              <MenuItem value="">Todas</MenuItem>
              {provinceMenuOptions.map((p) => (
                <MenuItem key={p} value={p}>
                  {p}
                </MenuItem>
              ))}
            </Select>
          </FormControl>

          <TextField
            label="Buscar (cliente / teléfono / DNI)"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            size="small"
            sx={{ width: { xs: "100%", md: 320 } }}
          />

          <Button variant="contained" onClick={loadLoans} disabled={loading}>
            {loading ? "Cargando..." : "Buscar"}
          </Button>

          <Box sx={{ flex: 1 }} />

          <Button
            variant="contained"
            color="success"
            onClick={printBatch}
            disabled={loading || selectedIds.length === 0}
          >
            Imprimir seleccionados ({selectedIds.length})
          </Button>
        </Stack>

        <Divider sx={{ my: 2 }} />

        <Stack direction="row" spacing={2} alignItems="center">
          <Button variant="outlined" onClick={toggleAll} disabled={rows.length === 0}>
            {allSelected ? "Deseleccionar todo" : "Seleccionar todo"}
          </Button>
          <Typography variant="body2" color="text.secondary">
            Resultados: {rows.length}
          </Typography>
        </Stack>
      </Paper>

      <Paper variant="outlined" sx={{ p: 1 }}>
        {rows.length === 0 ? (
          <Typography variant="body2" sx={{ p: 2 }} color="text.secondary">
            No hay préstamos para mostrar.
          </Typography>
        ) : (
          <Box
            sx={{
              display: "grid",
              // ✅ Agregamos Monto cuota (col nueva)
              gridTemplateColumns: "44px 80px 1fr 140px 200px 110px 110px 130px 130px 130px 170px",
              gap: 0,
              alignItems: "center",
            }}
          >
            {/* header */}
            <Box sx={{ p: 1, fontWeight: 700 }} />
            <Box sx={{ p: 1, fontWeight: 700 }}>ID</Box>
            <Box sx={{ p: 1, fontWeight: 700 }}>Cliente</Box>
            <Box sx={{ p: 1, fontWeight: 700 }}>Provincia</Box>
            <Box sx={{ p: 1, fontWeight: 700 }}>Cobrador</Box>
            <Box sx={{ p: 1, fontWeight: 700, textAlign: "center" }}>Cuota</Box>
            <Box sx={{ p: 1, fontWeight: 700, textAlign: "center" }}>Vence</Box>
            <Box sx={{ p: 1, fontWeight: 700, textAlign: "right" }}>Monto cuota</Box>
            <Box sx={{ p: 1, fontWeight: 700, textAlign: "right" }}>Saldo cuota</Box>
            <Box sx={{ p: 1, fontWeight: 700, textAlign: "right" }}>Saldo Crédito</Box>
            <Box sx={{ p: 1, fontWeight: 700 }} />

            {/* rows */}
            {rows.map((r) => (
              <React.Fragment key={r.id}>
                <Box
                  sx={{
                    p: 1,
                    borderTop: "1px solid rgba(255,255,255,0.08)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                  }}
                >
                  <Checkbox
                    checked={!!selected[r.id]}
                    onChange={(e) => toggleOne(r.id, e.target.checked)}
                  />
                </Box>

                <Box
                  sx={{
                    p: 1,
                    borderTop: "1px solid rgba(255,255,255,0.08)",
                    display: "flex",
                    alignItems: "center",
                  }}
                >
                  <Typography variant="body2" sx={{ fontWeight: 700 }}>
                    #{r.id}
                  </Typography>
                </Box>

                <Box
                  sx={{
                    p: 1,
                    borderTop: "1px solid rgba(255,255,255,0.08)",
                    display: "flex",
                    alignItems: "center",
                  }}
                >
                  <Typography variant="body1" sx={{ fontWeight: 600 }}>
                    {r.customer_name}
                  </Typography>
                </Box>

                <Box
                  sx={{
                    p: 1,
                    borderTop: "1px solid rgba(255,255,255,0.08)",
                    display: "flex",
                    alignItems: "center",
                  }}
                >
                  <Typography variant="body2" color="text.secondary">
                    {r.customer_province || "-"}
                  </Typography>
                </Box>

                <Box
                  sx={{
                    p: 1,
                    borderTop: "1px solid rgba(255,255,255,0.08)",
                    display: "flex",
                    alignItems: "center",
                  }}
                >
                  <Typography variant="body2">
                    {(r.collector_name || "").trim() || "Sin asignar"}
                  </Typography>
                </Box>

                <Box
                  sx={{
                    p: 1,
                    borderTop: "1px solid rgba(255,255,255,0.08)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                  }}
                >
                  <Typography variant="body2" sx={{ fontWeight: 700 }}>
                    {r.installment_number != null && r.installments_count != null
                      ? `${r.installment_number}/${r.installments_count}`
                      : "-"}
                  </Typography>
                </Box>

                <Box
                  sx={{
                    p: 1,
                    borderTop: "1px solid rgba(255,255,255,0.08)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                  }}
                >
                  <Typography variant="body2" color="text.secondary">
                    {formatDateISO(r.due_date)}
                  </Typography>
                </Box>

                {/* ✅ NUEVO: Monto cuota */}
                <Box
                  sx={{
                    p: 1,
                    borderTop: "1px solid rgba(255,255,255,0.08)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "flex-end",
                  }}
                >
                  <Typography variant="body2">
                    {formatMoney(r.installment_amount)}
                  </Typography>
                </Box>

                {/* Saldo cuota */}
                <Box
                  sx={{
                    p: 1,
                    borderTop: "1px solid rgba(255,255,255,0.08)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "flex-end",
                  }}
                >
                  <Typography variant="body2" sx={{ fontWeight: 700 }}>
                    {formatMoney(r.installment_balance)}
                  </Typography>
                </Box>

                {/* Saldo crédito */}
                <Box
                  sx={{
                    p: 1,
                    borderTop: "1px solid rgba(255,255,255,0.08)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "flex-end",
                  }}
                >
                  <Typography variant="body2">
                    {formatMoney(r.remaining)}
                  </Typography>
                </Box>

                <Box
                  sx={{
                    p: 1,
                    borderTop: "1px solid rgba(255,255,255,0.08)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "flex-start",
                  }}
                >
                  <Button
                    variant="outlined"
                    size="small"
                    onClick={() => printOne(r.id)}
                    disabled={loading}
                  >
                    Imprimir cupón
                  </Button>
                </Box>
              </React.Fragment>
            ))}
          </Box>
        )}
      </Paper>

      <Snackbar open={toast.open} autoHideDuration={4500} onClose={closeToast}>
        <Alert severity={toast.severity} onClose={closeToast}>
          {toast.msg}
        </Alert>
      </Snackbar>
    </Box>
  );
}
