import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) context.go('/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
        child: SafeArea(
          child: Stack(
            children: [
              // ── Center content ──
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo container
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.school_rounded, size: 48, color: Colors.white),
                    ).animate().fadeIn(duration: 300.ms),
                    const SizedBox(height: 20),
                    // App name
                    const Text(
                      'Campus Connect',
                      style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w800,
                        color: Colors.white, letterSpacing: -0.5,
                      ),
                    ).animate().fadeIn(delay: 300.ms, duration: 500.ms).slideY(begin: 0.3, end: 0),
                    const SizedBox(height: 6),
                    // University name
                    Text(
                      'City University Malaysia',
                      style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ).animate().fadeIn(delay: 500.ms, duration: 500.ms).slideY(begin: 0.3, end: 0),
                    const SizedBox(height: 40),
                    // Loading indicator
                    const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    ).animate().fadeIn(delay: 800.ms, duration: 400.ms),
                  ],
                ),
              ),
              // ── Bottom text ──
              Positioned(
                bottom: 40,
                left: 0, right: 0,
                child: Center(
                  child: Text(
                    'Powered by Campus Services',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                ).animate().fadeIn(delay: 1000.ms),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
