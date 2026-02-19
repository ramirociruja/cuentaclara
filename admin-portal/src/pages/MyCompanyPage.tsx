import * as React from "react";
import { Box, Card, CardContent, Chip, Divider, Stack, Typography } from "@mui/material";
import ApartmentIcon from "@mui/icons-material/Apartment";
import EventAvailableIcon from "@mui/icons-material/EventAvailable";
import WarningAmberIcon from "@mui/icons-material/WarningAmber";
import ErrorOutlineIcon from "@mui/icons-material/ErrorOutline";
import { Title } from "react-admin";
import { httpClient } from "../app/httpClient";

type CompanyInfo = {
  id: number;
  name: string;
  service_status: string;
  license_expires_at: string | null;
  suspended_at: string | null;
  suspension_reason: string | null;
  created_at: string;
  updated_at: string;
};

function formatDate(date: string | null | undefined) {
  if (!date) return "No informado";

  const parsed = new Date(date);
  if (Number.isNaN(parsed.getTime())) return "No informado";

  return new Intl.DateTimeFormat("es-AR", {
    year: "numeric",
    month: "long",
    day: "2-digit",
  }).format(parsed);
}

function getDaysToExpire(date: string | null | undefined) {
  if (!date) return null;

  const expiry = new Date(date);
  if (Number.isNaN(expiry.getTime())) return null;

  const now = new Date();
  const msDiff = expiry.getTime() - now.getTime();
  return Math.ceil(msDiff / (1000 * 60 * 60 * 24));
}

function statusLabel(status: string) {
  const normalized = String(status || "").toLowerCase();
  if (normalized === "active") return "Activa";
  if (normalized === "suspended") return "Suspendida";
  if (normalized === "expired") return "Vencida";
  return status || "No informado";
}

export default function MyCompanyPage() {
  const [company, setCompany] = React.useState<CompanyInfo | null>(null);
  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    let cancelled = false;

    (async () => {
      try {
        setLoading(true);
        const resp = await httpClient("/companies/");
        const rows = (resp.json ?? []) as CompanyInfo[];

        if (!cancelled) {
          setCompany(rows?.[0] ?? null);
          setError(null);
        }
      } catch (e: any) {
        if (!cancelled) {
          setError(e?.message ?? "No se pudo cargar la información de la empresa.");
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  const daysToExpire = getDaysToExpire(company?.license_expires_at);
  const licenseNearExpiry = typeof daysToExpire === "number" && daysToExpire >= 0 && daysToExpire <= 15;
  const licenseExpired = typeof daysToExpire === "number" && daysToExpire < 0;

  return (
    <Box sx={{ p: { xs: 1, md: 2 } }}>
      <Title title="Mi Empresa" />

      <Typography variant="h5" sx={{ mb: 2, fontWeight: 700 }}>
        Mi Empresa
      </Typography>

      <Card variant="outlined">
        <CardContent>
          {loading ? (
            <Typography>Cargando información de la empresa...</Typography>
          ) : error ? (
            <Typography color="error">{error}</Typography>
          ) : !company ? (
            <Typography>No encontramos datos de la empresa.</Typography>
          ) : (
            <Stack spacing={2}>
              <Stack direction="row" spacing={1.5} alignItems="center">
                <ApartmentIcon color="primary" />
                <Typography variant="h6" sx={{ fontWeight: 700 }}>
                  {company.name}
                </Typography>
                <Chip
                  size="small"
                  color={company.service_status === "active" ? "success" : "warning"}
                  label={`Servicio: ${statusLabel(company.service_status)}`}
                />
              </Stack>

              <Divider />

              <Box
                sx={{
                  display: "grid",
                  gridTemplateColumns: { xs: "1fr", md: "1fr 1fr" },
                  gap: 2,
                }}
              >
                <Box>
                  <Typography variant="body2" color="text.secondary">
                    Fecha de alta
                  </Typography>
                  <Typography variant="body1">{formatDate(company.created_at)}</Typography>
                </Box>

                <Box>
                  <Typography variant="body2" color="text.secondary">
                    Última actualización
                  </Typography>
                  <Typography variant="body1">{formatDate(company.updated_at)}</Typography>
                </Box>

                <Box>
                  <Typography variant="body2" color="text.secondary">
                    Vencimiento de licencia
                  </Typography>
                  <Stack direction="row" spacing={1} alignItems="center" sx={{ mt: 0.5 }}>
                    <EventAvailableIcon fontSize="small" color="action" />
                    <Typography variant="body1" sx={{ fontWeight: 700 }}>
                      {formatDate(company.license_expires_at)}
                    </Typography>
                  </Stack>

                  {typeof daysToExpire === "number" ? (
                    <Typography
                      variant="body2"
                      color={licenseExpired ? "error.main" : licenseNearExpiry ? "warning.main" : "text.secondary"}
                      sx={{ mt: 0.5 }}
                    >
                      {licenseExpired
                        ? `La licencia venció hace ${Math.abs(daysToExpire)} día(s).`
                        : `Quedan ${daysToExpire} día(s) para el vencimiento.`}
                    </Typography>
                  ) : null}
                </Box>

                <Box>
                  <Typography variant="body2" color="text.secondary">
                    Estado de suspensión
                  </Typography>
                  <Typography variant="body1">
                    {company.suspended_at ? `Suspendida desde ${formatDate(company.suspended_at)}` : "Sin suspensión"}
                  </Typography>
                  {company.suspension_reason ? (
                    <Typography variant="body2" color="text.secondary">
                      Motivo: {company.suspension_reason}
                    </Typography>
                  ) : null}
                </Box>
              </Box>

              {(licenseNearExpiry || licenseExpired) && (
                <Card variant="outlined" sx={{ borderColor: licenseExpired ? "error.main" : "warning.main" }}>
                  <CardContent sx={{ py: "12px !important" }}>
                    <Stack direction="row" spacing={1} alignItems="center">
                      {licenseExpired ? (
                        <ErrorOutlineIcon color="error" fontSize="small" />
                      ) : (
                        <WarningAmberIcon color="warning" fontSize="small" />
                      )}
                      <Typography variant="body2">
                        {licenseExpired
                          ? "La licencia está vencida. Te recomendamos renovarla para evitar bloqueos del servicio."
                          : "La licencia está próxima a vencer. Te recomendamos renovarla con anticipación."}
                      </Typography>
                    </Stack>
                  </CardContent>
                </Card>
              )}
            </Stack>
          )}
        </CardContent>
      </Card>
    </Box>
  );
}
