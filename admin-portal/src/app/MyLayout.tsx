import { Layout } from "react-admin";
import { MyMenu } from "./MyMenu";
import { MyAppBar } from "./MyAppBar";
import { MySidebar } from "./MySidebar";

export function MyLayout(props: any) {
  return <Layout {...props} menu={MyMenu} appBar={MyAppBar} sidebar={MySidebar} />;
}