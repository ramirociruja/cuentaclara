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
  ReferenceInput,
  SelectInput,
  required,
  email,
  regex,
  useRecordContext,
  useGetOne,
  ReferenceField,
} from "react-admin";

import { useNavigate } from "react-router-dom";
import {
  Box,
  Typography,
  Card,
  CardContent,
  Divider,
  Chip,
  Tabs,
  Tab,
  Table,
  TableHead,
  TableBody,
  TableRow,
  TableCell,
  TableContainer,
  TableSortLabel,
  Paper,
  Button,
  TextField as MuiTextField,
} from "@mui/material";

import OpenInNewIcon from "@mui/icons-material/OpenInNew";
import { httpClient } from "../app/httpClient";
import * as st from "../shared/status";
import { EmptyNoResults } from "../components/EmptyNoResults";
import { EntityFiltersBar } from "../shared/EntityFiltersBar";

const ARG_PROVINCES = [
  { id: "Buenos Aires", name: "Buenos Aires" },
  { id: "Catamarca", name: "Catamarca" },
  { id: "Chaco", name: "Chaco" },
  { id: "Chubut", name: "Chubut" },
  { id: "Córdoba", name: "Córdoba" },
  { id: "Corrientes", name: "Corrientes" },
  { id: "Entre Ríos", name: "Entre Ríos" },
  { id: "Formosa", name: "Formosa" },
  { id: "Jujuy", name: "Jujuy" },
  { id: "La Pampa", name: "La Pampa" },
  { id: "La Rioja", name: "La Rioja" },
  { id: "Mendoza", name: "Mendoza" },
  { id: "Misiones", name: "Misiones" },
  { id: "Neuquén", name: "Neuquén" },
  { id: "Río Negro", name: "Río Negro" },
  { id: "Salta", name: "Salta" },
  { id: "San Juan", name: "San Juan" },
  { id: "San Luis", name: "San Luis" },
  { id: "Santa Cruz", name: "Santa Cruz" },
  { id: "Santa Fe", name: "Santa Fe" },
  { id: "Santiago del Estero", name: "Santiago del Estero" },
  { id: "Tierra del Fuego, Antártida e Islas del Atlántico Sur", name: "Tierra del Fuego, Antártida e Islas del Atlántico Sur" },
  { id: "Tucumán", name: "Tucumán" },
  { id: "Ciudad Autónoma de Buenos Aires", name: "Ciudad Autónoma de Buenos Aires" },
];


// ---------------------------
// List
// ---------------------------
export function CustomersList() {
  return (
    <List title="Clientes" perPage={25} filterDefaultValues={{ tz: "America/Argentina/Tucuman" }}>
      <EntityFiltersBar
      dateLabel="Alta"
      fromKey="created_from"
      toKey="created_to"
      defaultPreset="this_week"
      employeeKey="employee_id"
      qKey="q"
      qLabel="Buscar"
      qPlaceholder="Nombre, apellido, DNI o tel…"
      scopeMt={1}
    />
      <Datagrid rowClick="show"
      empty={<EmptyNoResults />}>
        <NumberField source="id" label="ID" />
        <TextField source="last_name" label="Apellido" />
        <TextField source="first_name" label="Nombre" />
        <TextField source="dni" label="DNI" />
        <TextField source="phone" label="Teléfono" />
        <TextField source="address" label="Dirección" />
        <TextField source="province" label="Provincia" />
        <ReferenceField source="employee_id" reference="employees" label="Cobrador" link={false}>
  <TextField source="name" />
</ReferenceField>
        <DateField source="created_at" label="Alta" showTime />
      </Datagrid>
    </List>
  );
}

// ---------------------------
// Shared form fields
// ---------------------------
function CustomerFormFields() {
  return (
    <>
      <Card variant="outlined" sx={{ mb: 2 }}>
        <CardContent>
          <Typography variant="h6" sx={{ mb: 1 }}>
            Datos del cliente
          </Typography>
          <Divider sx={{ mb: 2 }} />

          <Box
            sx={{
              display: "grid",
              gridTemplateColumns: { xs: "1fr", md: "1fr 1fr" },
              gap: 2,
            }}
          >
            <TextInput source="first_name" label="Nombre" fullWidth validate={[required()]} />

            {/* last_name obligatorio pero permite vacío; lo dejamos opcional */}
            <TextInput source="last_name" label="Apellido" fullWidth />

            <TextInput
              source="dni"
              label="DNI"
              fullWidth
              validate={[required(), regex(/^\d{7,9}$/, "DNI inválido (7 a 9 dígitos)")]}

              type="tel"
              slotProps={{
                htmlInput: { inputMode: "numeric", pattern: "[0-9]*", maxLength: 9 },
              }}
              parse={(v) => String(v ?? "").replace(/\D/g, "")}
            />

            <TextInput
              source="phone"
              label="Teléfono"
              fullWidth
              validate={[required(), regex(/^\d{8,15}$/, "Teléfono inválido (8 a 15 dígitos)")]}
              type="tel"
              slotProps={{
                htmlInput: { inputMode: "numeric", pattern: "[0-9]*", maxLength: 15 },
              }}
              parse={(v) => String(v ?? "").replace(/\D/g, "")}
              helperText="Solo números, sin espacios ni guiones"
            />

            <TextInput source="address" label="Dirección" fullWidth validate={[required()]} />

            <SelectInput
              source="province"
              label="Provincia"
              fullWidth
              choices={ARG_PROVINCES}
              optionText="name"
              optionValue="id"
              validate={[required()]}
            />

            <TextInput source="email" label="Email" fullWidth helperText="Opcional" validate={[email()]} />
          </Box>
        </CardContent>
      </Card>

      <Card variant="outlined">
        <CardContent>
          <Typography variant="h6" sx={{ mb: 1 }}>
            Asignación
          </Typography>
          <Divider sx={{ mb: 2 }} />

          <ReferenceInput
            source="employee_id"
            reference="employees"
            label="Cobrador"
            perPage={1000}
            fullWidth
            placeholder="Seleccionar cobrador..."
          >
            <SelectInput optionText="name" optionValue="id" fullWidth validate={[required()]} />
          </ReferenceInput>

          <Typography variant="body2" sx={{ mt: 2, color: "text.secondary" }}>
            Nota: DNI / Teléfono / Email deben ser únicos por cobrador. Si reasignás el cliente a otro cobrador,
            el backend valida que no exista duplicado en el destino.
          </Typography>
        </CardContent>
      </Card>
    </>
  );
}

// ---------------------------
// Create
// ---------------------------
export function CustomersCreate() {
  return (
    <Create title="Nuevo cliente" redirect="show">
      <SimpleForm defaultValues={{ last_name: "" }}>
        <CustomerFormFields />
      </SimpleForm>
    </Create>
  );
}

// ---------------------------
// Edit
// ---------------------------
export function CustomersEdit() {
  return (
    <Edit title="Editar cliente">
      <SimpleForm>
        <CustomerFormFields />
      </SimpleForm>
    </Edit>
  );
}

// ---------------------------
// Show helpers
// ---------------------------
function Kpi({
  label,
  value,
  tone = "default",
}: {
  label: string;
  value: React.ReactNode;
  tone?: "default" | "danger";
}) {
  return (
    <Card variant="outlined">
      <CardContent>
        <Typography variant="body2" color="text.secondary">
          {label}
        </Typography>

        <Box sx={{ mt: 0.5 }}>
          {tone === "danger" ? (
            <Chip color="error" label={value as any} />
          ) : (
            <Typography variant="h6">{value}</Typography>
          )}
        </Box>
      </CardContent>
    </Card>
  );
}

function LabelValue({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <Box>
      <Typography variant="body2" color="text.secondary">
        {label}
      </Typography>
      <Typography variant="body1">{value}</Typography>
    </Box>
  );
}

function LoanStatusChipFromShared({ raw }: { raw?: string | null }) {
  const label = st.normalizeLoanStatus(raw);
  const color = st.loanStatusChipColor(label);

  return <Chip size="small" variant="outlined" label={label} color={color} />;
}

// ---------------------------
// Dashboard hook
// ---------------------------
function useCustomerDashboard(customerId?: number) {
  const [data, setData] = React.useState<any | null>(null);
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    if (!customerId) return;

    setLoading(true);
    setError(null);

    httpClient(`/customers/${customerId}/dashboard?tz=America/Argentina/Tucuman`, { method: "GET" })
      .then((res: any) => setData(res.json))
      .catch((e: any) => {
        setError(e?.message ?? "Error cargando resumen del cliente");
        setData(null);
      })
      .finally(() => setLoading(false));
  }, [customerId]);

  return { data, loading, error };
}

// ---------------------------
// Loans hook
// ---------------------------
function useCustomerLoans(customerId?: number, activeOnly: boolean = false) {
  const [data, setData] = React.useState<any | null>(null);
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    if (!customerId) return;

    setLoading(true);
    setError(null);

    const tz = "America/Argentina/Tucuman";
    const url =
      `/customers/${customerId}/loans` +
      `?active_only=${activeOnly ? "true" : "false"}` +
      `&tz=${encodeURIComponent(tz)}` +
      `&limit=500&offset=0`;

    httpClient(url, { method: "GET" })
      .then((res: any) => setData(res.json))
      .catch((e: any) => {
        setError(e?.message ?? "Error cargando préstamos del cliente");
        setData(null);
      })
      .finally(() => setLoading(false));
  }, [customerId, activeOnly]);

  return { data, loading, error };
}

// ---------------------------
// Sorting helpers
// ---------------------------
type Order = "asc" | "desc";

function cmpNumber(a: any, b: any) {
  const x = Number(a ?? 0) || 0;
  const y = Number(b ?? 0) || 0;
  return x - y;
}

function cmpString(a: any, b: any) {
  return String(a ?? "").localeCompare(String(b ?? ""), "es");
}

function cmpDate(a: any, b: any) {
  const ax = a ? new Date(a).getTime() : 0;
  const bx = b ? new Date(b).getTime() : 0;
  return ax - bx;
}

function sortRows<T>(
  rows: T[],
  orderBy: keyof T,
  order: Order,
  cmp: (a: any, b: any) => number
) {
  return [...rows].sort((r1: any, r2: any) => {
    const c = cmp(r1?.[orderBy], r2?.[orderBy]);
    return order === "asc" ? c : -c;
  });
}

// ---------------------------
// Loans tab
// ---------------------------
function CustomersLoansTab() {
  const record = useRecordContext<any>();
  const navigate = useNavigate();

  const [activeOnly, setActiveOnly] = React.useState(true);
  const [q, setQ] = React.useState("");

  const { data, loading, error } = useCustomerLoans(record?.id, activeOnly);

  const money = (n: any) => `$ ${Number(n ?? 0).toLocaleString("es-AR")}`;
  const rawRows: any[] = Array.isArray(data?.loans) ? data.loans : [];

  const filteredRows = React.useMemo(() => {
    const s = q.trim().toLowerCase();
    if (!s) return rawRows;

    return rawRows.filter((r) => {
      const hay = [r.loan_id, r.description, r.collector_name, r.status]
        .map((x) => String(x ?? "").toLowerCase())
        .join(" | ");
      return hay.includes(s);
    });
  }, [rawRows, q]);

  const [orderBy, setOrderBy] = React.useState<string>("total_due");
  const [order, setOrder] = React.useState<Order>("desc");

  const rows = React.useMemo(() => {
    const key = orderBy as any;

    const cmp =
      key === "loan_id" ? cmpNumber :
      key === "total_due" ? cmpNumber :
      key === "overdue_amount" ? cmpNumber :
      key === "overdue_installments_count" ? cmpNumber :
      key === "start_date" ? cmpDate :
      key === "collector_name" ? cmpString :
      key === "status" ? cmpString :
      cmpString;

    return sortRows(filteredRows, key, order, cmp);
  }, [filteredRows, orderBy, order]);

  const onSort = (key: string) => {
    if (orderBy === key) {
      setOrder((prev) => (prev === "asc" ? "desc" : "asc"));
    } else {
      setOrderBy(key);
      setOrder("desc");
    }
  };

  const SortHeader = ({ id, label, numeric }: { id: string; label: string; numeric?: boolean }) => (
    <TableCell align={numeric ? "right" : "left"} sortDirection={orderBy === id ? order : false}>
      <TableSortLabel
        active={orderBy === id}
        direction={orderBy === id ? order : "asc"}
        onClick={() => onSort(id)}
      >
        {label}
      </TableSortLabel>
    </TableCell>
  );

  if (!record) return null;

  return (
    <Box sx={{ p: 2 }}>
      <Box sx={{ mb: 1 }}>
  <Box
    sx={{
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      gap: 2,
      flexWrap: "wrap",
    }}
  >
    <Typography variant="h6" sx={{ mr: 1 }}>
      Préstamos
    </Typography>

    {/* Controles: chip a la izquierda del buscador, misma línea */}
    <Box
      sx={{
        display: "flex",
        alignItems: "center",
        gap: 1,
        flexWrap: "nowrap",
      }}
    >

      <MuiTextField
        size="small"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder="Buscar (ID, estado, descripción, cobrador)"
        sx={{ minWidth: 320, mr: 1.5 }}
      />
      <Chip
        clickable
        color={activeOnly ? "primary" : "default"}
        label={activeOnly ? "Solo activos: Sí" : "Solo activos: No"}
        onClick={() => setActiveOnly((v) => !v)}
        variant={activeOnly ? "filled" : "outlined"}
        sx={{ whiteSpace: "nowrap" }}
      />

      
    </Box>
  </Box>

  <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
    Lista de préstamos del cliente.
  </Typography>
</Box>

      <Card variant="outlined" sx={{ mb: 2 }}>
        <CardContent>
          <Box sx={{ display: "grid", gridTemplateColumns: { xs: "1fr", sm: "repeat(3, 1fr)" }, gap: 2 }}>
            <Kpi label="Cantidad" value={Number(data?.total_count ?? 0)} />
            <Kpi label="Saldo total" value={money(data?.total_due)} />
            <Kpi
              label="Vencido total"
              value={money(data?.overdue_amount)}
              tone={Number(data?.overdue_amount ?? 0) > 0 ? "danger" : "default"}
            />
          </Box>
        </CardContent>
      </Card>

      {loading && <Typography variant="body2">Cargando préstamos…</Typography>}
      {error && (
        <Typography variant="body2" color="error">
          {error}
        </Typography>
      )}

      {!loading && !error && rows.length === 0 && (
        <Typography variant="body2" color="text.secondary">
          No hay préstamos para mostrar.
        </Typography>
      )}

      {!loading && !error && rows.length > 0 && (
        <TableContainer component={Paper} variant="outlined">
          <Table size="small" stickyHeader>
            <TableHead>
              <TableRow>
                <SortHeader id="loan_id" label="Préstamo" />
                <SortHeader id="status" label="Estado" />
                <SortHeader id="total_due" label="Saldo" numeric />
                <SortHeader id="overdue_amount" label="Vencido" numeric />
                <SortHeader id="overdue_installments_count" label="Cuotas venc." numeric />
                <SortHeader id="start_date" label="Inicio" />
                <SortHeader id="collector_name" label="Cobrador" />
                <TableCell align="right">Acción</TableCell>
              </TableRow>
            </TableHead>

            <TableBody>
              {rows.map((r) => {
                const loanId = Number(r.loan_id);
                const totalDue = Number(r.total_due ?? 0);
                const overdueAmt = Number(r.overdue_amount ?? 0);
                const overdueCnt = Number(r.overdue_installments_count ?? 0);

                return (
                  <TableRow key={loanId} hover>
                    <TableCell>
                      <Typography variant="body2" sx={{ fontWeight: 700 }}>
                        #{loanId}
                      </Typography>
                      <Typography variant="caption" color="text.secondary">
                        {r.description ?? "-"}
                      </Typography>
                    </TableCell>

                    <TableCell>
                      {/* OJO: status del PRÉSTAMO, no del record del cliente */}
                      <LoanStatusChipFromShared raw={r.status} />
                    </TableCell>

                    <TableCell align="right">
                      <Typography variant="body2" sx={{ fontWeight: 700 }}>
                        {money(totalDue)}
                      </Typography>
                    </TableCell>

                    <TableCell align="right">
                      <Typography
                        variant="body2"
                        sx={{ fontWeight: overdueAmt > 0 ? 700 : 400 }}
                        color={overdueAmt > 0 ? "error" : "text.primary"}
                      >
                        {money(overdueAmt)}
                      </Typography>
                    </TableCell>

                    <TableCell align="right">
                      <Typography
                        variant="body2"
                        sx={{ fontWeight: overdueCnt > 0 ? 700 : 400 }}
                        color={overdueCnt > 0 ? "error" : "text.primary"}
                      >
                        {overdueCnt}
                      </Typography>
                    </TableCell>

                    {/* Inicio del préstamo */}
                    <TableCell>
                      <Typography variant="body2">
                        {fmtDate(r.start_date)}
                      </Typography>
                    </TableCell>


                    <TableCell>
                      <Typography variant="body2">{r.collector_name ?? "-"}</Typography>
                    </TableCell>

                    <TableCell align="right">
                      <Button
                        size="small"
                        variant="outlined"
                        endIcon={<OpenInNewIcon />}
                        onClick={() => navigate(`/loans/${loanId}/show`)}
                      >
                        Ver préstamo
                      </Button>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </TableContainer>
      )}
    </Box>
  );
}

// ---------------------------
// Show content (tabs)
// ---------------------------
function CustomersShowContent() {
  const record = useRecordContext<any>();
  const { data, loading, error } = useCustomerDashboard(record?.id);

  const [tab, setTab] = React.useState(0);

  if (!record) return null;

  const money = (n: any) => {
    const x = Number(n ?? 0);
    if (Number.isNaN(x)) return "$ 0";
    return `$ ${x.toLocaleString("es-AR")}`;
  };

  const overdueCount = Number(data?.overdue_installments_count ?? 0);
  const overdueAmount = Number(data?.overdue_amount ?? 0);

  return (
    <Box sx={{ p: 2 }}>
      <Tabs value={tab} onChange={(_, v) => setTab(v)} sx={{ mb: 2 }}>
        <Tab label="Resumen" />
        <Tab label="Préstamos" />
      </Tabs>

      {tab === 0 && (
        <>
          <Card variant="outlined" sx={{ mb: 2 }}>
            <CardContent>
              <Typography variant="h6">Resumen del cliente</Typography>
              <Divider sx={{ my: 2 }} />

              {loading && <Typography variant="body2">Cargando resumen…</Typography>}
              {error && (
                <Typography variant="body2" color="error">
                  {error}
                </Typography>
              )}

              {!loading && !error && data && (
                <>
                  <Box
                    sx={{
                      display: "grid",
                      gridTemplateColumns: { xs: "1fr", sm: "1fr 1fr", md: "repeat(4, 1fr)" },
                      gap: 2,
                    }}
                  >
                    <Kpi label="Deuda total" value={money(data.total_due)} />
                    <Kpi label="Créditos activos" value={Number(data.active_loans_count ?? 0)} />
                    <Kpi
                      label="Cuotas vencidas"
                      value={overdueCount}
                      tone={overdueCount > 0 ? "danger" : "default"}
                    />
                    <Kpi
                      label="Monto vencido"
                      value={money(overdueAmount)}
                      tone={overdueAmount > 0 ? "danger" : "default"}
                    />
                  </Box>

                  {(data.next_due_date || data.next_due_amount != null) && (
                    <>
                      <Divider sx={{ my: 2 }} />
                      <Typography variant="body2" color="text.secondary">
                        Próxima cuota
                      </Typography>
                      <Typography variant="body1">
                        {data.next_due_date ?? "-"}{" "}
                        {data.next_due_amount != null ? `— ${money(data.next_due_amount)}` : ""}
                      </Typography>
                    </>
                  )}
                </>
              )}

              {!loading && !error && !data && (
                <Typography variant="body2" color="text.secondary">
                  Sin datos de resumen.
                </Typography>
              )}
            </CardContent>
          </Card>

          <Card variant="outlined">
            <CardContent>
              <Typography variant="h6">Datos del cliente</Typography>
              <Divider sx={{ my: 2 }} />

              <Box
                sx={{
                  display: "grid",
                  gridTemplateColumns: { xs: "1fr", md: "1fr 1fr 1fr" },
                  gap: 2,
                }}
              >
                <LabelValue label="ID" value={record.id} />
                <LabelValue label="Nombre" value={record.first_name ?? "-"} />
                <LabelValue label="Apellido" value={record.last_name || "-"} />

                <LabelValue label="DNI" value={record.dni ?? "-"} />
                <LabelValue label="Teléfono" value={record.phone ?? "-"} />
                <LabelValue label="Email" value={record.email || "-"} />

                <LabelValue label="Dirección" value={record.address ?? "-"} />
                <LabelValue label="Provincia" value={record.province ?? "-"} />
                <Box>
  <Typography variant="body2" color="text.secondary">
    Cobrador
  </Typography>
  <CollectorName employeeId={record.employee_id} />
</Box>

              </Box>
            </CardContent>
          </Card>
        </>
      )}

      {tab === 1 && <CustomersLoansTab />}
    </Box>
  );
}

function fmtDate(d?: string | null) {
  if (!d) return "-";
  const dt = new Date(d);
  if (Number.isNaN(dt.getTime())) return "-";
  return dt.toLocaleDateString("es-AR"); // dd/mm/yyyy
}

function CollectorName({ employeeId }: { employeeId?: number | null }) {
  const id = employeeId ?? null;

  const { data, isLoading, error } = useGetOne(
    "employees",
    { id: id as any },
    { enabled: !!id }
  );

  if (!id) return <Typography variant="body1">-</Typography>;
  if (isLoading) return <Typography variant="body1">Cargando…</Typography>;
  if (error) return <Typography variant="body1">-</Typography>;

  // Ajustá "name" si tu employee usa otro campo (por ej first_name/last_name)
  return <Typography variant="body1">{(data as any)?.name ?? "-"}</Typography>;
}


export function CustomersShow() {
  return (
    <Show title="Cliente">
      <CustomersShowContent />
    </Show>
  );
}
