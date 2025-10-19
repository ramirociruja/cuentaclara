import 'dart:typed_data';
import 'package:frontend/models/installment.dart';
import 'package:frontend/models/loan.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/shared/status.dart' as st;

class ReceiptService {
  static final _money = NumberFormat.currency(locale: 'es_AR', symbol: r'$');
  static final _date = DateFormat('dd/MM/yyyy HH:mm');

  /// =========================================
  /// ========== RECIBO DE PAGO (OK) ==========
  /// =========================================

  static Future<void> shareReceiptByPaymentId(
    BuildContext context,
    int paymentId,
  ) async {
    final payment = await ApiService.getPayment(paymentId);
    List<Map<String, dynamic>> allocations = const [];
    try {
      allocations = await ApiService.getPaymentAllocations(paymentId);
    } catch (_) {}

    final pdfBytes = await _buildPaymentReceiptPdf(
      payment: payment,
      allocations: allocations,
    );

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'recibo_pago_$paymentId.pdf',
    );
  }

  static Future<Uint8List> _buildPaymentReceiptPdf({
    required Map<String, dynamic> payment,
    required List<Map<String, dynamic>> allocations,
  }) async {
    final doc = pw.Document();

    // ===== Helpers =====
    T? _as<T>(dynamic v) => v is T ? v : null;
    String _str(dynamic v) => v == null ? '-' : v.toString();
    String _fmtMoney(dynamic v) {
      if (v == null) return '-';
      final n = (v is num) ? v.toDouble() : double.tryParse('$v');
      return n == null ? _str(v) : _money.format(n);
    }

    String _fmtDate(dynamic v) {
      if (v == null) return '-';
      try {
        final dt = v is DateTime ? v : DateTime.parse(v.toString());
        return _date.format(dt);
      } catch (_) {
        return _str(v);
      }
    }

    String _methodLabel(String? m) {
      switch ((m ?? '').toLowerCase()) {
        case 'cash':
          return 'Efectivo';
        case 'transfer':
          return 'Transferencia';
        case 'other':
          return 'Otro';
        default:
          return '-';
      }
    }

    // ===== Datos =====
    final paymentId = _as<num>(payment['id'])?.toInt();
    final amount = payment['amount'];
    final paymentDate = payment['payment_date'] ?? payment['created_at'];
    final method = _as<String>(payment['payment_type']);
    final description = payment['description'];
    final receiptNumber = _as<String>(payment['receipt_number']);

    final customerName = _as<String>(payment['customer_name']);
    final customerDoc = _firstNonEmpty(payment, [
      'customer_doc',
      'customer_dni',
      'dni',
      'document',
      'document_number',
    ]);
    final customerPhone = _as<String>(payment['customer_phone']);
    final collector = _as<String>(payment['collector_name']);

    final companyName = _as<String>(payment['company_name']);
    final companyCUIT = _as<String>(payment['company_cuit']);

    // ===== Estilos / colores =====
    final base = pw.Font.helvetica();
    final bold = pw.Font.helveticaBold();

    final titleStyle = pw.TextStyle(font: bold, fontSize: 13);
    final kvLabel = pw.TextStyle(color: pdfGrey600, fontSize: 11);
    final kvValue = pw.TextStyle(font: bold, fontSize: 11);
    final small = pw.TextStyle(fontSize: 9, color: pdfGrey600);

    pw.Widget sep([double h = 8]) => pw.SizedBox(height: h);

    pw.Widget card(pw.Widget child) => pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: pdfGrey300),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: child,
    );

    pw.Widget kvRow(String k, String v) => pw.Table(
      columnWidths: {
        0: const pw.FixedColumnWidth(140),
        1: const pw.FlexColumnWidth(),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(k, style: kvLabel),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(v, style: kvValue),
            ),
          ],
        ),
      ],
    );

    // ===== Secciones =====
    pw.Widget header() => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: pw.BoxDecoration(
            color: pdfPrimary,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Text(
            'COMPROBANTE DE PAGO',
            style: pw.TextStyle(font: bold, color: pdfWhite, fontSize: 16),
          ),
        ),
        sep(10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Recibo N°: ${receiptNumber ?? paymentId?.toString() ?? '-'}',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.Text(
              'Fecha: ${_fmtDate(paymentDate)}',
              style: const pw.TextStyle(fontSize: 11),
            ),
          ],
        ),
        if (collector != null) ...[
          sep(4),
          pw.Text(
            'Cobrador: $collector',
            style: const pw.TextStyle(fontSize: 11),
          ),
        ],
      ],
    );

    pw.Widget sectionPago() => card(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Detalle del Pago', style: titleStyle),
          sep(8),
          kvRow('Prestamo', payment['reference']),
          kvRow('Monto', _fmtMoney(amount)),
          kvRow('Método', _methodLabel(method)),
          if (_str(description) != '-') kvRow('Referencia', _str(description)),
        ],
      ),
    );

    pw.Widget sectionCliente() => card(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Datos del Cliente', style: titleStyle),
          sep(8),
          kvRow('Nombre', _str(customerName)),
          kvRow('Documento', _str(customerDoc)),
          kvRow('Teléfono', _str(customerPhone)),
        ],
      ),
    );

    pw.Widget sectionAplicacion() {
      if (allocations.isEmpty) {
        return card(
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Aplicación del Pago', style: titleStyle),
              sep(8),
              pw.Text(
                'Sin información de asignación disponible',
                style: kvLabel,
              ),
            ],
          ),
        );
      }

      final rows = allocations.map((a) {
        final n = _str(a['installment_number']);
        final applied = _fmtMoney(a['applied']);
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            children: [
              pw.SizedBox(
                width: 120,
                child: pw.Text('Cuota #$n', style: kvLabel),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(child: pw.Text(applied, style: kvValue)),
            ],
          ),
        );
      });

      return card(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Aplicación del Pago', style: titleStyle),
            sep(8),
            ...rows,
          ],
        ),
      );
    }

    pw.Widget footer() => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Divider(color: pdfGrey300, thickness: 1),
        if (companyName != null) pw.Text('Empresa: $companyName', style: small),
        if (companyCUIT != null) pw.Text('CUIT: $companyCUIT', style: small),
        sep(2),
        pw.Text(
          'Generado automáticamente por el sistema CuentaClara',
          style: small,
        ),
      ],
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 50),
          theme: pw.ThemeData.withFont(base: base, bold: bold),
        ),
        build:
            (_) => [
              pw.Center(
                child: pw.ConstrainedBox(
                  constraints: const pw.BoxConstraints(maxWidth: 520),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      header(),
                      pw.SizedBox(height: 24),
                      sectionPago(),
                      pw.SizedBox(height: 18),
                      sectionCliente(),
                      pw.SizedBox(height: 18),
                      sectionAplicacion(),
                      pw.SizedBox(height: 30),
                      footer(),
                    ],
                  ),
                ),
              ),
            ],
      ),
    );

    return doc.save();
  }

  /// =========================================
  /// ======== COMPROBANTE ESTADO CRÉDITO =====
  /// =========================================

  static Future<void> shareLoanStatementByLoanId(
    BuildContext context,
    int loanId, {
    String? collectorName,
    String? creatorName,
  }) async {
    // 1) Traer préstamo
    final loan = await ApiService.fetchLoanDetails(loanId);

    // 2) Traer nombre del cliente (si podemos)
    String? customerName;
    try {
      final customer = await ApiService.fetchCustomerById(loan.customerId);
      customerName = customer.name;
    } catch (_) {
      customerName = null;
    }

    // 3) Traer nombre de la empresa usando SIEMPRE ApiService.getCompanyName()
    final companyName = (await ApiService.getCompanyName()) ?? '-';

    // 4) Traer pagos e impactaciones para el historial
    final payments = await ApiService.fetchPaymentsByLoan(loanId);

    // allocations por pago: {paymentId: [installment_numbers]}
    final Map<int, List<int>> impactedByPayment = {};
    for (final p in payments) {
      final pid = (p['id'] as num?)?.toInt();
      if (pid == null) continue;
      try {
        final allocs = await ApiService.getPaymentAllocations(pid);
        final nums = <int>[];
        for (final a in allocs) {
          int? n = (a['installment_number'] as num?)?.toInt();
          if (n == null) {
            final inst = a['installment'];
            if (inst is Map) n = (inst['number'] as num?)?.toInt();
          }
          n ??= (a['number'] as num?)?.toInt();
          if (n != null) nums.add(n);
        }
        if (nums.isNotEmpty) impactedByPayment[pid] = nums..sort();
      } catch (_) {}
    }

    final pdfBytes = await _buildLoanStatementPdf(
      loan,
      collectorName: collectorName,
      creatorName: creatorName,
      customerName: customerName,
      companyName: companyName,
      payments: payments,
      impactedByPayment: impactedByPayment,
    );

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'estado_credito_$loanId.pdf',
    );
  }

  static Future<Uint8List> _buildLoanStatementPdf(
    Loan loan, {
    String? collectorName,
    String? creatorName,
    String? customerName,
    String? companyName,
    List<Map<String, dynamic>> payments = const [],
    Map<int, List<int>> impactedByPayment = const {},
  }) async {
    final doc = pw.Document();

    // ===== Helpers =====
    final money = NumberFormat.currency(locale: 'es_AR', symbol: r'$');
    final df = DateFormat('dd/MM/yyyy');
    String fmtMoney(num v) => money.format(v.toDouble());
    String fmtDateStr(String iso) {
      try {
        final d = DateTime.parse(iso);
        return df.format(d);
      } catch (_) {
        return iso;
      }
    }

    String fmtDate(DateTime d) => df.format(d);

    // ===== Datos principales
    final total = loan.amount;
    final pending = loan.totalDue;
    final paid = (total - pending).clamp(0, total);

    // cuotas orden 1..n (y estado derivado robusto)
    final installments = [...loan.installments]
      ..sort((a, b) => a.number.compareTo(b.number));

    // === usar normalizador de cuota para considerar "Pagada"
    bool _isPaidInstallment(Installment i) {
      final label = st.normalizeInstallmentStatus(i.status);
      return i.isPaid || label == st.kCuotaPagada;
    }

    final paidCount = installments.where(_isPaidInstallment).length;
    final overdueCount =
        installments.where((i) => i.isOverdue && !_isPaidInstallment(i)).length;
    final freqLabel = loan.frequency == 'weekly' ? 'Semanal' : 'Mensual';

    final nextPending = installments.firstWhere(
      (i) => !_isPaidInstallment(i),
      orElse:
          () =>
              installments.isNotEmpty
                  ? installments.last
                  : Installment(
                    id: 0,
                    amount: 0,
                    dueDate: DateTime.now(),
                    status: '-',
                    isPaid: true,
                    isOverdue: false,
                    number: 0,
                    paidAmount: 0,
                  ),
    );

    // Estado del CRÉDITO: normalizado por función de Loan
    final estadoEs = st.normalizeLoanStatus(loan.status);
    final estadoColor = _statusPdfColor(estadoEs);
    final cobrador =
        (collectorName ?? '-').trim().isEmpty ? '-' : collectorName!;
    final cliente = (customerName ?? '-').trim().isEmpty ? '-' : customerName!;
    final company = (companyName ?? '-').trim().isNotEmpty ? companyName! : '-';

    // ===== Estilos/colores
    const primary = PdfColor.fromInt(0xFF3366CC);
    const band = PdfColor.fromInt(0xFFEDF2FF);
    const chipBg = PdfColor.fromInt(0xFFEFF6FF);
    const zebra = PdfColor.fromInt(0xFFF8FAFC);

    pw.Widget pill(String text, {PdfColor? fg}) =>
        _pill(text, fg: fg, bg: chipBg);

    // ===== Página
    doc.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 28),
        build:
            (context) => [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: band,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(width: 8, height: 36, color: primary),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Comprobante / Estado de Crédito #${loan.id}',
                            style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                              color: primary,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            df.format(DateTime.now()),
                            style: const pw.TextStyle(
                              fontSize: 10,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pill(estadoEs, fg: estadoColor),
                  ],
                ),
              ),

              pw.SizedBox(height: 12),

              // SOLO Datos del crédito (compacto + separadores) — SIN "Vinculaciones"
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
                ),
                child: _kvListCompact([
                  ['Cliente', cliente],
                  ['Cobrador', cobrador],
                  ['Estado', estadoEs],
                  ['Monto otorgado', fmtMoney(total)],
                  ['Saldo pendiente', fmtMoney(pending)],
                  ['Total pagado', fmtMoney(paid)],
                  ['Cuotas (totales)', '${loan.installmentsCount}'],
                  ['Cuotas pagadas', '$paidCount'],
                  ['Cuotas vencidas', '$overdueCount'],
                  ['Frecuencia', freqLabel],
                  ['Fecha de inicio', fmtDateStr(loan.startDate)],
                  ['Día de cobro', _dayNameEs(loan.collectionDay)],
                  if (loan.description != null &&
                      loan.description!.trim().isNotEmpty)
                    ['Descripción', loan.description!.trim()],
                ]),
              ),

              pw.SizedBox(height: 12),

              // Próxima cuota
              if (!_isPaidInstallment(nextPending))
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Próxima cuota #${nextPending.number}',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey800,
                        ),
                      ),
                      pw.Row(
                        children: [
                          pill(
                            'Monto: ${fmtMoney(nextPending.amount)}',
                            fg: PdfColors.blue800,
                          ),
                          pw.SizedBox(width: 6),
                          pill(
                            'Vence: ${fmtDate(nextPending.dueDate)}',
                            fg: PdfColors.blue800,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              pw.SizedBox(height: 12),

              // Detalle de cuotas
              pw.Text(
                'Detalle de cuotas',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: primary,
                ),
              ),
              pw.SizedBox(height: 6),
              _tableUnified(
                headers: const [
                  '#',
                  'Vencimiento',
                  'Monto',
                  'Pagado',
                  'Estado',
                ],
                columnWidths: const {
                  0: pw.FixedColumnWidth(24),
                  1: pw.FixedColumnWidth(80),
                  2: pw.FixedColumnWidth(64),
                  3: pw.FixedColumnWidth(64),
                  4: pw.FlexColumnWidth(),
                },
                rows: List.generate(installments.length, (idx) {
                  final i = installments[idx];
                  final statusEs =
                      _isPaidInstallment(i)
                          ? st.kCuotaPagada
                          : (i.isOverdue
                              ? st.kCuotaVencida
                              : st.normalizeInstallmentStatus(i.status));
                  return [
                    '${i.number}',
                    fmtDate(i.dueDate),
                    fmtMoney(i.amount),
                    fmtMoney(i.paidAmount),
                    statusEs,
                  ];
                }),
                zebraRow: zebra,
                forceNoWrapCols: const {1},
              ),

              pw.SizedBox(height: 14),

              // Historial de pagos
              pw.Text(
                'Historial de pagos',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: primary,
                ),
              ),
              pw.SizedBox(height: 6),
              _tableUnified(
                headers: const [
                  'Fecha',
                  'Monto',
                  'Método',
                  'Cuota impactada',
                  'Referencia',
                ],
                columnWidths: const {
                  0: pw.FixedColumnWidth(90),
                  1: pw.FixedColumnWidth(64),
                  2: pw.FixedColumnWidth(64),
                  3: pw.FixedColumnWidth(80),
                  4: pw.FlexColumnWidth(),
                },
                rows:
                    payments.map((p) {
                      final dtStr =
                          (p['payment_date'] ?? p['created_at'])?.toString();
                      DateTime? dt;
                      try {
                        dt = dtStr != null ? DateTime.parse(dtStr) : null;
                      } catch (_) {}
                      final fecha =
                          dt != null ? _date.format(dt) : (dtStr ?? '-');

                      final monto = (p['amount'] as num?)?.toDouble() ?? 0.0;
                      final metodo =
                          (() {
                            final m =
                                (p['payment_type'] ?? '')
                                    .toString()
                                    .toLowerCase();
                            if (m == 'cash') return 'Efectivo';
                            if (m == 'transfer') return 'Transferencia';
                            if (m == 'other') return 'Otro';
                            return '-';
                          })();

                      final pid = (p['id'] as num?)?.toInt();
                      String cuotaImpactada = '-';
                      if (pid != null && impactedByPayment.containsKey(pid)) {
                        final nums = impactedByPayment[pid]!;
                        cuotaImpactada = nums.isEmpty ? '-' : nums.join(', ');
                      }

                      final ref = (p['description'] ?? '').toString().trim();

                      return [
                        fecha,
                        fmtMoney(monto),
                        metodo,
                        cuotaImpactada,
                        ref.isEmpty ? '-' : ref,
                      ];
                    }).toList(),
                zebraRow: zebra,
              ),

              pw.SizedBox(height: 16),

              // Footer
              pw.Divider(color: pdfGrey300, thickness: 1),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Empresa: $company',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Generado automáticamente por el sistema CuentaClara',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
      ),
    );

    return await doc.save();
  }

  /// ===== Tabla unificada
  static pw.Widget _tableUnified({
    required List<String> headers,
    required List<List<String>> rows,
    required Map<int, pw.TableColumnWidth> columnWidths,
    PdfColor zebraRow = const PdfColor.fromInt(0xFFF8FAFC),
    Set<int> forceNoWrapCols = const {},
  }) {
    final tableRows = <pw.TableRow>[];

    // Header
    tableRows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEAEAEA)),
        children: List.generate(headers.length, (c) {
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: pw.Text(
              headers[c],
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          );
        }),
      ),
    );

    // Body
    for (int r = 0; r < rows.length; r++) {
      final bg = r.isOdd ? zebraRow : PdfColors.white;
      tableRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: bg),
          children: List.generate(rows[r].length, (c) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 6,
                horizontal: 6,
              ),
              child: pw.Text(
                rows[r][c],
                maxLines: forceNoWrapCols.contains(c) ? 1 : null,
                overflow:
                    forceNoWrapCols.contains(c) ? pw.TextOverflow.clip : null,
                style: const pw.TextStyle(fontSize: 9),
              ),
            );
          }),
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.25, color: PdfColors.grey300),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: columnWidths,
      children: tableRows,
    );
  }

  /// Lista Key-Value compacta con separadores finos
  static pw.Widget _kvListCompact(List<List<String>> items) {
    final children = <pw.Widget>[];
    for (int i = 0; i < items.length; i++) {
      final pair = items[i];
      children.add(_kv(pair[0], pair[1], verticalPad: 2)); // compacto
      if (i < items.length - 1) {
        children.add(pw.Divider(color: PdfColors.grey300, thickness: 0.4));
      }
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    );
  }

  // ================== Helpers locales (status/día/kv/pill) ==================

  // Estado del CRÉDITO (usa normalizador de Loan del front)

  // (Solo por si en el futuro la necesitás en este archivo)

  static PdfColor _statusPdfColor(String statusEs) {
    final flutterColor = st.installmentStatusColor(statusEs);
    return PdfColor.fromInt(flutterColor.value);
  }

  static String _dayNameEs(int? isoDay) {
    switch (isoDay) {
      case 1:
        return 'Lunes';
      case 2:
        return 'Martes';
      case 3:
        return 'Miércoles';
      case 4:
        return 'Jueves';
      case 5:
        return 'Viernes';
      case 6:
        return 'Sábado';
      case 7:
        return 'Domingo';
      default:
        return '-';
    }
  }

  static pw.Widget _pill(
    String text, {
    PdfColor? fg,
    PdfColor bg = const PdfColor.fromInt(0xFFEFF6FF),
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(24),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: fg ?? const PdfColor.fromInt(0xFF1D4ED8),
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _kv(String k, String v, {double verticalPad = 4}) {
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(vertical: verticalPad),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 5,
            child: pw.Text(
              k,
              style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 10),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            flex: 7,
            child: pw.Text(
              v,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ====== COLORES PDF ======
final pdfWhite = PdfColor.fromInt(0xFFFFFFFF);
final pdfPrimary = PdfColor.fromInt(0xFF3366CC);
final pdfGrey300 = PdfColor.fromInt(0xFFD6D6D6);
final pdfGrey600 = PdfColor.fromInt(0xFF666666);
final pdfGrey700 = PdfColor.fromInt(0xFF4D4D4D);

String? _firstNonEmpty(Map src, List<String> keys) {
  for (final k in keys) {
    final v = src[k];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty && s != 'null') return s;
  }
  return null;
}
