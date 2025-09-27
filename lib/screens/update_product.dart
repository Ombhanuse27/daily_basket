import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'db_helper.dart';

class UpdateProductPage extends StatefulWidget {
  const UpdateProductPage({Key? key}) : super(key: key);

  @override
  State<UpdateProductPage> createState() => _UpdateProductPageState();
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

class _UpdateProductPageState extends State<UpdateProductPage> {
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> allProducts = [];
  List<String> categories = [];
  Map<String, dynamic>? selectedProduct;
  bool isUpdating = false;
  bool isUploadingImage = false;
  bool isLoading = true;
  bool isInitializing = true;
  String? selectedCategory;
  String searchQuery = "";

  final nameController = TextEditingController();
  final rateController = TextEditingController();
  final quantityController = TextEditingController();
  final originalRateController = TextEditingController();

  String? selectedType;
  String? selectedUnit;
  String? selectedImage;
  String? cloudinaryImageUrl;
  final List<String> types = [];
  final List<String> units = [];

  // User info
  String? currentUserEmail;
  String? adminId;
  String? employeeId;
  bool isEmployee = false;

  // Cloudinary configuration
  static const String CLOUD_NAME = "da9xvfoye";
  static const String UPLOAD_PRESET = "ml_default";

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

      print('UpdateProductPage - User Email: $currentUserEmail');
      print('UpdateProductPage - Admin ID: $adminId');
      print('UpdateProductPage - Employee ID: $employeeId');
      print('UpdateProductPage - Is Employee: $isEmployee');

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
        await _loadUnits();
        await _loadProducts();
      } else {
        _showAccessDeniedMessage('Access denied. You are not authorized to update products.');
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

      final categoryList = categorySnapshot.docs.map((doc) => doc['name'] as String).toList();

      print('Loaded ${categoryList.length} categories: $categoryList');

      setState(() {
        categories = categoryList;
        types.clear();
        types.addAll(categoryList);
      });
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

  Future<void> _loadUnits() async {
    if (adminId == null) return;

    try {
      print('Loading units for admin: $adminId');

      final unitSnapshot = await FirebaseFirestore.instance
          .collection('admins')
          .doc(adminId!)
          .collection('units')
          .get();

      final unitList = unitSnapshot.docs.map((doc) => doc['name'] as String).toList();

      print('Loaded ${unitList.length} units: $unitList');

      setState(() {
        units.clear();
        units.addAll(unitList);
      });
    } catch (e) {
      print('Error loading units: $e');
      if (mounted) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          SnackBar(
            content: Text('Error loading units: $e'),
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
          'id': doc.id,
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

  // Upload image to Cloudinary
  Future<String?> _uploadToCloudinary(String imagePath) async {
    try {
      setState(() => isUploadingImage = true);

      final url = Uri.parse('https://api.cloudinary.com/v1_1/$CLOUD_NAME/image/upload');
      final request = http.MultipartRequest('POST', url);

      request.fields['upload_preset'] = UPLOAD_PRESET;
      final file = await http.MultipartFile.fromPath('file', imagePath);
      request.files.add(file);

      final response = await request.send();

      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonResponse = json.decode(responseData);
        return jsonResponse['secure_url'];
      } else {
        print('Cloudinary upload failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error uploading to Cloudinary: $e');
      return null;
    } finally {
      setState(() => isUploadingImage = false);
    }
  }

  void _startUpdate(Map<String, dynamic> product) {
    setState(() {
      selectedProduct = product;
      nameController.text = product['name'];
      rateController.text = product['rate'].toString();
      originalRateController.text = product['originalRate']?.toString() ?? '';
      quantityController.text = product['quantity'].toString();
      selectedType = product['category'];
      selectedUnit = product['unit'];
      selectedImage = product['image'];
      cloudinaryImageUrl = product['image'].startsWith('http') ? product['image'] : null;
    });
  }

  Future<void> _selectImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      // First, save locally for immediate display
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = basename(pickedFile.path);
      final savedImage = await File(pickedFile.path).copy('${appDir.path}/$fileName');

      setState(() {
        selectedImage = savedImage.path;
        cloudinaryImageUrl = null;
      });

      // Then upload to Cloudinary
      final cloudinaryUrl = await _uploadToCloudinary(savedImage.path);
      if (cloudinaryUrl != null) {
        setState(() {
          cloudinaryImageUrl = cloudinaryUrl;
        });
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          const SnackBar(
            content: Text('✅ Image uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Failed to upload image. Using local copy.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _updateProduct() async {
    if (selectedProduct == null ||
        nameController.text.isEmpty ||
        rateController.text.isEmpty ||
        quantityController.text.isEmpty ||
        selectedType == null ||
        selectedUnit == null ||
        selectedImage == null) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and select image')),
      );
      return;
    }

    setState(() => isUpdating = true);

    try {
      if (adminId == null) {
        throw Exception("Admin ID not found.");
      }

      final productData = {
        'name': nameController.text.trim(),
        'rate': rateController.text.trim(),
        'originalRate': originalRateController.text.trim(),
        'category': selectedType!,
        'imagePath': cloudinaryImageUrl ?? selectedImage!,
        'quantity': quantityController.text.trim(),
        'unit': selectedUnit!,
        'updatedAt': Timestamp.now(),
        'updatedBy': isEmployee ? 'employee' : 'admin', // Track who updated the product
        'updatedByEmail': currentUserEmail,
      };

      print('Updating product in admin: $adminId');

      // Update in Firestore (same for both admin and employee)
      await FirebaseFirestore.instance
          .collection('admins')
          .doc(adminId!)
          .collection('products')
          .doc(selectedProduct!['id'])
          .update(productData);

      // Also update in local DB if you're still using it
      await DBHelper.updateProduct(
        selectedProduct!['id'].hashCode,
        nameController.text.trim(),
        rateController.text.trim(),
        originalRateController.text.trim(),
        selectedType!,
        cloudinaryImageUrl ?? selectedImage!,
        quantityController.text.trim(),
        selectedUnit!,
      );

      final successMessage = isEmployee
          ? '✅ Product updated in admin\'s inventory successfully!'
          : '✅ Product updated successfully!';

      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: Colors.green,
        ),
      );

      setState(() {
        selectedProduct = null;
        nameController.clear();
        rateController.clear();
        originalRateController.clear();
        quantityController.clear();
        selectedType = null;
        selectedUnit = null;
        selectedImage = null;
        cloudinaryImageUrl = null;
        isUpdating = false;
      });

      _loadProducts();
    } catch (e) {
      setState(() => isUpdating = false);
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text('❌ Error updating product: $e'),
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
          title: const Text('Update Product'),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading update product page...'),
            ],
          ),
        ),
      );
    }

    if (adminId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9F9F9),
        appBar: AppBar(
          title: const Text('Update Product'),
          backgroundColor: Colors.deepPurple,
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
              Text('You are not authorized to update products.'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selectedProduct == null ? 'Update Product' : 'Edit ${selectedProduct!['name']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
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
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          if (selectedProduct != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => selectedProduct = null),
              tooltip: 'Cancel Edit',
            ),
        ],
      ),
      body: selectedProduct == null
          ? Column(
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
                  itemCount: categories.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final isSelected = selectedCategory == null;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                            label: const Text(
                              'All',
                              style: TextStyle(color: Colors.black), // White text
                            ),
                          selected: isSelected,
                          selectedColor: Colors.deepPurple,
                          onSelected: (_) {
                            setState(() => selectedCategory = null);
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
                        label: Text(cat,
                          style: TextStyle(
                            color:  Colors.black, // White text if selected
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: Colors.deepPurple,
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
                        : "No products available to update.",
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
                        color: Colors.deepPurple[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.edit, color: Colors.deepPurple),
                        onPressed: () => _startUpdate(item),
                        tooltip: "Edit Product",
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
                        foregroundColor: Colors.deepPurple,
                      ),
                    ),
                ],
              ),
            ),
        ],
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (isUpdating || isUploadingImage)
              LinearProgressIndicator(
                color: Colors.deepPurple,
                backgroundColor: Colors.deepPurple.shade100,
              ),
            const SizedBox(height: 16),

            // Image selection
            GestureDetector(
              onTap: (isUpdating || isUploadingImage) ? null : _selectImage,
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Container(
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: Colors.grey[200],
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: buildProductImage(
                          cloudinaryImageUrl ?? selectedImage,
                          size: 220,
                        ),
                      ),
                      if (isUploadingImage)
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            color: Colors.black.withOpacity(0.5),
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(color: Colors.white),
                                SizedBox(height: 10),
                                Text(
                                  'Uploading image...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (!isUploadingImage)
                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: CircleAvatar(
                            backgroundColor: Colors.deepPurple,
                            child: const Icon(
                              Icons.edit,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
            _buildTextField(nameController, 'Product Name', Icons.shopping_bag),
            const SizedBox(height: 16),
            _buildTextField(rateController, 'Rate', Icons.currency_rupee),
            const SizedBox(height: 16),
            _buildTextField(originalRateController, 'Original Rate', Icons.currency_rupee),
            const SizedBox(height: 16),
            _buildTextField(quantityController, 'Quantity', Icons.production_quantity_limits),
            const SizedBox(height: 20),

            // Category dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.deepPurple.shade100),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: selectedType,
                  hint: const Text("Choose Category"),
                  icon: const Icon(Icons.arrow_drop_down),
                  items: types.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                  onChanged: (value) => setState(() => selectedType = value),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Unit dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.deepPurple.shade100),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: selectedUnit,
                  hint: const Text("Choose Unit"),
                  icon: const Icon(Icons.arrow_drop_down),
                  items: units.map((unit) => DropdownMenuItem(value: unit, child: Text(unit))).toList(),
                  onChanged: (value) => setState(() => selectedUnit = value),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Update button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (isUpdating || isUploadingImage) ? null : _updateProduct,
                icon: const Icon(Icons.update),
                label: const Text("Update Product"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Cancel button
            TextButton(
              onPressed: () => setState(() => selectedProduct = null),
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.red, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon) {
    return TextField(
      controller: controller,
      keyboardType: hint.toLowerCase().contains('rate') || hint.toLowerCase().contains('quantity')
          ? TextInputType.number
          : null,
      decoration: InputDecoration(
        labelText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}