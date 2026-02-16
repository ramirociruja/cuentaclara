import * as React from "react";
import { useListContext } from "react-admin";
import {
  TextField,
  MenuItem,
  Chip,
  Button,
  Typography,
  Box,
} from "@mui/material";

// Helpers mínimos (si ya los tenés en dateRange.ts, importalos)
function pad2(n: number) {
  return n < 10 ? `0${n}` : `${n}`;
}
function ymd(d: Date) {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}
function startOfWeek(d: Date) {
  // Semana empieza lunes
  const x = new Date(d);
  const day = (x.getDay() + 6) % 7; // lunes=0 ... domingo=6
  x.setDate(x.getDate() - day);
  x.setHours(0, 0, 0, 0);
  return x;
}
function endOfWeek(d: Date) {
  const x = startOfWeek(d);
  x.setDate(x.getDate() + 6);
  x.setHours(23, 59, 59, 999);
  return x;
}
function startOfMonth(d: Date) {
  const x = new Date(d.getFullYear(), d.getMonth(), 1);
  x.setHours(0, 0, 0, 0);
  return x;
}
function endOfMonth(d: Date) {
  const x = new Date(d.getFullYear(), d.getMonth() + 1, 0);
  x.setHours(23, 59, 59, 999);
  return x;
}
function fmtHuman(isoYmd: string) {
  // "YYYY-MM-DD" -> "DD/MM/YYYY"
  const [y, m, d] = isoYmd.split("-");
  if (!y || !m || !d) return isoYmd;
  return `${d}/${m}/${y}`;
}

type Preset = "all" | "this_week" | "last_week" | "this_month" | "last_month" | "custom";

type Props = {
  label?: string;
  fromKey: string;
  toKey: string;
  defaultPreset?: Preset;
  alignSummaryRight?: boolean;

  // NUEVO
  compact?: boolean;        // estilo toolbar
  showLabel?: boolean;      // mostrar "Alta" como etiqueta
};

export function DateRangeFilterBar({
  label = "Fecha",
  fromKey,
  toKey,
  defaultPreset = "all",
  compact = false,
  showLabel = true,
  alignSummaryRight = false,
}: Props) {
  const { filterValues, setFilters } = useListContext();

  const initialPreset = (filterValues?.__date_preset as Preset) || defaultPreset;
  const [preset, setPreset] = React.useState<Preset>(initialPreset);

  const [from, setFrom] = React.useState<string>(() => {
    const v = filterValues?.[fromKey];
    return typeof v === "string" && v ? v : "";
  });
  const [to, setTo] = React.useState<string>(() => {
    const v = filterValues?.[toKey];
    return typeof v === "string" && v ? v : "";
  });

  const applyRange = React.useCallback(
    (p: Preset) => {
      const today = new Date();

      if (p === "all") {
        setPreset(p);
        setFrom("");
        setTo("");

        const next = { ...filterValues };
        next.__date_preset = p;
        delete next[fromKey];
        delete next[toKey];

        setFilters(next, null, false);
        return;
      }


      let nextFrom = from;
      let nextTo = to;

      if (p === "this_week") {
        nextFrom = ymd(startOfWeek(today));
        nextTo = ymd(endOfWeek(today));
      } else if (p === "last_week") {
        const last = new Date(today);
        last.setDate(last.getDate() - 7);
        nextFrom = ymd(startOfWeek(last));
        nextTo = ymd(endOfWeek(last));
      } else if (p === "this_month") {
        nextFrom = ymd(startOfMonth(today));
        nextTo = ymd(endOfMonth(today));
      } else if (p === "last_month") {
        const last = new Date(today.getFullYear(), today.getMonth() - 1, 1);
        nextFrom = ymd(startOfMonth(last));
        nextTo = ymd(endOfMonth(last));
      } else {
        nextFrom = from || ymd(today);
        nextTo = to || ymd(today);
      }

      setPreset(p);
      setFrom(nextFrom);
      setTo(nextTo);

      setFilters(
        {
          ...filterValues,
          __date_preset: p,
          [fromKey]: nextFrom,
          [toKey]: nextTo,
        },
        null,
        false
      );
    },
    [filterValues, from, to, fromKey, toKey, setFilters]
  );

  React.useEffect(() => {
    const hasFrom = typeof filterValues?.[fromKey] === "string" && filterValues?.[fromKey];
    const hasTo = typeof filterValues?.[toKey] === "string" && filterValues?.[toKey];

    if (!hasFrom || !hasTo) {
      // ✅ si el preset inicial es "all", dejamos sin filtro de fechas
      if (initialPreset === "all") {
        setPreset("all");
        setFrom("");
        setTo("");
        setFilters(
          (() => {
            const next = { ...filterValues };
            next.__date_preset = "all";
            delete next[fromKey];
            delete next[toKey];
            return next;
          })(),
          null,
          false
        );
      } else {
        applyRange(initialPreset);
      }
    } else {
      setFrom(filterValues?.[fromKey] as string);
      setTo(filterValues?.[toKey] as string);
      setPreset(initialPreset);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const isCustom = preset === "custom";
  const summary = from && to ? `${fmtHuman(from)} → ${fmtHuman(to)}` : "";

  // estilos comunes para que TODO tenga misma “altura visual”
  const controlSx = {
  "& .MuiInputBase-root": {
    height: compact ? 40 : 44,
    display: "flex",
    alignItems: "center",
  },
  "& .MuiSelect-select": {
    display: "flex",
    alignItems: "center",
    paddingTop: 0,
    paddingBottom: 0,
  },
};


  return (
    <Box
      sx={{
        display: "flex",
        alignItems: "center",
        gap: 1,
        flexWrap: "wrap",
        minWidth: 0,
      }}
    >
      {showLabel ? (
        <Typography
          variant="caption"
          sx={{ opacity: 0.75, letterSpacing: 0.4, textTransform: "uppercase" }}
        >
          {label}
        </Typography>
      ) : null}

      <TextField
        select
        size="small"
        value={preset}
        onChange={(e) => applyRange(e.target.value as Preset)}
        sx={{
          ...controlSx,
          width: { xs: "100%", sm: compact ? 220 : 240 },
          minWidth: 0,
        }}
      >
        <MenuItem value="all">Todos</MenuItem>
        <MenuItem value="this_week">Semana actual</MenuItem>
        <MenuItem value="last_week">Semana anterior</MenuItem>
        <MenuItem value="this_month">Mes actual</MenuItem>
        <MenuItem value="last_month">Mes anterior</MenuItem>
        <MenuItem value="custom">Personalizado</MenuItem>
      </TextField>

            {!isCustom && summary ? (
        <Chip
          label={summary}
          variant="outlined"
          size="small"
          sx={{
            height: compact ? 30 : 32,
            maxWidth: "100%",
            ...(alignSummaryRight ? { ml: { xs: 0, sm: "auto" } } : {}),
            "& .MuiChip-label": {
              overflow: "hidden",
              textOverflow: "ellipsis",
              whiteSpace: "nowrap",
            },
          }}
        />
      ) : null}


      {isCustom ? (
        <>
          <TextField
            label="Desde"
            type="date"
            size="small"
            value={from}
            onChange={(e) => {
              const v = e.target.value;
              setFrom(v);
              setFilters(
                { ...filterValues, __date_preset: "custom", [fromKey]: v, [toKey]: to || v },
                null,
                false
              );
            }}
            InputLabelProps={{ shrink: true }}
            sx={{ ...controlSx, width: { xs: "100%", sm: 170 } }}
          />

          <TextField
            label="Hasta"
            type="date"
            size="small"
            value={to}
            onChange={(e) => {
              const v = e.target.value;
              setTo(v);
              setFilters(
                { ...filterValues, __date_preset: "custom", [fromKey]: from || v, [toKey]: v },
                null,
                false
              );
            }}
            InputLabelProps={{ shrink: true }}
            sx={{ ...controlSx, width: { xs: "100%", sm: 170 } }}
          />

          <Button
            size="small"
            variant="text"
            onClick={() => applyRange("this_week")}
            sx={{ height: compact ? 38 : 40, whiteSpace: "nowrap" }}
          >
            Volver a semana
          </Button>
        </>
      ) : null}
    </Box>
  );
}

