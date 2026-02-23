import { createTheme } from "@mui/material/styles";

export const theme = createTheme({
  palette: {
    mode: "light",
    primary: { main: "#60a5fa" },
    secondary: { main: "#1e293b" },
    background: {
      default: "#f1f5f9",
      paper: "#ffffff",
    },
    text: {
      primary: "#0f172a",
      secondary: "#334155",
    },
  },

  shape: { borderRadius: 12 },

  components: {
    // 🔵 APP BAR
    MuiAppBar: {
      styleOverrides: {
        root: {
          background: "linear-gradient(135deg, #0f172a, #1e293b)",
          color: "#fff",
          boxShadow: "0 6px 24px rgba(0,0,0,0.15)",
        },
      },
    },

    // 🔵 SIDEBAR (FIX PRINCIPAL)
    MuiDrawer: {
      styleOverrides: {
        paper: {
          "& .MuiListItemIcon-root": {
  color: "rgba(255,255,255,0.88)",
},
"& .MuiSvgIcon-root": {
  fill: "currentColor",
},
          background: "linear-gradient(135deg, #0f172a, #111827)",
          borderRight: "1px solid rgba(255,255,255,0.08)",

          // ITEM BASE
          "& .RaMenuItemLink-root": {
            borderRadius: 12,
            margin: "4px 10px",
            paddingTop: 10,
            paddingBottom: 10,
            color: "rgba(255,255,255,0.90)",
            transition: "all 120ms ease",
          },

          // TEXTO NORMAL
          "& .RaMenuItemLink-root .MuiListItemText-primary": {
            color: "rgba(255,255,255,0.90)",
            fontWeight: 650,
          },

          // ICONO NORMAL
          "& .RaMenuItemLink-root .MuiListItemIcon-root": {
            color: "rgba(255,255,255,0.85)",
            minWidth: 40,
          },

          // HOVER
          "& .RaMenuItemLink-root:hover": {
            backgroundColor: "rgba(96,165,250,0.14)",
          },

          // ACTIVO
          "& .RaMenuItemLink-active": {
            backgroundColor: "rgba(96,165,250,0.22)",
            boxShadow: "inset 3px 0 0 rgba(96,165,250,0.95)",
          },

          // ACTIVO TEXTO
          "& .RaMenuItemLink-active .MuiListItemText-primary": {
            color: "#ffffff",
            fontWeight: 750,
          },

          // ACTIVO ICONO
          "& .RaMenuItemLink-active .MuiListItemIcon-root": {
            color: "#ffffff",
          },
        },
      },
    },

    // 🔵 CARDS / PAPER (para dashboard)
    MuiPaper: {
      styleOverrides: {
        root: {
          boxShadow: "0 8px 30px rgba(15,23,42,0.08)",
          border: "1px solid rgba(15,23,42,0.06)",
        },
      },
    },
  },
});