// src/shared/status.ts
import * as React from "react";
import { Chip } from "@mui/material";

/** ===============================
 *  Etiquetas (UI) — Español
 * =============================== */

// Cuotas
export const kCuotaPendiente = "Pendiente";
export const kCuotaParcial = "Parcialmente pagada";
export const kCuotaPagada = "Pagada";
export const kCuotaVencida = "Vencida";
export const kCuotaCancelada = "Cancelada";
export const kCuotaRefinanciada = "Refinanciada";

// Préstamos
export const kPrestamoActivo = "Activo";
export const kPrestamoPagado = "Pagado";
export const kPrestamoIncumplido = "Incumplido";
export const kPrestamoCancelado = "Cancelado";
export const kPrestamoRefinanciado = "Refinanciado";

/** ===============================
 *  Normalizadores desde API/legacy
 *  (aceptan EN canónico o ES legacy y devuelven etiqueta ES para UI)
 * =============================== */

// ---- Cuotas
export function normalizeInstallmentStatus(raw?: string | null): string {
  const s = (raw ?? "").trim().toLowerCase();
  if (!s) return kCuotaPendiente;

  // EN canónico → ES
  if (s === "pending") return kCuotaPendiente;
  if (s === "partial" || s === "partially paid" || s === "partially_paid") return kCuotaParcial;
  if (s === "paid") return kCuotaPagada;
  if (s === "overdue") return kCuotaVencida;
  if (s === "canceled" || s === "cancelled") return kCuotaCancelada;
  if (s === "refinanced") return kCuotaRefinanciada;

  // ES legacy → ES UI
  if (s === "pendiente") return kCuotaPendiente;
  if (s === "parcialmente pagada" || s === "parcial") return kCuotaParcial;
  if (s === "pagada" || s === "pagado") return kCuotaPagada;
  if (s === "vencida" || s === "vencido") return kCuotaVencida;
  if (s === "cancelada" || s === "cancelado") return kCuotaCancelada;
  if (s === "refinanciada" || s === "refinanciado") return kCuotaRefinanciada;

  // fallback
  return raw ? raw[0].toUpperCase() + raw.substring(1) : kCuotaPendiente;
}

// ---- Préstamos
export function normalizeLoanStatus(raw?: string | null): string {
  const s = (raw ?? "").trim().toLowerCase();
  if (!s) return kPrestamoActivo;

  // EN canónico → ES
  if (s === "active") return kPrestamoActivo;
  if (s === "paid") return kPrestamoPagado;
  if (s === "defaulted") return kPrestamoIncumplido;
  if (s === "canceled" || s === "cancelled") return kPrestamoCancelado;
  if (s === "refinanced") return kPrestamoRefinanciado;

  // ES legacy → ES UI
  if (s === "activo") return kPrestamoActivo;
  if (s === "pagado" || s === "pagada") return kPrestamoPagado;
  if (s === "incumplido" || s === "en mora") return kPrestamoIncumplido;
  if (s === "cancelado" || s === "cancelada") return kPrestamoCancelado;
  if (s === "refinanciado" || s === "refinanciada") return kPrestamoRefinanciado;

  return raw ? raw[0].toUpperCase() + raw.substring(1) : kPrestamoActivo;
}

/** ===============================
 *  Canonicalizadores para enviar a la API
 *  (de etiqueta ES o EN a EN canónico)
 * =============================== */

export function toCanonicalInstallmentStatus(raw?: string | null): string {
  const s = (raw ?? "").trim().toLowerCase();
  if (!s) return "pending";
  switch (s) {
    case "pendiente":
    case "pending":
      return "pending";
    case "parcialmente pagada":
    case "parcial":
    case "partial":
    case "partially paid":
      return "partial";
    case "pagada":
    case "pagado":
    case "paid":
      return "paid";
    case "vencida":
    case "vencido":
    case "overdue":
      return "overdue";
    case "cancelada":
    case "cancelado":
    case "canceled":
    case "cancelled":
      return "canceled";
    case "refinanciada":
    case "refinanciado":
    case "refinanced":
      return "refinanced";
    default:
      return "pending";
  }
}

export function toCanonicalLoanStatus(raw?: string | null): string {
  const s = (raw ?? "").trim().toLowerCase();
  if (!s) return "active";
  switch (s) {
    case "activo":
    case "active":
      return "active";
    case "pagado":
    case "pagada":
    case "paid":
      return "paid";
    case "incumplido":
    case "en mora":
    case "defaulted":
      return "defaulted";
    case "cancelado":
    case "cancelada":
    case "canceled":
    case "cancelled":
      return "canceled";
    case "refinanciado":
    case "refinanciada":
    case "refinanced":
      return "refinanced";
    default:
      return "active";
  }
}

/** ===============================
 *  Chips/visual (Material UI)
 *  Usamos color semántico (success/warning/error/info/default)
 * =============================== */

type MuiChipColor = "default" | "primary" | "secondary" | "error" | "info" | "success" | "warning";

export function loanStatusChipColor(statusLabelEs: string): MuiChipColor {
  const s = statusLabelEs.toLowerCase();
  switch (s) {
    case "pagado":
      return "success";
    case "incumplido":
      return "error";
    case "activo":
      return "info";
    case "cancelado":
      return "default";
    case "refinanciado":
      return "warning";
    default:
      return "info";
  }
}

export function installmentStatusChipColor(statusLabelEs: string): MuiChipColor {
  const s = statusLabelEs.toLowerCase();
  switch (s) {
    case "pagada":
      return "success";
    case "parcialmente pagada":
      return "warning";
    case "pendiente":
      return "info";
    case "vencida":
      return "error";
    case "cancelada":
      return "default";
    case "refinanciada":
      return "warning";
    default:
      return "info";
  }
}

/** Helpers listos para usar en RA FunctionField render */
export function LoanStatusChip({ raw }: { raw?: string | null }) {
  const label = normalizeLoanStatus(raw);
  return React.createElement(Chip, {
    size: "small",
    label: label,
    color: loanStatusChipColor(label),
    variant: "outlined"
  });
}

export function InstallmentStatusChip({ raw }: { raw?: string | null }) {
  const label = normalizeInstallmentStatus(raw);
  return React.createElement(Chip, {
    size: "small",
    label: label,
    color: installmentStatusChipColor(label),
    variant: "outlined"
  });
}


// ===============================
// Pagos — Métodos (UI) — Español
// ===============================
export const kPagoEfectivo = "Efectivo";
export const kPagoTransferencia = "Transferencia";
export const kPagoOtro = "Otro";

export function normalizePaymentType(raw?: string | null): string {
  const s = (raw ?? "").trim().toLowerCase();
  if (!s) return "-";

  // EN canónico → ES
  if (s === "cash" || s === "efectivo") return kPagoEfectivo;
  if (s === "transfer" || s === "transferencia") return kPagoTransferencia;
  if (s === "other" || s === "otro") return kPagoOtro;

  // fallback
  return raw ? raw[0].toUpperCase() + raw.substring(1) : "-";
}

// ===============================
// Pagos — Estado derivado
// ===============================
// Recomendación: "Aplicado" / "Anulado" (son claros para negocio y auditoría)
export const kPagoAplicado = "Aplicado";
export const kPagoAnulado = "Anulado";
