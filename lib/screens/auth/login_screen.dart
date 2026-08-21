import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/luxe.dart';

class LoginScreen extends StatefulWidget {
  final bool isAdminLogin;

  /// When true, the login screen behaves as a dialog (pop on success).
  /// When false, it navigates to the main app on success.
  final bool isDialog;

  const LoginScreen({
    super.key,
    this.isAdminLogin = false,
    this.isDialog = false,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _idCtrl;
  late final TextEditingController _passCtrl;
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
    if (widget.isDialog) return;
    final appState = context.read<AppState>();
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

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    final appState = context.read<AppState>();

    final result = await appState.loginUser(
      _idCtrl.text.trim(),
      _passCtrl.text,
      _isAdmin,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
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
    final result =
        await context.read<AppState>().sendPasswordReset(_idCtrl.text);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.message ?? 'Password reset email sent'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleAccountType() {
    setState(() {
      _isAdmin = !_isAdmin;
      _idCtrl.clear();
      _passCtrl.clear();
      _errorMsg = null;
    });
  }

  void _applyStudentCredential(_StudentCredential account) {
    setState(() {
      _idCtrl.text = account.id;
      _passCtrl.text = account.password;
      _errorMsg = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isDialog) return _buildDialogLayout();

    return Scaffold(
      backgroundColor: Luxe.bg,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _LoginBackdropPainter()),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 760;
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    24,
                    compact ? 14 : 24,
                    24,
                    12,
                  ),
                  child: Column(
                    children: [
                      const _CampusLogo(size: 76),
                      SizedBox(height: compact ? 14 : 18),
                      Text(
                        _isAdmin ? 'Admin Portal' : 'Welcome Back',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 31,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF14213D),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _isAdmin
                            ? 'Enter your admin credentials'
                            : 'Sign in to your student account',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF758195),
                        ),
                      ),
                      SizedBox(height: compact ? 22 : 28),
                      _buildLoginCard(),
                      const SizedBox(height: 14),
                      _LoginOptionCard(
                        icon: Icons.shield_outlined,
                        title: _isAdmin
                            ? 'Switch to Student Login'
                            : 'Are you an admin?',
                        onTap: _toggleAccountType,
                      ),
                      if (!_isAdmin) ...[
                        const SizedBox(height: 10),
                        _LoginOptionCard(
                          icon: Icons.person_add_alt_1_rounded,
                          title: 'Don\'t have an account?',
                          accent: 'Register',
                          onTap: () => context.push('/register'),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const SizedBox(
                        height: 86,
                        width: double.infinity,
                        child: CustomPaint(painter: _LoginSkylinePainter()),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'v2.0 | City University Malaysia',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF8290A3),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Luxe.primary.withValues(alpha: 0.09)),
        boxShadow: [
          BoxShadow(
            color: Luxe.primary.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFF718096).withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_errorMsg != null) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.danger.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppTheme.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMsg!,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        color: AppTheme.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          _LoginFieldLabel(_isAdmin ? 'Admin ID' : 'Student ID'),
          const SizedBox(height: 7),
          _LoginTextField(
            controller: _idCtrl,
            enabled: !_isLoading,
            icon: Icons.person_outline_rounded,
            hintText: 'Enter your student ID',
            textInputAction: TextInputAction.next,
            suffix: _isAdmin
                ? null
                : _SavedStudentPicker(onSelected: _applyStudentCredential),
          ),
          const SizedBox(height: 17),
          const _LoginFieldLabel('Password'),
          const SizedBox(height: 7),
          _LoginTextField(
            controller: _passCtrl,
            enabled: !_isLoading,
            icon: Icons.lock_outline_rounded,
            hintText: 'Enter your password',
            obscureText: _obscurePass,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!_isLoading) _handleLogin();
            },
            suffix: IconButton(
              tooltip: _obscurePass ? 'Show password' : 'Hide password',
              onPressed: _isLoading
                  ? null
                  : () => setState(() => _obscurePass = !_obscurePass),
              icon: Icon(
                _obscurePass
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 21,
                color: const Color(0xFF7A8798),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: _isLoading ? null : _handleForgotPassword,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Luxe.primaryDeep,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          InkWell(
            onTap: _isLoading
                ? null
                : () => setState(() => _rememberMe = !_rememberMe),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  _RememberBox(checked: _rememberMe),
                  const SizedBox(width: 10),
                  const Text(
                    'Remember me',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF59677A),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SignInButton(isLoading: _isLoading, onTap: _handleLogin),
        ],
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
                decoration: const BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isAdmin ? Icons.shield_rounded : Icons.person_rounded,
                  size: 48,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_errorMsg != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.1),
                  border: Border.all(
                    color: AppTheme.danger.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _errorMsg!,
                  style: const TextStyle(
                    color: AppTheme.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            const Text(
              'ID / Username',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _idCtrl,
              enabled: !_isLoading,
              decoration: InputDecoration(
                hintText: _isAdmin ? 'ADMIN001' : 'S001',
                prefixIcon: const Icon(Icons.badge_rounded),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Password',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              enabled: !_isLoading,
              decoration: InputDecoration(
                hintText: '********',
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  tooltip: _obscurePass ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePass
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: AppTheme.textMuted,
                  ),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Login'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentCredential {
  final String id;
  final String password;
  final String label;

  const _StudentCredential({
    required this.id,
    required this.password,
    required this.label,
  });
}

const _savedStudentCredentials = <_StudentCredential>[
  _StudentCredential(id: 'S001', password: 'Student@123', label: 'Student 1'),
  _StudentCredential(id: 'S002', password: 'Student@123', label: 'Student 2'),
  _StudentCredential(id: 'S003', password: 'Student@123', label: 'Student 3'),
  _StudentCredential(id: 'S004', password: 'Student@123', label: 'Student 4'),
  _StudentCredential(id: 'S005', password: 'Student@123', label: 'Student 5'),
];

class _SavedStudentPicker extends StatelessWidget {
  final ValueChanged<_StudentCredential> onSelected;

  const _SavedStudentPicker({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_StudentCredential>(
      tooltip: 'Choose saved student',
      padding: EdgeInsets.zero,
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 22,
        color: Color(0xFF7A8798),
      ),
      onSelected: onSelected,
      itemBuilder: (context) => _savedStudentCredentials
          .map(
            (account) => PopupMenuItem<_StudentCredential>(
              value: account,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.person_outline_rounded,
                    size: 20,
                    color: Luxe.primaryDeep,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        account.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        account.id,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7A8798),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _CampusLogo extends StatelessWidget {
  final double size;

  const _CampusLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE92D51), Color(0xFFB7193E)],
        ),
        borderRadius: BorderRadius.circular(23),
        boxShadow: [
          BoxShadow(
            color: Luxe.primary.withValues(alpha: 0.24),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.shield_outlined,
            size: size * 0.70,
            color: Colors.white.withValues(alpha: 0.96),
          ),
          Icon(
            Icons.school_rounded,
            size: size * 0.36,
            color: Colors.white,
          ),
        ],
      ),
    );
  }
}

class _LoginFieldLabel extends StatelessWidget {
  final String label;

  const _LoginFieldLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Color(0xFF26354C),
      ),
    );
  }
}

class _LoginTextField extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final String hintText;
  final bool enabled;
  final bool obscureText;
  final TextInputAction textInputAction;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  const _LoginTextField({
    required this.controller,
    required this.icon,
    required this.hintText,
    required this.enabled,
    this.obscureText = false,
    this.textInputAction = TextInputAction.next,
    this.suffix,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: Color(0xFF26354C),
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF8793A3),
        ),
        filled: true,
        fillColor: Colors.white,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 10, right: 10),
          child: _FieldIcon(icon: icon),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 62,
          minHeight: 56,
        ),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 50,
          minHeight: 56,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2E6EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2E6EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Luxe.primary, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2E6EB)),
        ),
      ),
    );
  }
}

class _FieldIcon extends StatelessWidget {
  final IconData icon;

  const _FieldIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Luxe.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, size: 22, color: Luxe.primaryDeep),
    );
  }
}

class _RememberBox extends StatelessWidget {
  final bool checked;

  const _RememberBox({required this.checked});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 25,
      height: 25,
      decoration: BoxDecoration(
        color: checked ? Luxe.primaryDeep : Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: checked ? Luxe.primaryDeep : const Color(0xFFD8DEE6),
          width: 1.3,
        ),
        boxShadow: checked
            ? [
                BoxShadow(
                  color: Luxe.primary.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
          : null,
    );
  }
}

class _SignInButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _SignInButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            gradient: Luxe.heroGradient,
            borderRadius: BorderRadius.circular(17),
            boxShadow: [
              BoxShadow(
                color: Luxe.primary.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 11),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 23,
                        ),
                ),
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    'Sign In',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 47),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? accent;
  final VoidCallback onTap;

  const _LoginOptionCard({
    required this.icon,
    required this.title,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Luxe.primary.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: Luxe.primary.withValues(alpha: 0.035),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Luxe.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 23, color: Luxe.primaryDeep),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: accent == null
                    ? Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF26354C),
                        ),
                      )
                    : Text.rich(
                        TextSpan(
                          text: '$title ',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF26354C),
                          ),
                          children: [
                            TextSpan(
                              text: accent,
                              style: const TextStyle(
                                color: Luxe.primaryDeep,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 24,
                color: Color(0xFF7A8798),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginBackdropPainter extends CustomPainter {
  const _LoginBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Luxe.primary.withValues(alpha: 0.025);

    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.98, size.height * 0.04),
        radius: size.width * 0.82,
      ),
      mathPi * 0.44,
      mathPi * 0.90,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.98, size.height * 0.04),
        radius: size.width * 1.10,
      ),
      mathPi * 0.44,
      mathPi * 0.90,
      false,
      stroke,
    );
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.35),
      size.width * 0.55,
      Paint()..color = const Color(0xFFFFE9EE).withValues(alpha: 0.13),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LoginSkylinePainter extends CustomPainter {
  const _LoginSkylinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final color = Luxe.primary.withValues(alpha: 0.085);
    final soft = Luxe.primary.withValues(alpha: 0.055);
    final baseline = size.height * 0.82;
    final building = Paint()..color = color;
    final detail = Paint()..color = soft;

    void block(double x, double width, double height) {
      canvas.drawRect(
        Rect.fromLTWH(x, baseline - height, width, height),
        building,
      );
      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 2; col++) {
          canvas.drawRect(
            Rect.fromLTWH(
              x + width * (0.22 + col * 0.40),
              baseline - height + 9 + row * 11,
              width * 0.12,
              5,
            ),
            detail,
          );
        }
      }
    }

    block(size.width * 0.02, size.width * 0.12, size.height * 0.42);
    block(size.width * 0.15, size.width * 0.10, size.height * 0.30);
    block(size.width * 0.76, size.width * 0.10, size.height * 0.34);
    block(size.width * 0.88, size.width * 0.12, size.height * 0.46);

    final centerX = size.width * 0.50;
    final centerWidth = size.width * 0.27;
    final centerLeft = centerX - centerWidth / 2;
    canvas.drawRect(
      Rect.fromLTWH(
        centerLeft,
        baseline - size.height * 0.39,
        centerWidth,
        size.height * 0.39,
      ),
      building,
    );
    canvas.drawPath(
      Path()
        ..moveTo(centerLeft - size.width * 0.03, baseline - size.height * 0.39)
        ..lineTo(centerX, baseline - size.height * 0.54)
        ..lineTo(centerLeft + centerWidth + size.width * 0.03,
            baseline - size.height * 0.39)
        ..close(),
      building,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        centerX - 1.5,
        baseline - size.height * 0.62,
        3,
        size.height * 0.08,
      ),
      building,
    );
    canvas.drawCircle(
      Offset(centerX, baseline - size.height * 0.64),
      2.5,
      building,
    );

    for (final x in [0.20, 0.27, 0.72, 0.82]) {
      final treeX = size.width * x;
      canvas.drawRect(
        Rect.fromLTWH(treeX - 1.5, baseline - 18, 3, 18),
        detail,
      );
      canvas.drawCircle(Offset(treeX, baseline - 22), 10, detail);
      canvas.drawCircle(Offset(treeX - 7, baseline - 16), 7, detail);
      canvas.drawCircle(Offset(treeX + 7, baseline - 16), 7, detail);
    }

    canvas.drawPath(
      Path()
        ..moveTo(0, baseline + 1)
        ..quadraticBezierTo(
          size.width * 0.50,
          baseline - 12,
          size.width,
          baseline + 1,
        )
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = soft,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

const double mathPi = 3.141592653589793;
