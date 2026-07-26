import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';

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
    final creds = await appState.loadSavedCredentials();
    if (creds != null && mounted) {
      setState(() {
        _idCtrl.text = creds['id']!;
        _passCtrl.text = creds['password']!;
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

    final success = await appState.loginUser(
      _idCtrl.text.trim(),
      _passCtrl.text,
      _isAdmin,
    );

    setState(() => _isLoading = false);

    if (success) {
      if (!mounted) return;

      // Save or clear credentials based on Remember Me
      if (_rememberMe) {
        appState.saveCredentials(_idCtrl.text.trim(), _passCtrl.text);
      } else {
        appState.clearSavedCredentials();
      }

      if (widget.isDialog) {
        Navigator.pop(context, true);
      } else {
        context.go('/lost-found');
      }
    } else {
      setState(() => _errorMsg = 'Invalid ID or password');
    }
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
                            Text(_errorMsg!, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600, fontSize: 13)),
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
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Contact admin to reset password'), behavior: SnackBarBehavior.floating),
                        ),
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
                        GestureDetector(
                          onTap: () => setState(() => _rememberMe = !_rememberMe),
                          child: const Text('Remember my credentials', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
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
                        _isAdmin ? 'Demo credentials: ADMIN001 / admin123' : 'Demo credentials: S001 / pass123',
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
                _isAdmin ? 'Demo: ADMIN001 / admin123' : 'Demo: S001 / pass123',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
