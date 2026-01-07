import { Menu } from "react-admin";
import ReceiptLongIcon from "@mui/icons-material/ReceiptLong";
import ViewListIcon from "@mui/icons-material/ViewList";

export function MyMenu() {
  return (
    <Menu>
      {/* lo que ya tenías */}
      <Menu.Item to="/collectable" primaryText="Cuotas cobrables" leftIcon={<ViewListIcon />} />

      {/* nueva pantalla */}
      <Menu.Item to="/bulk-payments" primaryText="Carga masiva de pagos" leftIcon={<ReceiptLongIcon />} />
    </Menu>
  );
}
