import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'db_helper.dart';

class DeleteProductPage extends StatefulWidget {
  const DeleteProductPage({super.key});

  @override
  State<DeleteProductPage> createState() => _DeleteProductPageState();
}

Widget buildProductImage(String? imagePath, {double size = 70}) {
  if (imagePath != null && imagePath.startsWith("assets/")) {
    return Image.asset(imagePath, width: size, height: size, fit: BoxFit.cover);
  } else if (imagePath != null && imagePath.startsWith("http")) {
    // Handle Cloudinary URLs
    return Image.network(
      imagePath,
      width: size,
      height: size,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: size,
          height: size,
          color: Colors.grey[200],
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Image.asset('assets/images/img_4.png', width: size, height: size, fit: BoxFit.cover);
      },
    );
  } else if (imagePath != null && File(imagePath).existsSync()) {
    return Image.file(File(imagePath), width: size, height: size, fit: BoxFit.cover);
  } else {
    return Image.asset('assets/images/img_4.png', width: size, height: size, fit: BoxFit.cover);
  }
}

class _DeleteProductPageState extends State<DeleteProductPage> {
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> allProducts = [];
  List<String> categories = [];
  String? selectedCategory;
  String searchQuery = "";
  bool isLoading = true;
  bool isInitializing = true;

  // User info
  String? currentUserEmail;
  String? adminId;
  String? employeeId;
  bool isEmployee = false;

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    setState(() => isInitializing = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      // Get user info from SharedPreferences
      currentUserEmail = prefs.getString('user_email');
      adminId = prefs.getString('admin_id');
      employeeId = prefs.getString('employee_id');
      isEmployee = prefs.getBool('is_employee') ?? false;

      print('DeleteProductPage - User Email: $currentUserEmail');
      print('DeleteProductPage - Admin ID: $adminId');
      print('DeleteProductPage - Employee ID: $employeeId');
      print('DeleteProductPage - Is Employee: $isEmployee');

      if (currentUserEmail == null) {
        _showAccessDeniedMessage('No user email found. Please login again.');
        return;
      }

      // If no admin_id in SharedPreferences, fall back to the old method
      if (adminId == null) {
        print('No admin_id in SharedPreferences, using fallback method...');
        await _fallbackUserInitialization();
      }

      if (adminId != null) {
        await _loadCategories();
        await _loadProducts();
      } else {
        _showAccessDeniedMessage('Access denied. You are not authorized to delete products.');
      }
    } catch (e) {
      print('Error initializing user: $e');
      _showAccessDeniedMessage('Error loading user data. Please try again.');
    } finally {
      setState(() => isInitializing = false);
    }
  }

  // Fallback method for cases where SharedPreferences doesn't have admin_id
  Future<void> _fallbackUserInitialization() async {
    print('Using fallback user initialization method...');

    // First, check if user is an admin
    final adminSnapshot = await FirebaseFirestore.instance
        .collection('admins')
        .where('email', isEqualTo: currentUserEmail)
        .limit(1)
        .get();

    if (adminSnapshot.docs.isNotEmpty) {
      // User is an admin
      adminId = adminSnapshot.docs.first.id;
      isEmployee = false;
      print('Fallback: User is admin with ID: $adminId');

      // Store in SharedPreferences for future use
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('admin_id', adminId!);
      await prefs.setBool('is_employee', false);
    } else {
      // Check if user is an employee
      final employeeResult = await _findEmployeeAndAdmin();
      if (employeeResult != null) {
        adminId = employeeResult['adminId'];
        employeeId = employeeResult['employeeId'];
        isEmployee = true;
        print('Fallback: User is employee under admin: $adminId');

        // Store in SharedPreferences for future use
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('admin_id', adminId!);
        await prefs.setString('employee_id', employeeId!);
        await prefs.setBool('is_employee', true);
      }
    }
  }

  Future<Map<String, String>?> _findEmployeeAndAdmin() async {
    try {
      print('Searching for employee with email: $currentUserEmail');

      // Get all admins
      final adminsSnapshot = await FirebaseFirestore.instance
          .collection('admins')
          .get();

      print('Found ${adminsSnapshot.docs.length} admins to check');

      for (var adminDoc in adminsSnapshot.docs) {
        print('Checking admin: ${adminDoc.id}');

        // Check employees under each admin
        final employeesSnapshot = await FirebaseFirestore.instance
            .collection('admins')
            .doc(adminDoc.id)
            .collection('employees')
            .where('email', isEqualTo: currentUserEmail)
            .limit(1)
            .get();

        if (employeesSnapshot.docs.isNotEmpty) {
          print('Found employee under admin ${adminDoc.id}');
          return {
            'adminId': adminDoc.id,
            'employeeId': employeesSnapshot.docs.first.id,
          };
        }
      }

      print('Employee not found under any admin');
    } catch (e) {
      print('Error finding employee: $e');
    }
    return null;
  }

  void _showAccessDeniedMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _loadCategories() async {
    if (adminId == null) return;

    try {
      print('Loading categories for admin: $adminId');

      final categorySnapshot = await FirebaseFirestore.instance
          .collection('admins')
          .doc(adminId!)
          .collection('categories')
          .get();

      final catList = categorySnapshot.docs.map((doc) => doc['name'] as String).toList();

      print('Loaded ${catList.length} categories: $catList');

      setState(() => categories = catList);
    } catch (e) {
      print('Error loading categories: $e');
      if (mounted) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          SnackBar(
            content: Text('Error loading categories: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _loadProducts() async {
    if (adminId == null) return;

    setState(() => isLoading = true);

    try {
      print('Loading products for admin: $adminId');

      final productSnapshot = await FirebaseFirestore.instance
          .collection('admins')
          .doc(adminId!)
          .collection('products')
          .orderBy('name')
          .get();

      final List<Map<String, dynamic>> fetchedProducts = productSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id, // Use Firestore document ID
          'name': data['name'] ?? '',
          'rate': data['rate'] ?? '0',
          'originalRate': data['originalRate'] ?? '0',
          'quantity': data['quantity'] ?? '0',
          'unit': data['unit'] ?? '',
          'category': data['category'] ?? '',
          'image': data['imagePath'] ?? '',
          'createdAt': data['createdAt'],
        };
      }).toList();

      print('Loaded ${fetchedProducts.length} products');

      setState(() {
        allProducts = fetchedProducts;
        _applyFilters();
        isLoading = false;
      });
    } catch (e) {
      print('Error loading products: $e');
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          SnackBar(content: Text('Error loading products: $e')),
        );
      }
    }
  }

  void _applyFilters() {
    setState(() {
      products = allProducts
          .where((item) => selectedCategory == null || item['category'] == selectedCategory)
          .where((item) => item['name']
          .toString()
          .toLowerCase()
          .contains(searchQuery.toLowerCase()))
          .toList();
    });
  }

  Future<void> _deleteProduct(String documentId, String productName) async {
    try {
      if (adminId == null) {
        throw Exception("Admin ID not found.");
      }

      print('Deleting product from admin: $adminId');

      // Delete from Firestore (same for both admin and employee)
      await FirebaseFirestore.instance
          .collection('admins')
          .doc(adminId!)
          .collection('products')
          .doc(documentId)
          .delete();

      // Also delete from local DB if you're still using it
      await DBHelper.deleteProduct(documentId.hashCode);

      final successMessage = isEmployee
          ? '✅ $productName deleted from admin\'s inventory successfully'
          : '✅ $productName deleted successfully';

      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: Colors.green,
        ),
      );

      _loadProducts(); // Refresh the list
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text('❌ Error deleting product: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isInitializing) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9F9F9),
        appBar: AppBar(
          title: const Text('Delete Products'),
          backgroundColor: Colors.redAccent,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading delete product page...'),
            ],
          ),
        ),
      );
    }

    if (adminId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9F9F9),
        appBar: AppBar(
          title: const Text('Delete Products'),
          backgroundColor: Colors.redAccent,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Access Denied',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('You are not authorized to delete products.'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Delete Products", style: TextStyle(fontWeight: FontWeight.bold)),
            if (isEmployee)
              Text(
                'Employee Mode',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
          ],
        ),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      body: Column(
        children: [



          // Category filter chips
          if (categories.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: categories.length + 1, // +1 for "All" option
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // "All" option
                      final isSelected = selectedCategory == null;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: const Text('All'),
                          selected: isSelected,
                          selectedColor: Colors.redAccent,
                          onSelected: (_) {
                            setState(() {
                              selectedCategory = null;
                            });
                            _applyFilters();
                          },
                        ),
                      );
                    }

                    final cat = categories[index - 1];
                    final isSelected = cat == selectedCategory;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        selectedColor: Colors.redAccent,
                        onSelected: (_) {
                          setState(() {
                            selectedCategory = isSelected ? null : cat;
                          });
                          _applyFilters();
                        },
                      ),
                    );
                  },
                ),
              ),
            ),

          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Search Products',
                hintText: 'Enter product name to search...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onChanged: (value) {
                searchQuery = value;
                _applyFilters();
              },
            ),
          ),

          // Products list
          Expanded(
            child: isLoading
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading products...'),
                ],
              ),
            )
                : products.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    searchQuery.isNotEmpty || selectedCategory != null
                        ? "No products found matching your search."
                        : "No products available.",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (searchQuery.isNotEmpty || selectedCategory != null) ...[
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          searchQuery = "";
                          selectedCategory = null;
                        });
                        _applyFilters();
                      },
                      child: const Text("Clear Filters"),
                    ),
                  ],
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final item = products[index];
                final documentId = item['id'] as String;

                return Card(
                  elevation: 3,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: buildProductImage(item['image'], size: 60),
                    ),
                    title: Text(
                      item['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          "Rate: ₹${item['rate']} • Category: ${item['category']}",
                          style: const TextStyle(fontSize: 14),
                        ),
                        Text(
                          "Stock: ${item['quantity']} ${item['unit']}",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    trailing: Container(
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _showDeleteDialog(documentId, item['name']),
                        tooltip: "Delete Product",
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom info bar
          if (products.isNotEmpty && !isLoading)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${products.length} product${products.length == 1 ? '' : 's'} found",
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  if (searchQuery.isNotEmpty || selectedCategory != null)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          searchQuery = "";
                          selectedCategory = null;
                        });
                        _applyFilters();
                      },
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text("Clear Filters"),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showDeleteDialog(String documentId, String productName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[400]),
            const SizedBox(width: 8),
            const Text("Confirm Delete"),
          ],
        ),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.black, fontSize: 16),
            children: [
              const TextSpan(text: "Are you sure you want to delete "),
              TextSpan(
                text: "\"$productName\"",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextSpan(
                text: isEmployee
                    ? "?\n\nThis will delete the product from the admin's inventory. This action cannot be undone."
                    : "?\n\nThis action cannot be undone.",
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _deleteProduct(documentId, productName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }
}