import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'db_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

Widget buildProductImage(String? imagePath, {double size = 70}) {
  if (imagePath != null && imagePath.startsWith("assets/")) {
    return Image.asset(imagePath, width: size, height: size, fit: BoxFit.cover);
  } else if (imagePath != null && imagePath.startsWith("http")) {
    // Handle Cloudinary URLs
    return Image.network(imagePath, width: size, height: size, fit: BoxFit.cover);
  } else if (imagePath != null && File(imagePath).existsSync()) {
    return Image.file(File(imagePath), width: size, height: size, fit: BoxFit.cover);
  } else {
    return Image.asset('assets/images/img_4.png', width: size, height: size, fit: BoxFit.cover);
  }
}

class _AddProductPageState extends State<AddProductPage> {
  String? selectedType;
  String? selectedUnit;
  final nameController = TextEditingController();
  final rateController = TextEditingController();
  final quantityController = TextEditingController();
  final categoryController = TextEditingController();
  final unitController = TextEditingController();
  final originalRateController = TextEditingController();

  bool isLoading = false;
  bool isUploadingImage = false;
  bool isInitializing = true;
  String? selectedImage;
  String? cloudinaryImageUrl; // Store Cloudinary URL

  // User info
  String? currentUserEmail;
  String? adminId;
  String? employeeId;
  bool isEmployee = false;

  // Cloudinary configuration
  static const String CLOUD_NAME = "da9xvfoye";
  static const String UPLOAD_PRESET = "ml_default";

  //dummy image
  final String dummyImg = "assets/images/img_4.png";

  List<String> types = [];
  List<String> units = [];

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

      print('AddProductPage - User Email: $currentUserEmail');
      print('AddProductPage - Admin ID: $adminId');
      print('AddProductPage - Employee ID: $employeeId');
      print('AddProductPage - Is Employee: $isEmployee');

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
      } else {
        _showAccessDeniedMessage('Access denied. You are not authorized to add products.');
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

      setState(() => types = categoryList);
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

      setState(() => units = unitList);
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

  // Upload image to Cloudinary
  Future<String?> _uploadToCloudinary(String imagePath) async {
    try {
      setState(() => isUploadingImage = true);

      final url = Uri.parse('https://api.cloudinary.com/v1_1/$CLOUD_NAME/image/upload');
      final request = http.MultipartRequest('POST', url);

      // Add upload preset
      request.fields['upload_preset'] = UPLOAD_PRESET;

      // Add the image file
      final file = await http.MultipartFile.fromPath('file', imagePath);
      request.files.add(file);

      final response = await request.send();

      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonResponse = json.decode(responseData);

        // Return the secure URL from Cloudinary
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

  @override
  Widget build(BuildContext context) {
    if (isInitializing) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9F9F9),
        appBar: AppBar(
          title: const Text('Add Product'),
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
              Text('Loading add product page...'),
            ],
          ),
        ),
      );
    }

    if (adminId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9F9F9),
        appBar: AppBar(
          title: const Text('Add Product'),
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
              Text('You are not authorized to add products.'),
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
            const Text('Add Product'),
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
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (isLoading || isUploadingImage)
              LinearProgressIndicator(
                color: Colors.deepPurple,
                backgroundColor: Colors.deepPurple.shade100,
              ),
            const SizedBox(height: 10),

            // Debug info (remove in production)



            GestureDetector(
              onTap: isUploadingImage ? null : _selectImage,
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
                        child: buildProductImage(cloudinaryImageUrl ?? selectedImage, size: 220),
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
                            child: Icon(
                              cloudinaryImageUrl != null ? Icons.edit : Icons.add_a_photo,
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
            Row(
              children: [
                Expanded(child: _buildTextField(quantityController, 'Quantity', Icons.production_quantity_limits)),
                const SizedBox(width: 10),
                if (units.isEmpty) ...[
                  Expanded(child: _buildTextField(unitController, 'Enter Unit', Icons.straighten)),
                ] else ...[
                  Expanded(
                    child: Container(
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
                  ),
                  IconButton(
                    onPressed: () => _showAddUnitDialog(context),
                    icon: const Icon(Icons.add),
                    tooltip: "Add Unit",
                  ),
                ],
              ],
            ),

            const SizedBox(height: 20),
            if (types.isEmpty) ...[
              _buildTextField(categoryController, 'Enter New Category', Icons.category),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Container(
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
                  ),
                  IconButton(
                    onPressed: () => _showAddCategoryDialog(context),
                    icon: const Icon(Icons.add),
                    tooltip: "Add Category",
                  ),
                ],
              ),
              if (selectedType != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text("Selected: $selectedType", style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
            ],

            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (isLoading || isUploadingImage) ? null : _uploadProduct,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text("Add Product"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            )
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

  Future<void> _selectImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      // First, save locally for immediate display
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = basename(pickedFile.path);
      final savedImage = await File(pickedFile.path).copy('${appDir.path}/$fileName');

      setState(() {
        selectedImage = savedImage.path;
        cloudinaryImageUrl = null; // Reset cloudinary URL
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

  Future<void> _uploadProduct() async {
    if ((selectedType == null && categoryController.text.trim().isEmpty) ||
        nameController.text.trim().isEmpty ||
        rateController.text.trim().isEmpty ||
        originalRateController.text.trim().isEmpty ||
        quantityController.text.trim().isEmpty ||
        (selectedUnit == null && unitController.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and select image')),
      );
      return;
    }

    final categoryToUse = selectedType ?? categoryController.text.trim();
    final unitToUse = selectedUnit ?? unitController.text.trim();

    setState(() => isLoading = true);

    try {
      if (adminId == null) {
        throw Exception("Admin ID not found.");
      }

      final productData = {
        'name': nameController.text.trim(),
        'rate': rateController.text.trim(),
        'originalRate': originalRateController.text.trim(),
        'category': categoryToUse,
        'imagePath': cloudinaryImageUrl ?? selectedImage ?? dummyImg, // Use Cloudinary URL if available
        'quantity': quantityController.text.trim(),
        'unit': unitToUse,
        'createdAt': Timestamp.now(),
        'addedBy': isEmployee ? 'employee' : 'admin', // Track who added the product
        'addedByEmail': currentUserEmail,
      };

      print('Adding product to admin: $adminId');

      // Store product under the admin's collection (same for both admin and employee)
      await FirebaseFirestore.instance
          .collection('admins')
          .doc(adminId!)
          .collection('products')
          .add(productData);

      // Add category if new
      if (!types.contains(categoryToUse)) {
        await FirebaseFirestore.instance
            .collection('admins')
            .doc(adminId!)
            .collection('categories')
            .add({'name': categoryToUse});

        // Reload categories
        await _loadCategories();
      }

      // Add unit if new
      if (!units.contains(unitToUse)) {
        await FirebaseFirestore.instance
            .collection('admins')
            .doc(adminId!)
            .collection('units')
            .add({'name': unitToUse});

        // Reload units
        await _loadUnits();
      }

      setState(() {
        nameController.clear();
        rateController.clear();
        originalRateController.clear();
        quantityController.clear();
        selectedType = null;
        selectedUnit = null;
        selectedImage = null;
        cloudinaryImageUrl = null;
        categoryController.clear();
        unitController.clear();
      });

      final successMessage = isEmployee
          ? '✅ Product added to admin\'s inventory successfully!'
          : '✅ Product uploaded successfully!';

      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('❌ Error uploading product: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showAddCategoryDialog(BuildContext context) {
    final newCategoryController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add New Category"),
        content: TextField(
          controller: newCategoryController,
          decoration: const InputDecoration(labelText: "Category Name"),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            child: const Text("Add"),
            onPressed: () async {
              final newCat = newCategoryController.text.trim();
              if (newCat.isNotEmpty && !types.contains(newCat) && adminId != null) {
                try {
                  // Add to Firestore instead of local DB
                  await FirebaseFirestore.instance
                      .collection('admins')
                      .doc(adminId!)
                      .collection('categories')
                      .add({'name': newCat});

                  // Reload categories
                  await _loadCategories();

                  setState(() {
                    selectedType = newCat;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Category "$newCat" added successfully!')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error adding category: $e')),
                  );
                }
              }
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  void _showAddUnitDialog(BuildContext context) {
    final newUnitController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add New Unit"),
        content: TextField(
          controller: newUnitController,
          decoration: const InputDecoration(labelText: "Unit Name"),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            child: const Text("Add"),
            onPressed: () async {
              final newUnit = newUnitController.text.trim();
              if (newUnit.isNotEmpty && !units.contains(newUnit) && adminId != null) {
                try {
                  // Add to Firestore instead of local DB
                  await FirebaseFirestore.instance
                      .collection('admins')
                      .doc(adminId!)
                      .collection('units')
                      .add({'name': newUnit});

                  // Reload units
                  await _loadUnits();

                  setState(() {
                    selectedUnit = newUnit;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Unit "$newUnit" added successfully!')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error adding unit: $e')),
                  );
                }
              }
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}