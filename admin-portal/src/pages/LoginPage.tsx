import { Box, Typography } from "@mui/material";
import { Login, PasswordInput, TextInput } from "react-admin";

export default function LoginPage() {
  return (
    <Login
      backgroundImage=""
      sx={{
        background:
          "radial-gradient(circle at top, rgba(37,99,235,0.16) 0%, rgba(255,255,255,1) 45%), linear-gradient(120deg, #f8fafc 0%, #eef2ff 100%)",
        "& .RaLogin-card": {
          borderRadius: 4,
          boxShadow: "0 20px 60px rgba(15, 23, 42, 0.15)",
          border: "1px solid rgba(37, 99, 235, 0.18)",
          minWidth: 380,
          maxWidth: 420,
          px: 4,
          pb: 3,
        },
        "& .RaLogin-avatar": {
          display: "none",
        },
      }}
    >
      <Box sx={{ display: "flex", flexDirection: "column", alignItems: "center", mb: 1 }}>
        <Box
          component="img"
          src="/cuentaclara-icon.svg"
          alt="CuentaClara"
          sx={{ width: 72, height: 72, mb: 1, borderRadius: 2 }}
        />
        <Typography variant="h5" fontWeight={700} color="primary.main" sx={{ mb: 0.5 }}>
          CuentaClara
        </Typography>
        <Typography variant="body2" color="text.secondary" textAlign="center">
          Ingresá al portal de administración para gestionar préstamos, pagos y clientes.
        </Typography>
      </Box>

      <TextInput source="username" label="Correo electrónico" fullWidth autoFocus />
      <PasswordInput source="password" label="Contraseña" fullWidth />
    </Login>
  );
}
