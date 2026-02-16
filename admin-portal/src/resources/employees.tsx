// src/resources/employees.tsx
import {
  List,
  Datagrid,
  TextField,
  NumberField,
  DateField,
  BooleanField,
  useNotify,
  useRefresh,
  useRecordContext,
  Button,
  Show,
  Edit,
  SimpleForm,
  TextInput,
  EditButton,
  FunctionField,
  Toolbar,
  SaveButton,
} from "react-admin";

import { Box, Chip, Divider, Paper, Typography } from "@mui/material";

import LockResetIcon from "@mui/icons-material/LockReset";
import BlockIcon from "@mui/icons-material/Block";
import CheckCircleIcon from "@mui/icons-material/CheckCircle";

import { httpClient } from "../app/httpClient";

/* =========================================================
   🔐 Botón: cambiar contraseña (admin)
========================================================= */
function ResetPasswordButton() {
  const record = useRecordContext<any>();
  const notify = useNotify();
  const refresh = useRefresh();

  if (!record) return null;

  return (
    <Button
      label="Contraseña"
      onClick={async () => {
        const pwd = window.prompt(
          `Nueva contraseña para ${record.name || record.email}:`,
          ""
        );
        if (pwd === null) return;

        const value = pwd.trim();
        if (value.length < 6) {
          notify("La contraseña debe tener al menos 6 caracteres", {
            type: "warning",
          });
          return;
        }

        try {
          await httpClient(`/employees/${record.id}/password`, {
            method: "PUT",
            body: JSON.stringify({ password: value }),
          });
          notify("Contraseña actualizada", { type: "success" });
          refresh();
        } catch (e: any) {
          notify(
            e?.body?.detail || e?.message || "No se pudo cambiar la contraseña",
            { type: "error" }
          );
        }
      }}
      startIcon={<LockResetIcon />}
    />
  );
}

/* =========================================================
   🚦 Botón: habilitar / deshabilitar
========================================================= */
function ToggleActiveButton() {
  const record = useRecordContext<any>();
  const notify = useNotify();
  const refresh = useRefresh();

  if (!record) return null;

  const isActive = Boolean(record.is_active);

  return (
    <Button
      label={isActive ? "Deshabilitar" : "Habilitar"}
      onClick={async () => {
        const ok = window.confirm(
          isActive
            ? `¿Deshabilitar a ${record.name || record.email}?`
            : `¿Habilitar a ${record.name || record.email}?`
        );
        if (!ok) return;

        try {
          if (isActive) {
            await httpClient(`/employees/${record.id}/disable`, {
              method: "POST",
            });
            notify("Empleado deshabilitado", { type: "success" });
          } else {
            await httpClient(`/employees/${record.id}/enable`, {
              method: "POST",
            });
            notify("Empleado habilitado", { type: "success" });
          }
          refresh();
        } catch (e: any) {
          notify(
            e?.body?.detail || e?.message || "No se pudo actualizar el estado",
            { type: "error" }
          );
        }
      }}
      startIcon={isActive ? <BlockIcon /> : <CheckCircleIcon />}
    />
  );
}

/* =========================================================
   📋 LIST (solo datos, click -> show)
========================================================= */
export function EmployeesList() {
  return (
    <List title="Empleados" perPage={25}>
      <Datagrid rowClick="show">
        <NumberField source="id" label="ID" />
        <TextField source="name" label="Nombre" />
        <TextField source="email" label="Email" />
        <FunctionField
          label="Rol"
          render={(record: any) => translateRole(record?.role)}
        />
        <TextField source="phone" label="Teléfono" />

        <BooleanField source="is_active" label="Activo" />
        <FunctionField
          label="Último login"
          render={(record: any) => formatDateTimeAR(record?.last_login_at)}
        />
        <DateField source="created_at" label="Alta" showTime />
      </Datagrid>
    </List>
  );
}

/* =========================================================
   👁 SHOW (acciones dentro del show, estilo LoanShow)
========================================================= */



function formatDateTimeAR(value?: any) {
  if (!value) return "-";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return "-";

  return d.toLocaleString("es-AR-u-hc-h23", {
    timeZone: "America/Argentina/Buenos_Aires",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
}



function InfoRow({
  label,
  value,
}: {
  label: string;
  value: React.ReactNode;
}) {
  return (
    <Box sx={{ display: "flex", gap: 2, py: 0.75 }}>
      <Typography
        variant="body2"
        sx={{ width: 180, color: "text.secondary", flex: "0 0 auto" }}
      >
        {label}
      </Typography>
      <Box sx={{ minWidth: 0, flex: "1 1 auto" }}>
        {typeof value === "string" || typeof value === "number" ? (
          <Typography variant="body2">{value}</Typography>
        ) : (
          value
        )}
      </Box>
    </Box>
  );
}

function EmployeeStatusChip({ isActive }: { isActive: boolean }) {
  const label = isActive ? "activo" : "inhabilitado";
  return (
    <Chip
      size="small"
      variant="outlined"
      label={label}
      sx={{
        borderRadius: 999,
        ...(isActive
          ? { bgcolor: "success.light", color: "success.dark", borderColor: "success.light" }
          : { bgcolor: "warning.light", color: "warning.dark", borderColor: "warning.light" }),
      }}
    />
  );
}

function EmployeeHeaderBlock() {
  const record = useRecordContext<any>();
  if (!record) return null;

  const isActive = Boolean(record.is_active);

  return (
    <Paper variant="outlined" sx={{ p: 2, borderRadius: 2 }}>
      <Box sx={{ display: "flex", alignItems: "flex-start", gap: 2, flexWrap: "wrap" }}>
        <Box sx={{ minWidth: 0, flex: "1 1 auto" }}>
          <Typography variant="h6" sx={{ fontWeight: 800, lineHeight: 1.2 }}>
            {record.name || "-"}
          </Typography>
          <Typography variant="body2" sx={{ color: "text.secondary", mt: 0.25 }}>
            {record.email || "-"}
          </Typography>

          <Box sx={{ display: "flex", gap: 1, mt: 1, flexWrap: "wrap" }}>
            <EmployeeStatusChip isActive={isActive} />
            {record.role ? (
              <Chip
                size="small"
                label={`Rol: ${translateRole(record.role)}`}
                variant="outlined"
              />
            ) : null}
            {record.phone ? (
              <Chip size="small" label={`Celular: ${record.phone}`} variant="outlined" />
            ) : null}
          </Box>
        </Box>

        <Box sx={{ textAlign: "right" }}>
          <Typography variant="caption" sx={{ color: "text.secondary" }}>
            ID
          </Typography>
          <Typography variant="body2" sx={{ fontWeight: 700 }}>
            #{record.id}
          </Typography>
        </Box>
      </Box>
    </Paper>
  );
}

function EmployeeActionsBlock() {
  return (
    <Paper
      variant="outlined"
      sx={{
        p: 1.5,
        borderRadius: 2,
        display: "flex",
        gap: 1,
        flexWrap: "wrap",
        alignItems: "center",
      }}
    >
      <EditButton />

      <ResetPasswordButton />

      <ToggleActiveButton />
    </Paper>
  );
}


function translateRole(role?: string) {
  if (!role) return "-";

  const normalized = role.toLowerCase();

  if (normalized === "admin") return "Administrador";
  if (normalized === "collector") return "Cobrador";
  if (normalized === "manager") return "Manager";

  return role;
}



export function EmployeesShow() {
  return (
    <Show title="Empleado" actions={false}>
      <Box sx={{ display: "flex", flexDirection: "column", gap: 2 }}>
        <EmployeeActionsBlock />

        <EmployeeHeaderBlock />

        <Divider />

        <FunctionField
          render={(r: any) => (
            <Paper variant="outlined" sx={{ p: 2, borderRadius: 2 }}>
              <Typography variant="subtitle1" sx={{ fontWeight: 800, mb: 1 }}>
                Detalle del empleado
              </Typography>

              <Divider sx={{ my: 1.5 }} />

              <InfoRow label="Nombre" value={r?.name || "-"} />
              <InfoRow label="Email" value={r?.email || "-"} />
              <InfoRow label="Rol" value={translateRole(r?.role)} />
              <InfoRow label="Teléfono" value={r?.phone || "-"} />

              <Divider sx={{ my: 1.5 }} />

              <InfoRow label="Activo" value={r?.is_active ? "Sí" : "No"} />
              <InfoRow label="Último login" value={formatDateTimeAR(r?.last_login_at)} />
              <InfoRow label="Creado" value={formatDateTimeAR(r?.created_at)} />
            </Paper>
          )}
        />
      </Box>
    </Show>
  );
}


/* =========================================================
   ✏ EDIT
========================================================= */

const EmployeeEditToolbar = () => (
  <Toolbar>
    <SaveButton />
  </Toolbar>
);



export function EmployeesEdit() {
  return (
    <Edit title="Editar empleado">
      <SimpleForm toolbar={<EmployeeEditToolbar />} warnWhenUnsavedChanges>
        {/* Cabecera "tipo resumen" */}
        <Paper variant="outlined" sx={{ p: 2, borderRadius: 2, mb: 2 }}>
          <Typography variant="subtitle1" sx={{ fontWeight: 800, mb: 1 }}>
            Datos del empleado
          </Typography>
          <Divider sx={{ my: 1.25 }} />
          <Box sx={{ display: "flex", gap: 2, flexWrap: "wrap" }}>
            <Box sx={{ minWidth: 260, flex: "1 1 320px" }}>
              <TextInput source="name" label="Nombre" fullWidth />
            </Box>
            <Box sx={{ minWidth: 260, flex: "1 1 320px" }}>
              <TextInput source="email" label="Email" fullWidth />
            </Box>
            <Box sx={{ minWidth: 260, flex: "1 1 320px" }}>
              <TextInput source="phone" label="Teléfono" fullWidth />
            </Box>
          </Box>

          {/* Rol solo lectura */}
          <Box sx={{ mt: 1.25 }}>
            <Typography variant="caption" sx={{ color: "text.secondary" }}>
              Rol (solo lectura)
            </Typography>
            <Typography variant="body2" sx={{ fontWeight: 700 }}>
              <FunctionField
          label="Rol"
          render={(record: any) => translateRole(record?.role)}
        />
            </Typography>
          </Box>
        </Paper>

        {/* Seguridad / estado (solo lectura) */}
        <Paper variant="outlined" sx={{ p: 2, borderRadius: 2 }}>
          <Typography variant="subtitle1" sx={{ fontWeight: 800, mb: 1 }}>
            Estado y seguridad
          </Typography>
          <Divider sx={{ my: 1.25 }} />

          <Box sx={{ display: "flex", gap: 2, flexWrap: "wrap" }}>
            <Box sx={{ minWidth: 240, flex: "1 1 280px" }}>
              <Typography variant="caption" sx={{ color: "text.secondary" }}>
                Activo
              </Typography>
              <Typography variant="body2" sx={{ fontWeight: 700 }}>
                <BooleanField source="is_active" />
              </Typography>
            </Box>

            <Box sx={{ minWidth: 240, flex: "1 1 280px" }}>
              <Typography variant="caption" sx={{ color: "text.secondary" }}>
                Último login
              </Typography>
              <Typography variant="body2" sx={{ fontWeight: 700 }}>
                <DateField source="last_login_at" showTime />
              </Typography>
            </Box>

            <Box sx={{ minWidth: 240, flex: "1 1 280px" }}>
              <Typography variant="caption" sx={{ color: "text.secondary" }}>
                Alta
              </Typography>
              <Typography variant="body2" sx={{ fontWeight: 700 }}>
                <DateField source="created_at" showTime />
              </Typography>
            </Box>
          </Box>

          <Divider sx={{ my: 1.25 }} />
          <Typography variant="body2" sx={{ color: "text.secondary" }}>
            Para cambiar contraseña o habilitar/deshabilitar el usuario, usá los botones en la pantalla de “Ver”.
          </Typography>
        </Paper>
      </SimpleForm>
    </Edit>
  );
}

