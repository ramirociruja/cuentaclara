import { Admin, Resource, List, Datagrid, TextField, NumberField , Layout} from "react-admin";
import { authProvider } from "./app/authProvider";
import { dataProvider } from "./app/dataProvider";
import BulkPaymentsScreen from "./pages/BulkPayments/BulkPaymentsScreen";
import { CustomRoutes } from "react-admin";
import { Route } from "react-router-dom";
import { MyMenu } from "./app/MyMenu";

function CollectableList() {
  return (
    <List resource="collectable" perPage={50} title="Cuotas cobrables (1 por préstamo)">
      <Datagrid rowClick={false}>
        <TextField source="collector_name" label="Cobrador" />
        <TextField source="customer_name" label="Cliente" />
        <TextField source="customer_phone" label="Teléfono" />
        <NumberField source="loan_id" label="Crédito" />
        <NumberField source="installment_number" label="N° Cuota" />
        <TextField source="due_date" label="Vence" />
        <NumberField source="installment_amount" label="Monto Cuota" />
        <NumberField source="installment_balance" label="Saldo Cuota" />
        <NumberField source="loan_balance" label="Saldo Crédito" />
      </Datagrid>
    </List>
  );
}

const MyLayout = (props: any) => <Layout {...props} menu={MyMenu} />;

export default function App() {
  return (
    <Admin dataProvider={dataProvider} authProvider={authProvider} layout={MyLayout}>
      <CustomRoutes>
        <Route path="/bulk-payments" element={<BulkPaymentsScreen />} />
      </CustomRoutes>

      {/* Este resource apunta a tu endpoint nuevo */}
      <Resource name="collectable" list={CollectableList} />
    </Admin>
  );
}
