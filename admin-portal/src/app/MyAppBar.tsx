import { AppBar, TitlePortal, useGetIdentity, useLogout } from "react-admin";
import {
  Box,
  Typography,
  Avatar,
  IconButton,
  Menu,
  MenuItem,
  ListItemIcon,
  ListItemText,
  Divider,
} from "@mui/material";
import LogoutIcon from "@mui/icons-material/Logout";
import BusinessIcon from "@mui/icons-material/Business";
import { useState } from "react";
import { useNavigate } from "react-router-dom";

function initials(fullName?: string) {
  const n = (fullName || "").trim().split(/\s+/);
  const a = n[0]?.[0] ?? "";
  const b = n[1]?.[0] ?? "";
  return (a + b).toUpperCase() || "U";
}

export function MyAppBar(props: any) {
  const { identity } = useGetIdentity();
  const logout = useLogout();
  const navigate = useNavigate();

  const companyName = localStorage.getItem("company_name") || "";

  const [anchorEl, setAnchorEl] = useState<null | HTMLElement>(null);
  const open = Boolean(anchorEl);

  const handleOpen = (e: React.MouseEvent<HTMLElement>) => setAnchorEl(e.currentTarget);
  const handleClose = () => setAnchorEl(null);

  return (
    <AppBar
      {...props}
      userMenu={false}
      // ✅ mata el refresh / acciones default SIN romper el layout
      toolbar={<></>}
    >
      {/* Contenedor flex propio */}
      <Box
        sx={{
          width: "100%",
          display: "flex",
          alignItems: "center",
          px: 2,
          gap: 2,
        }}
      >
        {/* IZQUIERDA */}
        <Box sx={{ display: "flex", alignItems: "center", minWidth: 0 }}>
          <TitlePortal />
        </Box>

        {/* ESPACIADOR */}
        <Box sx={{ flex: 1 }} />

        {/* DERECHA */}
        <Box sx={{ display: "flex", alignItems: "center", gap: 2 }}>
          {/* Logo + nombre */}
          <Box sx={{ display: "flex", alignItems: "center", gap: 1 }}>
            <Box
              component="img"
              src="/logo.png"
              alt="CuentaClara"
              sx={{ width: 26, height: 26 }}
            />

            <Box sx={{ lineHeight: 1 }}>
              <Typography sx={{ fontWeight: 800 }}>CuentaClara</Typography>
              <Typography sx={{ fontSize: 11, opacity: 0.8 }}>
                {companyName || "Admin"}
              </Typography>
            </Box>
          </Box>

          {/* Avatar clickeable */}
          <IconButton
            onClick={handleOpen}
            sx={{ p: 0 }}
            aria-controls={open ? "user-menu" : undefined}
            aria-haspopup="true"
            aria-expanded={open ? "true" : undefined}
          >
            <Avatar
              sx={{
                width: 34,
                height: 34,
                bgcolor: "rgba(96,165,250,0.25)",
                color: "#fff",
                fontWeight: 800,
                fontSize: 13,
                border: "1px solid rgba(255,255,255,0.15)",
              }}
            >
              {initials(identity?.fullName || identity?.name)}
            </Avatar>
          </IconButton>

          {/* Menú */}
          <Menu
            id="user-menu"
            anchorEl={anchorEl}
            open={open}
            onClose={handleClose}
            anchorOrigin={{ vertical: "bottom", horizontal: "right" }}
            transformOrigin={{ vertical: "top", horizontal: "right" }}
            PaperProps={{
              sx: {
                mt: 1,
                borderRadius: 2,
                minWidth: 240,
                boxShadow: "0 10px 30px rgba(0,0,0,0.25)",
              },
            }}
          >
            <Box sx={{ px: 2, py: 1.5 }}>
              <Typography sx={{ fontWeight: 800, color: "#0f172a" }}>
                {identity?.fullName || identity?.name || "Usuario"}
              </Typography>
              {identity?.email && (
                <Typography sx={{ fontSize: 12, color: "#64748b" }}>
                  {identity.email}
                </Typography>
              )}
            </Box>

            <Divider />

            <MenuItem
              onClick={() => {
                handleClose();
                navigate("/my-company");
              }}
              sx={{
                py: 1.1,
                "&:hover": { backgroundColor: "rgba(96,165,250,0.10)" },
              }}
            >
              <ListItemIcon sx={{ minWidth: 36, color: "#0f172a" }}>
                <BusinessIcon fontSize="small" />
              </ListItemIcon>
              <ListItemText primary="Mi empresa" />
            </MenuItem>

            <MenuItem
              onClick={() => {
                handleClose();
                logout();
              }}
              sx={{
                py: 1.1,
                "&:hover": { backgroundColor: "rgba(96,165,250,0.10)" },
              }}
            >
              <ListItemIcon sx={{ minWidth: 36, color: "#0f172a" }}>
                <LogoutIcon fontSize="small" />
              </ListItemIcon>
              <ListItemText primary="Cerrar sesión" />
            </MenuItem>
          </Menu>
        </Box>
      </Box>
    </AppBar>
  );
}