import 'package:flutter/material.dart';
import 'package:frontend/utils/utils.dart';
import 'package:intl/intl.dart';
import 'package:frontend/services/api_service.dart';
// usa shareReceiptByPaymentId(context, id) si ya lo tenés

class PaymentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> payment;
  const PaymentDetailScreen({super.key, required this.payment});

  @override
  State<PaymentDetailScreen> createState() => _PaymentDetailScreenState();
}

class _PaymentDetailScreenState extends State<PaymentDetailScreen> {
  static const Color primaryColor = Color(0xFF3366CC);
  final _df = DateFormat('dd/MM/yyyy HH:mm');
  final _fmt = NumberFormat.currency(locale: 'es_AR', symbol: '\$');

  Map<String, dynamic> _p = {};
  bool _loading = false;
  bool _error = false;
  bool _sharing = false;

  // NEW: allocations (aplicado a cuotas)
  bool _allocLoading = false;
  List<Map<String, dynamic>> _allocs = const [];

  @override
  void initState() {
    super.initState();
    _p = Map<String, dynamic>.from(widget.payment);
    _maybeFetchFullDetail();
    _fetchAllocations(); // traemos asignaciones siempre que tengamos id
  }

  /// Si vienen nulos (cuando llegamos desde /loans/{id}/payments), traigo el detalle completo de /payments/{id}
  Future<void> _maybeFetchFullDetail() async {
    final needsDetail =
        _p['customer_name'] == null ||
        _p['customer_doc'] == null ||
        _p['customer_phone'] == null ||
        _p['company_name'] == null ||
        _p['company_cuit'] == null ||
        _p['collector_name'] == null ||
        _p['receipt_number'] == null ||
        _p['reference'] == null;

    final pid = (_p['id'] as num?)?.toInt();
    if (!needsDetail || pid == null) return;

    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final full = await ApiService.getPayment(pid);
      if (!mounted) return;
      _p.addAll(full);
      setState(() {
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _fetchAllocations() async {
    final pid = (_p['id'] as num?)?.toInt();
    if (pid == null) return;
    setState(() => _allocLoading = true);
    try {
      final rows = await ApiService.getPaymentAllocations(pid);
      if (!mounted) return;
      setState(() {
        _allocs = rows;
        _allocLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _allocLoading = false);
    }
  }

  // ======= utils =======
  String _fmtDate(dynamic v) {
    if (v == null) return '-';
    try {
      final dt = v is DateTime ? v : DateTime.parse(v.toString());
      return _df.format(dt);
    } catch (_) {
      return v.toString();
    }
  }

  String _fmtMoney(dynamic v) {
    if (v == null) return '-';
    try {
      final n = (v as num).toDouble();
      return _fmt.format(n);
    } catch (_) {
      return v.toString();
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

  // ======= acciones =======
  Future<void> _confirmAndVoid() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Anular pago'),
            content: const Text(
              '¿Seguro que querés anular este pago? Se recalcularán las cuotas del préstamo.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Anular'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    try {
      final pid = (_p['id'] as num).toInt();
      await ApiService.voidPayment(pid);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pago anulado')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al anular: $e')));
    }
  }

  Future<void> _shareReceipt() async {
    final pid = (_p['id'] as num?)?.toInt();
    if (pid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ID de pago no disponible')));
      return;
    }

    if (_sharing) return;
    setState(() => _sharing = true);

    try {
      // Si ya tenés esta función utilitaria, perfecto:
      await shareReceiptByPaymentId(context, pid);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recibo listo para compartir')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al compartir: $e')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVoided = _p['is_voided'] == true;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white, // header en blanco
        title: const Text('Detalle del pago'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'void') _confirmAndVoid();
            },
            itemBuilder:
                (_) => const [
                  PopupMenuItem(
                    value: 'void',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.cancel_outlined),
                      title: Text('Anular pago'),
                    ),
                  ),
                ],
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error
              ? _errorView()
              : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (isVoided)
                    _banner(
                      text:
                          'Este pago está ANULADO. Los totales del préstamo/cuotas fueron recalculados.',
                      color: Colors.red.shade600,
                      icon: Icons.report_gmailerrorred,
                    ),
                  _mainCard(), // Pago + Cliente
                  const SizedBox(height: 12),
                  _appliedToSection(), // NEW: Aplicado a cuotas
                  const SizedBox(height: 16),
                  _bottomActions(), // único botón: Compartir comprobante
                ],
              ),
    );
  }

  // ======= vistas =======
  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 42, color: Colors.redAccent),
          const SizedBox(height: 8),
          const Text('No se pudo cargar el detalle del pago'),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _maybeFetchFullDetail,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _banner({required String text, required Color color, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon ?? Icons.info_outline, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Card principal: **Pago + Cliente** juntos
  Widget _mainCard() {
    final amount = _fmtMoney(_p['amount']);
    final date = _fmtDate(_p['payment_date']);
    final pid = _p['id']?.toString() ?? '-';
    final method = _methodLabel(_p['payment_type']);
    final desc =
        (_p['description']?.toString().isNotEmpty ?? false)
            ? _p['description']
            : '-';
    final reference = _p['reference']?.toString() ?? '-';
    final receiptNumber = _p['receipt_number']?.toString();
    final loanId = _p['loan_id']?.toString() ?? '-';

    final customerName = _p['customer_name']?.toString() ?? '-';
    final customerDoc = _p['customer_doc']?.toString() ?? '-';
    final customerPhone = _p['customer_phone']?.toString() ?? '-';
    final collectorName = _p['collector_name']?.toString() ?? '-';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header azul con texto blanco (monto + fecha + id)
          Container(
            decoration: const BoxDecoration(
              color: primaryColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Colors.white),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Monto
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.payments, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          amount,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      _pillWhite(icon: Icons.calendar_today, label: date),
                      _pillWhite(icon: Icons.tag, label: 'Pago #$pid'),
                      if ((receiptNumber ?? '').isNotEmpty)
                        _pillWhite(
                          icon: Icons.confirmation_number,
                          label: 'Recibo $receiptNumber',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Contenido: Pago + Cliente
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Pago'),
                _kvRow('Método', method),
                _kvRow('Préstamo', loanId),
                _kvRow('Referencia', reference),
                _kvRow('Descripción', desc),
                _kvRow('Cobrador', collectorName),
                const SizedBox(height: 12),
                _sectionTitle('Cliente'),
                _kvRow('Nombre', customerName),
                _kvRow('Documento', customerDoc),
                _kvRow('Teléfono', customerPhone),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // NEW: Sección "Aplicado a"
  Widget _appliedToSection() {
    if (_allocLoading) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_allocs.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Aplicado a: (sin información de asignación)'),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.link, color: primaryColor),
                SizedBox(width: 8),
                Text(
                  'Aplicado a',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ..._allocs.map((a) {
              final n = a['installment_number']?.toString() ?? '-';
              final applied = _fmt.format(
                (a['applied'] as num?)?.toDouble() ?? 0.0,
              );
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        'Cuota #$n',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        applied,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        t,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    );
  }

  Widget _kvRow(String a, String b) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(a, style: const TextStyle(color: Colors.black54)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(b, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _pillWhite({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomActions() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _sharing ? null : _shareReceipt,
        icon:
            _sharing
                ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                : const Icon(Icons.ios_share),
        label: Text(_sharing ? 'Generando…' : 'Compartir comprobante'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}
