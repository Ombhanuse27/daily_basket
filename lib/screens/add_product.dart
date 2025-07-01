import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'db_helper.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  String? selectedType;
  String? selectedUnit;
  final nameController = TextEditingController();
  final rateController = TextEditingController();
  final quantityController = TextEditingController();
  final categoryController = TextEditingController();
  final unitController = TextEditingController();
  bool isLoading = false;
  String? selectedImage;

  List<String> types = [];
  List<String> units = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadUnits();
  }

  Future<void> _loadCategories() async {
    final allCategories = await DBHelper.getAllCategories();
    setState(() => types = allCategories);
  }

  Future<void> _loadUnits() async {
    final allUnits = await DBHelper.getAllUnits();
    setState(() => units = allUnits);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text('Add Product'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (isLoading) const LinearProgressIndicator(color: Colors.deepPurple),
            const SizedBox(height: 20),

            GestureDetector(
              onTap: _selectImage,
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
                  child: selectedImage == null
                      ? const Center(child: Text('Tap to select product image'))
                      : ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.file(File(selectedImage!), fit: BoxFit.cover),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
            _buildTextField(nameController, 'Product Name', Icons.shopping_bag),
            const SizedBox(height: 16),
            _buildTextField(rateController, 'Rate', Icons.currency_rupee),
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
                onPressed: _uploadProduct,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text("Upload Product"),
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
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = basename(pickedFile.path);
      final savedImage = await File(pickedFile.path).copy('${appDir.path}/$fileName');
      setState(() {
        selectedImage = savedImage.path;
      });
    }
  }

  Future<void> _uploadProduct() async {
    if (selectedImage == null ||
        (selectedType == null && categoryController.text.trim().isEmpty) ||
        nameController.text.trim().isEmpty ||
        rateController.text.trim().isEmpty ||
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
      await DBHelper.insertProduct(
        nameController.text.trim(),
        rateController.text.trim(),
        categoryToUse,
        selectedImage!,
        quantityController.text.trim(),
        unitToUse,
      );

      if (!types.contains(categoryToUse)) {
        await DBHelper.insertCategory(categoryToUse);
        await _loadCategories();
      }

      if (!units.contains(unitToUse)) {
        await DBHelper.insertUnit(unitToUse);
        await _loadUnits();
      }

      setState(() {
        nameController.clear();
        rateController.clear();
        quantityController.clear();
        selectedType = null;
        selectedUnit = null;
        selectedImage = null;
        categoryController.clear();
        unitController.clear();
      });

      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        const SnackBar(content: Text('Product uploaded successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Error uploading product: $e')),
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
              if (newCat.isNotEmpty && !types.contains(newCat)) {
                await DBHelper.insertCategory(newCat);
                final allCategories = await DBHelper.getAllCategories();
                setState(() {
                  types = allCategories;
                  selectedType = newCat;
                });
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
              if (newUnit.isNotEmpty && !units.contains(newUnit)) {
                await DBHelper.insertUnit(newUnit);
                final allUnits = await DBHelper.getAllUnits();
                setState(() {
                  units = allUnits;
                  selectedUnit = newUnit;
                });
              }
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
