import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'db_helper.dart';

class UpdateProductPage extends StatefulWidget {
  const UpdateProductPage({Key? key}) : super(key: key);

  @override
  State<UpdateProductPage> createState() => _UpdateProductPageState();
}

Widget buildProductImage(String? imagePath, {double size = 70}) {
  if (imagePath != null && imagePath.startsWith("assets/")) {
    return Image.asset(imagePath, width: size, height: size, fit: BoxFit.cover);
  } else if (imagePath != null && File(imagePath).existsSync()) {
    return Image.file(File(imagePath), width: size, height: size, fit: BoxFit.cover);
  } else {
    return Image.asset('assets/images/img_4.png', width: size, height: size, fit: BoxFit.cover);
  }
}



class _UpdateProductPageState extends State<UpdateProductPage> {
  List<Map<String, dynamic>> products = [];
  Map<String, dynamic>? selectedProduct;
  bool isUpdating = false;

  final nameController = TextEditingController();
  final rateController = TextEditingController();
  final quantityController = TextEditingController();
  String? selectedType;
  String? selectedUnit;
  String? selectedImage;
  final List<String> types = [];
  final List<String> units = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadCategories();
    _loadUnits();
  }

  Future<void> _loadProducts() async {
    final data = await DBHelper.getProducts();
    setState(() {
      products = data;
    });
  }

  Future<void> _loadCategories() async {
    final allCategories = await DBHelper.getAllCategories();
    setState(() => types.addAll(allCategories));
  }

  Future<void> _loadUnits() async {
    final allUnits = await DBHelper.getAllUnits();
    setState(() => units.addAll(allUnits));
  }

  void _startUpdate(Map<String, dynamic> product) {
    setState(() {
      selectedProduct = product;
      nameController.text = product['name'];
      rateController.text = product['rate'].toString();
      quantityController.text = product['quantity'].toString();
      selectedType = product['type'];
      selectedUnit = product['unit'];
      selectedImage = product['image'];
    });
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

    await DBHelper.updateProduct(
      selectedProduct!['id'],
      nameController.text.trim(),
      rateController.text.trim(),
      selectedType!,
      selectedImage!,
      quantityController.text.trim(),
      selectedUnit!,
    );

    ScaffoldMessenger.of(context as BuildContext).showSnackBar(
      const SnackBar(content: Text('Product updated successfully!')),
    );

    setState(() {
      selectedProduct = null;
      nameController.clear();
      rateController.clear();
      quantityController.clear();
      selectedType = null;
      selectedUnit = null;
      selectedImage = null;
      isUpdating = false;
    });

    _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text('Update Product'),
        backgroundColor: Colors.deepPurple,
      ),
      body: selectedProduct == null
          ? ListView.builder(
        itemCount: products.length,
        itemBuilder: (context, index) {
          final item = products[index];
          return ListTile(
            leading: buildProductImage(item['image']),
            title: Text(item['name']),
            subtitle: Text("₹${item['rate']} • ${item['type']} • ${item['quantity']} ${item['unit']}"),
            trailing: IconButton(
              icon: const Icon(Icons.edit, color: Colors.deepPurple),
              onPressed: () => _startUpdate(item),
            ),
          );
        },
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (isUpdating) const LinearProgressIndicator(color: Colors.deepPurple),
            const SizedBox(height: 16),

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
                    child: Image.file(
                      File(selectedImage!),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 220,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
            _buildTextField(nameController, 'Product Name', Icons.shopping_bag),
            const SizedBox(height: 16),
            _buildTextField(rateController, 'Rate', Icons.currency_rupee),
            const SizedBox(height: 16),
            _buildTextField(quantityController, 'Quantity', Icons.production_quantity_limits),
            const SizedBox(height: 20),

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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _updateProduct,
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
            TextButton(
              onPressed: () => setState(() => selectedProduct = null),
              child: const Text("Cancel", style: TextStyle(color: Colors.red)),
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
}
