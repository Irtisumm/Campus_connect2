import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../widgets/common.dart';
import '../../data/mock_data.dart';
import '../../theme/app_theme.dart';
import '../../services/data_service.dart';

// ── Student Registration Screen ─────────────────────────────────
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});
  @override State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _studentIdCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  String? _faculty;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _agreed = false;
  bool _done = false;

  static const _faculties = [
    'Faculty of Computing',
    'Faculty of Engineering',
    'Faculty of Business',
    'Faculty of Education',
    'Faculty of Creative Media',
    'Faculty of Hospitality',
  ];

  @override
  void dispose() {
    _studentIdCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return Scaffold(
        backgroundColor: AppTheme.bgApp,
        body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 80, height: 80, decoration: BoxDecoration(gradient: LinearGradient(colors: [AppTheme.red.withOpacity(0.2), AppTheme.redLight.withOpacity(0.15)]), shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: AppTheme.red, size: 40)).animate().scale(delay: 100.ms, duration: 400.ms, curve: Curves.elasticOut),
          const SizedBox(height: 24),
          const Text('Registration Submitted!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 12),
          const Text('Your account is pending admin approval.\nYou will be able to log in once approved.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.65)).animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 28),
          GradientButton(label: 'Back to Login', onPressed: () => context.go('/login')),
        ])))),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bgApp,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(children: [
            const SizedBox(height: 40),
            Center(
              child: Container(
                width: 70, height: 70,
                decoration: const BoxDecoration(gradient: AppTheme.primaryGradient, shape: BoxShape.circle),
                child: const Icon(Icons.person_add_rounded, size: 38, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Create Account', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
            const SizedBox(height: 6),
            const Text('Register your student account', style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            const SizedBox(height: 28),

            // Form
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Form(
                key: _formKey,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Student ID', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _studentIdCtrl,
                    decoration: const InputDecoration(hintText: 'e.g. S220500', prefixIcon: Icon(Icons.badge_rounded)),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Student ID is required';
                      if (!v.startsWith('S') || v.length < 4) return 'Must start with S followed by numbers';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  const Text('Full Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(hintText: 'Your full name', prefixIcon: Icon(Icons.person_rounded)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 16),

                  const Text('Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(hintText: 'student@city.edu.my', prefixIcon: Icon(Icons.email_rounded)),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Email is required';
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  const Text('Faculty', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _faculty,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.school_rounded)),
                    hint: const Text('Select your faculty'),
                    items: _faculties.map((f) => DropdownMenuItem(value: f, child: Text(f, style: const TextStyle(fontSize: 14)))).toList(),
                    onChanged: (v) => setState(() => _faculty = v),
                    validator: (v) => v == null ? 'Faculty is required' : null,
                  ),
                  const SizedBox(height: 16),

                  const Text('Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscurePass,
                    decoration: InputDecoration(
                      hintText: 'Choose a password',
                      prefixIcon: const Icon(Icons.lock_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePass ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: AppTheme.textMuted),
                        onPressed: () => setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required';
                      if (v.length < 6) return 'At least 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  const Text('Confirm Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _confirmPassCtrl,
                    obscureText: _obscureConfirm,
                    decoration: InputDecoration(
                      hintText: 'Re-enter password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: AppTheme.textMuted),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Please confirm password';
                      if (v != _passCtrl.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Agreement
                  InkWell(
                    onTap: () => setState(() => _agreed = !_agreed),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Checkbox(
                          value: _agreed,
                          onChanged: (v) => setState(() => _agreed = v ?? false),
                          activeColor: AppTheme.red,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        const Expanded(child: Text(
                          'I confirm that the information provided is accurate and agree to the university policies.',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                        )),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Submit
                  GradientButton(
                    label: 'Register',
                    onPressed: _agreed ? () {
                      if (_formKey.currentState!.validate()) {
                        final dataService = context.read<DataService>();
                        final reg = StudentRegistration(
                          id: 'REG-${DateTime.now().millisecondsSinceEpoch}',
                          studentId: _studentIdCtrl.text.trim(),
                          name: _nameCtrl.text.trim(),
                          email: _emailCtrl.text.trim(),
                          faculty: _faculty!,
                          password: _passCtrl.text,
                          status: 'Pending',
                          submittedDate: DateTime.now().toString().split(' ')[0],
                        );
                        dataService.submitRegistration(reg);
                        setState(() => _done = true);
                      }
                    } : null,
                  ),
                ]),
              ),
            ),

            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => context.go('/login'),
              child: const Text('Already have an account? Sign In', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.red)),
            ),
            const SizedBox(height: 16),
            const Text('v2.0 | City University Malaysia', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}
