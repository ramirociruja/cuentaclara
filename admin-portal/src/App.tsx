import { Admin, Resource, List, Datagrid, TextField, NumberField, Layout, CustomRoutes } from "react-admin";
import { authProvider } from "./app/authProvider";
import { dataProvider } from "./app/dataProvider";
import BulkPaymentsScreen from "./pages/BulkPayments/BulkPaymentsScreen";
import CouponsScreen from "./pages/Coupons/CouponsScreen";
import DashboardScreen from "./pages/Dashboard/DashboardScreen";
import { Route } from "react-router-dom";
import { MyMenu } from "./app/MyMenu";

import { CustomersList, CustomersCreate, CustomersEdit, CustomersShow } from "./resources/customers";
import { LoanList, LoanCreate, LoanEdit, LoanShow } from "./resources/loans";
import { PaymentsList, PaymentsShow, PaymentsEdit, LoanPaymentsCreate } from "./resources/payments";
import { InstallmentShow, InstallmentsList } from "./resources/installments";
import { EmployeesEdit, EmployeesList, EmployeesShow } from "./resources/employees";
import { i18nProvider } from "./i18nProvider";
import { ServiceGate } from "./app/ServiceGate";
import { ServiceSuspendedPage } from "./pages/ServiceSuspendedPage";
import MyCompanyPage from "./pages/MyCompanyPage";


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

const MyLayout = (props: any) => <ServiceGate><Layout {...props} menu={MyMenu} /></ServiceGate>;

export default function App() {
  return (
    <Admin
      dataProvider={dataProvider}
      i18nProvider={i18nProvider}
      authProvider={authProvider}
      layout={MyLayout}
      dashboard={DashboardScreen}
    >
      <CustomRoutes noLayout>
          <Route path="/service-suspended" element={<ServiceSuspendedPage />} />
        </CustomRoutes>
      <CustomRoutes>
        <Route path="/dashboard" element={<DashboardScreen />} />
        <Route path="/bulk-payments" element={<BulkPaymentsScreen />} />
        <Route path="/coupons" element={<CouponsScreen />} />
        <Route path="/my-company" element={<MyCompanyPage />} />
      </CustomRoutes>

      <Resource
        name="customers"
        list={CustomersList}
        create={CustomersCreate}
        edit={CustomersEdit}
        show={CustomersShow}
      />
      <Resource
        name="loans"
        list={LoanList}
        create={LoanCreate}
        edit={LoanEdit}
        show={LoanShow}
      />
      <Resource name="payments" list={PaymentsList} show={PaymentsShow} edit={PaymentsEdit} />
      <Resource
        name="installments"
        list={InstallmentsList}
        show={InstallmentShow}
      />
      <Resource
        name="employees"
        list={EmployeesList}
        edit={EmployeesEdit}
        show={EmployeesShow}
      />


      <Resource name="collectable" list={CollectableList} />
      <Resource name="loan_payments" create={LoanPaymentsCreate} />

    </Admin>
  );
}
