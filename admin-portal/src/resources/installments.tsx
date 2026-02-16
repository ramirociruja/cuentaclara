// src/resources/installments/installments.tsx
import * as React from "react";
import {
  List,
  Datagrid,
  TextField,
  NumberField,
  FunctionField,
  Show,
  TabbedShowLayout,
  Tab,
  SimpleShowLayout,
  useNotify,
  useRecordContext,
  useDataProvider,
  useRefresh,
} from "react-admin";
import {
  Box,
  Chip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  Stack,
  TextField as MuiTextField,
  MenuItem,
  Typography,
  Divider,
  Paper,
} from "@mui/material";
import { httpClient } from "../app/httpClient";
import {
  InstallmentStatusChip,
  kCuotaPendiente,
  kCuotaParcial,
  kCuotaPagada,
  kCuotaVencida,
  kCuotaCancelada,
  kCuotaRefinanciada,
  normalizePaymentType,
  kPagoAplicado,
  kPagoAnulado,
} from "../shared/status";
import { EmptyNoResults } from "../components/EmptyNoResults";
import { EntityFiltersBar } from "../shared/EntityFiltersBar";

/**
 * Helpers locales (mantener consistencia con Loans)
 * Si ya tenés helpers globales (MoneyField/StatusChip), podés reemplazarlos por imports.
 */
const money = new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS" });

function formatMoney(v: any) {
  const n = Number(v ?? 0);
  if (Number.isNaN(n)) return "-";
  return money.format(n);
}

function formatDateAR(v: any) {
  if (!v) return "-";

  // Soporta "YYYY-MM-DD" exacto (el caso más común de tu backend)
  const s = String(v);
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) {
    const [y, m, d] = s.split("-");
    return `${d}/${m}/${y}`;
  }

  const d = typeof v === "string" ? new Date(v) : v;
  if (!(d instanceof Date) || Number.isNaN(d.getTime())) return s;

  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const yy = d.getFullYear();
  return `${dd}/${mm}/${yy}`;
}

function calcBalance(record: any) {
  const amount = Number(record?.amount ?? 0);
  const paid = Number(record?.paid_amount ?? 0);
  const bal = amount - paid;
  return Math.max(0, Number.isFinite(bal) ? bal : 0);
}

function MoneyText({ value }: { value: any }) {
  return <span>{formatMoney(value)}</span>;
}

function debtTypeLabel(v: any) {
  const t = String(v ?? "").toLowerCase();
  if (t === "loan") return "Préstamo";
  if (t === "purchase") return "Venta";
  return v ? String(v) : "-";
}


/**
 * LIST
 */
export function InstallmentsList() {
  return (
    <List
      title="Cuotas"
      perPage={25}
      filterDefaultValues={{ tz: "America/Argentina/Tucuman" }}
    >
      <EntityFiltersBar
        // ✅ rango de fechas: vence (due_date)
        dateLabel="Vencimiento"
        fromKey="due_from"
        toKey="due_to"
        defaultPreset="all"
        // ✅ filtros comunes
        employeeKey="employee_id"
        qKey="q"
        qLabel="Buscar"
        qPlaceholder="Cliente o teléfono…"
        statusKey="status"
        statusLabel="Estado"
        statusChoices={[
          { id: "pending", name: kCuotaPendiente },
          { id: "partial", name: kCuotaParcial },
          { id: "paid", name: kCuotaPagada },
          { id: "overdue", name: kCuotaVencida },
          { id: "canceled", name: kCuotaCancelada },
          { id: "refinanced", name: kCuotaRefinanciada },
        ]}
        scopeMt={1}
      />
      <Datagrid rowClick="show"
      empty={<EmptyNoResults />}>
        <NumberField source="id" label="ID" />
        <TextField source="customer_name" label="Cliente" />
        <TextField source="customer_province" label="Provincia" />

        <FunctionField label="Tipo" render={(r: any) => debtTypeLabel(r?.debt_type)} />

        <NumberField source="loan_id" label="Préstamo ID" emptyText="-" />
        <NumberField source="number" label="N°" />

        <FunctionField label="Vence" render={(r: any) => formatDateAR(r?.due_date)} />

        <FunctionField label="Monto" render={(r: any) => <MoneyText value={r?.amount} />} />
        <FunctionField label="Pagado" render={(r: any) => <MoneyText value={r?.paid_amount} />} />
        <FunctionField label="Saldo" render={(r: any) => <MoneyText value={calcBalance(r)} />} />

        <FunctionField label="Estado" render={(r: any) => <InstallmentStatusChip raw={r?.status} />} />

      </Datagrid>
    </List>
  );
}

/**
 * PAY DIALOG
 */
type PaymentType = "cash" | "transfer" | "other";

function PayInstallmentDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const record = useRecordContext<any>();
  const dp = useDataProvider();
  const notify = useNotify();
  const refresh = useRefresh();

  const balance = calcBalance(record);

  const [amount, setAmount] = React.useState<number>(balance);
  const [paymentType, setPaymentType] = React.useState<PaymentType>("cash");
  const [description, setDescription] = React.useState<string>("");
  const [submitting, setSubmitting] = React.useState(false);

  React.useEffect(() => {
    if (!open) return;
    const b = calcBalance(record);
    setAmount(b);
    setPaymentType("cash");
    setDescription("");
  }, [open, record?.id]);

  const canPay = record?.id && balance > 0;

  const validate = () => {
    const a = Number(amount);
    if (!Number.isFinite(a) || a <= 0) return "El monto debe ser mayor a cero";
    if (a - balance > 1e-6) return `El monto excede el saldo. Máximo: ${formatMoney(balance)}`;
    return null;
  };

  const onSubmit = async () => {
    const err = validate();
    if (err) {
      notify(err, { type: "warning" });
      return;
    }

    try {
      setSubmitting(true);

      await dp.create("installment_payments", {
        data: {
          amount: Number(amount),
          payment_type: paymentType,
          description: description?.trim() ? description.trim() : null,
        },
        meta: { installment_id: record.id },
      } as any);

      notify("Pago registrado", { type: "success" });
      onClose();
      refresh();
    } catch (e: any) {
      notify(e?.message ?? "Error registrando pago", { type: "error" });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>Registrar pago</DialogTitle>
      <DialogContent>
        {!record ? (
          <Typography variant="body2">Sin registro seleccionado.</Typography>
        ) : (
          <Stack spacing={2} sx={{ mt: 1 }}>
            <Box>
              <Typography variant="body2" color="text.secondary">
                Saldo actual
              </Typography>
              <Typography variant="h6">{formatMoney(balance)}</Typography>
            </Box>

            <MuiTextField
              label="Monto"
              type="number"
              value={Number.isFinite(amount) ? amount : ""}
              onChange={(e) => setAmount(Number(e.target.value))}
              inputProps={{ min: 0, step: "0.01" }}
              disabled={!canPay || submitting}
              helperText={canPay ? `Máximo: ${formatMoney(balance)}` : "Cuota ya pagada"}
              fullWidth
            />

            <MuiTextField
              select
              label="Método"
              value={paymentType}
              onChange={(e) => setPaymentType(e.target.value as PaymentType)}
              disabled={!canPay || submitting}
              fullWidth
            >
              <MenuItem value="cash">Efectivo</MenuItem>
              <MenuItem value="transfer">Transferencia</MenuItem>
              <MenuItem value="other">Otro</MenuItem>
            </MuiTextField>

            <MuiTextField
              label="Descripción"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              disabled={submitting}
              fullWidth
              placeholder="Opcional (ej: 'Pago parcial', 'Seña', 'Transferencia MP', etc.)"
            />
          </Stack>
        )}
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={submitting}>
          Cancelar
        </Button>
        <Button variant="contained" onClick={onSubmit} disabled={!canPay || submitting}>
          Registrar
        </Button>
      </DialogActions>
    </Dialog>
  );
}

/**
 * PAYMENTS TAB (read-only)
 * Fix: usar useList() para armar un ListContext válido para Datagrid (evita data.map is not a function).
 */

function InstallmentPaymentsTab() {
  const record = useRecordContext<any>(); // record = installment
  const notify = useNotify();
  const refresh = useRefresh();

  const [rows, setRows] = React.useState<any[]>([]);
  const [loading, setLoading] = React.useState(false);

  // Dialog void
  const [openVoid, setOpenVoid] = React.useState(false);
  const [voiding, setVoiding] = React.useState(false);
  const [voidReason, setVoidReason] = React.useState("");
  const [selectedPayment, setSelectedPayment] = React.useState<any | null>(null);

  const formatMoneyLocal = (value: any) => {
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
    return d.toLocaleString("es-AR"); // dd/mm/aaaa hh:mm:ss (según navegador)
  };


  const paymentStatusLabel = (p: any) => (p?.is_voided ? kPagoAnulado : kPagoAplicado);


  // Advertencia: pago aplicado a más de una cuota
  // Soportamos distintos nombres por compatibilidad:
  // - allocations_count
  // - affected_installments_count
  // - allocations (array)
  const affectedInstallmentsCount = (p: any): number | null => {
    const a =
      p?.allocations_count ??
      p?.affected_installments_count ??
      (Array.isArray(p?.allocations) ? p.allocations.length : null);

    const n = Number(a);
    if (!Number.isFinite(n)) return null;
    return n;
  };

  const loadPayments = React.useCallback(async () => {
    if (!record?.id) return;

    setLoading(true);
    try {
      const res = await httpClient(`/installments/${record.id}/payments`, { method: "GET" });

      // Debe ser array. Si no, no explotar.
      const data = Array.isArray(res?.json) ? res.json : [];
      setRows(data);
    } catch (e: any) {
      notify(e?.message ?? "Error cargando pagos", { type: "error" });
      setRows([]);
    } finally {
      setLoading(false);
    }
  }, [record?.id, notify]);

  React.useEffect(() => {
    loadPayments();
  }, [loadPayments]);

  const openVoidDialog = (p: any) => {
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

    setVoiding(true);
    try {
      await httpClient(`/payments/void/${selectedPayment.id}`, {
        method: "POST",
        body: JSON.stringify({ reason: (voidReason || "").trim() || null }),
      });

      notify("Pago anulado", { type: "success" });

      // refrescar show + recargar tabla
      refresh();
      await loadPayments();

      closeVoidDialog();
    } catch (e: any) {
      notify(e?.message ?? "Error anulando pago", { type: "error" });
    } finally {
      setVoiding(false);
    }
  };

  return (
    <Box>
      <Typography variant="subtitle1" sx={{ mb: 1, fontWeight: 700 }}>
        Pagos
      </Typography>

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

                    // Advertencia si afecta 2+ cuotas
                    const cnt = affectedInstallmentsCount(p);
                    const affectsMany = cnt != null && cnt > 1;

                    return (
                      <tr key={p.id}>
                        <td style={{ padding: 8 }}>{p.id}</td>

                        <td style={{ padding: 8 }}>
                          {formatDateTime(p.payment_date ?? p.created_at)}
                        </td>

                        <td style={{ padding: 8, fontWeight: 700 }}>
                          <Box sx={{ display: "flex", gap: 1, alignItems: "center", flexWrap: "wrap" }}>
                            <span>{formatMoneyLocal(p.amount)}</span>

                            {affectsMany ? (
                              <Chip
                                size="small"
                                variant="outlined"
                                color="warning"
                                label={`Afecta ${cnt} cuotas`}
                              />
                            ) : null}
                          </Box>
                        </td>

                        <td style={{ padding: 8 }}>{normalizePaymentType(p?.payment_type)}</td>

                        <td style={{ padding: 8 }}>{p.description ?? "-"}</td>

                        <td style={{ padding: 8 }}>{paymentStatusLabel(p)}</td>

                        <td style={{ padding: 8 }}>
                          <Button
                            variant="outlined"
                            color="error"
                            size="small"
                            disabled={isVoided}
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

      {/* Dialog Anular */}
      <Dialog open={openVoid} onClose={closeVoidDialog} maxWidth="sm" fullWidth>
        <DialogTitle>Anular pago</DialogTitle>

        <DialogContent>
          <Typography variant="body2" sx={{ mb: 1 }}>
            Esta acción recalcula el préstamo. El pago quedará marcado como anulado.
          </Typography>

          {selectedPayment?.id != null && (
            <Paper variant="outlined" sx={{ p: 1.5, mb: 2 }}>
              <Typography variant="body2">
                Pago: <b>#{selectedPayment.id}</b>
              </Typography>
              <Typography variant="body2">
                Monto: <b>{formatMoneyLocal(selectedPayment.amount)}</b>
              </Typography>
              <Typography variant="body2">
                Fecha: <b>{formatDateTime(selectedPayment.payment_date ?? selectedPayment.created_at)}</b>
              </Typography>

              {(() => {
                const cnt = affectedInstallmentsCount(selectedPayment);
                if (cnt != null && cnt > 1) {
                  return (
                    <Typography variant="body2" sx={{ mt: 1 }}>
                      Advertencia: este pago afectó <b>{cnt}</b> cuotas.
                    </Typography>
                  );
                }
                return null;
              })()}
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
          <Button variant="contained" color="error" onClick={doVoid} disabled={voiding}>
            Anular
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}


/**
 * RESUMEN TAB
 * Jerarquía: SALDO + ESTADO arriba, luego Cliente/Préstamo/Vence/N°.
 */
function InstallmentSummaryTab() {
  const record = useRecordContext<any>();
  if (!record) return null;

  const balance = calcBalance(record);

  return (
    <SimpleShowLayout>
      <Box sx={{ width: "100%" }}>
        {/* Top: saldo + estado */}
        <Stack
          direction={{ xs: "column", md: "row" }}
          spacing={2}
          sx={{ mb: 2 }}
          alignItems={{ md: "center" }}
        >
          <Box sx={{ flex: 1 }}>
            <Typography variant="body2" color="text.secondary">
              Saldo
            </Typography>
            <Typography variant="h5">{formatMoney(balance)}</Typography>
          </Box>

          <Box sx={{ flex: 1 }}>
            <Typography variant="body2" color="text.secondary">
              Estado
            </Typography>
            <Box sx={{ mt: 0.5 }}>
              <InstallmentStatusChip raw={record?.status} />
            </Box>
          </Box>
        </Stack>

        <Divider sx={{ my: 2 }} />

        {/* Identificación */}
        <Stack direction={{ xs: "column", md: "row" }} spacing={2} sx={{ mb: 2 }}>
          <Box sx={{ flex: 1 }}>
            <Typography variant="body2" color="text.secondary">
              Cliente
            </Typography>
            <Typography variant="body1">{record?.customer_name ?? "-"}</Typography>
          </Box>

          <Box sx={{ flex: 1 }}>
            <Typography variant="body2" color="text.secondary">
              Tipo
            </Typography>
            <Typography variant="body1">{debtTypeLabel(record?.debt_type)}</Typography>
          </Box>

          <Box sx={{ flex: 1 }}>
            <Typography variant="body2" color="text.secondary">
              Préstamo ID
            </Typography>
            <Typography variant="body1">{record?.loan_id ? `#${record.loan_id}` : "-"}</Typography>
          </Box>
        </Stack>

        <Stack direction={{ xs: "column", md: "row" }} spacing={2} sx={{ mb: 2 }}>
          <Box sx={{ flex: 1 }}>
            <Typography variant="body2" color="text.secondary">
              Vence
            </Typography>
            <Typography variant="body1">{formatDateAR(record?.due_date)}</Typography>
          </Box>

          <Box sx={{ flex: 1 }}>
            <Typography variant="body2" color="text.secondary">
              N° cuota
            </Typography>
            <Typography variant="body1">{record?.number ?? "-"}</Typography>
          </Box>

          <Box sx={{ flex: 1 }}>
            <Typography variant="body2" color="text.secondary">
              Provincia
            </Typography>
            <Typography variant="body1">{record?.customer_province ?? "-"}</Typography>
          </Box>
        </Stack>

        <Divider sx={{ my: 2 }} />

        {/* Montos (secundario) */}
        <Stack direction={{ xs: "column", md: "row" }} spacing={2}>
          <Box sx={{ flex: 1 }}>
            <Typography variant="body2" color="text.secondary">
              Monto
            </Typography>
            <Typography variant="h6">{formatMoney(record?.amount)}</Typography>
          </Box>

          <Box sx={{ flex: 1 }}>
            <Typography variant="body2" color="text.secondary">
              Pagado
            </Typography>
            <Typography variant="h6">{formatMoney(record?.paid_amount)}</Typography>
          </Box>

          <Box sx={{ flex: 1 }}>
            <Typography variant="body2" color="text.secondary">
              Saldo
            </Typography>
            <Typography variant="h6">{formatMoney(balance)}</Typography>
          </Box>
        </Stack>
      </Box>
    </SimpleShowLayout>
  );
}

/**
 * SHOW (tabs)
 * - Resumen
 * - Pagos
 * - Acciones (registrar pago)
 *
 * Cambio: el botón no abre si la cuota no tiene saldo; muestra snackbar.
 */
export function InstallmentShow() {
  return (
    <Show title="Cuota">
      <InstallmentShowContent />
    </Show>
  );
}

function InstallmentShowContent() {
  const [payOpen, setPayOpen] = React.useState(false);
  const notify = useNotify();
  const record = useRecordContext<any>(); // AHORA sí: está dentro del <Show>

  const onClickPay = () => {
    // Igual que Loans: botón siempre habilitado; valida al click
    if (!record?.id) {
      notify("Cargando cuota…", { type: "info" });
      return;
    }

    const b = calcBalance(record);
    if (b <= 0) {
      notify("La cuota no tiene saldo pendiente para cobrar", { type: "warning" });
      return;
    }

    setPayOpen(true);
  };

  return (
    <Box sx={{ width: "100%", p: 2 }}>
      {/* Header acciones */}
      <Paper variant="outlined" sx={{ p: 2, mb: 2 }}>
        <Stack direction="row" spacing={1} alignItems="center" justifyContent="flex-start">
          <Button variant="contained" onClick={onClickPay}>
            Registrar pago
          </Button>
        </Stack>
      </Paper>

      <Paper variant="outlined" sx={{ p: 2 }}>
        <TabbedShowLayout>
          <Tab label="Resumen">
            <InstallmentSummaryTab />
          </Tab>

          <Tab label="Pagos">
            <InstallmentPaymentsTab />
          </Tab>
        </TabbedShowLayout>
      </Paper>

      <PayInstallmentDialog open={payOpen} onClose={() => setPayOpen(false)} />
    </Box>
  );
}
