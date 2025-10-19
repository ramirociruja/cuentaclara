import 'package:flutter/material.dart';
import 'package:frontend/screens/customer_detail_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/models/customer.dart';
import 'package:frontend/screens/add_customer_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color okColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);

  int? _employeeId;

  String searchQuery = '';
  bool showOnlyDebtors = false;
  bool isLoading = true;
  bool isRefreshing = false;

  List<Customer> customers = [];
  Map<int, bool> hasOverdueInstallments = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      if (!mounted) return; // ✅ guard antes de setState
      setState(() => isLoading = true);

      _employeeId = await ApiService.getEmployeeId();
      if (_employeeId == null) {
        throw Exception('No se encontró el empleado logueado');
      }
      await _fetchCustomers();
    } catch (e) {
      if (!mounted) return; // ✅ guard antes de setState / context
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error inicializando: $e'),
          backgroundColor: dangerColor,
        ),
      );
    }
  }

  Future<void> _fetchCustomers() async {
    try {
      if (!mounted) return; // ✅ guard antes de setState
      setState(() {
        isLoading = true;
        isRefreshing = false;
      });

      // 1) Clientes del cobrador
      final fetchedCustomers = await ApiService.fetchCustomersByEmployee();

      // 2) Índice de clientes con cuotas VENCIDAS
      final overdueItems = await ApiService.fetchInstallmentsEnriched(
        employeeId: _employeeId,
        dateFrom: null,
        dateTo: null,
        statusFilter: 'vencidas',
      );
      final overdueCustomerIds = <int>{
        for (final r in overdueItems)
          if (r.customerId != null) r.customerId!,
      };

      if (!mounted) return; // ✅ guard antes de setState
      setState(() {
        customers = fetchedCustomers;
        hasOverdueInstallments = {
          for (final c in fetchedCustomers)
            c.id: overdueCustomerIds.contains(c.id),
        };
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return; // ✅ guard antes de setState / context
      setState(() {
        isLoading = false;
        isRefreshing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar los clientes: $e'),
          backgroundColor: dangerColor,
        ),
      );
    }
  }

  Future<void> _refreshData() async {
    if (!mounted) return; // ✅
    setState(() => isRefreshing = true);
    await _fetchCustomers();
  }

  List<Customer> get _filteredCustomers {
    return customers.where((c) {
      final q = searchQuery.trim().toLowerCase();
      final matchesQuery = q.isEmpty || c.name.toLowerCase().contains(q);
      final isDebtor = hasOverdueInstallments[c.id] ?? false;
      return matchesQuery && (!showOnlyDebtors || isDebtor);
    }).toList();
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final total = customers.length;
    final debtors = hasOverdueInstallments.values.where((v) => v).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Clientes',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Actualizar lista',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddCustomerScreen()),
          );

          if (result == true) {
            await _fetchCustomers();

            // ✅ proteger el MISMO BuildContext que vamos a usar
            final ctx = context;
            // Si tu SDK soporta context.mounted, dejá esta línea:
            if (!(ctx as dynamic).mounted && !mounted) return;

            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(
                content: Text('Cliente creado exitosamente'),
                backgroundColor: okColor,
              ),
            );
          }
        },
        backgroundColor: primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        color: primaryColor,
        child: Column(
          children: [
            // Encabezado compacto con búsqueda + filtro + resumen
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  // Search
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar cliente por nombre...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                    ),
                    onChanged: (value) => setState(() => searchQuery = value),
                  ),
                  const SizedBox(height: 10),

                  // Resumen + Filtro
                  Row(
                    children: [
                      // Resumen
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            // was: primaryColor.withOpacity(.06)
                            color: primaryColor.withValues(alpha: .06), // ✅
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              // was: primaryColor.withOpacity(.18)
                              color: primaryColor.withValues(alpha: .18), // ✅
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.people_alt,
                                size: 16,
                                color: primaryColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$total clientes',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: primaryColor,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: const BoxDecoration(
                                  color: dangerColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  '$debtors con deuda',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: dangerColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Toggle "Solo con deuda"
                      Flexible(
                        fit: FlexFit.loose,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Solo con deuda',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Switch.adaptive(
                                  value: showOnlyDebtors,
                                  onChanged:
                                      (v) =>
                                          setState(() => showOnlyDebtors = v),
                                  activeColor: primaryColor,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Lista
            if (isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: primaryColor),
                ),
              )
            else if (_filteredCustomers.isEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _emptyStateCard(),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: _filteredCustomers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder:
                      (context, index) =>
                          _buildCustomerCard(_filteredCustomers[index]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard(Customer customer) {
    final hasDebt = hasOverdueInstallments[customer.id] ?? false;

    final sideColor =
        // was: dangerColor.withOpacity(.35)
        hasDebt
            ? dangerColor.withValues(alpha: .35)
            : Colors.grey.shade300; // ✅

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: sideColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => CustomerDetailScreen(customerId: customer.id),
            ),
          );
          if (result == true) {
            if (!mounted) {
              return; // ✅ guard antes de llamar setState dentro de _fetchCustomers
            }
            await _fetchCustomers();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar
              CircleAvatar(
                radius: 22,
                // was: primaryColor.withOpacity(.1)
                backgroundColor: primaryColor.withValues(alpha: .1), // ✅
                child: const Icon(Icons.person, color: primaryColor),
              ),
              const SizedBox(width: 12),

              // Info cliente
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nombre
                    Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // DNI + Tel
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _miniMeta(Icons.badge_outlined, 'DNI ${customer.dni}'),
                        _miniMeta(Icons.call_outlined, customer.phone),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Estado (pill)
                    _statusPill(hasDebt),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Chevron
              const Icon(Icons.chevron_right_rounded, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniMeta(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black45),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(bool hasDebt) {
    final bg = hasDebt ? dangerColor : okColor;
    final label = hasDebt ? 'Tiene cuotas vencidas' : 'Al día';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        // was: bg.withOpacity(.12)
        color: bg.withValues(alpha: .12), // ✅
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasDebt ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
            size: 16,
            color: bg.darken(.15),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: bg.darken(.15),
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyStateCard() {
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
                // was: okColor.withOpacity(.1)
                color: okColor.withValues(alpha: .1), // ✅
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.people_outline, color: okColor),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sin resultados',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'No se encontraron clientes para los filtros aplicados.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on Color {
  Color darken([double amount = .2]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}
