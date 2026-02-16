import * as React from "react";
import {
  List,
  Datagrid,
  TextField,
  NumberField,
  FunctionField,
  DateField,
  Show,
  TabbedShowLayout,
  Tab,
  Edit,
  SimpleForm,
  SelectInput,
  TextInput,
  useRecordContext,
  useNotify,
  useRefresh,
  useRedirect,
  useDataProvider,
  useListContext,
  TopToolbar,
  CreateButton,
  Create,
} from "react-admin";
import {
  Box,
  Paper,
  Stack,
  Typography,
  Divider,
  Chip,
  Button,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField as MuiTextField,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Autocomplete,
  Alert,
} from "@mui/material";
import BlockIcon from "@mui/icons-material/Block";
import EditIcon from "@mui/icons-material/Edit";
import OpenInNewIcon from "@mui/icons-material/OpenInNew";

import { normalizePaymentType, kPagoAplicado } from "../shared/status";
import { EmptyNoResults } from "../components/EmptyNoResults";
import { EntityFiltersBar } from "../shared/EntityFiltersBar";
import { httpClient } from "../app/httpClient";

const money = new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS" });
function formatMoney(v: any) {
  const n = Number(v ?? 0);
  if (!Number.isFinite(n)) return "-";
  return money.format(n);
}

function formatDateTimeAR(v: any) {
  if (!v) return "-";
  const d = typeof v === "string" ? new Date(v) : v;
  if (!(d instanceof Date) || Number.isNaN(d.getTime())) return String(v);

  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const yy = d.getFullYear();
  const hh = String(d.getHours()).padStart(2, "0");
  const mi = String(d.getMinutes()).padStart(2, "0");
  return `${dd}/${mm}/${yy} ${hh}:${mi}`;
}

function PaymentStatusChip({ isVoided }: { isVoided?: boolean }) {
  if (isVoided) return <Chip size="small" label="Anulado" color="error" variant="outlined" />;
  return <Chip size="small" label={kPagoAplicado} color="success" variant="outlined" />;
}


function InfoRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <Stack
      direction="row"
      spacing={2}
      sx={{ py: 0.75 }}
      alignItems="flex-start"
      justifyContent="space-between"
    >
      <Typography variant="body2" sx={{ color: "text.secondary", minWidth: 160 }}>
        {label}
      </Typography>
      <Box sx={{ flex: 1, textAlign: "right" }}>
        {typeof value === "string" ? (
          <Typography variant="body2" sx={{ whiteSpace: "pre-wrap" }}>
            {value || "-"}
          </Typography>
        ) : (
          value
        )}
      </Box>
    </Stack>
  );
}

function PaymentTitle() {
  const record = useRecordContext<any>();
  if (!record?.id) return "Pago";
  return `Pago #${record.id}`;
}

const PAYMENT_TYPE_CHOICES = [
  { id: "cash", name: "Efectivo" },
  { id: "transfer", name: "Transferencia" },
  { id: "other", name: "Otro" },
];

function PaymentsVoidedFilter() {
  const { filterValues, setFilters } = useListContext();

  const value =
    typeof (filterValues as any)?.is_voided === "boolean"
      ? String((filterValues as any).is_voided)
      : "all";

  const onChange = (v: "all" | "true" | "false") => {
    const next = { ...(filterValues || {}) } as any;

    if (v === "all") {
      delete next.is_voided;
      next.include_voided = true; // trae ambos
    } else if (v === "true") {
      next.is_voided = true;
      delete next.include_voided;
    } else {
      next.is_voided = false;
      delete next.include_voided;
    }

    setFilters(next, null, false);
  };

  return (
    <FormControl size="small" sx={{ minWidth: 180 }}>
      <InputLabel>Estado</InputLabel>
      <Select
        label="Estado"
        value={value}
        onChange={(e) => onChange(e.target.value as any)}
      >
        <MenuItem value="all">Todos</MenuItem>
        <MenuItem value="false">Activos</MenuItem>
        <MenuItem value="true">Anulados</MenuItem>
      </Select>
    </FormControl>
  );
}

function pickCustomerProvince(r: any) {
  return (
    r?.customer_province ??
    r?.customer?.province ??
    r?.customer?.customer_province ??
    r?.province ??
    "-"
  );
}

function pickCustomerName(r: any) {
  return (
    r?.customer_name ??
    (r?.customer
      ? `${(r.customer.last_name ?? "").trim()} ${(r.customer.first_name ?? "").trim()}`.trim()
      : null) ??
    "-"
  );
}

function pickCustomerPhone(r: any) {
  return r?.customer_phone ?? r?.customer?.phone ?? r?.customer?.customer_phone ?? "-";
}

function pickCustomerDoc(r: any) {
  return r?.customer_doc ?? r?.customer?.dni ?? r?.customer?.doc ?? "-";
}

function pickReceiptNumber(r: any) {
  // Tu #5: “N° Recibo” = ID de payments en DB => usamos el id del pago
  return r?.id ? String(r.id) : "-";
}


/**
 * LIST
 */
export function PaymentsList() {
  return (
    <List
      title="Pagos"
      perPage={25}
      filterDefaultValues={{ tz: "America/Argentina/Tucuman" }}
      actions={
        <TopToolbar>
          <CreateButton resource="loan_payments" label="Registrar pago" />
        </TopToolbar>
      }
    >
      <EntityFiltersBar
        dateLabel="Fecha"
        fromKey="date_from"
        toKey="date_to"
        defaultPreset="this_week"
        // ✅ mismos filtros “core” que en otras pantallas
        employeeKey="employee_id"
        qKey="q"
        qLabel="Buscar"
        qPlaceholder="Cliente, teléfono o ID pago…"
        scopeMt={1}
      />
      <Box sx={{ px: 1, pb: 1 }}>
        <Stack direction="row" spacing={1} alignItems="center" flexWrap="wrap" useFlexGap>
          <PaymentsVoidedFilter />
        </Stack>
      </Box>

      <Datagrid
        rowClick="show"
        empty={<EmptyNoResults />}
        rowSx={(record: any) => (record?.is_voided ? { opacity: 0.6 } : {})}
      >
        <NumberField source="id" label="ID" />
        <DateField source="payment_date" label="Fecha" showTime />
        <TextField source="customer_name" label="Cliente" />
        <TextField source="customer_province" label="Provincia" />
        <TextField source="collector_name" label="Cobrador" />

        <FunctionField label="Monto" render={(r: any) => <span>{formatMoney(r?.amount)}</span>} />
        <FunctionField label="Método" render={(r: any) => <span>{normalizePaymentType(r?.payment_type)}</span>} />

        <FunctionField
          label="Estado"
          render={(r: any) => <PaymentStatusChip isVoided={!!r?.is_voided} />}
        />
      </Datagrid>

    </List>
  );
}

/**
 * SHOW (estilo Installments/Loans)
 */
export function PaymentsShow() {
  return (
    <Show title={<PaymentTitle />} actions={false}>
      <PaymentsShowContent />
    </Show>
  );
}

function PaymentsShowContent() {
  const record = useRecordContext<any>();
  const dp = useDataProvider();
  const notify = useNotify();
  const refresh = useRefresh();
  const redirect = useRedirect();

  const [voidOpen, setVoidOpen] = React.useState(false);
  const [reason, setReason] = React.useState("");

  const goEdit = () => {
    if (!record?.id) return;
    redirect(`/payments/${record.id}`);
  };

  const goLoan = () => {
    if (!record?.loan_id) return;
    redirect(`/loans/${record.loan_id}/show`);
  };


const goCustomer = async () => {
  // Caso ideal
  if (record?.customer_id) {
    redirect(`/customers/${record.customer_id}/show`);
    return;
  }

  try {
    // Fallback 1: desde préstamo
    if (record?.loan_id) {
      const res = await dp.getOne("loans", { id: record.loan_id } as any);
      const loan = (res as any)?.data;

      const cid =
        loan?.customer_id ??
        loan?.customer?.id ??
        loan?.customerId ??
        loan?.customer?.customer_id;

      if (cid) {
        redirect(`/customers/${cid}/show`);
        return;
      }
    }

    // Fallback 2: desde compra (si tu admin tiene resource "purchases")
    if (record?.purchase_id) {
      const res = await dp.getOne("purchases", { id: record.purchase_id } as any);
      const purch = (res as any)?.data;

      const cid =
        purch?.customer_id ??
        purch?.customer?.id ??
        purch?.customerId ??
        purch?.customer?.customer_id;

      if (cid) {
        redirect(`/customers/${cid}/show`);
        return;
      }
    }

    notify("No pude resolver el cliente para este pago", { type: "warning" });
  } catch (e: any) {
    notify(e?.message ?? "Error buscando el cliente", { type: "error" });
  }
};



  const onVoid = async () => {
    if (record?.is_voided) {
      notify("El pago ya está anulado", { type: "info" });
      return;
    }

    try {
      await dp.delete("payments", {
        id: record.id,
        previousData: record,
        meta: { reason: reason.trim() || null },
      } as any);

      notify("Pago anulado", { type: "success" });
      setVoidOpen(false);
      refresh();
      redirect("/payments");
    } catch (e: any) {
      notify(e?.message ?? "No se pudo anular el pago", { type: "error" });
    }
  };

  return (
    <Box sx={{ width: "100%", p: 2 }}>
      {/* Header acciones (como installments) */}
      <Paper variant="outlined" sx={{ p: 2, mb: 2 }}>
        <Stack direction="row" spacing={1} alignItems="center" flexWrap="wrap" useFlexGap>
          <Button
            variant="contained"
            startIcon={<EditIcon />}
            onClick={goEdit}
            disabled={!record?.id || !!record?.is_voided}  // ✅
          >
            Editar
          </Button>

          <Button
            variant="outlined"
            color="error"
            startIcon={<BlockIcon />}
            onClick={() => setVoidOpen(true)}
            disabled={!record?.id || !!record?.is_voided}   // ✅
          >
            Anular
          </Button>


          <Button
            variant="outlined"
            startIcon={<OpenInNewIcon />}
            onClick={goLoan}
            disabled={!record?.loan_id}
          >
            Ver préstamo
          </Button>

          <Button
            variant="outlined"
            startIcon={<OpenInNewIcon />}
            onClick={goCustomer}
            disabled={!record?.customer_id && !record?.loan_id}
          >
            Ver cliente
          </Button>


        </Stack>
      </Paper>

      {/* Contenido tabs */}
      <Paper variant="outlined" sx={{ p: 2 }}>
        <TabbedShowLayout>
          <Tab label="Resumen">
            {/* “Hero” del pago */}
            <Paper variant="outlined" sx={{ p: 2, mb: 2 }}>
              <Stack direction="row" spacing={2} alignItems="flex-start" justifyContent="space-between">
                <Box>
                  <Typography variant="body2" sx={{ color: "text.secondary" }}>
                    Monto
                  </Typography>
                  <Typography variant="h5" sx={{ fontWeight: 800 }}>
                    {formatMoney(record?.amount)}
                  </Typography>

                  <Typography variant="body2" sx={{ mt: 0.5, color: "text.secondary" }}>
                    {record?.payment_date ? formatDateTimeAR(record.payment_date) : "-"}
                  </Typography>
                </Box>

                <Stack direction="row" spacing={1} alignItems="center" useFlexGap flexWrap="wrap">
                  <PaymentStatusChip isVoided={!!record?.is_voided} />
                  <Chip
                    size="small"
                    label={normalizePaymentType(record?.payment_type)}
                    variant="outlined"
                  />
                  {record?.collector_name ? (
                    <Chip size="small" label={`Cobrador: ${record.collector_name}`} variant="outlined" />
                  ) : null}
                </Stack>
              </Stack>
            </Paper>

            {/* Cliente */}
            <Paper variant="outlined" sx={{ p: 2, mb: 2 }}>
              <Typography variant="subtitle1" sx={{ fontWeight: 800, mb: 1 }}>
                Cliente
              </Typography>
              <Divider sx={{ my: 1.5 }} />

              <InfoRow label="Nombre" value={pickCustomerName(record)} />
              <InfoRow label="DNI" value={String(pickCustomerDoc(record) ?? "-")} />
              <InfoRow label="Teléfono" value={String(pickCustomerPhone(record) ?? "-")} />
              <InfoRow label="Provincia" value={pickCustomerProvince(record)} />

            </Paper>

            {/* Detalle / Empresa */}
            <Paper variant="outlined" sx={{ p: 2, mb: 2 }}>
              <Typography variant="subtitle1" sx={{ fontWeight: 800, mb: 1 }}>
                Detalle del pago
              </Typography>
              <Divider sx={{ my: 1.5 }} />

              <InfoRow label="Referencia" value={record?.reference || "-"} />
              <InfoRow label="N° Recibo" value={pickReceiptNumber(record)} />

              <Divider sx={{ my: 1.5 }} />

              <InfoRow label="Empresa" value={record?.company_name || "-"} />
              <InfoRow label="CUIT" value="(pendiente)" />

              <Divider sx={{ my: 1.5 }} />

              <InfoRow
                label="Descripción"
                value={
                  record?.description ? (
                    <Typography variant="body2" sx={{ whiteSpace: "pre-wrap" }}>
                      {record.description}
                    </Typography>
                  ) : (
                    "-"
                  )
                }
              />
            </Paper>

            {/* Mini-resumen del préstamo (si aplica) */}
            {record?.loan_id ? (
              <Paper variant="outlined" sx={{ p: 2 }}>
                <Typography variant="subtitle1" sx={{ fontWeight: 800, mb: 1 }}>
                  Resumen del préstamo
                </Typography>
                <Divider sx={{ my: 1.5 }} />

                <InfoRow label="Préstamo" value={`#${record.loan_id}`} />
                <InfoRow label="Total" value={formatMoney(record?.loan_total_amount)} />
                <InfoRow label="Saldo" value={formatMoney(record?.loan_total_due)} />

                <Divider sx={{ my: 1.5 }} />

                <InfoRow
                  label="Cuotas"
                  value={`Pagadas: ${record?.installments_paid ?? "-"} · Vencidas: ${record?.installments_overdue ?? "-"} · Pendientes: ${
                    record?.installments_pending ?? "-"
                  }`}
                />
              </Paper>
            ) : null}
          </Tab>

          <Tab label="Recibo">
            <Paper variant="outlined" sx={{ p: 2 }}>
              <Typography variant="subtitle1" sx={{ fontWeight: 800, mb: 1 }}>
                Recibo
              </Typography>
              <Divider sx={{ my: 1.5 }} />
              <Typography variant="body2" sx={{ color: "text.secondary" }}>
                La descarga del comprobante en PDF estará disponible próximamente. Mientras tanto, puedes imprimir el resumen como comprobante.
              </Typography>
            </Paper>
          </Tab>
        </TabbedShowLayout>
      </Paper>

      {/* Dialog anular */}
      <Dialog open={voidOpen} onClose={() => setVoidOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Anular pago #{record?.id ?? ""}</DialogTitle>
        <DialogContent>
          <Typography variant="body2" sx={{ mb: 1, opacity: 0.8 }}>
            Esto no borra el pago: lo marca como anulado (contable) y recalcula el préstamo.
          </Typography>
          <MuiTextField
            label="Motivo (opcional)"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            fullWidth
            size="small"
            multiline
            minRows={2}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setVoidOpen(false)}>Cancelar</Button>
          <Button onClick={onVoid} color="error" variant="contained">
            Anular
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

/**
 * EDIT
 */
export function PaymentsEdit() {
  return (
    <Edit title={<PaymentTitle />}>
      <SimpleForm>
        <SelectInput source="payment_type" label="Método" choices={PAYMENT_TYPE_CHOICES} />
        <TextInput source="description" label="Descripción" fullWidth multiline minRows={3} />
      </SimpleForm>
    </Edit>
  );
}


function computeInstallmentsPreview(installments: any[], amountPaid: number) {
  const sorted = [...(installments ?? [])].sort((a, b) => (a.number ?? 0) - (b.number ?? 0));

  let remaining = Number(amountPaid ?? 0);
  let affected = 0;
  let full = 0;
  let partial = 0;

  for (const ins of sorted) {
    const amount = Number(ins.amount ?? 0);
    const paid = Number(ins.paid_amount ?? 0);

    const due = Math.max(0, amount - paid);
    if (due <= 1e-6) continue; // ya pagada

    if (remaining <= 1e-6) break;

    affected += 1;
    if (remaining >= due - 1e-6) {
      full += 1;
      remaining -= due;
    } else {
      partial += 1;
      remaining = 0;
      break;
    }
  }

  return { affected, full, partial, unused: remaining };
}

function moneyARS(v: any) {
  const n = Number(v ?? 0);
  if (!Number.isFinite(n)) return "-";
  return new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS" }).format(n);
}

function loanStatusLabel(s: any) {
  const v = String(s ?? "").toLowerCase();
  if (v.includes("default") || v.includes("late") || v.includes("venc")) return "Vencido";
  if (v.includes("act")) return "Activo";
  if (v.includes("paid") || v.includes("pag")) return "Pagado";
  return s ? String(s) : "-";
}

export function LoanPaymentsCreate() {
  return (
    <Create title="Registrar pago">
      <LoanPaymentsWizard />
    </Create>
  );
}

function LoanPaymentsWizard() {
  const dp = useDataProvider();
  const notify = useNotify();
  const redirect = useRedirect();
  const refresh = useRefresh();

  // Cliente (autocomplete)
  const [custInput, setCustInput] = React.useState("");
  const [custLoading, setCustLoading] = React.useState(false);
  const [custOptions, setCustOptions] = React.useState<any[]>([]);
  const [customer, setCustomer] = React.useState<any | null>(null);

  // Loans del cliente
  const [loansLoading, setLoansLoading] = React.useState(false);
  const [loanOptions, setLoanOptions] = React.useState<any[]>([]);
  const [loan, setLoan] = React.useState<any | null>(null);

  // Installments para preview
  const [instLoading, setInstLoading] = React.useState(false);
  const [installments, setInstallments] = React.useState<any[]>([]);

  // Form fields
  const [amountPaid, setAmountPaid] = React.useState<number | null>(null);
  const [paymentType, setPaymentType] = React.useState<string>("cash");
  const [description, setDescription] = React.useState<string>("");

  const totalDue = Number(loan?.total_due ?? loan?.remaining_due ?? 0);

  const preview = React.useMemo(() => {
    const amt = Number(amountPaid ?? 0);
    if (!loan || !installments?.length || amt <= 0) return null;
    return computeInstallmentsPreview(installments, amt);
  }, [loan, installments, amountPaid]);

  const amountError =
    amountPaid === null
      ? null
      : Number(amountPaid) <= 0
      ? "El monto debe ser mayor a 0"
      : loan && Number(amountPaid) > totalDue + 1e-6
      ? "El monto no puede ser mayor al saldo pendiente"
      : null;

  const descriptionRequired = paymentType === "other";
  const descriptionError =
    descriptionRequired && !String(description ?? "").trim()
      ? "Descripción requerida cuando el método es 'Otro'"
      : null;

  const canSubmit =
    !!customer &&
    !!loan &&
    !amountError &&
    Number(amountPaid ?? 0) > 0 &&
    (!descriptionRequired || !descriptionError);

  // Debounce búsqueda clientes
  React.useEffect(() => {
    const q = custInput.trim();
    if (q.length < 2) {
      setCustOptions([]);
      return;
    }

    const t = setTimeout(async () => {
      setCustLoading(true);
      try {
        const res = await dp.getList("customers", {
          pagination: { page: 1, perPage: 25 },
          sort: { field: "id", order: "DESC" },
          filter: { q, tz: "America/Argentina/Tucuman" },
        } as any);
        setCustOptions(res.data ?? []);
      } catch (e: any) {
        notify(e?.message ?? "Error buscando clientes", { type: "error" });
      } finally {
        setCustLoading(false);
      }
    }, 350);

    return () => clearTimeout(t);
  }, [custInput, dp, notify]);

  // Cargar loans cuando selecciona cliente
  React.useEffect(() => {
    const run = async () => {
      if (!customer?.id) {
        setLoanOptions([]);
        setLoan(null);
        return;
      }

      setLoansLoading(true);
      try {
        const res = await dp.getList("loans_effective", {
          pagination: { page: 1, perPage: 200 },
          sort: { field: "start_date", order: "DESC" },
          filter: { customer_id: customer.id, tz: "America/Argentina/Tucuman" },
        } as any);

        // opcional: quedarnos sólo con los que tienen saldo > 0 (por si acaso)
        const rows = (res.data ?? []).filter((r: any) => Number(r?.total_due ?? r?.remaining_due ?? 0) > 0);

        setLoanOptions(rows);
        setLoan(null);
        setInstallments([]);
        setAmountPaid(null);
      } catch (e: any) {
        notify(e?.message ?? "Error buscando préstamos", { type: "error" });
      } finally {
        setLoansLoading(false);
      }
    };
    run();
  }, [customer?.id, dp, notify]);

  // Cargar installments cuando selecciona préstamo
  React.useEffect(() => {
    const run = async () => {
      if (!loan?.id) {
        setInstallments([]);
        return;
      }
      setInstLoading(true);
      try {
        const resp = await httpClient(`/loans/${loan.id}/installments`);
        setInstallments((resp.json as any[]) ?? []);
      } catch (e: any) {
        // Si no tenés resource loan_installments, hacemos fallback con httpClient via dp.getOne custom no aplica.
        notify("No pude cargar cuotas para el preview (ver resource loan_installments)", { type: "warning" });
        setInstallments([]);
      } finally {
        setInstLoading(false);
      }
    };
    run();
  }, [loan?.id, dp, notify]);

const onConfirm = async () => {
  if (!loan?.id) return;

  try {
    const res = await dp.create("loan_payments", {
      data: {
        amount_paid: Number(amountPaid ?? 0),
        payment_type: paymentType,
        description: description.trim() || null,
      },
      meta: { loan_id: loan.id },
    } as any);

    const paymentId = (res as any)?.data?.id ?? (res as any)?.data?.payment_id;

    notify("Pago registrado correctamente", { type: "success" });
    refresh();

    if (paymentId) {
      redirect(`/payments/${paymentId}/show`);
    } else {
      // fallback
      redirect("/payments");
    }
  } catch (e: any) {
    notify(e?.message ?? "No se pudo registrar el pago", { type: "error" });
  }
};


  // Confirm dialog
  const [confirmOpen, setConfirmOpen] = React.useState(false);

  return (
    <SimpleForm toolbar={false}>
      <Box sx={{ width: "100%" }}>
        <Paper variant="outlined" sx={{ p: 2, mb: 2 }}>
          <Typography variant="h6" sx={{ fontWeight: 800, mb: 1 }}>
            1) Cliente
          </Typography>

          <Autocomplete
            value={customer}
            onChange={(_, v) => setCustomer(v)}
            inputValue={custInput}
            onInputChange={(_, v) => setCustInput(v)}
            options={custOptions}
            loading={custLoading}
            getOptionLabel={(o: any) =>
              `${(o?.last_name ?? "").trim()} ${(o?.first_name ?? "").trim()}`.trim() ||
              o?.customer_name ||
              `Cliente #${o?.id ?? ""}`
            }
            renderInput={(params) => (
              <MuiTextField
                {...params}
                label="Buscar cliente (nombre, DNI o teléfono)"
                size="small"
                placeholder="Ej: Perez, 30111222, 381..."
              />
            )}
          />

          {customer?.id ? (
            <Stack direction="row" spacing={1} sx={{ mt: 1 }} flexWrap="wrap" useFlexGap>
              <Chip size="small" label={`ID: ${customer.id}`} variant="outlined" />
              {customer?.dni ? <Chip size="small" label={`DNI: ${customer.dni}`} variant="outlined" /> : null}
              {customer?.phone ? <Chip size="small" label={`Tel: ${customer.phone}`} variant="outlined" /> : null}
              {customer?.province ? <Chip size="small" label={`Prov: ${customer.province}`} variant="outlined" /> : null}
            </Stack>
          ) : null}
        </Paper>

        <Paper variant="outlined" sx={{ p: 2, mb: 2, opacity: customer ? 1 : 0.6 }}>
          <Typography variant="h6" sx={{ fontWeight: 800, mb: 1 }}>
            2) Préstamo (Activo o Vencido)
          </Typography>

          <Autocomplete
            value={loan}
            onChange={(_, v) => setLoan(v)}
            options={loanOptions}
            loading={loansLoading}
            disabled={!customer}
            getOptionLabel={(o: any) => {
              const due = Number(o?.total_due ?? o?.remaining_due ?? 0);
              return `#${o?.id} · Saldo ${moneyARS(due)} · ${loanStatusLabel(o?.status)} · ${o?.customer_name ?? ""}`.trim();
            }}
            renderInput={(params) => (
              <MuiTextField {...params} label="Seleccionar préstamo" size="small" />
            )}
          />

          {customer && !loansLoading && loanOptions.length === 0 ? (
            <Alert severity="info" sx={{ mt: 1 }}>
              Este cliente no tiene préstamos con saldo pendiente.
            </Alert>
          ) : null}
        </Paper>

        <Paper variant="outlined" sx={{ p: 2, mb: 2, opacity: loan ? 1 : 0.6 }}>
          <Typography variant="h6" sx={{ fontWeight: 800, mb: 1 }}>
            3) Pago
          </Typography>

          {loan ? (
            <>
              <Paper variant="outlined" sx={{ p: 2, mb: 2 }}>
                <Stack direction="row" spacing={2} alignItems="flex-start" justifyContent="space-between">
                  <Box>
                    <Typography variant="body2" sx={{ color: "text.secondary" }}>
                      Préstamo
                    </Typography>
                    <Typography variant="h6" sx={{ fontWeight: 800 }}>
                      #{loan.id} · {loanStatusLabel(loan.status)}
                    </Typography>
                    <Typography variant="body2" sx={{ mt: 0.5, color: "text.secondary" }}>
                      Saldo pendiente: <b>{moneyARS(totalDue)}</b>
                    </Typography>
                  </Box>
                  {instLoading ? <Chip size="small" label="Cargando cuotas…" variant="outlined" /> : null}
                </Stack>
              </Paper>

              <Stack spacing={2}>
                <MuiTextField
                  label="Monto pagado"
                  type="number"
                  size="small"
                  value={amountPaid ?? ""}
                  onChange={(e) => setAmountPaid(e.target.value === "" ? null : Number(e.target.value))}
                  error={!!amountError}
                  helperText={amountError || `Máximo: ${moneyARS(totalDue)}`}
                  inputProps={{ min: 0, step: "0.01" }}
                />

                <SelectInput
                  source="payment_type"
                  label="Método"
                  choices={PAYMENT_TYPE_CHOICES}
                  defaultValue="cash"
                  onChange={(e: any) => setPaymentType(e.target.value)}
                />

                <MuiTextField
                  label={paymentType === "other" ? "Descripción (requerida)" : "Descripción (opcional)"}
                  size="small"
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  error={!!descriptionError}
                  helperText={descriptionError || "Ej: comprobante, observación, motivo, etc."}
                  multiline
                  minRows={2}
                />

                {/* Preview */}
                <Paper variant="outlined" sx={{ p: 2 }}>
                  <Typography variant="subtitle1" sx={{ fontWeight: 800, mb: 1 }}>
                    Preview de aplicación
                  </Typography>
                  <Divider sx={{ mb: 1.5 }} />

                  {!preview ? (
                    <Typography variant="body2" sx={{ color: "text.secondary" }}>
                      Elegí un monto para estimar cuántas cuotas se cubrirán.
                    </Typography>
                  ) : (
                    <Stack spacing={0.5}>
                      <Typography variant="body2">
                        Afecta: <b>{preview.affected}</b> cuotas (completas: <b>{preview.full}</b> · parciales:{" "}
                        <b>{preview.partial}</b>)
                      </Typography>
                      <Typography variant="body2">
                        Saldo estimado luego del pago: <b>{moneyARS(Math.max(0, totalDue - Number(amountPaid ?? 0)))}</b>
                      </Typography>
                      {preview.unused > 1e-6 ? (
                        <Alert severity="warning" sx={{ mt: 1 }}>
                          Parte del monto no se aplicaría a cuotas (revisar). Monto no aplicado: {moneyARS(preview.unused)}
                        </Alert>
                      ) : null}
                    </Stack>
                  )}
                </Paper>

                <Stack direction="row" spacing={1} justifyContent="flex-end">
                  <Button
                    variant="contained"
                    disabled={!canSubmit}
                    onClick={() => setConfirmOpen(true)}
                  >
                    Registrar pago
                  </Button>
                </Stack>
              </Stack>
            </>
          ) : (
            <Typography variant="body2" sx={{ color: "text.secondary" }}>
              Seleccioná un préstamo para continuar.
            </Typography>
          )}
        </Paper>

        <Dialog open={confirmOpen} onClose={() => setConfirmOpen(false)} maxWidth="sm" fullWidth>
          <DialogTitle>Confirmar pago</DialogTitle>
          <DialogContent>
            <Stack spacing={1}>
              <Typography variant="body2">
                Cliente: <b>{customer ? `${customer.last_name ?? ""} ${customer.first_name ?? ""}`.trim() : "-"}</b>
              </Typography>
              <Typography variant="body2">
                Préstamo: <b>#{loan?.id ?? "-"}</b>
              </Typography>
              <Typography variant="body2">
                Monto: <b>{moneyARS(amountPaid)}</b>
              </Typography>
              <Typography variant="body2">
                Método: <b>{paymentType}</b>
              </Typography>
              {preview ? (
                <Typography variant="body2">
                  Afecta: <b>{preview.affected}</b> cuotas (completas: <b>{preview.full}</b> · parciales:{" "}
                  <b>{preview.partial}</b>)
                </Typography>
              ) : null}
              <Typography variant="body2">
                Saldo luego: <b>{moneyARS(Math.max(0, totalDue - Number(amountPaid ?? 0)))}</b>
              </Typography>
            </Stack>
          </DialogContent>
          <DialogActions>
            <Button onClick={() => setConfirmOpen(false)}>Cancelar</Button>
            <Button
              variant="contained"
              onClick={() => {
                setConfirmOpen(false);
                onConfirm();
              }}
              disabled={!canSubmit}
            >
              Confirmar
            </Button>
          </DialogActions>
        </Dialog>
      </Box>
    </SimpleForm>
  );
}
