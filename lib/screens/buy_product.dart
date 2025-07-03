import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'db_helper.dart';

class BuyProductPage extends StatefulWidget {
  const BuyProductPage({super.key});

  @override
  State<BuyProductPage> createState() => _BuyProductPageState();
}

class _BuyProductPageState extends State<BuyProductPage> {
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> allProducts = [];
  List<String> categories = [];
  String? selectedCategory;
  String searchQuery = "";

  Map<int, bool> selectedProducts = {};
  Map<int, int> productQuantities = {};

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadProducts();
  }

  Future<void> _loadCategories() async {
    final cats = await DBHelper.getAllCategories();
    setState(() => categories = cats);
  }

  Future<void> _loadProducts() async {
    final data = await DBHelper.getProducts();
    final filtered = selectedCategory == null
        ? data
        : data.where((item) => item['type'] == selectedCategory).toList();

    setState(() {
      allProducts = data;
      products = filtered;
      for (var item in data) {
        selectedProducts.putIfAbsent(item['id'], () => false);
        productQuantities.putIfAbsent(item['id'], () => 1);
      }
    });
  }

  double _calculateTotalAmount() {
    double total = 0;
    for (var item in selectedProducts.entries.where((e) => e.value)) {
      final product = allProducts.firstWhere((p) => p['id'] == item.key, orElse: () => {});
      if (product != null) {
        int quantity = productQuantities[item.key] ?? 1;
        total += double.tryParse(product['rate'].toString())! * quantity;
      }
    }
    return total;
  }

  Future<void> _generatePdfBill() async {
    final pdf = pw.Document();
    final selectedItems = selectedProducts.entries
        .where((entry) => entry.value)
        .map((entry) => allProducts.firstWhere((p) => p['id'] == entry.key, orElse: () => {}))
        .where((item) => item != null)
        .toList();

    for (var item in selectedItems) {
      int id = item['id'];
      int qty = productQuantities[id] ?? 1;
      await DBHelper.reduceProductQuantity(id, qty);
    }

    await _loadProducts();

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text("Bill Receipt", style: pw.TextStyle(fontSize: 24)),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              headers: ['Product', 'Qty', 'Rate', 'Subtotal'],
              data: selectedItems.map((item) {
                int qty = productQuantities[item['id']]!;
                double rate = double.parse(item['rate'].toString());
                return [
                  item['name'],
                  qty.toString(),
                  "₹$rate",
                  "₹${(rate * qty).toStringAsFixed(2)}"
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 20),
            pw.Text("Total: ₹${_calculateTotalAmount().toStringAsFixed(2)}",
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Buy Products", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green,
        elevation: 4,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (categories.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final cat = categories[index];
                        final isSelected = cat == selectedCategory;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: ChoiceChip(
                            label: Text(cat),
                            selected: isSelected,
                            selectedColor: Colors.green,
                            onSelected: (_) {
                              setState(() {
                                selectedCategory = isSelected ? null : cat;
                              });
                              _loadProducts();
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: TextField(
                  decoration: InputDecoration(
                    labelText: 'Search Product',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    searchQuery = value;
                    setState(() {
                      products = allProducts
                          .where((item) => selectedCategory == null || item['type'] == selectedCategory)
                          .where((item) => item['name']
                          .toString()
                          .toLowerCase()
                          .contains(searchQuery.toLowerCase()))
                          .toList();
                    });
                  },
                ),
              ),
              Expanded(
                child: products.isEmpty
                    ? const Center(child: Text("No products found."))
                    : ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final item = products[index];
                    int id = item['id'];
                    int available = int.tryParse(item['quantity'].toString()) ?? 0;

                    return Card(
                      elevation: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: item['image'] != null
                                  ? Image.file(
                                File(item['image']),
                                width: 70,
                                height: 70,
                                fit: BoxFit.cover,
                              )
                                  : Container(
                                width: 70,
                                height: 70,
                                color: Colors.grey[300],
                                child: const Icon(Icons.image, size: 40),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item['name'],
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text("Rate: ₹${item['rate']} • Type: ${item['type']}"),
                                  Text("Available: ${item['quantity']} ${item['unit']}"),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.remove_circle_outline),
                                            onPressed: () {
                                              if (productQuantities[id]! > 1) {
                                                setState(() => productQuantities[id] = productQuantities[id]! - 1);
                                              }
                                            },
                                          ),
                                          Text("${productQuantities[id]} ${item['unit']}"),
                                          IconButton(
                                            icon: const Icon(Icons.add_circle_outline),
                                            onPressed: () {
                                              if (productQuantities[id]! < available) {
                                                setState(() => productQuantities[id] = productQuantities[id]! + 1);
                                              } else {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                      content: Text('Only $available items available')),
                                                );
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            selectedProducts[id] = true;
                                          });
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('${item['name']} added to cart')),
                                          );
                                        },
                                        icon: const Icon(Icons.add_shopping_cart),
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8))),
                                        label: const Text("Add"),
                                      )
                                    ],
                                  )
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16, top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Total: ₹${_calculateTotalAmount().toStringAsFixed(2)}",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.receipt_long),
                      onPressed: () {
                        if (selectedProducts.values.any((v) => v == true)) {
                          _generatePdfBill();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please select at least one product.')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      label: const Text("Buy & Generate Bill"),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (selectedProducts.values.any((v) => v == true))
            Positioned(
              left: 10,
              bottom: 20,
              child: GestureDetector(
                onTap: () {
                  final cartItems = selectedProducts.entries
                      .where((entry) => entry.value)
                      .map((entry) =>
                      allProducts.firstWhere((p) => p['id'] == entry.key, orElse: () => {}))
                      .where((item) => item != null)
                      .toList();

                  showModalBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                    builder: (_) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: ListView(
                          children: [
                            const Text("Cart Items",
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            ...cartItems.map((item) {
                              final id = item['id'];
                              final available = int.tryParse(item['quantity'].toString()) ?? 0;
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                title: Text(item['name']),
                                subtitle: Text(
                                    "Rate: ₹${item['rate']} • Available: ${item['quantity']} ${item['unit']}"),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        icon: const Icon(Icons.remove),
                                        onPressed: () {
                                          if ((productQuantities[id] ?? 1) > 1) {
                                            setState(() {
                                              productQuantities[id] =
                                                  (productQuantities[id] ?? 1) - 1;
                                            });
                                          }
                                        }),
                                    Text("${productQuantities[id]} ${item['unit']}"),
                                    IconButton(
                                        icon: const Icon(Icons.add),
                                        onPressed: () {
                                          if ((productQuantities[id] ?? 1) < available) {
                                            setState(() {
                                              productQuantities[id] =
                                                  (productQuantities[id] ?? 1) + 1;
                                            });
                                          } else {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                  content: Text(
                                                      'Only $available items available')),
                                            );
                                          }
                                        }),
                                    IconButton(
                                        icon: const Icon(Icons.delete),
                                        onPressed: () {
                                          setState(() {
                                            selectedProducts[id] = false;
                                          });
                                          Navigator.pop(context);
                                        }),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_cart, color: Colors.white),
                      SizedBox(width: 8),
                      Text("View Cart", style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            )
        ],
      ),
    );
  }
}
