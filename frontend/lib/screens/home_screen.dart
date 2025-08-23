import 'package:flutter/material.dart';
import 'package:frontend/screens/create_loan_or_purchase_screen.dart';
import 'package:frontend/screens/customers_screen.dart';
import 'package:frontend/screens/register_payment_screen.dart';
//import 'package:frontend/screens/weekly_installments_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Inicio del Cobrador',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF3366CC),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sincronizar datos',
            onPressed: _syncData,
          ),
          IconButton(
            icon: const Icon(Icons.account_circle),
            tooltip: 'Mi perfil',
            onPressed: _goToProfile,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        color: const Color(0xFF3366CC),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado con última sincronización
              _buildSyncHeader(),
              const SizedBox(height: 20),

              // Resumen semanal
              _buildWeeklySummary(),
              const SizedBox(height: 20),

              // Estadísticas rápidas
              _buildQuickStats(),
              const SizedBox(height: 20),

              // Título de acciones
              const Text(
                'Acciones Rápidas',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),

              // Grid de acciones
              _buildActionGrid(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncHeader() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Última sincronización: Hoy 10:30',
              style: TextStyle(fontSize: 13),
            ),
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklySummary() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumen Semanal',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3366CC),
              ),
            ),
            const SizedBox(height: 12),
            _buildSummaryItem('Total a Cobrar', '\$15,000'),
            _buildSummaryItem('Cobrado', '\$7,500'),
            _buildSummaryItem('Restante', '\$7,500'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: 0.5,
              backgroundColor: Colors.grey.shade200,
              color: const Color(0xFF3366CC),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                '50% completado',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Clientes',
            '125',
            Icons.people,
            const Color(0xFF3366CC),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Créditos Activos',
            '42',
            Icons.attach_money,
            const Color(0xFF00CC66),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Cuotas Vencidas',
            '8',
            Icons.warning,
            const Color(0xFFFF4444),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionGrid(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      children: [
        _buildActionButton(
          context,
          Icons.calendar_today,
          'Cuotas de Hoy',
          Colors.orange.shade600,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (context) =>
                        const RegisterPaymentScreen(), //const WeeklyInstallmentsScreen(),
              ),
            );
          },
        ),
        _buildActionButton(
          context,
          Icons.payment,
          'Registrar Pago',
          Colors.green.shade600,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const RegisterPaymentScreen(),
              ),
            );
          },
        ),
        _buildActionButton(
          context,
          Icons.attach_money,
          'Nuevo Crédito',
          Colors.blue.shade600,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CreateLoanOrPurchaseScreen(),
              ),
            );
          },
        ),
        _buildActionButton(
          context,
          Icons.people,
          'Mis Clientes',
          const Color(0xFF3366CC),
          () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CustomersScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
    VoidCallback onPressed,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _syncData() async {
    // Implementar lógica de sincronización
  }

  Future<void> _refreshData() async {
    // Implementar lógica de refresco
  }

  void _goToProfile() {
    // Navegar a pantalla de perfil
  }
}
