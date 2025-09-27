import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_basket/screens/login_screen.dart';
import 'package:daily_basket/screens/profile_screen.dart';
import 'package:daily_basket/screens/stocks_sales.dart';
import 'package:flutter/material.dart';
import 'package:daily_basket/screens/add_product.dart';
import 'package:daily_basket/screens/delete_product.dart';
import 'package:daily_basket/screens/update_product.dart';
import 'package:daily_basket/screens/buy_product.dart';

class AdminDashboard extends StatefulWidget {
  final String userEmail;

  const AdminDashboard({Key? key, required this.userEmail}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  // ##### CHANGE 1: ADD STATE VARIABLE FOR THE ADMIN'S NAME #####
  String _adminName = '';

  final Map<String, Widget> _navigationMap = {
    'Add Product': const AddProductPage(),
    'Delete Product': const DeleteProductPage(),
    'Update Product': const UpdateProductPage(),
    'Buy Product': const BuyProductPage(),
    'Stock & Sales': const StockAndSalesPage(),
    'Profile': const ProfileScreen(),
  };

  int? _hoveredIndex; // For web hover effects

  @override
  void initState() {
    super.initState();
    // Initialize with email as a fallback, then fetch the real name.
    _adminName = widget.userEmail;
    _loadAdminData();
  }

  // ##### CHANGE 2: UPDATE FUNCTION TO FETCH NAME AND CHECK EXPIRY #####
  Future<void> _loadAdminData() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('admins')
          .where('email', isEqualTo: widget.userEmail)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();

        // Fetch and set the admin's name
        final name = data['name'] as String?;
        if (mounted && name != null && name.isNotEmpty) {
          setState(() {
            _adminName = name;
          });
        }

        // Check the expiry date
        final expiry = (data['expiryDate'] as Timestamp).toDate();
        if (DateTime.now().isAfter(expiry)) {
          _showExpiredDialog();
        }
      }
    } catch (e) {
      debugPrint("Error loading admin data: $e");
    }
  }

  void _showExpiredDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Session Expired"),
        content: const Text(
            "Your activation key has expired. Please contact support or renew your access."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _navigateTo(String title) {
    final page = _navigationMap[title];
    if (page != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Admin Dashboard', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline, color: Colors.black54),
            onPressed: () => _navigateTo('Profile'),
            tooltip: 'Profile',
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

  // ##### CHANGE 3: UPDATE WIDGET TO USE THE _adminName STATE VARIABLE #####
  Widget _buildWelcomeHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Welcome Back,',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        Text(
          _adminName, // Now displays the fetched name or the email as a fallback
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['title']! as String,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const Text(
                      'Create new sales and generate bills',
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                    ),
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
      crossAxisCount = 5; // Adjusted to 5 since profile is in app bar
    } else if (screenWidth > 800) {
      crossAxisCount = 4;
    } else {
      crossAxisCount = 2;
    }

    final managementItems = _dashboardItems.where((item) => item['title'] != 'Buy Product' && item['title'] != 'Profile').toList();

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
}

final List<Map<String, Object>> _dashboardItems = [
  {'title': 'Buy Product', 'image': 'assets/images/img_2.png', 'color': Colors.green},
  {'title': 'Add Product', 'image': 'assets/images/add.png', 'color': Colors.blue},
  {'title': 'Update Product', 'image': 'assets/images/img_1.png', 'color': Colors.orange},
  {'title': 'Delete Product', 'image': 'assets/images/delete.png', 'color': Colors.red},
  {'title': 'Stock & Sales', 'image': 'assets/images/stocks.png', 'color': Colors.purple},
  {'title': 'Profile', 'image': 'assets/images/admin.png', 'color': Colors.teal},
];