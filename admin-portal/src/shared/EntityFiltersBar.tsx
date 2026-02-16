// src/shared/EntityFiltersBar.tsx
import { useGetList, useListContext } from "react-admin";
import {
  Box,
  Paper,
  Typography,
  TextField as MuiTextField,
  MenuItem,
  Button,
  Chip,
  InputAdornment,
} from "@mui/material";

import SearchIcon from "@mui/icons-material/Search";
import ClearIcon from "@mui/icons-material/Clear";

import { DateRangeFilterBar } from "./DateRangeFilterBar";

export type StatusChoice = { id: string; name: string };

type Props = {
  // Scope de fecha (siempre presente)
  dateLabel: string;
  fromKey: string;
  toKey: string;
  defaultPreset?: "all" | "this_week" | "last_week" | "this_month" | "last_month" | "custom";


  // Cobrador
  employeeKey?: string; // default: "employee_id"
  employeeResource?: string; // default: "employees"

  // Personalizado (texto libre)
  qKey?: string; // default: "q"
  qLabel?: string; // default: "Personalizado"
  qPlaceholder?: string; // default: "Nombre, provincia, DNI, tel…"

  // Status opcional (Loans / Installments)
  statusKey?: string; // ej: "status"
  statusLabel?: string; // ej: "Estado"
  statusChoices?: StatusChoice[]; // si se pasa, se muestra el select

  // Layout
  scopeMt?: number; // margen arriba del scope

  // Limpieza
  clearKeys?: string[]; // por defecto limpia employeeKey, qKey y statusKey (si existe)
};

export function EntityFiltersBar({
  dateLabel,
  fromKey,
  toKey,
  defaultPreset = "all",

  employeeKey = "employee_id",
  employeeResource = "employees",

  qKey = "q",
  qLabel = "Personalizado",
  qPlaceholder = "Nombre, provincia, DNI o tel…",

  statusKey,
  statusLabel = "Estado",
  statusChoices,

  scopeMt = 0.75,
  clearKeys,
}: Props) {
  const { filterValues, setFilters } = useListContext();

  const onChange = (patch: Record<string, any>) => {
    setFilters({ ...filterValues, ...patch }, null, false);
  };

  // Employees
  const { data: employees = [], isLoading: employeesLoading } = useGetList(employeeResource, {
    pagination: { page: 1, perPage: 1000 },
    sort: { field: "name", order: "ASC" },
    filter: {},
  });

  const selectedEmployeeId =
    filterValues?.[employeeKey] != null && String(filterValues[employeeKey]) !== ""
      ? String(filterValues[employeeKey])
      : "";

  const selectedEmployeeName =
    selectedEmployeeId && employees.length
      ? (employees.find((e: any) => String(e.id) === selectedEmployeeId)?.name ??
          `#${selectedEmployeeId}`)
      : "";

  const qRaw = filterValues?.[qKey];
  const q = String(qRaw ?? "").trim();

  const selectedStatus =
    statusKey && filterValues?.[statusKey] != null && String(filterValues[statusKey]) !== ""
      ? String(filterValues[statusKey])
      : "";

  const effectiveClearKeys =
    clearKeys ??
    [
      employeeKey,
      qKey,
      ...(statusKey ? [statusKey] : []),
    ];

  const hasFilters =
    Boolean(selectedEmployeeId) || Boolean(q) || (statusKey ? Boolean(selectedStatus) : false);

  const clearFilters = () => {
    const next = { ...filterValues };
    for (const k of effectiveClearKeys) {
      delete next[k];
    }
    setFilters(next, null, false);
  };

  const showStatus = Boolean(statusKey && statusChoices && statusChoices.length > 0);

  
  return (
    <Box sx={{ mx: 1, mb: 1, display: "flex", flexDirection: "column", gap: 1 }}>
      {/* SCOPE (Fecha) */}
      <Box
        sx={{
          border: "1px solid",
          borderColor: "divider",
          borderRadius: 2,
          px: 2,
          py: 1,          // compacto
          mt: scopeMt,
          bgcolor: "action.hover",
        }}
      >
        <Box sx={{ display: "flex", alignItems: "center", gap: 1.25, flexWrap: "wrap" }}>
          <Typography
            variant="caption"
            sx={{
              opacity: 0.75,
              letterSpacing: 0.5,
              textTransform: "uppercase",
              mr: 0.5,
            }}
          >
            {dateLabel}
          </Typography>

          <DateRangeFilterBar
            label={dateLabel}
            fromKey={fromKey}
            toKey={toKey}
            defaultPreset={defaultPreset}
            compact
            showLabel={false}
            alignSummaryRight
          />
        </Box>
      </Box>

      {/* OPERATIVOS */}
      <Paper variant="outlined" sx={{ p: 1.25, borderRadius: 2 }}>
        <Box
          sx={{
            display: "flex",
            alignItems: "center",
            gap: 1.25,
            flexWrap: "wrap",
          }}
        >
          {/* Cobrador */}
          <MuiTextField
            select
            size="small"
            label="Cobrador"
            value={selectedEmployeeId}
            onChange={(e) => {
              const v = e.target.value;
              onChange({ [employeeKey]: v ? Number(v) : undefined });
            }}
            sx={{
              width: { xs: "100%", sm: 260 },
              "& .MuiInputBase-root": { height: 38 },
            }}
          >
            <MenuItem value="">
              <em>{employeesLoading ? "Cargando..." : "Todos"}</em>
            </MenuItem>

            {employees.map((emp: any) => (
              <MenuItem key={emp.id} value={String(emp.id)}>
                {emp.name ?? `#${emp.id}`}
              </MenuItem>
            ))}
          </MuiTextField>

          {/* Status opcional */}
          {showStatus ? (
            <MuiTextField
              select
              size="small"
              label={statusLabel}
              value={selectedStatus}
              onChange={(e) => {
                const v = e.target.value;
                onChange({ [statusKey as string]: v || undefined });
              }}
              sx={{
                width: { xs: "100%", sm: 240 },
                "& .MuiInputBase-root": { height: 38 },
              }}
            >
              <MenuItem value="">
                <em>Todos</em>
              </MenuItem>
              {statusChoices!.map((c) => (
                <MenuItem key={c.id} value={c.id}>
                  {c.name}
                </MenuItem>
              ))}
            </MuiTextField>
          ) : null}

          {/* Personalizado */}
          <MuiTextField
            size="small"
            label={qLabel}
            placeholder={qPlaceholder}
            value={filterValues?.[qKey] ?? ""}
            onChange={(e) => onChange({ [qKey]: e.target.value || undefined })}
            sx={{
              width: { xs: "100%", sm: "min(520px, 100%)" },
              flex: { sm: "1 1 320px" },
              "& .MuiInputBase-root": { height: 38 },
            }}
            slotProps={{
              input: {
                startAdornment: (
                  <InputAdornment position="start">
                    <SearchIcon fontSize="small" />
                  </InputAdornment>
                ),
              },
            }}
          />

          {/* Limpiar */}
          {hasFilters ? (
            <Button
              size="small"
              variant="text"
              startIcon={<ClearIcon />}
              onClick={clearFilters}
              sx={{ height: 38, whiteSpace: "nowrap" }}
            >
              Limpiar
            </Button>
          ) : null}
        </Box>

        {/* Chips */}
        {hasFilters ? (
          <Box sx={{ mt: 0.75, display: "flex", gap: 1, flexWrap: "wrap", alignItems: "center" }}>
            {selectedEmployeeId ? (
              <Chip
                size="small"
                variant="outlined"
                label={`Cobrador: ${selectedEmployeeName || selectedEmployeeId}`}
                onDelete={() => onChange({ [employeeKey]: undefined })}
              />
            ) : null}

            {showStatus && selectedStatus ? (
              <Chip
                size="small"
                variant="outlined"
                label={`${statusLabel}: ${
                  statusChoices?.find((c) => c.id === selectedStatus)?.name ?? selectedStatus
                }`}
                onDelete={() => onChange({ [statusKey as string]: undefined })}
              />
            ) : null}

            {q ? (
              <Chip
                size="small"
                variant="outlined"
                label={`${qLabel}: ${q}`}
                onDelete={() => onChange({ [qKey]: undefined })}
              />
            ) : null}
          </Box>
        ) : null}
      </Paper>
    </Box>
  );
}
