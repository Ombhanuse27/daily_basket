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
        title: const Text("Buy Products"),
        backgroundColor: Colors.green,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (categories.isNotEmpty)
                SizedBox(
                  height: 50,
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
              Padding(
                padding: const EdgeInsets.all(10),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search Product',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
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
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            item['image'] != null
                                ? Image.file(
                              File(item['image']),
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                            )
                                : const Icon(Icons.image, size: 60),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item['name'],
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.bold)),
                                  Text("Rate: ₹${item['rate']}  •  Type: ${item['type']}"),
                                  Text("Available: ${item['quantity']} ${item['unit']}"),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.remove),
                                            onPressed: () {
                                              if (productQuantities[id]! > 1) {
                                                setState(() => productQuantities[id] = productQuantities[id]! - 1);
                                              }
                                            },
                                          ),
                                          Text("${productQuantities[id]} ${item['unit']}"),
                                          IconButton(
                                            icon: const Icon(Icons.add),
                                            onPressed: () {
                                              if (productQuantities[id]! < available) {
                                                setState(() => productQuantities[id] = productQuantities[id]! + 1);
                                              } else {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                      content:
                                                      Text('Only $available items available')),
                                                );
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          setState(() {
                                            selectedProducts[id] = true;
                                          });
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('${item['name']} added to cart')),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                        child: const Text("Add to Cart"),
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
                      icon: const Icon(Icons.picture_as_pdf),
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
                      ),
                      label: const Text("Buy & Generate Bill"),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 10,
            bottom: 20,
            child: selectedProducts.values.any((v) => v == true)
                ? GestureDetector(
              onTap: () {
                final cartItems = selectedProducts.entries
                    .where((entry) => entry.value)
                    .map((entry) => allProducts.firstWhere((p) => p['id'] == entry.key, orElse: () => {}))
                    .where((item) => item != null)
                    .toList();

                showModalBottomSheet(
                  context: context,
                  builder: (_) {
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text("Cart Items",
                            style:
                            TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        ...cartItems.map((item) {
                          final id = item['id'];
                          final available = int.tryParse(item['quantity'].toString()) ?? 0;
                          return ListTile(
                            title: Text(item['name']),
                            subtitle: Text("Rate: ₹${item['rate']} • Available: ${item['quantity']} ${item['unit']}") ,
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
                                          SnackBar(content: Text('Only $available items available')),
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
                    );
                  },
                );
              },
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(30),
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
            )
                : const SizedBox(),
          )
        ],
      ),
    );
  }
}
