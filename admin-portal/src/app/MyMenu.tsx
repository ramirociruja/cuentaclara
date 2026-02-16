import * as React from "react";
import { Menu, useSidebarState } from "react-admin";
import {
  List,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Collapse,
} from "@mui/material";

import ExpandLess from "@mui/icons-material/ExpandLess";
import ExpandMore from "@mui/icons-material/ExpandMore";

import DashboardIcon from "@mui/icons-material/Dashboard";
import PeopleIcon from "@mui/icons-material/People";
import AccountBalanceIcon from "@mui/icons-material/AccountBalance";
import PaymentsIcon from "@mui/icons-material/Payments";
import ReceiptLongIcon from "@mui/icons-material/ReceiptLong";
import ViewListIcon from "@mui/icons-material/ViewList";
import LocalPrintshopIcon from "@mui/icons-material/LocalPrintshop";
import BadgeIcon from "@mui/icons-material/Badge";

type SectionProps = {
  label: string;
  icon: React.ReactElement;
  children: React.ReactNode;
  defaultOpen?: boolean;
};

function Section({ label, icon, children, defaultOpen }: SectionProps) {
  const [open, setOpen] = React.useState(!!defaultOpen);
  const [sidebarOpen] = useSidebarState();

  // Si el sidebar se colapsa, cerramos las secciones
  React.useEffect(() => {
    if (!sidebarOpen) setOpen(false);
  }, [sidebarOpen]);

  return (
    <>
      <ListItemButton onClick={() => setOpen(v => !v)}>
        <ListItemIcon>{icon}</ListItemIcon>
        <ListItemText primary={label} />
        {open ? <ExpandLess /> : <ExpandMore />}
      </ListItemButton>

      <Collapse in={open} timeout="auto" unmountOnExit>
        <List component="div" disablePadding sx={{ pl: 2 }}>
          {children}
        </List>
      </Collapse>
    </>
  );
}

export function MyMenu() {
  return (
    <Menu>
      {/* Dashboard */}
      <Menu.Item
        to="/dashboard"
        primaryText="Resumen general"
        leftIcon={<DashboardIcon />}
      />

      {/* Operación */}
      <Section
        label="Operación"
        icon={<AccountBalanceIcon />}
        defaultOpen
      >
        <Menu.Item
          to="/customers"
          primaryText="Clientes"
          leftIcon={<PeopleIcon />}
        />
        <Menu.Item
          to="/loans"
          primaryText="Préstamos"
          leftIcon={<AccountBalanceIcon />}
        />
        <Menu.Item
          to="/installments"
          primaryText="Cuotas"
          leftIcon={<ViewListIcon />}
        />
      </Section>

      {/* Pagos */}
      <Section label="Pagos" icon={<PaymentsIcon />}>
        <Menu.Item
          to="/payments"
          primaryText="Registrar / Ver pagos"
          leftIcon={<PaymentsIcon />}
        />
        <Menu.Item
          to="/bulk-payments"
          primaryText="Carga masiva de pagos"
          leftIcon={<ReceiptLongIcon />}
        />
      </Section>

      {/* Cupones */}
      <Section label="Cupones" icon={<LocalPrintshopIcon />}>
        <Menu.Item
          to="/collectable"
          primaryText="Cuotas cobrables"
          leftIcon={<ViewListIcon />}
        />
        <Menu.Item
          to="/coupons"
          primaryText="Imprimir cupones"
          leftIcon={<LocalPrintshopIcon />}
        />
      </Section>

      {/* Administración */}
      <Section label="Administración" icon={<BadgeIcon />}>
        <Menu.Item
          to="/employees"
          primaryText="Empleados"
          leftIcon={<BadgeIcon />}
        />
      </Section>
    </Menu>
  );
}
