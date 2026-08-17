import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';

// ── Dev account model for quick-switch ──────────────────────────────
// These are the accounts created by tools/seed_dev_accounts.mjs.
// Passwords are stored here for dev convenience only — this is NOT
// a production feature and must never ship to end users.

class _DevAccount {
  final String id;
  final String password;
  final String label;
  final bool isAdmin;
  const _DevAccount({
    required this.id,
    required this.password,
    required this.label,
    required this.isAdmin,
  });
}

const _kDevAccounts = <_DevAccount>[
  // Admins
  _DevAccount(id: 'ADMIN001', password: 'Admin@12345', label: 'Admin 1', isAdmin: true),
  _DevAccount(id: 'ADMIN002', password: 'Admin@12345', label: 'Admin 2', isAdmin: true),
  // Students
  _DevAccount(id: 'S001', password: 'Student@123', label: 'Student 1', isAdmin: false),
  _DevAccount(id: 'S002', password: 'Student@123', label: 'Student 2', isAdmin: false),
  _DevAccount(id: 'S003', password: 'Student@123', label: 'Student 3', isAdmin: false),
  _DevAccount(id: 'S004', password: 'Student@123', label: 'Student 4', isAdmin: false),
  _DevAccount(id: 'S005', password: 'Student@123', label: 'Student 5', isAdmin: false),
];

class LoginScreen extends StatefulWidget {
  final bool isAdminLogin;
  /// When true, the login screen behaves as a dialog (pop on success).
  /// When false, it navigates to the main app on success.
  final bool isDialog;
  const LoginScreen({super.key, this.isAdminLogin = false, this.isDialog = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late TextEditingController _idCtrl;
  late TextEditingController _passCtrl;
  bool _isLoading = false;
  bool _obscurePass = true;
  bool _rememberMe = false;
  String? _errorMsg;
  late bool _isAdmin;

  @override
  void initState() {
    super.initState();
    _idCtrl = TextEditingController();
    _passCtrl = TextEditingController();
    _isAdmin = widget.isAdminLogin;
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    if (widget.isDialog) return; // Don't auto-fill in dialog mode
    final appState = context.read<AppState>();
    // Only the identifier is remembered — passwords are never persisted.
    final savedId = await appState.loadRememberedIdentifier();
    if (savedId != null && mounted) {
      setState(() {
        _idCtrl.text = savedId;
        _rememberMe = true;
      });
    }
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_idCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _errorMsg = 'Please fill all fields');
      return;
    }

    setState(() { _isLoading = true; _errorMsg = null; });
    final appState = context.read<AppState>();

    final result = await appState.loginUser(
      _idCtrl.text.trim(),
      _passCtrl.text,
      _isAdmin,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      // Remember the identifier only — never the password.
      if (_rememberMe) {
        appState.saveRememberedIdentifier(_idCtrl.text.trim());
      } else {
        appState.clearRememberedIdentifier();
      }

      if (widget.isDialog) {
        Navigator.pop(context, true);
      } else {
        context.go('/lost-found');
      }
    } else {
      setState(() => _errorMsg = result.message ?? 'Invalid ID or password');
    }
  }

  /// Sends a Firebase password-reset email to the address behind the ID
  /// currently typed in the form.
  Future<void> _handleForgotPassword() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<AppState>().sendPasswordReset(_idCtrl.text);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.message ?? 'Password reset email sent'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If used as a dialog overlay (admin toggle), use simpler layout
    if (widget.isDialog) return _buildDialogLayout();

    return Scaffold(
      backgroundColor: AppTheme.bgApp,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ── Top section ──
              const SizedBox(height: 60),
              Center(
                child: Container(
                  width: 80, height: 80,
                  decoration: const BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isAdmin ? Icons.shield_rounded : Icons.person_rounded,
                    size: 48, color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _isAdmin ? 'Admin Portal' : 'Welcome Back',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                _isAdmin ? 'Enter your admin credentials' : 'Sign in to your student account',
                style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 40),

              // ── Dev account quick-switch ──
              if (!widget.isDialog)
                _DevAccountSwitcher(
                  isAdmin: _isAdmin,
                  onSelect: (account) {
                    setState(() {
                      _idCtrl.text = account.id;
                      _passCtrl.text = account.password;
                      _errorMsg = null;
                    });
                  },
                ),
              if (!widget.isDialog) const SizedBox(height: 16),

              // ── Form card ──
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Error state
                    if (_errorMsg != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withOpacity(0.1),
                          border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMsg!,
                                style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600, fontSize: 13),
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ID field
                    Text(
                      _isAdmin ? 'Admin ID' : 'Student ID',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _idCtrl,
                      enabled: !_isLoading,
                      decoration: InputDecoration(
                        hintText: _isAdmin ? 'e.g. ADMIN001' : 'e.g. S001',
                        prefixIcon: const Icon(Icons.badge_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Password field
                    const Text('Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscurePass,
                      enabled: !_isLoading,
                      decoration: InputDecoration(
                        hintText: '--------',
                        prefixIcon: const Icon(Icons.lock_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePass ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: AppTheme.textMuted),
                          onPressed: () => setState(() => _obscurePass = !_obscurePass),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Forgot password
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: _isLoading ? null : _handleForgotPassword,
                        child: const Text('Forgot Password?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.red)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Remember Me checkbox
                    Row(
                      children: [
                        SizedBox(
                          width: 24, height: 24,
                          child: Checkbox(
                            value: _rememberMe,
                            onChanged: (v) => setState(() => _rememberMe = v ?? false),
                            activeColor: AppTheme.red,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _rememberMe = !_rememberMe),
                            child: const Text('Remember my credentials', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Sign In button
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: _isLoading ? null : _handleLogin,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 4))],
                          ),
                          child: Center(
                            child: _isLoading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Sign In', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Demo credentials
                    Center(
                      child: Text(
                        _isAdmin ? 'Admin: ADMIN001 / Admin@12345' : 'Student: S001 / Student@123',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Bottom section ──
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => setState(() {
                  _isAdmin = !_isAdmin;
                  _idCtrl.clear();
                  _passCtrl.clear();
                  _errorMsg = null;
                }),
                child: Text(
                  _isAdmin ? 'Switch to Student Login' : 'Are you admin?',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.red),
                ),
              ),
              if (!_isAdmin) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => context.push('/register'),
                  child: const Text(
                    "Don't have an account? Register",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.red),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text('v2.0 | City University Malaysia', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// Simpler dialog layout used when switching to admin from the header toggle.
  Widget _buildDialogLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isAdmin ? 'Admin Login' : 'Student Login'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(gradient: AppTheme.primaryGradient, shape: BoxShape.circle),
                child: Icon(_isAdmin ? Icons.shield_rounded : Icons.person_rounded, size: 48, color: Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            if (_errorMsg != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(0.1),
                  border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_errorMsg!, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 20),
            ],
            const Text('ID / Username', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
            const SizedBox(height: 8),
            TextField(controller: _idCtrl, enabled: !_isLoading,
              decoration: InputDecoration(hintText: _isAdmin ? 'ADMIN001' : 'S001', prefixIcon: const Icon(Icons.badge_rounded))),
            const SizedBox(height: 16),
            const Text('Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
            const SizedBox(height: 8),
            TextField(controller: _passCtrl, obscureText: _obscurePass, enabled: !_isLoading,
              decoration: InputDecoration(
                hintText: '••••••••', prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePass ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: AppTheme.textMuted),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              )),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Login'),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                _isAdmin ? 'Admin: ADMIN001 / Admin@12345' : 'Student: S001 / Student@123',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dev Account Quick-Switch Widget ─────────────────────────────────
// Renders tappable chips that auto-fill the login form. Only visible
// when the login screen is used full-screen (not in dialog mode).

class _DevAccountSwitcher extends StatelessWidget {
  final bool isAdmin;
  final void Function(_DevAccount account) onSelect;

  const _DevAccountSwitcher({
    required this.isAdmin,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final accounts = _kDevAccounts.where((a) => a.isAdmin == isAdmin).toList();
    if (accounts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.switch_account_rounded,
                  size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              const Text(
                'Quick Switch',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: accounts.map((a) {
              return Material(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(20),
                elevation: 0.5,
                child: InkWell(
                  onTap: () => onSelect(a),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: AppTheme.red.withOpacity(0.2), width: 1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isAdmin
                              ? Icons.shield_rounded
                              : Icons.person_rounded,
                          size: 14,
                          color: AppTheme.red,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          a.label,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
