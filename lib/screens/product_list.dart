import 'dart:io';
import 'package:flutter/material.dart';
import 'db_helper.dart';

class ProductListPage extends StatefulWidget {
  const ProductListPage({super.key});

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Product List"),
        backgroundColor: Colors.deepPurple,
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
              leading: item['image'] != null
                  ? Image.file(
                File(item['image']),
                width: 50,
                height: 50,
                fit: BoxFit.cover,
              )
                  : const Icon(Icons.image_not_supported),
              title: Text(item['name']),
              subtitle: Text("Rate: ₹${item['rate']}  •  Type: ${item['type']}  • Quantity: ${item['quantity']}"),
            ),
          );
        },
      ),
    );
  }
}
