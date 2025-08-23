/*// TODO Implement this library.
import 'package:flutter/material.dart';
import 'package:frontend/models/installment.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/screens/installment_detail_screen.dart';
import 'package:frontend/screens/register_payment_screen.dart';
import 'package:intl/intl.dart';

class WeeklyInstallmentsScreen extends StatefulWidget {
  const WeeklyInstallmentsScreen({super.key});

  @override
  State<WeeklyInstallmentsScreen> createState() => _WeeklyInstallmentsScreenState();
}

class _WeeklyInstallmentsScreenState extends State<WeeklyInstallmentsScreen> {
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color secondaryColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);
  static const Color warningColor = Color(0xFFFFA000);

  List<Installment> installments = [];
  bool isLoading = true;
  DateTimeRange? currentWeek;
  final DateFormat dateFormat = DateFormat('EEEE dd/MM', 'es_AR');

  @override
  void initState() {
    super.initState();
    _calculateCurrentWeek();
    _loadInstallments();
  }

  void _calculateCurrentWeek() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday)); // Domingo
    final endOfWeek = startOfWeek.add(const Duration(days: 6)); // Sábado
    setState(() {
      currentWeek = DateTimeRange(start: startOfWeek, end: endOfWeek);
    });
  }

  Future<void> _loadInstallments() async {
    try {
      if (currentWeek == null) return;
      
      final fetchedInstallments = await ApiService.fetchWeeklyInstallments(
        currentWeek!.start,
        currentWeek!.end,
      );
      
      setState(() {
        installments = fetchedInstallments;
        isLoading = false;
      });
    } catch (e) {
      print("Error loading weekly installments: $e");
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error al cargar las cuotas'),
          backgroundColor: dangerColor,
        ),
      );
    }
  }

  void _navigateToPayment(Installment installment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RegisterPaymentScreen(
          installment: installment,
          onPaymentSuccess: _loadInstallments,
        ),
      ),
    );
  }

  void _navigateToDetail(Installment installment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InstallmentDetailScreen(
          installment: installment,
          onUpdate: _loadInstallments,
        ),
      ),
    );
  }

  Widget _buildWeekHeader() {
    if (currentWeek == null) return const SizedBox.shrink();
    
    final weekFormatter = DateFormat("dd 'al' dd MMMM y", 'es_AR');
    final weekRange = '${weekFormatter.format(currentWeek!.start)} - ${weekFormatter.format(currentWeek!.end)}';
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Semana: $weekRange',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () {
              // TODO: Implementar selector de semana
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDaySection(DateTime day, List<Installment> dayInstallments) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            dateFormat.format(day),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _isToday(day) ? primaryColor : Colors.grey.shade700,
              fontSize: 16,
            ),
          ),
        ),
        ...dayInstallments.map((inst) => _buildInstallmentCard(inst)),
      ],
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && 
           date.month == now.month && 
           date.day == now.day;
  }

  Widget _buildInstallmentCard(Installment installment) {
    final isOverdue = installment.isOverdue;
    final isToday = _isToday(installment.dueDate);
    final isPaid = installment.isPaid;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isOverdue 
              ? dangerColor.withOpacity(0.3) 
              : Colors.grey.shade200,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _navigateToDetail(installment),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Crédito #${installment.loanId} - Cuota ${installment.number}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isOverdue ? dangerColor : Colors.grey.shade800,
                    ),
                  ),
                  if (isOverdue)
                    _buildStatusChip('VENCIDA', dangerColor)
                  else if (isPaid)
                    _buildStatusChip('PAGADA', secondaryColor)
                  else if (isToday)
                    _buildStatusChip('HOY', warningColor),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailRow('Cliente:', installment.customerName),
                        _buildDetailRow('Monto:', '\$${installment.amount.toStringAsFixed(2)}'),
                      ],
                    ),
                  ),
                  if (!isPaid)
                    ElevatedButton(
                      onPressed: () => _navigateToPayment(installment),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: const Text('Cobrar'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String text, Color color) {
    return Chip(
      label: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
      ),
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '$label ',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Agrupar cuotas por día
    final Map<DateTime, List<Installment>> installmentsByDay = {};
    
    for (var inst in installments) {
      final day = DateTime(inst.dueDate.year, inst.dueDate.month, inst.dueDate.day);
      installmentsByDay.putIfAbsent(day, () => []).add(inst);
    }

    // Ordenar los días
    final sortedDays = installmentsByDay.keys.toList()
      ..sort((a, b) => a.compareTo(b));

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Cuotas Semanales',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInstallments,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWeekHeader(),
                  const SizedBox(height: 8),
                  if (installments.isEmpty)
                    const Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.credit_card_off,
                            size: 48,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text('No hay cuotas esta semana'),
                        ],
                      ),
                    )
                  else
                    ...sortedDays.map((day) => _buildDaySection(
                          day,
                          installmentsByDay[day]!
                            ..sort((a, b) => a.dueDate.compareTo(b.dueDate)),
                        ),
                ],
              ),
            ),
    );
  }
}*/
