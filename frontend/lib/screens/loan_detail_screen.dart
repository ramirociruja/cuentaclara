import 'package:flutter/material.dart';
import 'package:frontend/models/loan.dart';
import 'package:frontend/models/installment.dart';
import 'package:frontend/services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:frontend/screens/installment_detail_screen.dart';

class LoanDetailScreen extends StatefulWidget {
  final int loanId;
  final Loan? loanData;
  final bool fromCreateScreen;

  const LoanDetailScreen({
    Key? key,
    required this.loanId,
    this.loanData,
    this.fromCreateScreen = false,
  }) : super(key: key);

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color secondaryColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);
  static const Color warningColor = Color(0xFFFFA000);

  late Future<List<Installment>> installments;
  late Future<Loan?> loanDetails;
  bool isLoading = false;

  final currencyFormatter = NumberFormat.currency(
    locale: 'es_AR',
    symbol: '\$',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      installments = ApiService.fetchInstallmentsByLoan(widget.loanId);
      loanDetails =
          widget.loanData != null
              ? Future.value(widget.loanData)
              : ApiService.fetchLoanDetails(widget.loanId);
    });
  }

  Future<void> _refreshData() async {
    setState(() => isLoading = true);
    await Future.delayed(
      Duration(milliseconds: 300),
    ); // Pequeño delay para visualizar el refresh
    _loadData();
    setState(() => isLoading = false);
  }

  Widget _buildLoanHeader(Loan loan) {
    final startDate = DateTime.tryParse(loan.startDate) ?? DateTime.now();
    final formattedDate = DateFormat('dd/MM/yyyy').format(startDate);
    final progress = (loan.amount - loan.totalDue) / loan.amount;

    return Card(
      elevation: 2,
      margin: EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Préstamo #${loan.id}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                Chip(
                  label: Text(
                    loan.status == 'active' ? 'Pendiente' : 'Pagado',
                    style: TextStyle(color: Colors.white),
                  ),
                  backgroundColor: _getStatusColor(
                    loan.status == 'active' ? 'Pendiente' : 'Pagado',
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            _buildDetailRow(
              'Monto Total:',
              currencyFormatter.format(loan.amount),
            ),
            _buildDetailRow(
              'Saldo Pendiente:',
              currencyFormatter.format(loan.totalDue),
            ),
            _buildDetailRow(
              'Cuota:',
              currencyFormatter.format(loan.installmentAmount),
            ),
            _buildDetailRow('Inicio:', formattedDate),
            SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade200,
              color: progress == 1 ? secondaryColor : primaryColor,
              minHeight: 8,
            ),
            SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${(progress * 100).toStringAsFixed(1)}% Pagado',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstallmentItem(Installment installment) {
    final isPaid = installment.isPaid;
    final progress = installment.paidAmount / installment.amount;
    final dueDate = DateFormat('dd/MM/yyyy').format(installment.dueDate);
    final isOverdue = installment.isOverdue && !isPaid;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color:
              isOverdue ? dangerColor.withOpacity(0.3) : Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isPaid ? null : () => _navigateToInstallmentDetail(installment),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Cuota ${installment.number}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isOverdue ? dangerColor : Colors.grey.shade800,
                    ),
                  ),
                  if (isOverdue)
                    Chip(
                      label: Text(
                        'VENCIDA',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                      backgroundColor: dangerColor,
                      padding: EdgeInsets.symmetric(horizontal: 8),
                    )
                  else if (isPaid)
                    Chip(
                      label: Text(
                        'PAGADA',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                      backgroundColor: secondaryColor,
                      padding: EdgeInsets.symmetric(horizontal: 8),
                    ),
                ],
              ),
              SizedBox(height: 8),
              _buildDetailRow(
                'Monto:',
                currencyFormatter.format(installment.amount),
              ),
              _buildDetailRow(
                'Pagado:',
                currencyFormatter.format(installment.paidAmount),
              ),
              _buildDetailRow('Vencimiento:', dueDate),
              SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey.shade200,
                color: isPaid ? secondaryColor : primaryColor,
                minHeight: 6,
              ),
              if (!isPaid && installment.paidAmount > 0)
                Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Falta pagar: ${currencyFormatter.format(installment.amount - installment.paidAmount)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToInstallmentDetail(Installment installment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InstallmentDetailScreen(installment: installment),
      ),
    ).then((paymentCompleted) {
      if (paymentCompleted == true) {
        _refreshData();
      }
    });
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pagado':
        return secondaryColor;
      case 'vencido':
        return dangerColor;
      case 'pendiente':
        return warningColor;
      default:
        return primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Solo redirigir al home si venimos de CreateLoanOrPurchaseScreen
        if (widget.fromCreateScreen) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return false;
        }
        // En otros casos, permitir el comportamiento normal (volver atrás)
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Detalle del Préstamo',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: primaryColor,
          iconTheme: IconThemeData(color: Colors.white),
          actions: [
            IconButton(icon: Icon(Icons.refresh), onPressed: _refreshData),
          ],
        ),
        body:
            isLoading
                ? Center(child: CircularProgressIndicator(color: primaryColor))
                : FutureBuilder(
                  future: Future.wait([loanDetails, installments]),
                  builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(color: primaryColor),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: dangerColor,
                              size: 48,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Error al cargar los datos',
                              style: TextStyle(
                                fontSize: 16,
                                color: dangerColor,
                              ),
                            ),
                            SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _refreshData,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                              ),
                              child: Text('Reintentar'),
                            ),
                          ],
                        ),
                      );
                    }

                    if (snapshot.data == null ||
                        snapshot.data![0] == null ||
                        snapshot.data![1] == null) {
                      return Center(
                        child: Text(
                          'No se encontraron datos del préstamo',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      );
                    }

                    final loan = snapshot.data![0] as Loan;
                    final installments = snapshot.data![1] as List<Installment>;

                    return RefreshIndicator(
                      onRefresh: _refreshData,
                      color: primaryColor,
                      child: SingleChildScrollView(
                        physics: AlwaysScrollableScrollPhysics(),
                        child: Column(
                          children: [
                            _buildLoanHeader(loan),
                            SizedBox(height: 8),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Cuotas (${installments.length})',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Text(
                                    'Total: ${currencyFormatter.format(loan.amount)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 8),
                            ...installments
                                .map((i) => _buildInstallmentItem(i))
                                .toList(),
                            SizedBox(height: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      ),
    );
  }
}
