import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/screens/weekly_installments_screen.dart';
import 'package:frontend/screens/customers_screen.dart';
import 'package:frontend/screens/create_loan_or_purchase_screen.dart';
import 'package:frontend/screens/register_payment_screen.dart';

/// HOME ejecutiva para cobradores (sin hardcodeos)
/// - Resumen semanal conciso: A cobrar (semana), Cobrado (semana por fecha de pago) y progreso
/// - Vencidas como alerta operativa
/// - Acciones rápidas reordenadas (Cuotas semana → Cobrar → Nuevo préstamo → Clientes)
/// - Última sincronización real (SharedPreferences)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color successColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);
  static const Color infoColor = Color(0xFF607D8B);

  bool _loading = true;
  String? _error;
  int? _employeeId;

  late DateTime _monday;
  late DateTime _sunday;

  // Métricas
  double weeklyDueAmount = 0; // A cobrar (semana)
  double weeklyCollected =
      0; // Cobrado en la semana (por fecha de pago), sin importar due_date
  int overdueCount = 0; // Cantidad de cuotas vencidas (no pagadas)

  // Créditos otorgados en la semana (opcional)
  int weeklyCreditsCount = 0;
  double weeklyCreditsAmount = 0;

  String? _lastSync; // mostrado en UI

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _monday = _toMonday(now);
    _sunday = _monday.add(const Duration(days: 6));
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final id = await ApiService.getEmployeeId();
      if (!mounted) return;
      if (id == null) {
        setState(() {
          _error = 'No se encontró el empleado logueado';
          _loading = false;
        });
        return;
      }
      _employeeId = id;

      final prefs = await SharedPreferences.getInstance();
      _lastSync = prefs.getString('last_sync');

      await _loadData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error inicializando: $e';
        _loading = false;
      });
    }
  }

  DateTime _toMonday(DateTime d) => d.subtract(Duration(days: d.weekday - 1));
  String _fmtDMY(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // 1) Cuotas de la SEMANA (para "a cobrar")
      final weeklyItems = await ApiService.fetchInstallmentsEnriched(
        employeeId: _employeeId!,
        dateFrom: _monday,
        dateTo: _sunday,
        statusFilter: '',
      );

      // 2) Pagos de la semana (por fecha de pago)
      double weeklyPaymentsTotal = 0;
      try {
        // Recomendado: endpoint de summary
        weeklyPaymentsTotal = await ApiService.fetchPaymentsTotal(
          employeeId: _employeeId!,
          dateFrom: _monday,
          dateTo: _sunday,
        );
      } catch (_) {
        // Fallback: listar pagos y sumar
        final payments = await ApiService.fetchPayments(
          employeeId: _employeeId!,
          dateFrom: _monday,
          dateTo: _sunday,
        );
        double acc = 0;
        for (final p in payments) {
          try {
            final num? amount = p.amount ?? p['amount'];
            if (amount != null) acc += amount.toDouble();
          } catch (_) {}
        }
        weeklyPaymentsTotal = acc;
      }

      // 3) Todas las cuotas (para vencidas)
      final allItems = await ApiService.fetchInstallmentsEnriched(
        employeeId: _employeeId!,
        dateFrom: null,
        dateTo: null,
        statusFilter: '',
      );

      // 4) Créditos de la semana (si existe endpoint)
      try {
        final summary = await ApiService.fetchCreditsSummary(
          employeeId: _employeeId!,
          dateFrom: _monday,
          dateTo: _sunday,
        );
        weeklyCreditsCount = summary.count;
        weeklyCreditsAmount = summary.amount;
      } catch (_) {
        // dejar en 0 si no está disponible aún
      }

      _deriveMetrics(weeklyItems, allItems, weeklyPaymentsTotal);

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = 'Error cargando datos: $e';
        _loading = false;
      });
    }
  }

  void _deriveMetrics(
    List<InstallmentListItem> weekly,
    List<InstallmentListItem> all,
    double weeklyPaymentsTotal,
  ) {
    weeklyDueAmount = 0;
    weeklyCollected = 0;
    overdueCount = 0;

    final today = DateTime.now();

    for (final row in weekly) {
      final it = row.installment;
      weeklyDueAmount += it.amount;
    }

    for (final row in all) {
      final it = row.installment;
      final s = (it.status).toLowerCase().trim();
      final isPaid = it.isPaid == true || s == 'pagada';
      if (!isPaid) {
        final dueOnlyDate = DateTime(
          it.dueDate.year,
          it.dueDate.month,
          it.dueDate.day,
        );
        final todayOnly = DateTime(today.year, today.month, today.day);
        if (dueOnlyDate.isBefore(todayOnly)) overdueCount++;
      }
    }

    weeklyCollected = weeklyPaymentsTotal;
  }

  Future<void> _sync() async {
    await _loadData();
    final prefs = await SharedPreferences.getInstance();
    final ts = DateTime.now().toIso8601String();
    await prefs.setString('last_sync', ts);
    setState(() => _lastSync = ts);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sincronización completada')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Inicio',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: PopupMenuButton<String>(
          tooltip: 'Menú',
          icon: const Icon(Icons.menu, color: Colors.white),
          onSelected: (value) async {
            switch (value) {
              case 'sync':
                await _sync();
                break;
              case 'logout':
                // TODO: implementar logout real
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sesión cerrada (demo)')),
                );
                break;
            }
          },
          itemBuilder:
              (ctx) => const [
                PopupMenuItem(value: 'sync', child: Text('Sincronizar ahora')),
                PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
              ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sincronizar ahora',
            onPressed: _loading ? null : _sync,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body:
          _loading
              ? const Center(
                child: CircularProgressIndicator(color: primaryColor),
              )
              : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                color: primaryColor,
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _lastSyncRow(),
                    const SizedBox(height: 12),
                    _executiveSummaryCard(),
                    const SizedBox(height: 12),
                    _quickActions(),
                    const SizedBox(height: 12),
                    _overdueCard(),
                  ],
                ),
              ),
    );
  }

  Widget _lastSyncRow() {
    String subtitle;
    if (_lastSync == null) {
      subtitle = 'Aún no sincronizado';
    } else {
      final dt = DateTime.tryParse(_lastSync!);
      subtitle =
          dt == null
              ? 'Última sincronización: desconocida'
              : 'Última sincronización: ${_fmtDMY(dt)}';
    }
    return Row(
      children: [
        const Icon(Icons.cloud_sync_outlined, color: infoColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(subtitle, style: const TextStyle(color: Colors.black54)),
        ),
        TextButton.icon(
          onPressed: _loading ? null : _sync,
          icon: const Icon(Icons.sync),
          label: const Text('Sincronizar'),
        ),
      ],
    );
  }

  Widget _executiveSummaryCard() {
    final double progress =
        weeklyDueAmount == 0
            ? 0
            : (weeklyCollected / weeklyDueAmount).clamp(0, 1);
    final bool overAchieved =
        weeklyCollected > weeklyDueAmount && weeklyDueAmount > 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumen semanal',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Semana ${_fmtDMY(_monday)} – ${_fmtDMY(_sunday)}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),

            // KPIs
            Row(
              children: [
                Expanded(child: _money('A cobrar (semana)', weeklyDueAmount)),
                const SizedBox(width: 12),
                Expanded(child: _money('Cobrado (semana)', weeklyCollected)),
              ],
            ),

            const SizedBox(height: 12),
            // Progreso semanal
            Text(
              'Progreso semanal',
              style: TextStyle(
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation(primaryColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    overAchieved
                        ? '¡Superaste el objetivo semanal!'
                        : 'Objetivo semanal en curso',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            // Créditos de la semana (si hay datos)
            if (weeklyCreditsCount > 0 || weeklyCreditsAmount > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _money(
                      'Créditos otorgados (semana)',
                      weeklyCreditsCount,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _money(
                      'Monto prestado (semana)',
                      weeklyCreditsAmount,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _overdueCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: dangerColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_outlined,
                color: dangerColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cuotas vencidas',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    overdueCount == 0
                        ? 'No hay cuotas vencidas pendientes.'
                        : 'Tenés $overdueCount cuotas vencidas sin cobrar.',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WeeklyInstallmentsScreen(),
                  ),
                );
              },
              child: const Text('Ver'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Acciones rápidas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            // 1) Cuotas de la semana (primero)
            _actionButton(
              icon: Icons.calendar_view_week,
              label: 'Cuotas de la semana',
              bg: primaryColor,
              fg: Colors.white,
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WeeklyInstallmentsScreen(),
                    ),
                  ),
            ),
            // 2) Cobrar
            _actionButton(
              icon: Icons.attach_money,
              label: 'Cobrar',
              bg: successColor,
              fg: Colors.white,
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RegisterPaymentScreen(),
                    ),
                  ),
            ),
            // 3) Nuevo préstamo / venta
            _actionButton(
              icon: Icons.add_shopping_cart,
              label: 'Nuevo préstamo',
              bg: Color(0xFF7E57C2),
              fg: Colors.white,
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateLoanOrPurchaseScreen(),
                    ),
                  ),
            ),
            // 4) Clientes
            _actionButton(
              icon: Icons.people_alt_outlined,
              label: 'Clientes',
              bg: Color(0xFF26A69A),
              fg: Colors.white,
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CustomersScreen()),
                  ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minWidth: 180, minHeight: 64),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: bg.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _money(String label, num value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          '\$${value.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ],
    );
  }
}
