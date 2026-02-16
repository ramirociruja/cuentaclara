// src/resources/loans.tsx
import * as React from "react";
import {
  List,
  Datagrid,
  TextField,
  NumberField,
  DateField,
  Create,
  Edit,
  Show,
  SimpleForm,
  TextInput,
  NumberInput,
  DateInput,
  SelectInput,
  ReferenceInput,
  required,
  useNotify,
  useRedirect,
  useRefresh,
  useRecordContext,
  TabbedShowLayout,
  Tab,
  FunctionField,
  useGetOne,
  FormDataConsumer,
} from "react-admin";
import {
  Box,
  Button,
  Divider,
  Typography,
  Stack,
  Paper,
  Card,
  CardContent,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField as MuiTextField,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Alert,
  Chip,
} from "@mui/material";

import { httpPdf, openBlobInNewTab } from "../app/httpClientPdf"; // ajustá el path si tu proyecto lo tiene distinto
import { httpClient } from "../app/httpClient"; // ajustá el path si tu proyecto lo tiene distinto
import { LoanStatusChip, InstallmentStatusChip } from "../shared/status";
import { extractApiErrorMessage } from "../app/httpError";
import { normalizePaymentType } from "../shared/status";
import { EmptyNoResults } from "../components/EmptyNoResults";
import { EntityFiltersBar } from "../shared/EntityFiltersBar";

// ============================
// LIST
// ============================
export function LoanList() {
  return (
    <List title="Préstamos" perPage={25}>
      <EntityFiltersBar
        dateLabel="Fecha de inicio"
        // ✅ backend: date_from/date_to (YYYY-MM-DD)
        fromKey="date_from"
        toKey="date_to"
        defaultPreset="all"
        employeeKey="employee_id"
        qKey="q"
        qLabel="Buscar"
        qPlaceholder="Cliente, provincia, ID…"
        statusKey="status"
        statusLabel="Estado"
        statusChoices={[
          // ✅ Estos ids deben ser los que guarda tu backend en Loan.status
          { id: "active", name: "Activo" },
          { id: "paid", name: "Pagado" },
          { id: "defaulted", name: "Incumplido" },
          { id: "canceled", name: "Cancelado" },
          { id: "refinanced", name: "Refinanciado" },
        ]}
        scopeMt={1}
      />
      <Datagrid rowClick="show"
      empty={<EmptyNoResults />}>
        <NumberField source="id" label="ID" />
        <TextField source="customer_name" label="Cliente" />
        <TextField source="customer_province" label="Provincia" />
        <TextField source="collector_name" label="Cobrador" />
        <NumberField source="amount" label="Monto" />
        <NumberField source="remaining_due" label="Saldo" />
        <FunctionField label="Estado" render={(r: any) => <LoanStatusChip raw={r.status} />} />
        <DateField source="start_date" label="Fecha de inicio" />
      </Datagrid>
    </List>
  );
}

// ============================
// CREATE
// ============================
function formatMoneyARS(value: any) {
  const n = Number(value);
  if (!Number.isFinite(n)) return "-";
  return new Intl.NumberFormat("es-AR", {
    style: "currency",
    currency: "ARS",
    maximumFractionDigits: 2,
  }).format(n);
}

function parseMoneyInput(v: any) {
  if (v === "" || v == null) return undefined;
  if (typeof v === "number") return v;

  const s = String(v).trim();
  if (!s) return undefined;

  const cleaned = s.replace(/[^\d,.-]/g, "");
  const normalized = cleaned.includes(",") ? cleaned.replace(/\./g, "").replace(",", ".") : cleaned;

  const n = Number(normalized);
  return Number.isFinite(n) ? n : undefined;
}

function parseIntSafe(v: any) {
  if (v === "" || v == null) return undefined;
  const n = Number(v);
  if (!Number.isFinite(n)) return undefined;
  return Math.trunc(n);
}

function parseDateInputAsLocalDate(value: any): Date | null {
  if (!value) return null;

  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    const d = new Date(value);
    d.setHours(12, 0, 0, 0);
    return d;
  }

  if (typeof value === "string") {
    // Caso clave: "YYYY-MM-DD" (DateInput)
    const m = value.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (m) {
      const y = Number(m[1]);
      const mo = Number(m[2]) - 1;
      const day = Number(m[3]);
      return new Date(y, mo, day, 12, 0, 0, 0); // mediodía local anti-corrimiento
    }

    const d = new Date(value);
    if (!Number.isNaN(d.getTime())) {
      d.setHours(12, 0, 0, 0);
      return d;
    }
  }

  return null;
}

function formatBusinessDate(value?: any) {
  const d =
    parseDateInputAsLocalDate(value) ??
    (() => {
      const now = new Date();
      now.setHours(12, 0, 0, 0);
      return now;
    })();

  return d.toLocaleDateString("es-AR");
}

/**
 * Para enviar al backend: si viene "YYYY-MM-DD", lo convierte a datetime estable.
 * Usamos mediodía local -> UTC ISO (no se corre de día).
 */
function parseDateAsLocalISO(value: any): string | undefined {
  const d = parseDateInputAsLocalDate(value);
  return d ? d.toISOString() : undefined;
}

function formatLocalDate(value?: Date | null) {
  if (!value) return "-";
  const d = new Date(value);
  d.setHours(12, 0, 0, 0);
  return d.toLocaleDateString("es-AR");
}

function calcPreview(formData: any) {
  const amount = parseMoneyInput(formData?.amount);
  const installments = parseIntSafe(formData?.installments_count);
  const intervalDays = parseIntSafe(formData?.installment_interval_days);

  const start = parseDateInputAsLocalDate(formData?.start_date);

  const ok =
    Number.isFinite(amount) &&
    amount! > 0 &&
    Number.isFinite(installments) &&
    installments! > 0 &&
    Number.isFinite(intervalDays) &&
    intervalDays! > 0 &&
    start != null;

  if (!ok) {
    return {
      valid: false,
      installmentAmount: null as number | null,
      lastDue: null as Date | null,
      total: amount ?? null,
    };
  }

  const installmentAmount = Math.round(((amount as number) / (installments as number)) * 100) / 100;

  const lastDue = new Date(start);
  lastDue.setDate(lastDue.getDate() + (intervalDays as number) * (installments as number));
  lastDue.setHours(12, 0, 0, 0);

  return {
    valid: true,
    installmentAmount,
    lastDue,
    total: amount as number,
  };
}

const WEEKDAY_CHOICES = [
  { id: 1, name: "Lunes" },
  { id: 2, name: "Martes" },
  { id: 3, name: "Miércoles" },
  { id: 4, name: "Jueves" },
  { id: 5, name: "Viernes" },
  { id: 6, name: "Sábado" },
  { id: 7, name: "Domingo" },
];

function LoanCreatePreview() {
  return (
    <FormDataConsumer>
      {({ formData }) => {
        const p = calcPreview(formData);

        const collectionDay = formData?.collection_day;
        const collectionDayLabel =
          WEEKDAY_CHOICES.find((d) => String(d.id) === String(collectionDay))?.name ?? "-";

        return (
          <Card variant="outlined">
            <CardContent>
              <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
                Previsualización
              </Typography>

              <Typography variant="body2" sx={{ color: "text.secondary", mb: 1.5 }}>
                Esto es una estimación para ayudar a cargar el préstamo. El backend calcula el plan definitivo.
              </Typography>

              <Stack direction="row" spacing={1} sx={{ flexWrap: "wrap", gap: 1, mb: 1.5 }}>
                <Chip
                  label={`Cuota estimada: ${
                    p.installmentAmount != null ? formatMoneyARS(p.installmentAmount) : "-"
                  }`}
                  variant="outlined"
                />
                <Chip
                  label={`Total: ${p.total != null ? formatMoneyARS(p.total) : "-"}`}
                  variant="outlined"
                />
                <Chip label={`Día de cobro: ${collectionDayLabel}`} variant="outlined" />
              </Stack>

              <Divider sx={{ my: 1.5 }} />

              <Box
                sx={{
                  display: "grid",
                  gridTemplateColumns: { xs: "1fr", md: "repeat(2, 1fr)" },
                  gap: 1,
                }}
              >
                <Box>
                  <Typography variant="body2" sx={{ color: "text.secondary" }}>
                    Cantidad de cuotas
                  </Typography>
                  <Typography variant="body1" sx={{ fontWeight: 700 }}>
                    {formData?.installments_count ?? "-"}
                  </Typography>
                </Box>

                <Box>
                  <Typography variant="body2" sx={{ color: "text.secondary" }}>
                    Intervalo
                  </Typography>
                  <Typography variant="body1" sx={{ fontWeight: 700 }}>
                    {formData?.installment_interval_days ? `${formData.installment_interval_days} días` : "-"}
                  </Typography>
                </Box>

                <Box>
                  <Typography variant="body2" sx={{ color: "text.secondary" }}>
                    Inicio (por defecto: hoy)
                  </Typography>
                  <Typography variant="body1" sx={{ fontWeight: 700 }}>
                    {formatBusinessDate(formData?.start_date)}
                  </Typography>
                </Box>

                <Box>
                  <Typography variant="body2" sx={{ color: "text.secondary" }}>
                    Terminaría aprox.
                  </Typography>
                  <Typography variant="body1" sx={{ fontWeight: 700 }}>
                    {formatLocalDate(p.lastDue)}
                  </Typography>
                </Box>
              </Box>

              {!p.valid && (
                <Alert severity="info" sx={{ mt: 2 }}>
                  Completá <b>Monto</b>, <b>Cantidad de cuotas</b> e <b>Intervalo</b> para ver la estimación.
                </Alert>
              )}
            </CardContent>
          </Card>
        );
      }}
    </FormDataConsumer>
  );
}

function localISODateString(d = new Date()) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export function LoanCreate() {
  return (
    <Create
      redirect="show"
      transform={(data: any) => {
        const payload: any = {
          customer_id: parseIntSafe(data?.customer_id),
          employee_id: data?.employee_id != null && data?.employee_id !== "" ? parseIntSafe(data.employee_id) : undefined,
          amount: parseMoneyInput(data?.amount),
          installments_count: parseIntSafe(data?.installments_count),
          installment_interval_days: parseIntSafe(data?.installment_interval_days),
          start_date: parseDateAsLocalISO(data?.start_date),
          collection_day: data?.collection_day != null && data?.collection_day !== "" ? parseIntSafe(data.collection_day) : undefined,
          description: data?.description?.trim?.() ? String(data.description).trim() : undefined,
        };

        Object.keys(payload).forEach((k) => payload[k] === undefined && delete payload[k]);
        return payload;
      }}
    >
      <SimpleForm sanitizeEmptyValues defaultValues={{ start_date: localISODateString() }}>
        <Typography variant="h6" sx={{ fontWeight: 800 }}>
          Nuevo Préstamo
        </Typography>
        <Typography variant="body2" sx={{ color: "text.secondary", mb: 1 }}>
          Cargá los datos principales y revisá la previsualización antes de guardar.
        </Typography>
        <Divider sx={{ my: 1.5 }} />

        <Box sx={{ display: "grid", gridTemplateColumns: { xs: "1fr", md: "1.2fr 0.8fr" }, gap: 2 }}>
          <Box sx={{ display: "grid", gap: 2 }}>
            <Card variant="outlined">
              <CardContent>
                <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
                  Datos principales
                </Typography>

                <ReferenceInput source="customer_id" reference="customers" perPage={200}>
                  <SelectInput
                    optionText={(r: any) => `${r.first_name ?? ""} ${r.last_name ?? ""}`.trim()}
                    optionValue="id"
                    validate={[required()]}
                    label="Cliente"
                    fullWidth
                  />
                </ReferenceInput>

                <ReferenceInput source="employee_id" reference="employees" perPage={200}>
                  <SelectInput
                    optionText={(r: any) => r.name ?? r.email ?? String(r.id)}
                    optionValue="id"
                    label="Cobrador"
                    validate={[required()]}
                    fullWidth
                  />
                </ReferenceInput>

                <Divider sx={{ my: 1.5 }} />

                <NumberInput
                  source="amount"
                  label="Monto"
                  validate={[required()]}
                  fullWidth
                  parse={parseMoneyInput}
                  format={(v: any) => (v == null || v === "" ? "" : String(v))}
                  helperText="Ingresá el total del préstamo. La cuota se calcula automáticamente."
                />

                <Box
                  sx={{
                    display: "grid",
                    gridTemplateColumns: { xs: "1fr", md: "repeat(2, 1fr)" },
                    gap: 2,
                    mt: 1,
                  }}
                >
                  <NumberInput source="installments_count" label="Cantidad de cuotas" validate={[required()]} fullWidth parse={parseIntSafe} />
                  <NumberInput
                    source="installment_interval_days"
                    label="Intervalo (días)"
                    validate={[required()]}
                    fullWidth
                    parse={parseIntSafe}
                    helperText="Ej: 7 semanal, 14 quincenal, 30 mensual"
                  />
                </Box>

                <Box
                  sx={{
                    display: "grid",
                    gridTemplateColumns: { xs: "1fr", md: "repeat(2, 1fr)" },
                    gap: 2,
                    mt: 1,
                  }}
                >
                  <DateInput source="start_date" label="Fecha de inicio" fullWidth helperText="Por defecto: hoy" />

                  <SelectInput
                    source="collection_day"
                    label="Día de cobro"
                    choices={WEEKDAY_CHOICES}
                    emptyText="Seleccionar..."
                    fullWidth
                    helperText="Día de la semana para cobrar."
                    validate={[required()]}
                  />
                </Box>

                <Divider sx={{ my: 1.5 }} />

                <TextInput
                  source="description"
                  label="Descripción (opcional)"
                  fullWidth
                  multiline
                  minRows={2}
                  helperText="Ej: motivo, observaciones, condiciones acordadas."
                />
              </CardContent>
            </Card>
          </Box>

          <Box sx={{ display: "grid", gap: 2 }}>
            <LoanCreatePreview />

            <Card variant="outlined">
              <CardContent>
                <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
                  Ayuda rápida
                </Typography>
                <Typography variant="body2" sx={{ color: "text.secondary" }}>
                  - La <b>cuota</b> se calcula como <b>Monto / Cantidad de cuotas</b>.<br />
                  - La fecha de vencimiento se calcula automáticamente según el intervalo.<br />
                  - El <b>día de cobro</b> es informativo para el cobrador (lunes a domingo).
                </Typography>
              </CardContent>
            </Card>
          </Box>
        </Box>
      </SimpleForm>
    </Create>
  );
}

// ============================
// EDIT (tu código actual, lo dejo como está)
// ============================
function buildLoanUpdatePayload(data: any, record: any) {
  const paymentsCount = Number(record?.payments_count ?? 0);
  const totalPaid = Number(record?.total_paid ?? 0);
  const hasPayments = paymentsCount > 0 || totalPaid > 0;

  const payload: any = {
    description: data?.description ?? null,
    collection_day: data?.collection_day != null && data?.collection_day !== "" ? Number(data.collection_day) : null,
    employee_id: data?.employee_id != null && data?.employee_id !== "" ? Number(data.employee_id) : null,
  };

  if (!hasPayments) {
    if (data?.amount != null && data?.amount !== "") payload.amount = Number(data.amount);
    if (data?.installments_count != null && data?.installments_count !== "") payload.installments_count = Number(data.installments_count);
    // NOTA: NO mandamos installment_amount, porque ya no querías editarlo.
    if (data?.installment_interval_days != null && data?.installment_interval_days !== "")
      payload.installment_interval_days = Number(data.installment_interval_days);
    if (data?.start_date) payload.start_date = data.start_date;
  }

  Object.keys(payload).forEach((k) => payload[k] === undefined && delete payload[k]);
  return payload;
}

function LoanEditHeader() {
  const r = useRecordContext<any>();
  if (!r) return null;

  const paymentsCount = Number(r?.payments_count ?? 0);
  const totalPaid = Number(r?.total_paid ?? 0);
  const hasPayments = paymentsCount > 0 || totalPaid > 0;

  return (
    <Box sx={{ mb: 2 }}>
      <Typography variant="h6" sx={{ fontWeight: 700 }}>
        Editar Préstamo #{r?.id ?? "-"}
      </Typography>

      <Typography variant="body2" sx={{ color: "text.secondary", mt: 0.5 }}>
        Cliente: {r?.customer_name ?? `#${r?.customer_id ?? "-"}`} — Cobrador: {r?.collector_name ?? (r?.employee_id ? `#${r.employee_id}` : "-")}
      </Typography>

      <Divider sx={{ my: 1.5 }} />

      {hasPayments ? (
        <Alert severity="info">
          Este préstamo ya tiene pagos registrados. Por seguridad, solo podés editar campos no estructurales (cobrador,
          día de cobro y descripción). Para cambiar monto/cuotas/fechas, cancelalo y creá uno nuevo.
        </Alert>
      ) : (
        <Alert severity="success">Este préstamo todavía no tiene pagos. Podés editar monto, cuotas, intervalo y fecha de inicio.</Alert>
      )}
    </Box>
  );
}

function LoanEditForm() {
  const r = useRecordContext<any>();
  const paymentsCount = Number(r?.payments_count ?? 0);
  const totalPaid = Number(r?.total_paid ?? 0);
  const hasPayments = paymentsCount > 0 || totalPaid > 0;

  return (
    <Box sx={{ display: "grid", gap: 2 }}>
      <LoanEditHeader />

      <Card variant="outlined">
        <CardContent>
          <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
            Datos generales
          </Typography>

          <ReferenceInput source="employee_id" reference="employees" perPage={200}>
            <SelectInput
              label="Cobrador"
              optionText={(e: any) => e?.name ?? e?.email ?? String(e?.id)}
              optionValue="id"
              emptyText="Seleccionar..."
              fullWidth
              validate={[required()]}
            />
          </ReferenceInput>

          <SelectInput source="collection_day" label="Día de cobro" choices={WEEKDAY_CHOICES} emptyText="Seleccionar..." fullWidth validate={[required()]} />

          <TextInput source="description" label="Descripción" fullWidth multiline minRows={2} />
        </CardContent>
      </Card>

      <Card variant="outlined">
        <CardContent>
          <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
            Estructura del préstamo
          </Typography>

          <Typography variant="body2" sx={{ color: "text.secondary", mb: 2 }}>
            Estos campos recalculan el plan de cuotas. Se bloquean automáticamente cuando hay pagos.
          </Typography>

          <Box
            sx={{
              display: "grid",
              gridTemplateColumns: { xs: "1fr", md: "repeat(2, 1fr)" },
              gap: 2,
            }}
          >
            <NumberInput source="amount" label="Monto" disabled={hasPayments} />
            <NumberInput source="installments_count" label="Cantidad de cuotas" disabled={hasPayments} />
            <NumberInput
              source="installment_interval_days"
              label="Intervalo de cuotas (días)"
              helperText="Ej: 7 semanal, 14 quincenal, 30 mensual"
              disabled={hasPayments}
            />
            <DateInput source="start_date" label="Fecha de inicio" disabled={hasPayments} />
          </Box>
        </CardContent>
      </Card>
    </Box>
  );
}

export function LoanEdit() {
  const notify = useNotify();
  const redirect = useRedirect();
  const refresh = useRefresh();

  return (
    <Edit
      mutationMode="pessimistic"
      transform={(data: any) => {
        const record = (data as any)?.__previousData ?? null;
        return buildLoanUpdatePayload(data, record);
      }}
      mutationOptions={{
        onSuccess: () => {
          notify("Préstamo actualizado", { type: "success" });
          refresh();
          redirect("show", "loans");
        },
        onError: (error: any) => {
          notify(extractApiErrorMessage(error) || "Error actualizando préstamo", { type: "error" });
        },
      }}
    >
      <SimpleForm sanitizeEmptyValues>
        <LoanEditForm />
      </SimpleForm>
    </Edit>
  );
}

// ============================
// SHOW
// ============================
const WEEKDAY_ISO: Record<number, string> = {
  1: "Lunes",
  2: "Martes",
  3: "Miércoles",
  4: "Jueves",
  5: "Viernes",
  6: "Sábado",
  7: "Domingo",
};

function weekdayIsoLabel(v: any): string {
  const n = typeof v === "number" ? v : Number(v);
  if (!Number.isFinite(n)) return "-";
  return WEEKDAY_ISO[n] ?? String(n);
}

function InfoRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <Box sx={{ display: "flex", gap: 2, py: 0.5 }}>
      <Typography variant="body2" sx={{ minWidth: 160, color: "text.secondary" }}>
        {label}
      </Typography>
      <Typography variant="body2">{value ?? "-"}</Typography>
    </Box>
  );
}

function Money({ value }: { value: any }) {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return <>-</>;
  return (
    <>
      {n.toLocaleString("es-AR", {
        style: "currency",
        currency: "ARS",
        maximumFractionDigits: 0,
      })}
    </>
  );
}

function isLoanLocked(r: any) {
  const st = String(r?.status ?? "").toLowerCase();

  const canceled = st === "canceled" || st === "cancelled";
  const refinanced = st === "refinanced" || r?.refinanced_to_loan_id != null || r?.refinanced_from_loan_id != null;

  return {
    locked: canceled || refinanced,
    canceled,
    refinanced,
  };
}

function formatDateTimeAR(value: any) {
  if (!value) return "-";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return String(value);
  return d.toLocaleString("es-AR");
}

function LoanLockedBanner() {
  const r = useRecordContext<any>();
  if (!r) return null;

  const { locked, canceled } = isLoanLocked(r);
  if (!locked) return null;

  const title = canceled ? "Crédito cancelado" : "Crédito refinanciado";
  const body = canceled
    ? "Este crédito ya no se cobrará. Las acciones están bloqueadas para evitar errores."
    : "Este crédito fue refinanciado. Las acciones están bloqueadas para evitar errores.";

  return (
    <Alert severity="warning" sx={{ mb: 2 }}>
      <Typography variant="subtitle1" sx={{ fontWeight: 800 }}>
        {title}
      </Typography>
      <Typography variant="body2">{body}</Typography>
    </Alert>
  );
}

function LoanHeaderBlock() {
  const r = useRecordContext<any>();

  const customerId = r?.customer_id;
  const employeeId = r?.employee_id;

  const { data: customer } = useGetOne("customers", { id: customerId }, { enabled: !!customerId });
  const { data: employee } = useGetOne("employees", { id: employeeId }, { enabled: !!employeeId });

  if (!r) return null;

  const customerName =
    r?.customer_name ??
    (customer
      ? `${customer.first_name ?? ""} ${customer.last_name ?? ""}`.trim() || customer.name || `#${customer.id}`
      : "-");

  const collectorName = r?.collector_name ?? (employee ? employee.name ?? employee.email ?? `#${employee.id}` : "-");

  const statusRaw = r?.status;
  const saldo = Number.isFinite(Number(r?.total_due)) ? Number(r.total_due) : 0;

  return (
    <Box sx={{ mb: 2 }}>
      <Typography variant="h5" sx={{ fontWeight: 700, mb: 0.5 }}>
        Préstamo #{r?.id ?? "-"} — {customerName}
      </Typography>

      <Stack direction="row" spacing={2} alignItems="center" sx={{ mb: 2 }}>
        <Typography variant="body2" sx={{ color: "text.secondary" }}>
          Cobrador:
        </Typography>
        <Typography variant="body2" sx={{ fontWeight: 600 }}>
          {collectorName}
        </Typography>

        <Box sx={{ flex: 1 }} />

        <LoanStatusChip raw={statusRaw} />
      </Stack>

      <Box
        sx={{
          display: "grid",
          gridTemplateColumns: { xs: "1fr", md: "repeat(2, 1fr)" },
          gap: 2,
        }}
      >
        <Card variant="outlined">
          <CardContent>
            <Typography variant="overline" sx={{ color: "text.secondary" }}>
              Saldo
            </Typography>
            <Typography variant="h4" sx={{ fontWeight: 800, lineHeight: 1.1 }}>
              <Money value={saldo} />
            </Typography>
            <Typography variant="body2" sx={{ color: "text.secondary", mt: 0.5 }}>
              Total adeudado
            </Typography>
          </CardContent>
        </Card>

        <Card variant="outlined">
          <CardContent>
            <Typography variant="overline" sx={{ color: "text.secondary" }}>
              Monto prestado
            </Typography>
            <Typography variant="h5" sx={{ fontWeight: 700 }}>
              <Money value={r?.amount} />
            </Typography>
            <Typography variant="body2" sx={{ color: "text.secondary", mt: 0.5 }}>
              Capital original
            </Typography>
          </CardContent>
        </Card>
      </Box>
    </Box>
  );
}

// ============================
// Dialogs (Confirmaciones irreversibles)
// ============================
function ConfirmDialog({
  open,
  title,
  severity = "warning",
  message,
  reasonLabel = "Motivo (opcional)",
  confirmText = "Confirmar",
  confirmColor = "error",
  onClose,
  onConfirm,
  loading,
}: {
  open: boolean;
  title: string;
  severity?: "warning" | "error" | "info" | "success";
  message: string;
  reasonLabel?: string;
  confirmText?: string;
  confirmColor?: "error" | "warning" | "info" | "success" | "primary" | "secondary";
  onClose: () => void;
  onConfirm: (reason: string) => void;
  loading?: boolean;
}) {
  const [reason, setReason] = React.useState("");

  React.useEffect(() => {
    if (open) setReason("");
  }, [open]);

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>{title}</DialogTitle>
      <DialogContent>
        <Alert severity={severity} sx={{ mb: 2 }}>
          {message}
        </Alert>

        <MuiTextField
          label={reasonLabel}
          fullWidth
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          multiline
          minRows={2}
        />
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={!!loading}>
          Volver
        </Button>
        <Button
          variant="contained"
          color={confirmColor}
          onClick={() => onConfirm(reason)}
          disabled={!!loading}
        >
          {confirmText}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

// ============================
// ACTIONS
// ============================
function PayLoanDialog({
  open,
  onClose,
  loanId,
  suggestedAmount,
  firstUnpaidNumber,
  firstUnpaidBalance,
  onSuccess,
  locked,
}: {
  open: boolean;
  onClose: () => void;
  loanId: number;
  suggestedAmount: number;
  firstUnpaidNumber?: number | null;
  firstUnpaidBalance?: number | null;
  onSuccess: (paymentId?: number) => void;
  locked?: boolean;
}) {
  const notify = useNotify();

  const [amount, setAmount] = React.useState<string>("");
  const [paymentType, setPaymentType] = React.useState<"cash" | "transfer" | "other">("cash");
  const [description, setDescription] = React.useState<string>("");
  const [submitting, setSubmitting] = React.useState(false);

  React.useEffect(() => {
    if (open) {
      setAmount(String(suggestedAmount || ""));
      setPaymentType("cash");
      setDescription("");
    }
  }, [open, suggestedAmount]);

  const toNumber = (s: string) => {
    const n = Number(String(s).replace(",", "."));
    return Number.isFinite(n) ? n : NaN;
  };

  const handleSubmit = async () => {
    if (locked) {
      notify("Este crédito está cancelado/refinanciado. No se pueden registrar pagos.", { type: "warning" });
      return;
    }

    const n = toNumber(amount);
    if (!Number.isFinite(n) || n <= 0) {
      notify("Ingresá un monto válido mayor a 0", { type: "warning" });
      return;
    }

    setSubmitting(true);
    try {
      const res = await httpClient(`/loans/${loanId}/pay`, {
        method: "POST",
        body: JSON.stringify({
          amount_paid: n,
          payment_type: paymentType,
          description: description?.trim() || null,
        }),
      });

      const paymentId = res?.json?.payment_id;
      notify("Pago registrado correctamente", { type: "success" });
      onSuccess(paymentId);
      onClose();
    } catch (e: any) {
      const msg = extractApiErrorMessage(e);
      notify(msg || "Error registrando pago", { type: "error" });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>Registrar pago</DialogTitle>

      <DialogContent>
        <Typography variant="body2" sx={{ mb: 1 }}>
          Se aplicará automáticamente a las cuotas impagas más antiguas. Si sobra, pasa a las siguientes.
        </Typography>

        {(firstUnpaidNumber != null || firstUnpaidBalance != null) && (
          <Paper variant="outlined" sx={{ p: 1.5, mb: 2 }}>
            {firstUnpaidNumber != null && (
              <Typography variant="body2">
                Primera cuota impaga: <b>#{firstUnpaidNumber}</b>
              </Typography>
            )}
            {firstUnpaidBalance != null && (
              <Typography variant="body2">
                Saldo de esa cuota:{" "}
                <b>
                  {Number(firstUnpaidBalance).toLocaleString("es-AR", {
                    style: "currency",
                    currency: "ARS",
                    maximumFractionDigits: 0,
                  })}
                </b>
              </Typography>
            )}
          </Paper>
        )}

        {locked && (
          <Alert severity="warning" sx={{ mb: 2 }}>
            Este crédito está cancelado/refinanciado. No se pueden registrar pagos.
          </Alert>
        )}

        <MuiTextField
          label="Monto a cobrar"
          fullWidth
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          sx={{ mb: 2 }}
          disabled={submitting || !!locked}
        />

        <FormControl fullWidth sx={{ mb: 2 }} disabled={submitting || !!locked}>
          <InputLabel>Método</InputLabel>
          <Select label="Método" value={paymentType} onChange={(e) => setPaymentType(e.target.value as any)}>
            <MenuItem value="cash">Efectivo</MenuItem>
            <MenuItem value="transfer">Transferencia</MenuItem>
            <MenuItem value="other">Otro</MenuItem>
          </Select>
        </FormControl>

        <MuiTextField
          label="Descripción (opcional)"
          fullWidth
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          multiline
          minRows={2}
          disabled={submitting || !!locked}
        />
      </DialogContent>

      <DialogActions>
        <Button onClick={onClose} disabled={submitting}>
          Cancelar
        </Button>
        <Button variant="contained" onClick={handleSubmit} disabled={submitting || !!locked}>
          Registrar
        </Button>
      </DialogActions>
    </Dialog>
  );
}

function LoanActions() {
  const record = useRecordContext<any>();
  const notify = useNotify();
  const refresh = useRefresh();

  const { locked } = isLoanLocked(record);

  const [openPay, setOpenPay] = React.useState(false);
  const [firstUnpaid, setFirstUnpaid] = React.useState<{ num: number; bal: number } | null>(null);
  const [payLoading, setPayLoading] = React.useState(false);

  const [openCancel, setOpenCancel] = React.useState(false);
  const [openRefinance, setOpenRefinance] = React.useState(false);
  const [actionLoading, setActionLoading] = React.useState(false);

  if (!record) return null;

  const loanId = record.id;

  const n0 = (v: any) => {
    const n = typeof v === "number" ? v : Number(v);
    return Number.isFinite(n) ? n : 0;
  };

  const calcSaldo = (it: any) => {
    const amount = n0(it?.amount);
    const paid = n0(it?.paid_amount);
    const bal = amount - paid;
    return bal > 0 ? bal : 0;
  };

  const onPrintCoupon = async () => {
    if (locked) {
      notify("Acción bloqueada: el crédito está cancelado/refinanciado.", { type: "warning" });
      return;
    }
    try {
      const tz = "America/Argentina/Tucuman";
      const res = await httpPdf(`/loans/${loanId}/coupon.pdf?tz=${encodeURIComponent(tz)}`);
      openBlobInNewTab(res);
    } catch (e: any) {
      notify(e?.message ?? "Error imprimiendo cupón", { type: "error" });
    }
  };

  const openPayDialog = async () => {
    if (locked) {
      notify("Acción bloqueada: el crédito está cancelado/refinanciado.", { type: "warning" });
      return;
    }

    setPayLoading(true);
    try {
      const res = await httpClient(`/loans/${loanId}/installments`, { method: "GET" });
      const rows = Array.isArray(res?.json) ? res.json : [];

      const candidates = rows
        .map((it: any) => {
          const bal = calcSaldo(it);
          const num = n0(it?.number ?? it?.installment_number);
          return { num, bal };
        })
        .filter((x: any) => x.bal > 0 && x.num > 0);

      if (candidates.length === 0) {
        setFirstUnpaid(null);
        notify("No hay cuotas pendientes para cobrar", { type: "info" });
        return;
      }

      candidates.sort((a: any, b: any) => a.num - b.num);
      setFirstUnpaid(candidates[0]);
      setOpenPay(true);
    } catch (e: any) {
      notify(e?.message ?? "Error preparando el cobro", { type: "error" });
    } finally {
      setPayLoading(false);
    }
  };

  const doCancel = async (reason: string) => {
    setActionLoading(true);
    try {
      await httpClient(`/loans/${loanId}/cancel`, {
        method: "POST",
        body: JSON.stringify({ reason: reason?.trim() ? reason.trim() : null }),
      });
      notify("Crédito cancelado correctamente", { type: "success" });
      setOpenCancel(false);
      refresh();
    } catch (e: any) {
      notify(extractApiErrorMessage(e) || "No se pudo cancelar el crédito", { type: "error" });
    } finally {
      setActionLoading(false);
    }
  };

  const doRefinance = async (reason: string) => {
    setActionLoading(true);
    try {
      const res = await httpClient(`/loans/${loanId}/refinance`, {
        method: "POST",
        body: JSON.stringify({ reason: reason?.trim() ? reason.trim() : null }),
      });

      const remainingDue = res?.json?.remaining_due;
      notify(
        remainingDue != null
          ? `Refinanciado. Saldo restante: ${new Intl.NumberFormat("es-AR", {
              style: "currency",
              currency: "ARS",
              maximumFractionDigits: 0,
            }).format(Number(remainingDue) || 0)}. Creá un nuevo préstamo por ese monto.`
          : "Crédito refinanciado correctamente",
        { type: "success" }
      );
      setOpenRefinance(false);
      refresh();
    } catch (e: any) {
      notify(extractApiErrorMessage(e) || "No se pudo refinanciar el crédito", { type: "error" });
    } finally {
      setActionLoading(false);
    }
  };

  return (
    <>
      <Stack direction="row" spacing={2} sx={{ mb: 2, mt: 1 }}>
        <Button variant="outlined" onClick={onPrintCoupon} disabled={locked}>
          Imprimir cupón
        </Button>

        <Button variant="outlined" color="warning" onClick={() => setOpenRefinance(true)} disabled={locked}>
          Refinanciar
        </Button>

        <Button variant="outlined" color="error" onClick={() => setOpenCancel(true)} disabled={locked}>
          Cancelar
        </Button>

        <Button variant="outlined" color="success" onClick={openPayDialog} disabled={payLoading || locked}>
          Registrar Pago
        </Button>
      </Stack>

      <PayLoanDialog
        open={openPay}
        onClose={() => setOpenPay(false)}
        loanId={loanId}
        suggestedAmount={firstUnpaid?.bal ?? 0}
        firstUnpaidNumber={firstUnpaid?.num ?? null}
        firstUnpaidBalance={firstUnpaid?.bal ?? null}
        locked={locked}
        onSuccess={() => refresh()}
      />

      <ConfirmDialog
        open={openCancel}
        title="Cancelar crédito"
        severity="error"
        message="Esta acción es irreversible. El crédito quedará cancelado y ya no se cobrará."
        confirmText="Confirmar cancelación"
        confirmColor="error"
        loading={actionLoading}
        onClose={() => setOpenCancel(false)}
        onConfirm={doCancel}
      />

      <ConfirmDialog
        open={openRefinance}
        title="Refinanciar crédito"
        severity="warning"
        message="Esta acción es irreversible. El crédito quedará refinanciado y ya no se cobrará como estaba."
        confirmText="Confirmar refinanciación"
        confirmColor="warning"
        loading={actionLoading}
        onClose={() => setOpenRefinance(false)}
        onConfirm={doRefinance}
      />
    </>
  );
}

// ============================
// Cuotas TAB
// ============================
function LoanInstallmentsTab() {
  const record = useRecordContext<any>();
  const notify = useNotify();
  const refresh = useRefresh();

  const { locked } = isLoanLocked(record);

  const [rows, setRows] = React.useState<any[]>([]);
  const [loading, setLoading] = React.useState(false);

  const n0 = (v: any) => {
    const n = typeof v === "number" ? v : Number(v);
    return Number.isFinite(n) ? n : 0;
  };

  const calcSaldo = (it: any) => {
    const amount = n0(it?.amount);
    const paid = n0(it?.paid_amount);
    const bal = amount - paid;
    return bal > 0 ? bal : 0;
  };

  const formatMoney = (value: any) => {
    const n = typeof value === "number" ? value : Number(value);
    if (!Number.isFinite(n)) return "-";
    return n.toLocaleString("es-AR", {
      style: "currency",
      currency: "ARS",
      maximumFractionDigits: 0,
    });
  };

  const formatDateOnly = (value: any) => {
    if (!value) return "-";
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return String(value);
    return d.toLocaleDateString("es-AR");
  };

  const loadInstallments = React.useCallback(async () => {
    if (!record?.id) return;
    setLoading(true);
    try {
      const res = await httpClient(`/loans/${record.id}/installments`, { method: "GET" });
      setRows(Array.isArray(res?.json) ? res.json : []);
    } catch (e: any) {
      notify(e?.message ?? "Error cargando cuotas", { type: "error" });
    } finally {
      setLoading(false);
    }
  }, [record?.id]);

  React.useEffect(() => {
    loadInstallments();
  }, [loadInstallments]);

  const [openPay, setOpenPay] = React.useState(false);

  const firstUnpaid = React.useMemo(() => {
    const candidates = rows
      .map((it) => {
        const bal = calcSaldo(it);
        const num = n0(it?.number ?? it?.installment_number);
        return { num, bal };
      })
      .filter((x) => x.bal > 0);

    if (candidates.length === 0) return null;
    candidates.sort((a, b) => a.num - b.num);
    return candidates[0];
  }, [rows]);

  return (
    <Box>
      <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 2 }}>
        <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
          Cuotas
        </Typography>

        <Button variant="contained" onClick={() => setOpenPay(true)} disabled={!record?.id || !firstUnpaid || locked}>
          Registrar Pago
        </Button>
      </Stack>

      {locked && (
        <Alert severity="warning" sx={{ mb: 2 }}>
          Crédito cancelado/refinanciado: acciones bloqueadas.
        </Alert>
      )}

      {loading ? (
        <Typography>Cargando…</Typography>
      ) : (
        <Paper variant="outlined" sx={{ p: 2 }}>
          {rows.length === 0 ? (
            <Typography variant="body2">No hay cuotas para mostrar.</Typography>
          ) : (
            <Box sx={{ overflowX: "auto" }}>
              <table style={{ width: "100%", borderCollapse: "collapse" }}>
                <thead>
                  <tr>
                    <th style={{ textAlign: "left", padding: 8 }}>N°</th>
                    <th style={{ textAlign: "left", padding: 8 }}>Vence</th>
                    <th style={{ textAlign: "left", padding: 8 }}>Monto</th>
                    <th style={{ textAlign: "left", padding: 8 }}>Pagado</th>
                    <th style={{ textAlign: "left", padding: 8 }}>Saldo</th>
                    <th style={{ textAlign: "left", padding: 8 }}>Estado</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((it) => (
                    <tr key={it.id}>
                      <td style={{ padding: 8 }}>{it.number ?? it.installment_number ?? "-"}</td>
                      <td style={{ padding: 8 }}>{formatDateOnly(it.due_date)}</td>
                      <td style={{ padding: 8 }}>{formatMoney(it.amount)}</td>
                      <td style={{ padding: 8 }}>{formatMoney(it.paid_amount)}</td>
                      <td style={{ padding: 8, fontWeight: 700 }}>{formatMoney(calcSaldo(it))}</td>
                      <td style={{ padding: 8 }}>
                        <InstallmentStatusChip raw={it.status} />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </Box>
          )}
        </Paper>
      )}

      {record?.id && (
        <PayLoanDialog
          open={openPay}
          onClose={() => setOpenPay(false)}
          loanId={record.id}
          suggestedAmount={firstUnpaid?.bal ?? 0}
          firstUnpaidNumber={firstUnpaid?.num ?? null}
          firstUnpaidBalance={firstUnpaid?.bal ?? null}
          locked={locked}
          onSuccess={() => {
            refresh();
            loadInstallments();
          }}
        />
      )}
    </Box>
  );
}

// ============================
// Pagos TAB
// ============================
function LoanPaymentsTab() {
  const record = useRecordContext<any>();
  const notify = useNotify();
  const refresh = useRefresh();

  const { locked } = isLoanLocked(record);

  const [rows, setRows] = React.useState<any[]>([]);
  const [loading, setLoading] = React.useState(false);

  const [openVoid, setOpenVoid] = React.useState(false);
  const [voiding, setVoiding] = React.useState(false);
  const [voidReason, setVoidReason] = React.useState("");
  const [selectedPayment, setSelectedPayment] = React.useState<any | null>(null);

  const formatMoney = (value: any) => {
    const n = typeof value === "number" ? value : Number(value);
    if (!Number.isFinite(n)) return "-";
    return n.toLocaleString("es-AR", {
      style: "currency",
      currency: "ARS",
      maximumFractionDigits: 0,
    });
  };

  const formatDateTime = (value: any) => {
    if (!value) return "-";
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return String(value);
    return d.toLocaleString("es-AR");
  };

  const loadPayments = React.useCallback(async () => {
    if (!record?.id) return;
    setLoading(true);
    try {
      const res = await httpClient(`/loans/${record.id}/payments`, { method: "GET" });
      setRows(Array.isArray(res?.json) ? res.json : []);
    } catch (e: any) {
      notify(e?.message ?? "Error cargando pagos", { type: "error" });
    } finally {
      setLoading(false);
    }
  }, [record?.id]);

  React.useEffect(() => {
    loadPayments();
  }, [loadPayments]);

  const openVoidDialog = (p: any) => {
    if (locked) {
      notify("Acción bloqueada: el crédito está cancelado/refinanciado.", { type: "warning" });
      return;
    }
    setSelectedPayment(p);
    setVoidReason("");
    setOpenVoid(true);
  };

  const closeVoidDialog = () => {
    setOpenVoid(false);
    setSelectedPayment(null);
    setVoidReason("");
  };

  const doVoid = async () => {
    if (!selectedPayment?.id) return;

    if (locked) {
      notify("Acción bloqueada: el crédito está cancelado/refinanciado.", { type: "warning" });
      return;
    }

    setVoiding(true);
    try {
      await httpClient(`/payments/void/${selectedPayment.id}`, {
        method: "POST",
        body: JSON.stringify({ reason: (voidReason || "").trim() || null }),
      });

      notify("Pago anulado", { type: "success" });
      refresh();
      await loadPayments();
      closeVoidDialog();
    } catch (e: any) {
      notify(extractApiErrorMessage(e) || "Error anulando pago", { type: "error" });
    } finally {
      setVoiding(false);
    }
  };

  const paymentStatusLabel = (p: any) => (p?.is_voided ? "Anulado" : "Aplicado");
  const paymentTypeLabel = (p: any) => normalizePaymentType(p?.payment_type);

  return (
    <Box>
      <Typography variant="subtitle1" sx={{ mb: 1, fontWeight: 700 }}>
        Pagos
      </Typography>

      {locked && (
        <Alert severity="warning" sx={{ mb: 2 }}>
          Crédito cancelado/refinanciado: acciones bloqueadas.
        </Alert>
      )}

      {loading ? (
        <Typography>Cargando…</Typography>
      ) : (
        <Paper variant="outlined" sx={{ p: 2 }}>
          {rows.length === 0 ? (
            <Typography variant="body2">No hay pagos para mostrar.</Typography>
          ) : (
            <Box sx={{ overflowX: "auto" }}>
              <table style={{ width: "100%", borderCollapse: "collapse" }}>
                <thead>
                  <tr>
                    <th style={{ textAlign: "left", padding: 8 }}>ID</th>
                    <th style={{ textAlign: "left", padding: 8 }}>Fecha</th>
                    <th style={{ textAlign: "left", padding: 8 }}>Monto</th>
                    <th style={{ textAlign: "left", padding: 8 }}>Método</th>
                    <th style={{ textAlign: "left", padding: 8 }}>Descripción</th>
                    <th style={{ textAlign: "left", padding: 8 }}>Estado</th>
                    <th style={{ textAlign: "left", padding: 8 }}></th>
                  </tr>
                </thead>

                <tbody>
                  {rows.map((p) => {
                    const isVoided = !!p?.is_voided;

                    return (
                      <tr key={p.id}>
                        <td style={{ padding: 8 }}>{p.id}</td>
                        <td style={{ padding: 8 }}>{formatDateTime(p.payment_date ?? p.created_at)}</td>
                        <td style={{ padding: 8, fontWeight: 700 }}>{formatMoney(p.amount)}</td>
                        <td style={{ padding: 8 }}>{paymentTypeLabel(p)}</td>
                        <td style={{ padding: 8 }}>{p.description ?? "-"}</td>
                        <td style={{ padding: 8 }}>{paymentStatusLabel(p)}</td>
                        <td style={{ padding: 8 }}>
                          <Button
                            variant="outlined"
                            color="error"
                            size="small"
                            disabled={isVoided || locked}
                            onClick={() => openVoidDialog(p)}
                          >
                            Anular
                          </Button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </Box>
          )}
        </Paper>
      )}

      <Dialog open={openVoid} onClose={closeVoidDialog} maxWidth="sm" fullWidth>
        <DialogTitle>Anular pago</DialogTitle>

        <DialogContent>
          <Alert severity="warning" sx={{ mb: 2 }}>
            Esta acción es irreversible. El pago quedará marcado como anulado y se recalculará el préstamo.
          </Alert>

          {selectedPayment?.id != null && (
            <Paper variant="outlined" sx={{ p: 1.5, mb: 2 }}>
              <Typography variant="body2">
                Pago: <b>#{selectedPayment.id}</b>
              </Typography>
              <Typography variant="body2">
                Monto: <b>{formatMoney(selectedPayment.amount)}</b>
              </Typography>
              <Typography variant="body2">
                Fecha: <b>{formatDateTime(selectedPayment.payment_date ?? selectedPayment.created_at)}</b>
              </Typography>
            </Paper>
          )}

          <MuiTextField
            label="Motivo (opcional)"
            fullWidth
            value={voidReason}
            onChange={(e) => setVoidReason(e.target.value)}
            multiline
            minRows={2}
          />
        </DialogContent>

        <DialogActions>
          <Button onClick={closeVoidDialog} disabled={voiding}>
            Cancelar
          </Button>
          <Button variant="contained" color="error" onClick={doVoid} disabled={voiding || locked}>
            Anular
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

// ============================
// SHOW
// ============================
export function LoanShow() {
  return (
    <Show>
      <TabbedShowLayout>
        <Tab label="Resumen">
          <LoanLockedBanner />
          <LoanActions />

          <LoanHeaderBlock />

          <Divider sx={{ my: 2 }} />

          <FunctionField
            render={(r: any) => {
              const installmentsCount = r?.installments_count;
              const installmentAmount = r?.installment_amount;
              const intervalDays = r?.installment_interval_days;
              const collectionDayLabel = weekdayIsoLabel(r?.collection_day);
              const description = r?.description;

              return (
                <Paper variant="outlined" sx={{ p: 2 }}>
                  <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
                    Detalle del préstamo
                  </Typography>
                <Divider sx={{ my: 1.5 }} />
                
                  <InfoRow
                    label="Fecha de inicio"
                    value={r?.start_date ? new Date(r.start_date).toLocaleDateString("es-AR") : "-"}
                  />

                  <InfoRow label="Cantidad de cuotas" value={installmentsCount ?? "-"} />
                  <InfoRow label="Monto de cuota" value={<Money value={installmentAmount} />} />
                  <InfoRow label="Intervalo (días)" value={intervalDays ?? "-"} />
                  <InfoRow label="Día de cobro" value={collectionDayLabel} />

                  <Divider sx={{ my: 1.5 }} />

                  <InfoRow
                    label="Descripción"
                    value={
                      description ? (
                        <Typography variant="body2" sx={{ whiteSpace: "pre-wrap" }}>
                          {description}
                        </Typography>
                      ) : (
                        "-"
                      )
                    }
                  />
                <Divider sx={{ my: 1.5 }} />
                  <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1 }}>
                  Último cambio de estado
                </Typography>

                <InfoRow label="Fecha" value={formatDateTimeAR(r?.status_changed_at)} />
                <InfoRow
                  label="Motivo"
                  value={
                    r?.status_reason ? (
                      <Typography variant="body2" sx={{ whiteSpace: "pre-wrap" }}>
                        {r.status_reason}
                      </Typography>
                    ) : (
                      "-"
                    )
                  }
                />
                </Paper>
              );
            }}
          />
        </Tab>

        <Tab label="Cuotas">
          <LoanInstallmentsTab />
        </Tab>

        <Tab label="Pagos">
          <LoanPaymentsTab />
        </Tab>
      </TabbedShowLayout>
    </Show>
  );
}
