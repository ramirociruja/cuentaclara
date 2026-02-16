import * as React from "react";
import {
  Box,
  Paper,
  Typography,
  Stack,
  MenuItem,
  TextField,
  Divider,
  Table,
  TableHead,
  TableRow,
  TableCell,
  TableBody,
  Chip,
  LinearProgress,
} from "@mui/material";
import { httpClient } from "../../app/httpClient";
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
} from "recharts";
import { useTheme, alpha } from "@mui/material/styles";



type DashboardResponse = {
  start_date: string; // YYYY-MM-DD
  end_date: string; // YYYY-MM-DD
  tz: string;

  kpis: {
    expected_amount: number;
    collected_amount: number; // pagos en período
    collected_for_due_amount: number; // aplicado a cuotas del período
    pending_amount: number;
    effectiveness_pct: number; // efectividad = aplicado/esperado
    payments_count: number;

    overdue_customers_count: number;
    overdue_installments_count: number;
    overdue_amount: number;
  };

  cashflow_30d_by_collector: Array<{
    collector_id: number;
    collector_name?: string | null;
    points: Array<{
      date: string; // YYYY-MM-DD
      collected_amount: number;
      issued_amount: number;
    }>;
  }>;


  by_day: Array<{
    date: string; // YYYY-MM-DD
    expected_amount: number;
    collected_amount: number;
  }>;

  // IMPORTANTE: en UI vamos a usar la efectividad "real" del período (aplicado/esperado).
  // Esta lista hoy viene armada con pagos totales por cobrador (NO aplicado). Por eso:
  // - mostramos "Cobrado (pagos)" por cobrador
  // - y la "Efectividad" del cobrador la calculamos contra esperado, con pagos (aprox)
  // Si querés que sea 100% correcto por cobrador, hay que exponer "collected_for_due_amount por cobrador" en backend.
  collectors: Array<{
  collector_id: number;
  collector_name?: string | null;

  expected_amount: number;      // cuotas del período
  registered_amount: number;    // pagos registrados en período (Payment.amount)
  applied_amount: number;       // pagos aplicados a cuotas del período (PaymentAllocation)
  payments_count: number;       // cantidad de pagos registrados

  effectiveness_pct: number;    // applied / expected
}>;
  cashflow_30d: Array<{
    date: string; // YYYY-MM-DD
    collected_amount: number; // pagos registrados (payment_date)
    issued_amount: number;    // préstamos otorgados (start_date)
  }>;


  issued_by_collector: Array<{
    collector_id: number;
    collector_name?: string | null;

    loans_count: number;
    loans_principal_amount: number;
    loans_total_due: number;

    purchases_count: number;
    purchases_principal_amount: number;
    purchases_total_due: number;
  }>;

  loans_status: Array<{
    status: string;
    count: number;
    total_due: number;
  }>;

  purchases_status: Array<{
    status: string;
    count: number;
    total_due: number;
  }>;

  loan_status_changes: Array<{
    status: string;
    count: number;
    total_due: number;
  }>;

  loan_status_changes_by_collector: Array<{
    collector_id: number;
    collector_name?: string | null;
    canceled_count: number;
    refinanced_count: number;
  }>;

  overdue: Array<{
    installment_id: number;
    loan_id?: number | null;
    purchase_id?: number | null;
    due_date: string;
    amount: number;
    paid_amount: number;
    status: string;
    days_overdue: number;
    customer_id?: number | null;
    customer_name?: string | null;
    customer_phone?: string | null;
    assigned_collector_id?: number | null;
    assigned_collector_name?: string | null;
  }>;
};

const TZ = "America/Argentina/Tucuman";

function money(n: number) {
  try {
    return new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS" }).format(n || 0);
  } catch {
    return `$${(n || 0).toFixed(2)}`;
  }
}

function ymd(d: Date): string {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

function startOfWeek(d: Date) {
  const x = new Date(d);
  const day = (x.getDay() + 6) % 7; // lunes=0
  x.setDate(x.getDate() - day);
  x.setHours(0, 0, 0, 0);
  return x;
}

function endOfWeek(d: Date) {
  const s = startOfWeek(d);
  const e = new Date(s);
  e.setDate(e.getDate() + 6);
  e.setHours(0, 0, 0, 0);
  return e;
}

function startOfMonth(d: Date) {
  const x = new Date(d.getFullYear(), d.getMonth(), 1);
  x.setHours(0, 0, 0, 0);
  return x;
}

function endOfMonth(d: Date) {
  const x = new Date(d.getFullYear(), d.getMonth() + 1, 0);
  x.setHours(0, 0, 0, 0);
  return x;
}

function clampPct01(x: number) {
  if (!Number.isFinite(x)) return 0;
  return Math.max(0, Math.min(1, x));
}

function MetricCard({
  title,
  value,
  subtitle,
  right,
  accent,
  children,
}: {
  title: string;
  value: React.ReactNode;
  subtitle?: React.ReactNode;
  right?: React.ReactNode;
  accent?: "primary" | "success" | "warning" | "error" | "info";
  children?: React.ReactNode;
}) {
  const barColor =
    accent === "success"
      ? "success.main"
      : accent === "warning"
      ? "warning.main"
      : accent === "error"
      ? "error.main"
      : accent === "info"
      ? "info.main"
      : "primary.main";

  return (
    <Paper sx={{ p: 2, position: "relative", overflow: "hidden" }}>
      <Box
        sx={{
          position: "absolute",
          left: 0,
          top: 0,
          bottom: 0,
          width: 4,
          bgcolor: barColor,
          opacity: 0.9,
        }}
      />
      <Stack spacing={0.5} sx={{ pl: 1 }}>
        <Stack direction="row" justifyContent="space-between" alignItems="baseline">
          <Typography variant="caption" sx={{ opacity: 0.75 }}>
            {title}
          </Typography>
          {right}
        </Stack>
        <Typography variant="h6" sx={{ lineHeight: 1.2 }}>
          {value}
        </Typography>
        {subtitle && (
          <Typography variant="body2" sx={{ opacity: 0.75 }}>
            {subtitle}
          </Typography>
        )}
        {children}
      </Stack>
    </Paper>
  );
}

export default function DashboardScreen() {
  const [preset, setPreset] = React.useState<"week" | "prev_week" | "month" | "prev_month" | "custom">("week");
  const [startDate, setStartDate] = React.useState<string>(ymd(startOfWeek(new Date())));
  const [endDate, setEndDate] = React.useState<string>(ymd(endOfWeek(new Date())));
  const [loading, setLoading] = React.useState(false);
  const [data, setData] = React.useState<DashboardResponse | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [cashflowMode, setCashflowMode] = React.useState<"both" | "collected" | "issued">("both");
  const [cashflowCollector, setCashflowCollector] = React.useState<number>(-1); // -1 = Todos
  const theme = useTheme();


  React.useEffect(() => {
    const now = new Date();
    if (preset === "week") {
      setStartDate(ymd(startOfWeek(now)));
      setEndDate(ymd(endOfWeek(now)));
    } else if (preset === "prev_week") {
      const s = startOfWeek(now);
      s.setDate(s.getDate() - 7);
      const e = endOfWeek(new Date(s));
      setStartDate(ymd(s));
      setEndDate(ymd(e));
    } else if (preset === "month") {
      setStartDate(ymd(startOfMonth(now)));
      setEndDate(ymd(endOfMonth(now)));
    } else if (preset === "prev_month") {
      const prev = new Date(now.getFullYear(), now.getMonth() - 1, 15);
      setStartDate(ymd(startOfMonth(prev)));
      setEndDate(ymd(endOfMonth(prev)));
    }
  }, [preset]);

  const load = React.useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const qs = new URLSearchParams({
        start_date: startDate,
        end_date: endDate,
        tz: TZ,
      });

      const resp = await httpClient(`/dashboard/summary?${qs.toString()}`, { method: "GET" });
      setData(resp.json as DashboardResponse);
    } catch (e: any) {
      setError(e?.message || "Error cargando dashboard");
      setData(null);
    } finally {
      setLoading(false);
    }
  }, [startDate, endDate]);

  React.useEffect(() => {
    void load();
  }, [load]);

  const k = data?.kpis;

  // Cobranza "correcta" para el período (aplicada a cuotas del período)
  const expected = k?.expected_amount || 0;
  const applied = k?.collected_for_due_amount || 0;
  const eff01 = expected > 0 ? applied / expected : 0;
  const effPct = (clampPct01(eff01) * 100).toFixed(1);

  const pending = k?.pending_amount || 0;
  const overdueAmount = k?.overdue_amount || 0;

  // Métricas de otorgamiento agregadas (para que “resalte” sin tabla de entrada)
  const issuedAgg = (data?.issued_by_collector || []).reduce(
    (acc, r) => {
      acc.loans_count += r.loans_count || 0;
      acc.purchases_count += r.purchases_count || 0;
      acc.principal += (r.loans_principal_amount || 0) + (r.purchases_principal_amount || 0);
      acc.total_due += (r.loans_total_due || 0) + (r.purchases_total_due || 0);
      return acc;
    },
    { loans_count: 0, purchases_count: 0, principal: 0, total_due: 0 }
  );

const issuedTotalOps = (issuedAgg.loans_count || 0) + (issuedAgg.purchases_count || 0);
const issuedAvgTicket = issuedTotalOps > 0 ? (issuedAgg.total_due || 0) / issuedTotalOps : 0;


  return (
    <Box p={2}>
      <Stack spacing={2}>
        {/* Header + filtros */}
        <Paper sx={{ p: 2 }}>
          <Stack
            direction={{ xs: "column", md: "row" }}
            spacing={2}
            alignItems={{ md: "center" }}
            justifyContent="space-between"
          >
            <Box>
              <Typography variant="h6">Dashboard</Typography>
              <Typography variant="body2" sx={{ opacity: 0.75 }}>
                Enfoque semanal: cobranzas por cuotas del período + actividad (altas y cambios de estado).
              </Typography>
            </Box>

            <Stack direction={{ xs: "column", sm: "row" }} spacing={1} alignItems="center">
              <TextField
                select
                size="small"
                label="Período"
                value={preset}
                onChange={(e) => setPreset(e.target.value as any)}
                sx={{ minWidth: 220 }}
              >
                <MenuItem value="week">Semana actual</MenuItem>
                <MenuItem value="prev_week">Semana anterior</MenuItem>
                <MenuItem value="month">Mes actual</MenuItem>
                <MenuItem value="prev_month">Mes anterior</MenuItem>
                <MenuItem value="custom">Personalizado</MenuItem>
              </TextField>

              <TextField
                size="small"
                type="date"
                label="Desde"
                value={startDate}
                onChange={(e) => {
                  setPreset("custom");
                  setStartDate(e.target.value);
                }}
                InputLabelProps={{ shrink: true }}
              />

              <TextField
                size="small"
                type="date"
                label="Hasta"
                value={endDate}
                onChange={(e) => {
                  setPreset("custom");
                  setEndDate(e.target.value);
                }}
                InputLabelProps={{ shrink: true }}
              />
            </Stack>
          </Stack>

          {loading && <LinearProgress sx={{ mt: 2 }} />}
        </Paper>

        {error && (
          <Paper sx={{ p: 2 }}>
            <Typography color="error">{error}</Typography>
          </Paper>
        )}

        {/* =========================================
            BLOQUE 1: COBRANZA (lo que tiene que resaltar)
           ========================================= */}
        <Paper sx={{ p: 2 }}>
          <Stack direction={{ xs: "column", md: "row" }} spacing={1} justifyContent="space-between" alignItems="baseline">
            <Typography variant="subtitle1">Cobranza del período</Typography>
            <Typography variant="caption" sx={{ opacity: 0.7 }}>
              Esperado por due_date · Efectividad = aplicado/esperado (correcto)
            </Typography>
          </Stack>

          <Divider sx={{ my: 2 }} />

          <Box
            sx={{
              display: "grid",
              gap: 2,
              gridTemplateColumns: { xs: "1fr", md: "repeat(4, 1fr)" },
            }}
          >
            <MetricCard
              title="Esperado (cuotas del período)"
              value={money(expected)}
              subtitle="Suma de cuotas que vencen en el rango"
              accent="info"
            />
            <MetricCard
              title="Aplicado a cuotas del período"
              value={money(applied)}
              subtitle={`Efectividad ${effPct}%`}
              accent={eff01 >= 0.85 ? "success" : eff01 >= 0.6 ? "warning" : "error"}
              right={
                <Chip
                  size="small"
                  label={`${effPct}%`}
                  color={eff01 >= 0.85 ? "success" : eff01 >= 0.6 ? "warning" : "error"}
                />
              }
            >
              <Box sx={{ mt: 1 }}>
                <LinearProgress variant="determinate" value={clampPct01(eff01) * 100} />
              </Box>
            </MetricCard>

            <MetricCard
              title="Pendiente del período"
              value={money(pending)}
              subtitle={pending > 0 ? "Foco: recuperar saldo pendiente" : "Al día ✅"}
              accent={pending > 0 ? "warning" : "success"}
            />

            <MetricCard
              title="Pagos registrados (en período)"
              value={money(k?.collected_amount || 0)}
              subtitle={`${k?.payments_count || 0} pagos`}
              accent="primary"
            />
          </Box>

          <Divider sx={{ my: 2 }} />

          {/* Cobranza por cobrador (aclarando que es pagos, no aplicado) */}
          <Stack direction="row" justifyContent="space-between" alignItems="baseline">
            <Typography variant="subtitle2">Cobranza por cobrador</Typography>
            <Typography variant="caption" sx={{ opacity: 0.7 }}>
              Registrado = Todos los pagos dentro del periodo. Aplicado = pagos aplicados a cuotas del período.
            </Typography>
          </Stack>

          <Table size="small" sx={{ mt: 1 }}>
            <TableHead>
              <TableRow>
                <TableCell>Cobrador</TableCell>
                <TableCell align="right">Esperado</TableCell>
                <TableCell align="right">Registrado</TableCell>
                <TableCell align="right">Aplicado</TableCell>
                <TableCell align="right">Efectividad</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {(data?.collectors || []).map((r) => (
                <TableRow key={r.collector_id}>
                  <TableCell>{r.collector_name || `#${r.collector_id}`}</TableCell>

                  <TableCell align="right">{money(r.expected_amount || 0)}</TableCell>

                  <TableCell align="right">
                    <Stack direction="row" spacing={1} justifyContent="flex-end" alignItems="baseline">
                      <Typography variant="body2">{money(r.registered_amount || 0)}</Typography>
                      <Typography variant="caption" sx={{ opacity: 0.75 }}>
                        ({r.payments_count || 0})
                      </Typography>
                    </Stack>
                  </TableCell>

                  <TableCell align="right">{money(r.applied_amount || 0)}</TableCell>

                  <TableCell align="right">{(r.effectiveness_pct || 0).toFixed(1)}%</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Paper>

        {/* =========================================
            BLOQUE 2: ACTIVIDAD (altas + cambios)
           ========================================= */}
        <Box
          sx={{
            display: "grid",
            gap: 2,
            gridTemplateColumns: { xs: "1fr", md: "repeat(2, 1fr)" },
          }}
        >
          {/* Altas */}
          <Paper sx={{ p: 2 }}>
            <Stack direction="row" justifyContent="space-between" alignItems="baseline">
              <Typography variant="subtitle1">Altas en el período</Typography>
              <Typography variant="caption" sx={{ opacity: 0.7 }}>
                Fecha de inicio dentro del rango
              </Typography>
            </Stack>

            <Divider sx={{ my: 2 }} />

            <Box
              sx={{
                display: "grid",
                gap: 2,
                gridTemplateColumns: { xs: "1fr", sm: "repeat(3, 1fr)" },
              }}
            >
              <MetricCard title="Créditos" value={issuedAgg.loans_count} accent="primary" />
              <MetricCard
                title="Ticket promedio"
                value={money(issuedAvgTicket)}
                subtitle={`${issuedTotalOps} altas`}
                accent="info"
              />
              <MetricCard title="Total a cobrar (altas)" value={money(issuedAgg.total_due)} accent="success" />
            </Box>

            <Divider sx={{ my: 2 }} />

            <Typography variant="subtitle2">Detalle por cobrador</Typography>
            <Box sx={{ maxHeight: 320, overflow: "auto", mt: 1 }}> 
            <Table size="small" sx={{ mt: 1 }}>
              <TableHead>
                <TableRow>
                  <TableCell>Cobrador</TableCell>
                  <TableCell align="right">Créditos</TableCell>
                  <TableCell align="right">Ticket prom.</TableCell>
                  <TableCell align="right">Total a cobrar</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {(data?.issued_by_collector || []).map((r) => (
                  <TableRow key={r.collector_id} hover>
                    <TableCell>{r.collector_name || `#${r.collector_id}`}</TableCell>
                    <TableCell align="right">
                      <Stack direction="row" spacing={1} justifyContent="flex-end" alignItems="center">
                        <Typography variant="body2">{r.loans_count || 0}</Typography>
                        <Typography variant="caption" sx={{ opacity: 0.75 }}>
                          ({money(r.loans_total_due || 0)})
                        </Typography>
                      </Stack>
                    </TableCell>
                    <TableCell align="right">
                      {(() => {
                        const ops = (r.loans_count || 0) + (r.purchases_count || 0);
                        const total = (r.loans_total_due || 0) + (r.purchases_total_due || 0);
                        const avg = ops > 0 ? total / ops : 0;

                        return (
                          <Stack direction="row" spacing={1} justifyContent="flex-end" alignItems="baseline">
                            <Typography variant="body2" sx={{ fontWeight: 600 }}>
                              {money(avg)}
                            </Typography>
                            <Typography variant="caption" sx={{ opacity: 0.75 }}>
                              ({ops} altas)
                            </Typography>
                          </Stack>
                        );
                      })()}
                    </TableCell>

                    <TableCell align="right">{money((r.loans_total_due || 0) + (r.purchases_total_due || 0))}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
            </Box>
          </Paper>

          {/* Cambios de estado */}
            <Paper sx={{ p: 2 }}>
  {(() => {
    const seriesByCollector = data?.cashflow_30d_by_collector || [];

    const collectorOptions = [
      { id: -1, name: "Todos" },
      ...seriesByCollector
        .slice()
        .sort((a, b) => (a.collector_name || "").localeCompare(b.collector_name || ""))
        .map((c) => ({
          id: c.collector_id,
          name: c.collector_name || `#${c.collector_id}`,
        })),
    ];

    const selected =
      cashflowCollector === -1
        ? null
        : seriesByCollector.find((x) => x.collector_id === cashflowCollector) || null;

    // Serie base: si “Todos”, sumamos por fecha
    const points =
      selected?.points?.length
        ? selected.points.map((p) => ({
            date: String(p.date).slice(0, 10),
            collected_amount: p.collected_amount || 0,
            issued_amount: p.issued_amount || 0,
          }))
        : (() => {
            const acc = new Map<string, { collected: number; issued: number }>();
            for (const c of seriesByCollector) {
              for (const p of c.points || []) {
                const key = String(p.date).slice(0, 10);
                const prev = acc.get(key) || { collected: 0, issued: 0 };
                prev.collected += p.collected_amount || 0;
                prev.issued += p.issued_amount || 0;
                acc.set(key, prev);
              }
            }
            const keys = Array.from(acc.keys()).sort();
            return keys.map((k) => ({
              date: k,
              collected_amount: acc.get(k)?.collected || 0,
              issued_amount: acc.get(k)?.issued || 0,
            }));
          })();

    const showCollected = cashflowMode === "both" || cashflowMode === "collected";
    const showIssued = cashflowMode === "both" || cashflowMode === "issued";

    // Datos para Recharts (xAxis corto)
    const chartData = points.map((r) => ({
      day: r.date.slice(5, 10), // MM-DD (compacto)
      collected: r.collected_amount,
      issued: r.issued_amount,
    }));

    const totalCollected = points.reduce((a, r) => a + (r.collected_amount || 0), 0);
    const totalIssued = points.reduce((a, r) => a + (r.issued_amount || 0), 0);

    return (
      <>
        <Stack
          direction={{ xs: "column", md: "row" }}
          justifyContent="space-between"
          alignItems={{ md: "center" }}
          spacing={1}
        >
          <Box>
            <Typography variant="subtitle1">Movimientos últimos 30 días</Typography>
            <Typography variant="caption" sx={{ opacity: 0.7 }}>
              Cobros (registrados) vs Plata prestada
            </Typography>
          </Box>

          <Stack direction={{ xs: "column", sm: "row" }} spacing={1}>
            <TextField
              select
              size="small"
              label="Cobrador"
              value={cashflowCollector}
              onChange={(e) => setCashflowCollector(Number(e.target.value))}
              sx={{ minWidth: 220 }}
            >
              {collectorOptions.map((c) => (
                <MenuItem key={c.id} value={c.id}>
                  {c.name}
                </MenuItem>
              ))}
            </TextField>

            <TextField
              select
              size="small"
              label="Mostrar"
              value={cashflowMode}
              onChange={(e) => setCashflowMode(e.target.value as any)}
              sx={{ minWidth: 180 }}
            >
              <MenuItem value="both">Cobrado + Prestado</MenuItem>
              <MenuItem value="collected">Solo Cobrado</MenuItem>
              <MenuItem value="issued">Solo Prestado</MenuItem>
            </TextField>
          </Stack>
        </Stack>

        <Divider sx={{ my: 2 }} />

        <Box
          sx={{
            display: "grid",
            gap: 2,
            gridTemplateColumns: { xs: "1fr", sm: "repeat(2, 1fr)" },
            mb: 1,
          }}
        >
          <MetricCard title="Total cobrado (30 días)" value={money(totalCollected)} subtitle="Pagos registrados" accent="primary" />
          <MetricCard title="Total prestado (30 días)" value={money(totalIssued)} subtitle="Dinero total prestado" accent="info" />
        </Box>

        <Box
  sx={{
    height: 300,
    borderRadius: 2,
    bgcolor: alpha(theme.palette.background.paper, 0.6),
    border: "1px solid",
    borderColor: "divider",
    p: 1.5,
  }}
>
  <ResponsiveContainer width="100%" height={300}>
  <BarChart
    data={chartData}
    margin={{ top: 8, right: 10, left: 0, bottom: 0 }}
    barCategoryGap={10}
  >
    <CartesianGrid
      stroke={alpha(theme.palette.text.primary, 0.18)}
      strokeDasharray="4 4"
    />

    <XAxis
      dataKey="day"
      tickMargin={8}
      interval={2}
      tick={{ fill: alpha(theme.palette.text.primary, 0.7), fontSize: 12 }}
      axisLine={{ stroke: alpha(theme.palette.text.primary, 0.2) }}
      tickLine={{ stroke: alpha(theme.palette.text.primary, 0.2) }}
    />

    <YAxis
      tickFormatter={(v) =>
        new Intl.NumberFormat("es-AR", { notation: "compact" }).format(v)
      }
      tick={{ fill: alpha(theme.palette.text.primary, 0.7), fontSize: 12 }}
      axisLine={{ stroke: alpha(theme.palette.text.primary, 0.2) }}
      tickLine={{ stroke: alpha(theme.palette.text.primary, 0.2) }}
    />

    <Tooltip
      cursor={{ fill: alpha(theme.palette.primary.main, 0.08) }}
      content={({ active, payload, label }) => {
        if (!active || !payload || payload.length === 0) return null;

        const cobrado = (payload.find((p) => p.dataKey === "collected")?.value as number) || 0;
        const prestado = (payload.find((p) => p.dataKey === "issued")?.value as number) || 0;

        const total = cobrado + prestado;

        return (
          <Paper
            elevation={6}
            sx={{
              p: 1.25,
              borderRadius: 2,
              bgcolor: "background.paper",
              border: "1px solid",
              borderColor: "divider",
              minWidth: 220,
            }}
          >
            <Typography variant="subtitle2" sx={{ mb: 0.5 }}>
              Día {label}
            </Typography>

            {showCollected && (
              <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ mb: 0.5 }}>
                <Stack direction="row" spacing={1} alignItems="center">
                  <Box sx={{ width: 10, height: 10, borderRadius: 0.5, bgcolor: theme.palette.success.main }} />
                  <Typography variant="body2">Cobrado</Typography>
                </Stack>
                <Typography variant="body2" sx={{ fontWeight: 700 }}>
                  {money(cobrado)}
                </Typography>
              </Stack>
            )}

            {showIssued && (
              <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ mb: 0.5 }}>
                <Stack direction="row" spacing={1} alignItems="center">
                  <Box sx={{ width: 10, height: 10, borderRadius: 0.5, bgcolor: theme.palette.warning.main }} />
                  <Typography variant="body2">Prestado</Typography>
                </Stack>
                <Typography variant="body2" sx={{ fontWeight: 700 }}>
                  {money(prestado)}
                </Typography>
              </Stack>
            )}

            {(showCollected && showIssued) && (
              <Divider sx={{ my: 0.75 }} />
            )}

            {(showCollected && showIssued) && (
              <Stack direction="row" justifyContent="space-between" alignItems="center">
                <Typography variant="caption" sx={{ opacity: 0.8 }}>
                  Total día
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 800 }}>
                  {money(total)}
                </Typography>
              </Stack>
            )}
          </Paper>
        );
      }}
    />

    <Legend
      verticalAlign="top"
      align="right"
      iconType="circle"
      formatter={(value) => (
        <span style={{ color: alpha(theme.palette.text.primary, 0.85), fontSize: 12 }}>
          {value === "collected" ? "Cobrado" : "Prestado"}
        </span>
      )}
    />

    {/* ✅ BARRAS APILADAS (sin radius + colores más contrastantes) */}
    {showIssued && (
      <Bar
        dataKey="issued"
        name="issued"
        stackId="cashflow"
        fill={theme.palette.warning.main} // Prestado
        barSize={28}
        maxBarSize={36}
      />
    )}

    {showCollected && (
      <Bar
        dataKey="collected"
        name="collected"
        stackId="cashflow"
        fill={theme.palette.success.main} // Cobrado
        barSize={28}
        maxBarSize={36}
      />
    )}
  </BarChart>
</ResponsiveContainer>

</Box>

      </>
    );
  })()}
</Paper>


        </Box>

        {/* =========================================
            BLOQUE 3: MORA (separado, foco “riesgo”)
           ========================================= */}
        <Paper sx={{ p: 2 }}>
          <Stack direction="row" justifyContent="space-between" alignItems="baseline">
            <Typography variant="subtitle1">Mora (al día de hoy)</Typography>
            <Chip
              size="small"
              label={overdueAmount > 0 ? "Atención" : "OK"}
              color={overdueAmount > 0 ? "warning" : "success"}
              variant="outlined"
            />
          </Stack>

          <Divider sx={{ my: 2 }} />

          <Box
            sx={{
              display: "grid",
              gap: 2,
              gridTemplateColumns: { xs: "1fr", sm: "repeat(3, 1fr)" },
            }}
          >
            <MetricCard title="Clientes en mora" value={k?.overdue_customers_count || 0} accent="warning" />
            <MetricCard title="Cuotas vencidas" value={k?.overdue_installments_count || 0} accent="warning" />
            <MetricCard title="Monto vencido (saldo)" value={money(overdueAmount)} accent={overdueAmount > 0 ? "error" : "success"} />
          </Box>

          <Divider sx={{ my: 2 }} />
          <Typography variant="subtitle2" gutterBottom>
            Top vencimientos (más antiguos)
          </Typography>

          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>Cliente</TableCell>
                <TableCell>Vence</TableCell>
                <TableCell align="right">Saldo</TableCell>
                <TableCell>Días</TableCell>
                <TableCell>Cobrador</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {(data?.overdue || []).map((o) => {
                const saldo = Math.max(0, (o.amount || 0) - (o.paid_amount || 0));
                return (
                  <TableRow key={o.installment_id} hover>
                    <TableCell>
                      <Typography variant="body2">{o.customer_name || "-"}</Typography>
                      <Typography variant="caption" sx={{ opacity: 0.7 }}>
                        {o.customer_phone || ""}
                      </Typography>
                    </TableCell>

                    <TableCell>
                      <Typography variant="body2">{String(o.due_date).slice(0, 10)}</Typography>
                    </TableCell>

                    <TableCell align="right">{money(saldo)}</TableCell>

                    <TableCell>
                      <Chip
                        size="small"
                        label={`${o.days_overdue}d`}
                        color={o.days_overdue >= 14 ? "error" : "warning"}
                      />
                    </TableCell>

                    <TableCell>
                      <Typography variant="body2">{o.assigned_collector_name || "-"}</Typography>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </Paper>

        {!loading && !data && (
          <Paper sx={{ p: 2 }}>
            <Typography sx={{ opacity: 0.8 }}>Sin datos para el período seleccionado.</Typography>
          </Paper>
        )}
      </Stack>
    </Box>
  );
}
