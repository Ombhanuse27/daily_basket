import 'dart:io';
import 'package:flutter/material.dart';
import 'db_helper.dart';

class DeleteProductPage extends StatefulWidget {
  const DeleteProductPage({super.key});

  @override
  State<DeleteProductPage> createState() => _DeleteProductPageState();
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



class _DeleteProductPageState extends State<DeleteProductPage> {
  List<Map<String, dynamic>> products = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final data = await DBHelper.getProducts();
    setState(() {
      products = data;
    });
  }

  Future<void> _deleteProduct(int id) async {
    await DBHelper.deleteProduct(id);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Product deleted successfully')),
    );
    _loadProducts(); // Refresh the list
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Delete Product"),
        backgroundColor: Colors.redAccent,
      ),
      body: products.isEmpty
          ? const Center(child: Text("No products found."))
          : ListView.builder(
        itemCount: products.length,
        itemBuilder: (context, index) {
          final item = products[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: ListTile(
              leading: buildProductImage(item['image']),
              title: Text(item['name']),
              subtitle:
              Text("Rate: ₹${item['rate']}  •  Type: ${item['type']}"),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _showDeleteDialog(item['id']),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDeleteDialog(int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: const Text("Are you sure you want to delete this product?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _deleteProduct(id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }
}
