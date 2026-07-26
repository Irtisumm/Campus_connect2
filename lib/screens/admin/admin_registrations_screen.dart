import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../widgets/common.dart';
import '../../data/mock_data.dart';
import '../../theme/app_theme.dart';
import '../../services/data_service.dart';
import '../../services/app_state.dart';

void _toast(BuildContext ctx, String msg) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
  content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
  behavior: SnackBarBehavior.floating, backgroundColor: AppTheme.textPrimary,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)), duration: const Duration(seconds: 2)));

AppBar _appBar(String t, BuildContext ctx) => AppBar(
  title: Text(t), backgroundColor: Colors.transparent,
  flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.headerGradient)),
  leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => ctx.pop()));

// ── Admin Registrations Screen ──────────────────────────────────
class AdminRegistrationsScreen extends StatefulWidget {
  const AdminRegistrationsScreen({super.key});
  @override State<AdminRegistrationsScreen> createState() => _AdminRegistrationsScreenState();
}

class _AdminRegistrationsScreenState extends State<AdminRegistrationsScreen> {
  bool _showPending = true;

  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        final allRegs = dataService.pendingRegistrations;
        final pending = allRegs.where((r) => r.status == 'Pending').toList();
        final processed = allRegs.where((r) => r.status != 'Pending').toList();
        final data = _showPending ? pending : processed;

        return Scaffold(
          appBar: _appBar('Student Registrations', context),
          body: Column(children: [
            const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: AdminBar()),

            // Stats row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Expanded(child: StatCard(value: '${pending.length}', label: 'Pending', valueColor: AppTheme.goldDark, bgColor: AppTheme.gold.withOpacity(0.15))),
                const SizedBox(width: 10),
                Expanded(child: StatCard(value: '${allRegs.where((r) => r.status == 'Approved').length}', label: 'Approved', valueColor: AppTheme.redDark, bgColor: AppTheme.red.withOpacity(0.07))),
                const SizedBox(width: 10),
                Expanded(child: StatCard(value: '${allRegs.where((r) => r.status == 'Rejected').length}', label: 'Rejected', valueColor: const Color(0xFFB03030), bgColor: const Color(0x08D65E5E))),
              ]),
            ),

            // Tabs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _showPending = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: _showPending ? AppTheme.red : Colors.transparent, width: 3)),
                      ),
                      child: Text('Pending (${pending.length})', textAlign: TextAlign.center, style: TextStyle(fontWeight: _showPending ? FontWeight.w800 : FontWeight.w600, color: _showPending ? AppTheme.red : AppTheme.textMuted)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _showPending = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: !_showPending ? AppTheme.red : Colors.transparent, width: 3)),
                      ),
                      child: Text('Processed (${processed.length})', textAlign: TextAlign.center, style: TextStyle(fontWeight: !_showPending ? FontWeight.w800 : FontWeight.w600, color: !_showPending ? AppTheme.red : AppTheme.textMuted)),
                    ),
                  ),
                ),
              ]),
            ),

            // List
            Expanded(child: data.isEmpty
              ? Center(child: EmptyState(
                  title: _showPending ? 'No Pending Registrations' : 'No Processed Registrations',
                  subtitle: _showPending ? 'All registrations have been reviewed.' : 'No registrations have been processed yet.',
                  icon: Icons.person_search_rounded,
                ))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: data.length,
                  itemBuilder: (ctx, i) {
                    final reg = data[i];
                    return _RegistrationCard(reg: reg).animate().fadeIn(delay: (i * 55).ms).slideY(begin: 0.12);
                  },
                ),
            ),
          ]),
        );
      },
    );
  }
}

class _RegistrationCard extends StatelessWidget {
  final StudentRegistration reg;
  const _RegistrationCard({required this.reg});

  @override
  Widget build(BuildContext context) {
    final isPending = reg.status == 'Pending';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isPending ? AppTheme.gold.withOpacity(0.3) : AppTheme.red.withOpacity(0.12)),
        boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: const BoxDecoration(gradient: AppTheme.primaryGradient, shape: BoxShape.circle),
              child: Center(child: Text(reg.name.isNotEmpty ? reg.name[0] : '?', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(reg.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              Text('${reg.studentId} · ${reg.faculty}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ])),
            StatusBadge(reg.status),
          ]),

          const SizedBox(height: 10),

          // Details
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.creamLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _DetailRow('Email', reg.email),
              _DetailRow('Submitted', fmtDate(reg.submittedDate)),
            ]),
          ),

          // Actions for pending
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlineBtn(
                label: 'Reject',
                color: AppTheme.danger,
                onPressed: () => _showRejectDialog(context, reg),
              )),
              const SizedBox(width: 10),
              Expanded(child: GradientButton(
                label: 'Approve',
                onPressed: () => _showApproveDialog(context, reg),
              )),
            ]),
          ],
        ]),
      ),
    );
  }

  void _showApproveDialog(BuildContext context, StudentRegistration reg) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Approve Registration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Approve ${reg.name} (${reg.studentId})?\n\nThis will create a student account and allow them to log in.', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.5)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppTheme.red.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Student ID: ${reg.studentId}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text('Faculty: ${reg.faculty}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text('Email: ${reg.email}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              // Approve registration in DataService
              context.read<DataService>().approveRegistration(reg.id);
              // Create login account in AuthService via AppState
              context.read<AppState>().addApprovedStudent(
                reg.studentId,
                reg.password,
                reg.name,
                email: reg.email,
                programme: reg.faculty,
              );
              _toast(context, '${reg.name} approved! Account created.');
            },
            child: const Text('Approve', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(BuildContext context, StudentRegistration reg) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Registration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text('Reject registration for ${reg.name} (${reg.studentId})?\n\nThe student will not be able to log in.', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              context.read<DataService>().rejectRegistration(reg.id);
              _toast(context, '${reg.name} registration rejected.');
            },
            child: const Text('Reject', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  const _DetailRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted)),
      Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
    ]),
  );
}
