import 'package:flutter/material.dart';

/// ===============================
///  Etiquetas (UI) — Español
/// ===============================
/// Cuotas
const kCuotaPendiente = 'Pendiente';
const kCuotaParcial = 'Parcialmente pagada';
const kCuotaPagada = 'Pagada';
const kCuotaVencida = 'Vencida';
const kCuotaCancelada = 'Cancelada';
const kCuotaRefinanciada = 'Refinanciada';

/// Préstamos
const kPrestamoActivo = 'Activo';
const kPrestamoPagado = 'Pagado';
const kPrestamoIncumplido = 'Incumplido';
const kPrestamoCancelado = 'Cancelado';
const kPrestamoRefinanciado = 'Refinanciado';

/// ===============================
///  Normalizadores desde API/legacy
///  (aceptan EN canónico o ES legacy y devuelven etiqueta ES para UI)
/// ===============================

// ---- Cuotas
String normalizeInstallmentStatus(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return kCuotaPendiente;

  // EN canónico → ES
  if (s == 'pending') return kCuotaPendiente;
  if (s == 'partial' || s == 'partially paid') return kCuotaParcial;
  if (s == 'paid') return kCuotaPagada;
  if (s == 'overdue') return kCuotaVencida;
  if (s == 'canceled' || s == 'cancelled') return kCuotaCancelada;
  if (s == 'refinanced') return kCuotaRefinanciada;

  // ES legacy → ES UI
  if (s == 'pendiente') return kCuotaPendiente;
  if (s == 'parcialmente pagada' || s == 'parcial') return kCuotaParcial;
  if (s == 'pagada' || s == 'pagado') return kCuotaPagada;
  if (s == 'vencida' || s == 'vencido') return kCuotaVencida;
  if (s == 'cancelada' || s == 'cancelado') return kCuotaCancelada;
  if (s == 'refinanciada' || s == 'refinanciado') return kCuotaRefinanciada;

  // fallback: capitalizar mínimamente
  if (raw == null || raw.isEmpty) return kCuotaPendiente;
  return raw[0].toUpperCase() + raw.substring(1);
}

// ---- Préstamos
String normalizeLoanStatus(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return kPrestamoActivo;

  // EN canónico → ES
  if (s == 'active') return kPrestamoActivo;
  if (s == 'paid') return kPrestamoPagado;
  if (s == 'defaulted') return kPrestamoIncumplido;
  if (s == 'canceled' || s == 'cancelled') return kPrestamoCancelado;
  if (s == 'refinanced') return kPrestamoRefinanciado;

  // ES legacy → ES UI
  if (s == 'activo') return kPrestamoActivo;
  if (s == 'pagado' || s == 'pagada') return kPrestamoPagado;
  if (s == 'incumplido' || s == 'en mora') return kPrestamoIncumplido;
  if (s == 'cancelado' || s == 'cancelada') return kPrestamoCancelado;
  if (s == 'refinanciado' || s == 'refinanciada') return kPrestamoRefinanciado;

  if (raw == null || raw.isEmpty) return kPrestamoActivo;
  return raw[0].toUpperCase() + raw.substring(1);
}

/// ===============================
///  Canonicalizadores para enviar a la API
///  (de etiqueta ES o EN a EN canónico)
/// ===============================
String toCanonicalInstallmentStatus(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return 'pending';
  switch (s) {
    case 'pendiente':
    case 'pending':
      return 'pending';
    case 'parcialmente pagada':
    case 'parcial':
    case 'partial':
    case 'partially paid':
      return 'partial';
    case 'pagada':
    case 'pagado':
    case 'paid':
      return 'paid';
    case 'vencida':
    case 'vencido':
    case 'overdue':
      return 'overdue';
    case 'cancelada':
    case 'cancelado':
    case 'canceled':
    case 'cancelled':
      return 'canceled';
    case 'refinanciada':
    case 'refinanciado':
    case 'refinanced':
      return 'refinanced';
    default:
      return 'pending';
  }
}

String toCanonicalLoanStatus(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return 'active';
  switch (s) {
    case 'activo':
    case 'active':
      return 'active';
    case 'pagado':
    case 'pagada':
    case 'paid':
      return 'paid';
    case 'incumplido':
    case 'en mora':
    case 'defaulted':
      return 'defaulted';
    case 'cancelado':
    case 'cancelada':
    case 'canceled':
    case 'cancelled':
      return 'canceled';
    case 'refinanciado':
    case 'refinanciada':
    case 'refinanced':
      return 'refinanced';
    default:
      return 'active';
  }
}

/// ===============================
///  Helpers visuales (chips/colores)
/// ===============================
Color installmentStatusColor(String statusLabelEs) {
  final s = statusLabelEs.toLowerCase();
  const ok = Color(0xFF2E7D32); // verde
  const warn = Color(0xFFF9A825); // amarillo
  const danger = Color(0xFFC62828); // rojo
  const primary = Color(0xFF1565C0); // azul
  const neutral = Color(0xFF6D6D6D); // gris
  const info = Color(0xFF455A64); // blue-grey

  switch (s) {
    case 'pagada':
      return ok;
    case 'parcialmente pagada':
      return warn;
    case 'pendiente':
      return primary;
    case 'vencida':
      return danger;
    case 'cancelada':
      return neutral;
    case 'refinanciada':
      return info;
    default:
      return primary;
  }
}

Color loanStatusColor(String statusLabelEs) {
  final s = statusLabelEs.toLowerCase();
  const ok = Color(0xFF2E7D32);
  const danger = Color(0xFFC62828);
  const primary = Color(0xFF1565C0);
  const neutral = Color(0xFF6D6D6D);
  const info = Color(0xFF455A64);

  switch (s) {
    case 'pagado':
      return ok;
    case 'incumplido':
      return danger;
    case 'activo':
      return primary;
    case 'cancelado':
      return neutral;
    case 'refinanciado':
      return info;
    default:
      return primary;
  }
}
