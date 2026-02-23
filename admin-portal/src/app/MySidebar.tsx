import { Sidebar } from "react-admin";

export function MySidebar(props: any) {
  return (
    <Sidebar
      {...props}
      sx={{
        "& .RaSidebar-fixed": {
          background: "linear-gradient(135deg, #0f172a, #111827)",
          color: "#e5e7eb",
        },
      }}
    />
  );
}