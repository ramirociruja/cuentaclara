import { createTheme } from "@mui/material/styles";

export const theme = createTheme({
  palette: {
    mode: "light",
    primary: { main: "#60a5fa" }, // celeste del botón/login
    secondary: { main: "#1e293b" },
    background: {
      default: "#f8fafc",
      paper: "#ffffff",
    },
    text: {
      primary: "#0f172a",
      secondary: "#334155",
    },
  },
  shape: { borderRadius: 12 },
  components: {
    MuiAppBar: {
      styleOverrides: {
        root: {
          background: "linear-gradient(135deg, #0f172a, #1e293b)",
          color: "#fff",
          boxShadow: "0 6px 24px rgba(0,0,0,0.15)",
        },
      },
    },
    MuiDrawer: {
      styleOverrides: {
        paper: {
          background: "linear-gradient(135deg, #0f172a, #111827)",
          color: "#e5e7eb",
          borderRight: "1px solid rgba(255,255,255,0.08)",
        },
      },
    },
    MuiListItemIcon: {
      styleOverrides: {
        root: { color: "rgba(255,255,255,0.75)" },
      },
    },
    MuiListItemText: {
      styleOverrides: {
        primary: { color: "rgba(255,255,255,0.9)" },
      },
    },
    MuiPaper: {
      styleOverrides: {
        root: { boxShadow: "0 4px 20px rgba(0,0,0,0.08)" },
      },
    },
  },
});