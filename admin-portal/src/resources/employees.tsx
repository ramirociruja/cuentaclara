import * as React from "react";
import { List, Datagrid, TextField, NumberField, DateField } from "react-admin";

export function EmployeesList() {
  return (
    <List title="Empleados" perPage={25}>
      <Datagrid rowClick="show">
        <NumberField source="id" label="ID" />
        <TextField source="name" label="Nombre" />
        <TextField source="email" label="Email" />
        <TextField source="role" label="Rol" />
        <TextField source="phone" label="Teléfono" />
        <NumberField source="company_id" label="Empresa (ID)" />
        <DateField source="created_at" label="Alta" showTime />
      </Datagrid>
    </List>
  );
}
