// src/LoginPage.tsx
import { Card, CardContent, TextField, Button, Typography, Box } from "@mui/material";
import { useLogin } from "react-admin";
import { useState } from "react";
import CircularProgress from "@mui/material/CircularProgress";

export default function LoginPage() {
  const login = useLogin();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

const [loading, setLoading] = useState(false);

const handleSubmit = async (e: any) => {
  e.preventDefault();
  setLoading(true);

  try {
    await login({ username: email, password });
  } catch (err) {
    setLoading(false);
  }
};

  return (
    <>
    <Box display="flex" height="100vh">
      {/* Lado izquierdo */}
      <Box
        flex={1}
        display="flex"
        flexDirection="column"
        justifyContent="center"
        alignItems="center"
        sx={{ background: "linear-gradient(135deg, #0f172a, #1e293b)", color: "white", p: 4 }}
      >
       <img src={"/logo.png"} style={{ width: 120, marginBottom: 24 }} />

        <Typography variant="h4" fontWeight="bold">
          CuentaClara
        </Typography>

        <Typography mt={2}>
          Gestioná préstamos, cuotas y cobranzas de forma simple y segura.
        </Typography>
      </Box>

      {/* Lado derecho */}
      <Box
        flex={1}
        display="flex"
        justifyContent="center"
        alignItems="center"
        sx={{ backgroundColor: "white", p: 4 }}
      >
        <Card sx={{ width: 400, p: 2,  boxShadow: "0 4px 20px rgba(0,0,0,0.1)", borderRadius: 2  }}>
          <CardContent>
            <Typography variant="h5" mb={2}>
              Iniciar sesión
            </Typography>

            <form onSubmit={handleSubmit}>
              <TextField
                label="Email"
                fullWidth
                margin="normal"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                variant="outlined"
                disabled={loading}
              />

              <TextField
                label="Contraseña"
                type="password"
                fullWidth
                margin="normal"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                variant="outlined"
                disabled={loading}
              />

              <Button
                type="submit"
                variant="contained"
                fullWidth
                disabled={loading}
                sx={{
                    mt: 2,
                    fontWeight: "bold",
                    py: 1.5,
                }}
                >
                    Ingresar al sistema
                </Button>
            </form>
          </CardContent>
        </Card>
      </Box>
    </Box>
    {loading && (
  <Box
    sx={{
      position: "fixed",
      top: 0,
      left: 0,
      width: "100vw",
      height: "100vh",
      backgroundColor: "rgba(0,0,0,0.2)",
      zIndex: 9999,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
    }}
  >
    <CircularProgress />
  </Box>
)}
    </>
  );
}