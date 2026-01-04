// src/pages/OnboardingImportPage.tsx
import React, { useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { api } from "../api/client";

type ImportIssue = {
  sheet: string;
  row: number;
  field?: string | null;
  code: string;
  message: string;
};

type ProductiveSummary = {
  quality: {
    blocking_errors: boolean;
    errors_total: number;
    warnings_total: number;
    by_sheet: Record<
      "Customers" | "Loans" | "Payments",
      { rows: number; errors: number; warnings: number }
    >;
  };
  coverage: {
    customers: {
      with_dni: number;
      with_phone: number;
      with_email: number;
      with_address: number;
      with_province: number;
    };
    loans: {
      with_employee_email: number;
      missing_employee_email: number;
      with_start_date: number;
      missing_start_date: number;
    };
    payments: {
      with_collector_email: number;
      missing_collector_email: number;
      with_payment_type: number;
      missing_payment_type: number;
      with_payment_date: number;
      missing_payment_date: number;
    };
  };
  consistency: {
    duplicate_refs: {
      customer_ref: number;
      loan_ref: number;
      payment_ref: number;
    };
    dangling_refs: {
      loans_missing_customer: number;
      payments_missing_loan: number;
    };
    loan_amount_mismatches: {
      count: number;
      tolerance: number;
    };
  };
  impact: {
    customers_total: number;
    loans_total: number;
    payments_total: number;
    installments_to_generate_total: number;
    loans_total_due_sum: number;
    payments_total_amount: number;
    estimated_paid_ratio: number;
  };
  risks: {
    customers_without_identifiers: number;
    loans_without_start_date: number;
    payments_without_payment_date: number;
    loans_without_employee_email: number;
    payments_without_collector_email: number;
  };
};

type ValidateResponse = {
  batch_token: string;
  summary: ProductiveSummary;
  errors: ImportIssue[];
  warnings?: ImportIssue[];
};

type CommitResponse = {
  import_batch_id: string;
  created_counts?: {
    customers_created: number;
    loans_created: number;
    payments_created: number;
    installments_created: number;
    payment_allocations_created: number;
  };
  summary?: any;
  created_ids?: Record<string, number>;
};

function downloadCsv(filename: string, rows: Record<string, any>[]) {
  const headers = Object.keys(
    rows[0] ?? {
      sheet: "",
      row: "",
      field: "",
      code: "",
      message: "",
    }
  );

  const esc = (v: any) => {
    const s = String(v ?? "");
    const needsQuotes = /[\n\r,\"]/g.test(s);
    const escaped = s.replace(/\"/g, '""');
    return needsQuotes ? `"${escaped}"` : escaped;
  };

  const csv = [headers.join(",")]
    .concat(rows.map((r) => headers.map((h) => esc((r as any)[h])).join(",")))
    .join("\n");

  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

function fmtMoney(v: any) {
  const n = Number(v ?? 0);
  return new Intl.NumberFormat("es-AR", {
    style: "currency",
    currency: "ARS",
    maximumFractionDigits: 2,
  }).format(Number.isFinite(n) ? n : 0);
}

function fmtPct(v: any) {
  const n = Number(v ?? 0);
  const pct = Number.isFinite(n) ? n * 100 : 0;
  return `${pct.toFixed(2)}%`;
}

function anyRisk(risks: any) {
  if (!risks) return false;
  return Object.values(risks).some((x) => Number(x ?? 0) > 0);
}

function ErrorBanner({
  title,
  message,
}: {
  title: string;
  message: string;
}) {
  return (
    <div
      style={{
        background: "#fee2e2",
        border: "1px solid #fecaca",
        color: "#7f1d1d",
        borderRadius: "0.75rem",
        padding: "0.9rem 1rem",
        marginBottom: "1rem",
      }}
      role="alert"
      aria-live="polite"
    >
      <div style={{ fontWeight: 800, marginBottom: "0.25rem" }}>
        ❌ {title}
      </div>
      <div style={{ fontSize: "0.95rem", whiteSpace: "pre-wrap" }}>
        {message}
      </div>
    </div>
  );
}

export default function OnboardingImportPage() {
  const navigate = useNavigate();
  const params = useParams();
  const companyId = params.id;

  const [file, setFile] = useState<File | null>(null);
  const [validating, setValidating] = useState(false);
  const [committing, setCommitting] = useState(false);

  const [validateResp, setValidateResp] = useState<ValidateResponse | null>(
    null
  );
  const [commitResp, setCommitResp] = useState<CommitResponse | null>(null);

  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const hasErrors = useMemo(() => {
    return (validateResp?.errors?.length ?? 0) > 0;
  }, [validateResp]);

  async function handleValidate() {
    if (!companyId) {
      setErrorMsg("Falta el companyId en la URL.");
      return;
    }
    if (!file) {
      setErrorMsg("Seleccioná un archivo .xlsx para validar.");
      return;
    }

    setErrorMsg(null);
    setValidating(true);
    setValidateResp(null);
    setCommitResp(null);

    try {
      const form = new FormData();
      form.append("file", file);

      // IMPORTANT: no setear Content-Type para multipart/form-data (el browser setea el boundary)
      const resp = await api.post<ValidateResponse>(
        `/superadmin/companies/${companyId}/onboarding-import/validate`,
        form
      );

      setValidateResp(resp.data);
    } catch (err: any) {
      console.error(err);
      setErrorMsg(
        err?.response?.data?.detail ||
          "No se pudo validar el archivo. Revisá el formato del Excel."
      );
    } finally {
      setValidating(false);
    }
  }

  async function handleCommit() {
    if (!companyId) {
      setErrorMsg("Falta el companyId en la URL.");
      return;
    }
    if (!validateResp?.batch_token) {
      setErrorMsg("Primero validá el archivo.");
      return;
    }
    if (hasErrors) {
      setErrorMsg(
        "Hay errores de validación. Corregilos antes de confirmar la importación."
      );
      return;
    }

    const ok = window.confirm(
      "¿Confirmás la importación? Esta acción creará datos en la base."
    );
    if (!ok) return;

    setErrorMsg(null);
    setCommitting(true);
    setCommitResp(null);

    try {
      const resp = await api.post<CommitResponse>(
        `/superadmin/companies/${companyId}/onboarding-import/commit`,
        { batch_token: validateResp.batch_token }
      );
      setCommitResp(resp.data);
    } catch (err: any) {
      console.error(err);
      const backendMsg =
        err?.response?.data?.detail || "No se pudo confirmar la importación.";
      setErrorMsg(backendMsg);
    } finally {
      setCommitting(false);
    }
  }

  const summary = validateResp?.summary;
  const warnings = validateResp?.warnings ?? [];
  const errors = validateResp?.errors ?? [];

  return (
    <div style={{ padding: "0.5rem" }}>
      <header
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          marginBottom: "1rem",
          gap: "1rem",
        }}
      >
        <div>
          <h1 style={{ fontSize: "1.5rem", fontWeight: 600, margin: 0 }}>
            Onboarding (Importación)
          </h1>
          <div style={{ fontSize: "0.9rem", color: "#6b7280" }}>
            Empresa ID: {companyId}
          </div>
        </div>

        <button
          onClick={() => navigate("/companies")}
          style={{
            padding: "0.4rem 0.9rem",
            borderRadius: "9999px",
            border: "1px solid #d1d5db",
            background: "white",
            cursor: "pointer",
            fontSize: "0.9rem",
          }}
        >
          Volver
        </button>
      </header>

      {/* Card: Upload */}
      <section
        style={{
          background: "white",
          borderRadius: "0.75rem",
          padding: "1rem",
          boxShadow: "0 10px 25px rgba(0, 0, 0, 0.05)",
          marginBottom: "1rem",
        }}
      >
        <div style={{ fontWeight: 600, marginBottom: "0.5rem" }}>
          1) Subir Excel
        </div>
        <div style={{ fontSize: "0.9rem", color: "#6b7280" }}>
          El archivo debe contener hojas: <b>Customers</b>, <b>Loans</b>,{" "}
          <b>Payments</b>.
        </div>

        <div
          style={{
            display: "flex",
            gap: "0.75rem",
            alignItems: "center",
            marginTop: "0.75rem",
            flexWrap: "wrap",
          }}
        >
          <input
            type="file"
            accept=".xlsx"
            onChange={(e) => {
              setFile(e.target.files?.[0] ?? null);
              setValidateResp(null);
              setCommitResp(null);
              setErrorMsg(null);
            }}
          />

          <button
            onClick={handleValidate}
            disabled={validating || !file}
            style={{
              padding: "0.45rem 0.9rem",
              borderRadius: "9999px",
              border: "none",
              background: validating ? "#9ca3af" : "#2563eb",
              color: "white",
              fontSize: "0.9rem",
              fontWeight: 500,
              cursor: validating ? "not-allowed" : "pointer",
            }}
          >
            {validating ? "Validando..." : "Validar (dry-run)"}
          </button>

          {validateResp?.batch_token && (
            <span style={{ fontSize: "0.85rem", color: "#6b7280" }}>
              Token: <code>{validateResp.batch_token}</code>
            </span>
          )}
        </div>

        {/* Error menor (validación/upload). Los errores críticos del commit se destacan en Preview */}
        {errorMsg && !validateResp && (
          <div style={{ marginTop: "0.75rem", color: "#b91c1c" }}>
            {errorMsg}
          </div>
        )}
      </section>

      {/* Card: Preview */}
      {validateResp && (
        <section
          style={{
            background: "white",
            borderRadius: "0.75rem",
            padding: "1rem",
            boxShadow: "0 10px 25px rgba(0, 0, 0, 0.05)",
            marginBottom: "1rem",
          }}
        >
          {/* Error crítico (por ejemplo commit rechazado): arriba y dominante */}
          {errorMsg && (
            <ErrorBanner
              title="La importación fue rechazada"
              message={errorMsg}
            />
          )}

          <div style={{ fontWeight: 600, marginBottom: "0.75rem" }}>
            2) Preview
          </div>

          {summary && (
            <>
              {/* TOP: Impacto / Calidad / Riesgos */}
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))",
                  gap: "0.75rem",
                  marginBottom: "1rem",
                }}
              >
                <KpiCard
                  title="Impacto (lo que se va a crear)"
                  accent={summary.quality.blocking_errors ? "muted" : "success"}
                  items={[
                    ["Clientes", summary.impact.customers_total],
                    ["Créditos", summary.impact.loans_total],
                    ["Pagos", summary.impact.payments_total],
                    [
                      "Cuotas a generar",
                      summary.impact.installments_to_generate_total,
                    ],
                    ["Total adeudado", summary.impact.loans_total_due_sum],
                    ["Total pagado", summary.impact.payments_total_amount],
                    ["% pagado (estimado)", summary.impact.estimated_paid_ratio],
                  ]}
                  formatters={{
                    "Total adeudado": fmtMoney,
                    "Total pagado": fmtMoney,
                    "% pagado (estimado)": fmtPct,
                  }}
                />

                <KpiCard
                  title="Calidad del archivo"
                  accent={summary.quality.blocking_errors ? "danger" : "success"}
                  subtitle={
                    summary.quality.blocking_errors
                      ? "Corregí errores antes de confirmar."
                      : "Validación OK para importar."
                  }
                  items={[
                    ["Errores (bloquean)", summary.quality.errors_total],
                    ["Warnings", summary.quality.warnings_total],
                    [
                      "Customers (filas)",
                      summary.quality.by_sheet.Customers.rows,
                    ],
                    ["Loans (filas)", summary.quality.by_sheet.Loans.rows],
                    ["Payments (filas)", summary.quality.by_sheet.Payments.rows],
                  ]}
                />

                <KpiCard
                  title="Riesgos operativos"
                  accent={anyRisk(summary.risks) ? "warning" : "success"}
                  subtitle="No bloquea, pero conviene corregir antes de importar."
                  items={[
                    [
                      "Clientes sin DNI/tel/email",
                      summary.risks.customers_without_identifiers,
                    ],
                    [
                      "Créditos sin start_date",
                      summary.risks.loans_without_start_date,
                    ],
                    ["Créditos sin cobrador", summary.risks.loans_without_employee_email],
                    ["Pagos sin fecha", summary.risks.payments_without_payment_date],
                    ["Pagos sin cobrador", summary.risks.payments_without_collector_email],
                  ]}
                />
              </div>

              {/* SECUNDARIO: Cobertura y Consistencia */}
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "repeat(auto-fit, minmax(380px, 1fr))",
                  gap: "0.75rem",
                  marginBottom: "1rem",
                }}
              >
                <DetailCard
                  title="Cobertura de datos"
                  rows={[
                    [
                      "Clientes con DNI",
                      `${summary.coverage.customers.with_dni}/${summary.impact.customers_total}`,
                    ],
                    [
                      "Clientes con teléfono",
                      `${summary.coverage.customers.with_phone}/${summary.impact.customers_total}`,
                    ],
                    [
                      "Clientes con dirección",
                      `${summary.coverage.customers.with_address}/${summary.impact.customers_total}`,
                    ],
                    [
                      "Créditos con cobrador",
                      `${summary.coverage.loans.with_employee_email}/${summary.impact.loans_total}`,
                    ],
                    [
                      "Pagos con cobrador",
                      `${summary.coverage.payments.with_collector_email}/${summary.impact.payments_total}`,
                    ],
                    [
                      "Pagos con tipo",
                      `${summary.coverage.payments.with_payment_type}/${summary.impact.payments_total}`,
                    ],
                  ]}
                />

                <DetailCard
                  title="Consistencia (refs y números)"
                  rows={[
                    [
                      "Refs duplicadas (customer_ref)",
                      summary.consistency.duplicate_refs.customer_ref,
                    ],
                    [
                      "Refs duplicadas (loan_ref)",
                      summary.consistency.duplicate_refs.loan_ref,
                    ],
                    [
                      "Refs duplicadas (payment_ref)",
                      summary.consistency.duplicate_refs.payment_ref,
                    ],
                    [
                      "Loans sin customer_ref válido",
                      summary.consistency.dangling_refs.loans_missing_customer,
                    ],
                    [
                      "Payments sin loan_ref válido",
                      summary.consistency.dangling_refs.payments_missing_loan,
                    ],
                    [
                      "Mismatch total_due vs cuotas",
                      `${summary.consistency.loan_amount_mismatches.count} (tol ${summary.consistency.loan_amount_mismatches.tolerance})`,
                    ],
                  ]}
                />
              </div>
            </>
          )}

          <div style={{ display: "flex", gap: "0.75rem", flexWrap: "wrap" }}>
            <button
              onClick={handleCommit}
              disabled={committing || hasErrors}
              style={{
                padding: "0.45rem 0.9rem",
                borderRadius: "9999px",
                border: "none",
                background: committing || hasErrors ? "#9ca3af" : "#16a34a",
                color: "white",
                fontSize: "0.9rem",
                fontWeight: 600,
                cursor: committing || hasErrors ? "not-allowed" : "pointer",
              }}
              title={
                hasErrors
                  ? "Corregí los errores antes de confirmar"
                  : "Confirmar importación"
              }
            >
              {committing ? "Importando..." : "Confirmar importación"}
            </button>

            {errors.length > 0 && (
              <button
                onClick={() =>
                  downloadCsv(
                    `onboarding_errors_company_${companyId}.csv`,
                    errors.map((e) => ({
                      sheet: e.sheet,
                      row: e.row,
                      field: e.field ?? "",
                      code: e.code,
                      message: e.message,
                    }))
                  )
                }
                style={{
                  padding: "0.45rem 0.9rem",
                  borderRadius: "9999px",
                  border: "1px solid #d1d5db",
                  background: "white",
                  cursor: "pointer",
                  fontSize: "0.9rem",
                }}
              >
                Descargar errores (CSV)
              </button>
            )}

            {warnings.length > 0 && (
              <button
                onClick={() =>
                  downloadCsv(
                    `onboarding_warnings_company_${companyId}.csv`,
                    warnings.map((w) => ({
                      sheet: w.sheet,
                      row: w.row,
                      field: w.field ?? "",
                      code: w.code,
                      message: w.message,
                    }))
                  )
                }
                style={{
                  padding: "0.45rem 0.9rem",
                  borderRadius: "9999px",
                  border: "1px solid #d1d5db",
                  background: "white",
                  cursor: "pointer",
                  fontSize: "0.9rem",
                }}
              >
                Descargar warnings (CSV)
              </button>
            )}
          </div>

          <div style={{ marginTop: "1rem" }}>
            {errors.length > 0 && (
              <IssuesTable title="Errores" issues={errors} tone="danger" />
            )}
            {warnings.length > 0 && (
              <IssuesTable title="Warnings" issues={warnings} tone="warning" />
            )}
            {errors.length === 0 && warnings.length === 0 && !errorMsg && (
              <div style={{ color: "#166534" }}>
                Validación OK. Podés confirmar la importación.
              </div>
            )}
          </div>
        </section>
      )}

      {/* Card: Result */}
      {commitResp && (
        <section
          style={{
            background: "white",
            borderRadius: "0.75rem",
            padding: "1rem",
            boxShadow: "0 10px 25px rgba(0, 0, 0, 0.05)",
          }}
        >
          <div style={{ fontWeight: 600, marginBottom: "0.5rem" }}>
            3) Resultado
          </div>
          <div style={{ fontSize: "0.95rem" }}>
            Importación confirmada. Batch ID: <b>{commitResp.import_batch_id}</b>
          </div>

          {commitResp.created_counts && (
            <div style={{ marginTop: "0.75rem", color: "#374151" }}>
              <div style={{ fontWeight: 700, marginBottom: "0.25rem" }}>
                Conteos creados
              </div>
              <ul style={{ margin: 0, paddingLeft: "1.25rem" }}>
                <li>Clientes: {commitResp.created_counts.customers_created}</li>
                <li>Créditos: {commitResp.created_counts.loans_created}</li>
                <li>Cuotas: {commitResp.created_counts.installments_created}</li>
                <li>Pagos: {commitResp.created_counts.payments_created}</li>
                <li>
                  Allocations:{" "}
                  {commitResp.created_counts.payment_allocations_created}
                </li>
              </ul>
            </div>
          )}

          {commitResp.created_ids && (
            <div style={{ marginTop: "0.75rem", color: "#374151" }}>
              <div style={{ fontWeight: 600, marginBottom: "0.25rem" }}>
                Creados
              </div>
              <ul style={{ margin: 0, paddingLeft: "1.25rem" }}>
                {Object.entries(commitResp.created_ids).map(([k, v]) => (
                  <li key={k}>
                    {k}: {v}
                  </li>
                ))}
              </ul>
            </div>
          )}
        </section>
      )}
    </div>
  );
}

function KpiCard({
  title,
  subtitle,
  items,
  accent,
  formatters,
}: {
  title: string;
  subtitle?: string;
  items: Array<[string, any]>;
  accent: "danger" | "warning" | "success" | "muted";
  formatters?: Record<string, (v: any) => string>;
}) {
  const accentMap: Record<string, { border: string; title: string; sub: string }> =
    {
      danger: { border: "#fecaca", title: "#991b1b", sub: "#7f1d1d" },
      warning: { border: "#fde68a", title: "#92400e", sub: "#78350f" },
      success: { border: "#bbf7d0", title: "#166534", sub: "#14532d" },
      muted: { border: "#e5e7eb", title: "#111827", sub: "#374151" },
    };

  const c = accentMap[accent];

  return (
    <div
      style={{
        border: `1px solid ${c.border}`,
        borderRadius: "0.75rem",
        padding: "0.9rem",
      }}
    >
      <div
        style={{
          fontWeight: 800,
          marginBottom: "0.25rem",
          color: c.title,
        }}
      >
        {title}
      </div>
      {subtitle && (
        <div
          style={{
            fontSize: "0.85rem",
            color: c.sub,
            marginBottom: "0.6rem",
          }}
        >
          {subtitle}
        </div>
      )}
      <div style={{ display: "grid", gap: "0.35rem" }}>
        {items.map(([label, value]) => {
          const fmt = formatters?.[label];
          const display = fmt
            ? fmt(value)
            : typeof value === "number"
            ? value
            : String(value ?? "");
          return (
            <div
              key={label}
              style={{
                display: "flex",
                justifyContent: "space-between",
                fontSize: "0.92rem",
                color: "#111827",
              }}
            >
              <span style={{ color: "#374151" }}>{label}</span>
              <span
                style={{
                  fontVariantNumeric: "tabular-nums",
                  fontWeight: 700,
                }}
              >
                {display}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function DetailCard({
  title,
  rows,
}: {
  title: string;
  rows: Array<[string, any]>;
}) {
  return (
    <div
      style={{
        border: "1px solid #e5e7eb",
        borderRadius: "0.75rem",
        padding: "0.9rem",
      }}
    >
      <div style={{ fontWeight: 800, marginBottom: "0.6rem" }}>{title}</div>
      <div style={{ display: "grid", gap: "0.4rem" }}>
        {rows.map(([label, value]) => (
          <div
            key={label}
            style={{
              display: "flex",
              justifyContent: "space-between",
              fontSize: "0.92rem",
              color: "#111827",
            }}
          >
            <span style={{ color: "#374151" }}>{label}</span>
            <span style={{ fontVariantNumeric: "tabular-nums" }}>
              {String(value)}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function IssuesTable({
  title,
  issues,
  tone,
}: {
  title: string;
  issues: ImportIssue[];
  tone: "danger" | "warning";
}) {
  const headerBg = tone === "danger" ? "#fef2f2" : "#fffbeb";
  const headerColor = tone === "danger" ? "#991b1b" : "#92400e";

  return (
    <div style={{ marginTop: "1rem" }}>
      <div
        style={{
          fontWeight: 700,
          marginBottom: "0.5rem",
          color: headerColor,
        }}
      >
        {title} ({issues.length})
      </div>
      <div
        style={{
          overflowX: "auto",
          border: "1px solid #e5e7eb",
          borderRadius: "0.75rem",
        }}
      >
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ background: headerBg }}>
              <th style={thStyle}>Hoja</th>
              <th style={thStyle}>Fila</th>
              <th style={thStyle}>Campo</th>
              <th style={thStyle}>Código</th>
              <th style={thStyle}>Mensaje</th>
            </tr>
          </thead>
          <tbody>
            {issues.map((it, idx) => (
              <tr key={`${it.sheet}-${it.row}-${idx}`}>
                <td style={tdStyle}>{it.sheet}</td>
                <td style={tdStyle}>{it.row}</td>
                <td style={tdStyle}>{it.field ?? "-"}</td>
                <td style={tdStyle}>
                  <code>{it.code}</code>
                </td>
                <td style={tdStyle}>{it.message}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

const thStyle: React.CSSProperties = {
  padding: "0.65rem 0.75rem",
  textAlign: "left",
  borderBottom: "1px solid #e5e7eb",
  fontSize: "0.85rem",
  whiteSpace: "nowrap",
};

const tdStyle: React.CSSProperties = {
  padding: "0.6rem 0.75rem",
  borderBottom: "1px solid #f3f4f6",
  fontSize: "0.9rem",
};
