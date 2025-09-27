import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'dart:ui'; // For BackdropFilter

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

// Add TickerProviderStateMixin for animations
class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;

  // Animation controller for staggered entrance
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // --- EXISTING LOGIC (UNCHANGED) ---

  Future<void> _registerUser() async {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        String email = _emailController.text.trim();
        String name = _nameController.text.trim();
        String password = _passwordController.text;

        final existing = await FirebaseFirestore.instance
            .collection('admins')
            .where('email', isEqualTo: email)
            .get();

        if (existing.docs.isNotEmpty) {
          _showDialog(
            title: "Email Already Used",
            message:
            "This email is already registered. Please try logging in.",
          );
          return;
        }

        await FirebaseFirestore.instance.collection('admins').add({
          'name': name,
          'email': email,
          'password': password,
          'isActivated': false,
          'activationKey': '',
          'keyUsed': false,
          'expiryDate':
          Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
          'registeredAt': Timestamp.now(),
        });

        _showDialog(
          title: "Registration Successful!",
          message:
          "Please wait for admin approval. An activation key will be sent to your email.",
          success: true,
        );
      } catch (e) {
        _showDialog(
            title: "Registration Failed",
            message: "An error occurred: ${e.toString()}");
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  void _showDialog(
      {required String title,
        required String message,
        bool success = false}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              success
                  ? Icons.check_circle_outline_rounded
                  : Icons.error_outline_rounded,
              size: 50,
              color: success ? Colors.green.shade600 : Colors.red.shade600,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (success) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // --- NEW UI BUILD METHOD ---
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      body: Stack(
        children: [
          // Decorative Background
          _buildBackground(),

          // Header
          _buildHeader(),

          // Login Form Card
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: screenHeight * 0.65,
              padding:
              const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Animated Form Fields
                      _buildAnimatedFormField(
                        interval: const Interval(0.2, 0.7),
                        child: _buildTextFormField(
                          controller: _nameController,
                          labelText: 'Full Name',
                          prefixIcon: Icons.person_outline_rounded,
                          validator: (value) =>
                          (value == null || value.isEmpty)
                              ? 'Name is required'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildAnimatedFormField(
                        interval: const Interval(0.3, 0.8),
                        child: _buildTextFormField(
                          controller: _emailController,
                          labelText: 'Email Address',
                          prefixIcon: Icons.alternate_email_rounded,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) =>
                          (value == null || !value.contains('@'))
                              ? 'Enter a valid email'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildAnimatedFormField(
                        interval: const Interval(0.4, 0.9),
                        child: _buildTextFormField(
                          controller: _passwordController,
                          labelText: 'Password',
                          prefixIcon: Icons.lock_outline_rounded,
                          isPassword: true,
                          validator: (value) =>
                          (value == null || value.length < 6)
                              ? 'Password must be at least 6 characters'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildAnimatedFormField(
                        interval: const Interval(0.5, 1.0),
                        child: _buildTextFormField(
                          controller: _confirmPasswordController,
                          labelText: 'Confirm Password',
                          prefixIcon: Icons.lock_outline_rounded,
                          isPassword: true,
                          validator: (value) =>
                          (value != _passwordController.text)
                              ? 'Passwords do not match'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _buildAnimatedFormField(
                        interval: const Interval(0.6, 1.0),
                        child: _buildRegisterButton(),
                      ),
                      const SizedBox(height: 24),
                      _buildAnimatedFormField(
                        interval: const Interval(0.7, 1.0),
                        child: _buildLoginLink(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget for staggered animations
  Widget _buildAnimatedFormField({
    required Widget child,
    required Interval interval,
  }) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.5),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(parent: _animationController, curve: interval),
      ),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _animationController, curve: interval),
        child: child,
      ),
    );
  }

  // --- NEW UI WIDGETS ---

  Widget _buildBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade300, Colors.green.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -100,
            left: -100,
            child: _buildCircle(200, Colors.white.withOpacity(0.1)),
          ),
          Positioned(
            bottom: -50,
            right: -150,
            child: _buildCircle(300, Colors.white.withOpacity(0.15)),
          ),
        ],
      ),
    );
  }

  Widget _buildCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildHeader() {
    return const Positioned(
      top: 100,
      left: 24,
      right: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Create Account",
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 8),
          Text(
            "Sign up to get started",
            style: TextStyle(
              fontSize: 18,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String labelText,
    required IconData prefixIcon,
    required String? Function(String?) validator,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !_isPasswordVisible,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: labelText,
        prefixIcon: Icon(prefixIcon, color: Colors.grey.shade600),
        suffixIcon: isPassword
            ? IconButton(
          icon: Icon(
            _isPasswordVisible
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: Colors.grey.shade600,
          ),
          onPressed: () {
            setState(() {
              _isPasswordVisible = !_isPasswordVisible;
            });
          },
        )
            : null,
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade600, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade300, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.green.shade600, width: 2),
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildRegisterButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _registerUser,
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.transparent, // Important for gradient
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: EdgeInsets.zero, // Important for gradient
          elevation: 5,
          shadowColor: Colors.green.withOpacity(0.5),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isLoading
                  ? [Colors.grey.shade400, Colors.grey.shade500]
                  : [Colors.green.shade500, Colors.green.shade700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            alignment: Alignment.center,
            child: _isLoading
                ? const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: Colors.white),
            )
                : const Text("CREATE ACCOUNT",
                style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text("Already have an account?",
            style: TextStyle(color: Colors.grey.shade700)),
        TextButton(
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: Text(
            "Login Now",
            style: TextStyle(
              color: Colors.green.shade800,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}