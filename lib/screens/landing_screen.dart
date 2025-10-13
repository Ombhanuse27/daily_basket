import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';
import 'package:daily_basket/screens/login_screen.dart';
import 'package:daily_basket/screens/dashboard.dart';
import 'package:daily_basket/screens/emp_dashboard.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:ui'; // Required for ImageFilter.blur

// --- MAIN LANDING SCREEN WIDGET ---
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with TickerProviderStateMixin {
  // Animation Controllers
  late AnimationController _entranceController;
  late AnimationController _progressController;
  late AnimationController _backgroundController; // For animated background

  // Parallax effect state
  double _parallaxX = 0.0;
  double _parallaxY = 0.0;
  StreamSubscription? _accelerometerSubscription;

  String _statusMessage = "Initializing your workspace...";

  // Modern UI Colors
  static const Color _accentColor = Color(0xFF00FFA3);
  static const Color _textColor = Colors.white;
  static const Color _darkBgColor = Color(0xFF1A234E);
  static const Color _lightBgColor = Color(0xFF121212);

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeParallax();
    _startAnimationsAndCheckSession();
  }

  void _initializeAnimations() {
    _entranceController = AnimationController(
        duration: const Duration(milliseconds: 2000), vsync: this);
    _progressController =
    AnimationController(duration: const Duration(seconds: 2), vsync: this)
      ..repeat(reverse: true);
    _backgroundController =
    AnimationController(duration: const Duration(seconds: 15), vsync: this)
      ..repeat(reverse: true);
  }

  void _initializeParallax() {
    _accelerometerSubscription =
        accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
            .listen((AccelerometerEvent event) {
          if (mounted) {
            setState(() {
              // Parallax sensitivity
              _parallaxX = _parallaxX * 0.9 + event.x * 0.1 * -2.0;
              _parallaxY = _parallaxY * 0.9 + event.y * 0.1 * 2.0;
            });
          }
        });
  }

  void _startAnimationsAndCheckSession() {
    _entranceController.forward();
    Future.delayed(const Duration(seconds: 4), _checkSession);
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _progressController.dispose();
    _backgroundController.dispose();
    _accelerometerSubscription?.cancel();
    super.dispose();
  }

  // --- SESSION MANAGEMENT & NAVIGATION LOGIC (UNCHANGED) ---
  void _updateStatusMessage(String message) {
    if (mounted) setState(() => _statusMessage = message);
  }

  Future<void> _checkSession() async {
    try {
      _updateStatusMessage("Checking your credentials...");
      final prefs = await SharedPreferences.getInstance();
      final userEmail = prefs.getString('user_email');
      final userType = prefs.getString('user_type');
      final adminId = prefs.getString('admin_id');

      if (userEmail == null || userEmail.isEmpty) {
        _updateStatusMessage("Redirecting to login...");
        await Future.delayed(const Duration(seconds: 1));
        _goToLogin();
        return;
      }

      if (userType == 'employee') {
        await _checkEmployeeSession(userEmail, adminId);
      } else if (userType == 'admin') {
        await _checkAdminSession(userEmail);
      } else {
        _updateStatusMessage("Invalid session type, logging out...");
        await _clearSessionAndGoToLogin();
      }
    } catch (e) {
      _updateStatusMessage("Session verification failed...");
      await Future.delayed(const Duration(seconds: 1));
      _goToLogin();
    }
  }

  Future<void> _checkAdminSession(String userEmail) async {
    try {
      _updateStatusMessage("Verifying admin access...");
      final snapshot = await FirebaseFirestore.instance
          .collection('admins')
          .where('email', isEqualTo: userEmail)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        _updateStatusMessage("Admin not found...");
        await _clearSessionAndGoToLogin();
        return;
      }

      final data = snapshot.docs.first.data();
      final expiry = (data['expiryDate'] as Timestamp).toDate();

      if (DateTime.now().isAfter(expiry)) {
        _updateStatusMessage("Admin session expired...");
        await _clearSessionAndGoToLogin();
      } else {
        _updateStatusMessage("Welcome back, Admin!");
        await Future.delayed(const Duration(seconds: 1));
        _goToDashboard(userEmail, 'admin');
      }
    } catch (e) {
      _updateStatusMessage("Error verifying admin: ${e.toString()}");
      await _clearSessionAndGoToLogin();
    }
  }

  Future<void> _checkEmployeeSession(String userEmail, String? adminId) async {
    try {
      if (adminId == null || adminId.isEmpty) {
        _updateStatusMessage("Invalid employee session: Missing admin ID");
        await _clearSessionAndGoToLogin();
        return;
      }

      _updateStatusMessage("Verifying employee access...");
      final adminDoc =
      await FirebaseFirestore.instance.collection('admins').doc(adminId).get();

      if (!adminDoc.exists) {
        _updateStatusMessage("Associated admin not found");
        await _clearSessionAndGoToLogin();
        return;
      }

      final adminData = adminDoc.data() as Map<String, dynamic>;
      final adminExpiry = (adminData['expiryDate'] as Timestamp).toDate();

      if (DateTime.now().isAfter(adminExpiry)) {
        _updateStatusMessage("Admin subscription has expired");
        await _clearSessionAndGoToLogin();
        return;
      }

      final employeeQuery = await FirebaseFirestore.instance
          .collection('admins')
          .doc(adminId)
          .collection('employees')
          .where('email', isEqualTo: userEmail)
          .limit(1)
          .get();

      if (employeeQuery.docs.isEmpty) {
        _updateStatusMessage("Employee not found under this admin");
        await _clearSessionAndGoToLogin();
        return;
      }

      final employeeDoc = employeeQuery.docs.first;
      final employeeData = employeeDoc.data();

      if (employeeData['isActive'] != true) {
        _updateStatusMessage("Employee account is deactivated");
        await _clearSessionAndGoToLogin();
        return;
      }

      if (employeeData.containsKey('expiryDate') &&
          employeeData['expiryDate'] != null) {
        final employeeExpiry =
        (employeeData['expiryDate'] as Timestamp).toDate();
        if (DateTime.now().isAfter(employeeExpiry)) {
          _updateStatusMessage("Employee access has expired");
          await _clearSessionAndGoToLogin();
          return;
        }
      }

      _updateStatusMessage(
          "Welcome back, ${employeeData['name'] ?? 'Employee'}!");
      await Future.delayed(const Duration(seconds: 1));
      _goToDashboard(userEmail, 'employee', adminId: adminId);
    } catch (e) {
      _updateStatusMessage("Error verifying employee: ${e.toString()}");
      await _clearSessionAndGoToLogin();
    }
  }

  Future<void> _clearSessionAndGoToLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await Future.delayed(const Duration(seconds: 2));
    _goToLogin();
  }

  void _goToLogin() {
    if (mounted) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  void _goToDashboard(String email, String userType, {String? adminId}) {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => (userType == 'admin')
              ? AdminDashboard(userEmail: email)
              : EmployeeDashboard(userEmail: email),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  // --- UI BUILD METHOD & WIDGETS (REDESIGNED "MODERN" THEME) ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MouseRegion(
        onHover: (event) {
          final size = MediaQuery.of(context).size;
          if (mounted) {
            setState(() {
              _parallaxX = (event.position.dx - size.width / 2) / 80;
              _parallaxY = (event.position.dy - size.height / 2) / 80;
            });
          }
        },
        child: Stack(
          children: [
            _buildAnimatedBackground(),
            Center(
              child: _buildAnimatedContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: _backgroundController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [_darkBgColor, _lightBgColor],
              stops: [0.0, 0.7 + _backgroundController.value * 0.3],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedContent() {
    return TweenAnimationBuilder<Offset>(
      duration: const Duration(milliseconds: 200),
      tween: Tween<Offset>(
          begin: Offset.zero, end: Offset(_parallaxX, _parallaxY)),
      builder: (context, offset, _) {
        return Transform.translate(
          offset: offset,
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                _buildStaggeredAnimatedItem(
                  interval: const Interval(0.2, 0.8, curve: Curves.easeOut),
                  child: _buildLottieSection(),
                ),
                const SizedBox(height: 40),
                _buildStaggeredAnimatedItem(
                  interval: const Interval(0.4, 1.0, curve: Curves.easeOut),
                  child: _buildAppIdentity(),
                ),
                const SizedBox(height: 32),
                _buildStaggeredAnimatedItem(
                  interval: const Interval(0.5, 1.0, curve: Curves.easeOut),
                  child: _buildLoadingSection(),
                ),
                const Spacer(flex: 3),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStaggeredAnimatedItem({
    required Widget child,
    required Interval interval,
  }) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _entranceController, curve: interval),
      child: SlideTransition(
        position: CurvedAnimation(parent: _entranceController, curve: interval)
            .drive(Tween<Offset>(
            begin: const Offset(0, 0.5), end: Offset.zero)),
        child: child,
      ),
    );
  }

  Widget _buildLottieSection() {
    // This creates the "glass" effect.
    return ClipRRect(
      borderRadius: BorderRadius.circular(125),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(125),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Center(
            child: Lottie.asset('assets/images/groceries.json', width: 200),
          ),
        ),
      ),
    );
  }

  Widget _buildAppIdentity() {
    return Column(
      children: [
        Text(
          "DailyBasket",
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: _textColor,
            shadows: [
              Shadow(
                blurRadius: 20.0,
                color: _accentColor.withOpacity(0.7),
                offset: Offset.zero,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Smart Store Management",
          style: TextStyle(
            fontSize: 16,
            color: _textColor.withOpacity(0.7),
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingSection() {
    return Column(
      children: [
        ModernProgressIndicator(
          width: 280,
          height: 8,
          controller: _progressController,
        ),
        const SizedBox(height: 24),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (Widget child, Animation<double> animation) =>
              FadeTransition(opacity: animation, child: child),
          child: Text(
            _statusMessage,
            key: ValueKey<String>(_statusMessage),
            style: TextStyle(
              color: _textColor.withOpacity(0.6),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// --- CUSTOM MODERN PROGRESS INDICATOR WIDGET ---
class ModernProgressIndicator extends StatelessWidget {
  final double width;
  final double height;
  final AnimationController controller;

  const ModernProgressIndicator({
    super.key,
    required this.width,
    required this.height,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    // The track of the progress bar
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(height),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            // The moving fill of the progress bar
            return FractionallySizedBox(
              widthFactor: controller.value,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height),
                  gradient: LinearGradient(
                    colors: [
                      _LandingScreenState._accentColor.withOpacity(0.8),
                      _LandingScreenState._accentColor,
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _LandingScreenState._accentColor.withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
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