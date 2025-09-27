import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_basket/screens/login_screen.dart';
import 'package:daily_basket/screens/Emp_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:daily_basket/screens/add_product.dart';
import 'package:daily_basket/screens/delete_product.dart';
import 'package:daily_basket/screens/update_product.dart';
import 'package:daily_basket/screens/buy_product.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmployeeDashboard extends StatefulWidget {
  final String userEmail;

  const EmployeeDashboard({Key? key, required this.userEmail}) : super(key: key);

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  final Map<String, Widget> _navigationMap = {
    'Add Product': const AddProductPage(),
    'Delete Product': const DeleteProductPage(),
    'Update Product': const UpdateProductPage(),
    'Buy Product': const BuyProductPage(),
    'Profile': const EmpProfileScreen(),
  };

  String? adminId;
  String? employeeId;
  bool isLoading = true;
  String employeeName = '';
  int? _hoveredIndex; // For web hover effects

  @override
  void initState() {
    super.initState();
    _initializeEmployee();
  }

  // --- CORE LOGIC (UNCHANGED) ---
  Future<void> _initializeEmployee() async {
    await _findEmployeeAndAdmin();
    if (adminId != null && employeeId != null) {
      await _checkExpiryAndLogoutIfNeeded();
      await _storeEmployeeInfo();
    } else {
      if (mounted) _showErrorDialog('Employee data not found. Please contact your administrator.');
    }
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _findEmployeeAndAdmin() async {
    try {
      final adminsSnapshot = await FirebaseFirestore.instance.collection('admins').get();
      for (var adminDoc in adminsSnapshot.docs) {
        final employeesSnapshot = await adminDoc.reference
            .collection('employees')
            .where('email', isEqualTo: widget.userEmail)
            .limit(1)
            .get();

        if (employeesSnapshot.docs.isNotEmpty) {
          final employeeDoc = employeesSnapshot.docs.first;
          adminId = adminDoc.id;
          employeeId = employeeDoc.id;
          employeeName = employeeDoc.data()['name'] ?? 'Employee';
          return;
        }
      }
    } catch (e) {
      debugPrint('Error finding employee: $e');
    }
  }

  Future<void> _storeEmployeeInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email', widget.userEmail);
      await prefs.setString('admin_id', adminId!);
      await prefs.setString('employee_id', employeeId!);
      await prefs.setBool('is_employee', true);
    } catch (e) {
      debugPrint('Error storing employee info: $e');
    }
  }

  Future<void> _checkExpiryAndLogoutIfNeeded() async {
    if (adminId == null || employeeId == null) return;
    try {
      final employeeDoc = await FirebaseFirestore.instance
          .collection('admins').doc(adminId!).collection('employees').doc(employeeId!).get();

      if (employeeDoc.exists) {
        final expiryTimestamp = employeeDoc.data()?['expiryDate'];
        if (expiryTimestamp != null && (expiryTimestamp as Timestamp).toDate().isBefore(DateTime.now())) {
          _showExpiredDialog();
        }
      } else {
        _showErrorDialog('Employee record not found.');
      }
    } catch (e) {
      debugPrint("Error checking expiry: $e");
    }
  }

  void _showExpiredDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Session Expired"),
        content: const Text("Your access has expired. Please contact your administrator."),
        actions: [
          TextButton(onPressed: _clearPreferencesAndLogout, child: const Text("OK")),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(onPressed: _clearPreferencesAndLogout, child: const Text("OK")),
        ],
      ),
    );
  }

  Future<void> _clearPreferencesAndLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  void _navigateTo(String title) {
    final page = _navigationMap[title];
    if (page != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return _buildLoadingScreen();
    }

    if (adminId == null || employeeId == null) {
      return _buildErrorScreen();
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Employee Dashboard', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black54),
            onPressed: () => _showLogoutDialog(),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double horizontalPadding = constraints.maxWidth > 800 ? 64.0 : 16.0;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24.0),
                children: [
                  _buildWelcomeHeader(),
                  const SizedBox(height: 24),
                  _buildPrimaryActionCard(),
                  const SizedBox(height: 24),
                  _buildSectionHeader("Management Tools"),
                  const SizedBox(height: 16),
                  _buildManagementGrid(constraints.maxWidth),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: _clearPreferencesAndLogout, child: const Text('Logout')),
        ],
      ),
    );
  }

  Widget _buildWelcomeHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Welcome,',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        Text(
          employeeName,
          style: TextStyle(fontSize: 22, color: Colors.grey[800], fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildPrimaryActionCard() {
    final item = _dashboardItems.firstWhere((i) => i['title'] == 'Buy Product');
    return Card(
      elevation: 4,
      shadowColor: Colors.green.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _navigateTo(item['title']! as String),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade400, Colors.green.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Image.asset(item['image']! as String, width: 60, height: 60),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Buy Products', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('Create new sales and generate bills', style: TextStyle(fontSize: 14, color: Colors.white70)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800]),
    );
  }

  Widget _buildManagementGrid(double screenWidth) {
    int crossAxisCount;
    if (screenWidth > 1200) {
      crossAxisCount = 5;
    } else if (screenWidth > 800) {
      crossAxisCount = 4;
    } else {
      crossAxisCount = 2;
    }

    // Employee grid includes all items except the primary "Buy Product" action
    final managementItems = _dashboardItems.where((item) => item['title'] != 'Buy Product').toList();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: managementItems.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.2,
      ),
      itemBuilder: (context, index) {
        final item = managementItems[index];
        return _buildGridCard(
          index: index,
          title: item['title']! as String,
          imagePath: item['image']! as String,
          color: item['color'] as Color,
          onTap: () => _navigateTo(item['title']! as String),
        );
      },
    );
  }

  Widget _buildGridCard({
    required int index,
    required String title,
    required String imagePath,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isHovered = _hoveredIndex == index;
    final scale = isHovered ? 1.05 : 1.0;
    final elevation = isHovered ? 8.0 : 2.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = null),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.identity()..scale(scale),
        transformAlignment: Alignment.center,
        child: Card(
          elevation: elevation,
          shadowColor: color.withOpacity(0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset(imagePath, width: 45, height: 45),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Scaffold _buildLoadingScreen() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Loading Dashboard...', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Scaffold _buildErrorScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text('Access Error', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Could not load your data. Please ensure you are a registered employee and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _clearPreferencesAndLogout,
                child: const Text('Return to Login'),
              )
            ],
          ),
        ),
      ),
    );
  }
}

final List<Map<String, Object>> _dashboardItems = [
  {'title': 'Buy Product', 'image': 'assets/images/img_2.png', 'color': Colors.green},
  {'title': 'Add Product', 'image': 'assets/images/add.png', 'color': Colors.blue},
  {'title': 'Update Product', 'image': 'assets/images/img_1.png', 'color': Colors.orange},
  {'title': 'Delete Product', 'image': 'assets/images/delete.png', 'color': Colors.red},
  {'title': 'Profile', 'image': 'assets/images/emp.png', 'color': Colors.teal},
];