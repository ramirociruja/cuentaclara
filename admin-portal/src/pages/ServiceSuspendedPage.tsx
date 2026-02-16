import { useLogout } from "react-admin";
import { Box, Card, CardContent, Typography, Button, Stack } from "@mui/material";

export function ServiceSuspendedPage() {
  const logout = useLogout();

  const status = localStorage.getItem("service_suspended_status") ?? "expired";
  const reason = localStorage.getItem("service_suspended_reason");

  return (
    <Box sx={{ minHeight: "100vh", display: "grid", placeItems: "center", p: 2 }}>
      <Card variant="outlined" sx={{ maxWidth: 520, width: "100%" }}>
        <CardContent>
          <Typography variant="h5" sx={{ mb: 1, fontWeight: 800 }}>
            Servicio suspendido
          </Typography>

          <Typography variant="body1" sx={{ mb: 2 }}>
            Tu empresa tiene el servicio <b>{status}</b>. Para continuar, necesitás renovar la licencia.
          </Typography>

          {reason ? (
            <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
              Motivo: {reason}
            </Typography>
          ) : null}

          <Stack direction={{ xs: "column", sm: "row" }} spacing={1}>
            <Button variant="contained" onClick={() => window.location.reload()}>
              Reintentar
            </Button>
            <Button variant="outlined" onClick={() => logout()}>
              Cerrar sesión
            </Button>
          </Stack>

          <Typography variant="caption" color="text.secondary" sx={{ display: "block", mt: 2 }}>
            Si creés que esto es un error, contactá al administrador del sistema.
          </Typography>
        </CardContent>
      </Card>
    </Box>
  );
}
