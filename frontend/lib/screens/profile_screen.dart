import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:frontend/services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color primaryColor = Color(0xFF3366CC);

  bool _loading = true;
  String? _error;

  // Datos “crudos”

  // Datos enriquecidos
  String? _employeeName;
  String? _employeeRole;
  String? _employeeEmail;
  String? _employeePhone;
  DateTime? _employeeCreatedAt;

  String? _companyName;
  String? _companyStatus;
  DateTime? _companyLicenseExpiry;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final eId = await ApiService.getEmployeeId();
      final cId = await ApiService.getCompanyId();

      String? empName;
      String? cmpName;
      String? role;
      String? email;
      String? phone;
      DateTime? createdAt;
      String? companyStatus;
      DateTime? companyExpiry;

      empName = await ApiService.getEmployeeName();

      if (cId != null) {
        cmpName = await ApiService.getCompanyName();

        final comp = await ApiService.fetchCompanyById(cId);
        if (comp != null) {
          final rawStatus =
              (comp['service_status'] ?? comp['status'] ?? '').toString();
          final norm = rawStatus.trim().toLowerCase();

          if (norm == 'active' || norm == 'activo' || norm == 'activa') {
            companyStatus = 'Activa';
          } else if (norm.contains('suspend')) {
            companyStatus = 'Suspendida';
          } else if (norm.contains('vencid') || norm.contains('expir')) {
            companyStatus = 'Vencida';
          } else {
            companyStatus =
                rawStatus.isEmpty
                    ? '—'
                    : rawStatus[0].toUpperCase() + rawStatus.substring(1);
          }

          final expiryRaw =
              (comp['license_expires_at'] ??
                      comp['license_expires_on'] ??
                      comp['expires_at'] ??
                      comp['license_expiration'] ??
                      comp['license_expiry'])
                  ?.toString();

          if (expiryRaw != null && expiryRaw.isNotEmpty) {
            companyExpiry = DateTime.tryParse(expiryRaw);
          }
        }
      }

      if (eId != null) {
        final emp = await ApiService.fetchEmployeeById(eId);
        if (emp != null) {
          role = (emp['role'] ?? '').toString().trim();
          email = (emp['email'] ?? '').toString().trim();
          phone = (emp['phone'] ?? '').toString().trim();

          final createdRaw = emp['created_at']?.toString();
          if (createdRaw != null && createdRaw.isNotEmpty) {
            createdAt = DateTime.tryParse(createdRaw);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _employeeName = empName;
        _companyName = cmpName;

        _employeeRole = role;
        _employeeEmail = email;
        _employeePhone = phone;
        _employeeCreatedAt = createdAt;

        _companyStatus = companyStatus;
        _companyLicenseExpiry = companyExpiry;

        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar el perfil. ${e.toString()}';
      });
    }
  }

  String _initials(String? fullName) {
    if (fullName == null || fullName.trim().isEmpty) return '?';
    final parts = fullName.trim().split(RegExp(r'\s+'));
    final buf = StringBuffer();
    for (final p in parts.take(2)) {
      if (p.isNotEmpty) buf.write(p[0].toUpperCase());
    }
    return buf.toString();
  }

  Color _statusColor(String? status) {
    final s = (status ?? '').toLowerCase();
    if (s.contains('activa') || s.contains('active')) {
      return const Color(0xFF1E8E3E);
    }
    if (s.contains('suspend')) return const Color(0xFFD93025);
    if (s.contains('vencid') || s.contains('expir')) {
      return const Color(0xFFEA8600);
    }
    return Colors.grey;
  }

  Widget _statusPill(String label) {
    final c = _statusColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    String? value, {
    bool multiline = false,
  }) {
    final hasValue = value != null && value.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment:
            multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: Colors.grey[700]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 2),
                Text(
                  hasValue ? value.trim() : '—',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final createdStr =
        _employeeCreatedAt != null
            ? DateFormat('dd/MM/yyyy').format(_employeeCreatedAt!.toLocal())
            : null;
    final expiryStr =
        _companyLicenseExpiry != null
            ? DateFormat('dd/MM/yyyy').format(_companyLicenseExpiry!.toLocal())
            : null;

    final statusColor = _statusColor(_companyStatus);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        centerTitle: true,
        backgroundColor: statusColor.withValues(alpha: 0.85),
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : (_error != null)
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              )
              : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  children: [
                    // Encabezado
                    Card(
                      elevation: 0.5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 20,
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: primaryColor.withValues(
                                alpha: 0.15,
                              ),
                              child: Text(
                                _initials(_employeeName),
                                style: const TextStyle(
                                  color: primaryColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (_employeeName?.isNotEmpty ?? false)
                                        ? _employeeName!
                                        : 'Empleado',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if ((_employeeRole?.isNotEmpty ?? false))
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withValues(
                                          alpha: 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        _employeeRole!,
                                        style: const TextStyle(
                                          color: primaryColor,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Contacto
                    Card(
                      elevation: 0.5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Contacto',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _infoRow(
                              Icons.email_outlined,
                              'Email',
                              _employeeEmail,
                            ),
                            _infoRow(
                              Icons.phone_outlined,
                              'Teléfono',
                              _employeePhone,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Empresa
                    Card(
                      elevation: 0.5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Empresa',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _infoRow(
                              Icons.apartment_outlined,
                              'Nombre',
                              _companyName,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.verified_user_outlined,
                                  size: 20,
                                  color: Colors.grey[700],
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Estado',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _statusPill(
                                  (_companyStatus?.isNotEmpty ?? false)
                                      ? _companyStatus!
                                      : '—',
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _infoRow(
                              Icons.event_outlined,
                              'Vencimiento de licencia',
                              expiryStr,
                            ),
                            _infoRow(
                              Icons.person_add_alt_1_outlined,
                              'Miembro desde',
                              createdStr,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Desliza hacia abajo para actualizar.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
    );
  }
}
