import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'db_helper.dart';

class BuyProductPage extends StatefulWidget {
  const BuyProductPage({super.key});

  @override
  State<BuyProductPage> createState() => _BuyProductPageState();
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

class _BuyProductPageState extends State<BuyProductPage> {
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> allProducts = [];
  List<String> categories = [];
  String? selectedCategory;
  String searchQuery = "";

  Map<int, bool> selectedProducts = {};
  Map<int, double> productQuantities = {}; // changed to double
  final Map<int, TextEditingController> _quantityControllers = {};


  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadProducts();
  }

  bool isDecimalAllowed(String unit) {
    final lower = unit.toLowerCase();
    return !(lower.contains("piece") || lower.contains("packet") || lower.contains("unit") || lower.contains("bottle"));
  }


  Future<void> _loadCategories() async {
    final cats = await DBHelper.getAllCategories();
    setState(() => categories = cats);
  }

  Future<void> _loadProducts() async {
    final data = await DBHelper.getProducts();

    setState(() {
      allProducts = data;
      products = selectedCategory == null
          ? data
          : data.where((item) => item['type'] == selectedCategory).toList();

      for (var item in data) {
        int id = item['id'];
        selectedProducts.putIfAbsent(id, () => false);
        productQuantities.putIfAbsent(id, () => 1.0);
        _quantityControllers.putIfAbsent(id, () => TextEditingController(text: productQuantities[id]!.toString()));
      }

    });
  }


  double _calculateTotalAmount() {
    double total = 0;
    for (var item in selectedProducts.entries.where((e) => e.value)) {
      final product = allProducts.firstWhere((p) => p['id'] == item.key, orElse: () => {});
      if (product != null) {
        double quantity = productQuantities[item.key] ?? 1.0;
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
      double qty = productQuantities[id] ?? 1.0;
      await DBHelper.reduceProductQuantity(id, qty);
      await DBHelper.recordSale(id, qty);
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
              headers: ['Product', 'Quantity', 'Rate', 'Subtotal'],
              data: selectedItems.map((item) {
                double qty = productQuantities[item['id']]!;
                double rate = double.parse(item['rate'].toString());
                return [
                  item['name'],
                  "${qty.toString()} ${item['unit'] ?? ''}",
                  "Rs:$rate",
                  "Rs:${(rate * qty).toStringAsFixed(2)}"
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 20),
            pw.Text("Total: Rs:${_calculateTotalAmount().toStringAsFixed(2)}",
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
                    double available = double.tryParse(item['quantity'].toString()) ?? 0;

                    final unit = item['unit'] ?? '';
                    final allowDecimal = isDecimalAllowed(unit);

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
                              child: buildProductImage(item['image']),
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Left side: Quantity controls + Checkbox
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Checkbox(
                                                  value: selectedProducts[id] ?? false,
                                                  onChanged: (value) {
                                                    setState(() {
                                                      selectedProducts[id] = value ?? false;
                                                    });
                                                    if (value == true) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text('${item['name']} added to cart')),
                                                      );
                                                    } else {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text('${item['name']} removed from cart')),
                                                      );
                                                    }
                                                  },


                                                ),
                                                const Text("Select"),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.remove_circle_outline),
                                                  onPressed: () {
    final currentQty = productQuantities[id]!;
    if (currentQty > 1) {
    final newQty = allowDecimal ? currentQty - 1 : (currentQty - 1).floorToDouble();
    setState(() {
    productQuantities[id] = newQty;
    _quantityControllers[id]!.text = newQty.toString();
    });
    }


    },
                                                ),
                                                SizedBox(
                                                  width: 50,
                                                  child: TextField(
                                                    controller: _quantityControllers[id],
                                                    keyboardType: allowDecimal
                                                        ? const TextInputType.numberWithOptions(decimal: true)
                                                        : TextInputType.number,
                                                    inputFormatters: allowDecimal
                                                        ? []
                                                        : [FilteringTextInputFormatter.digitsOnly],
                                                    textAlign: TextAlign.center,
                                                    decoration: const InputDecoration(border: InputBorder.none),
                                                    onChanged: (value) {
                                                      final parsed = double.tryParse(value);
                                                      if (parsed != null && parsed <= available) {
                                                        setState(() => productQuantities[id] = parsed);
                                                      } else {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(content: Text('Only $available items available')),
                                                        );
                                                      }
                                                    },
                                                  )
                                                  ,
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.add_circle_outline),
    onPressed: () {
    final currentQty = productQuantities[id]!;
    final newQty = allowDecimal ? currentQty + 1 : (currentQty + 1).floorToDouble();
    if (newQty <= available) {
    setState(() {
    productQuantities[id] = newQty;
    _quantityControllers[id]!.text = newQty.toString();
    });
    } else {
    ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Only $available items available')),
    );
    }
    },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),


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
                padding: const EdgeInsets.only(bottom: 30, left: 16, right: 16, top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Total: ₹${_calculateTotalAmount().toStringAsFixed(2)}",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // 👇 Cart button on left
                        Expanded(
                          flex: 1,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.shopping_cart),
                            onPressed: () {
                              if (selectedProducts.values.any((v) => v == true)) {
                                _showCartDialog();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Cart is empty.')),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            label: const Text("Cart"),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // 👇 Buy button on right
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
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
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            label: const Text("Buy & Generate Bill"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            ],
          ),
        ],
      ),
    );
  }

  // Add this inside your existing _BuyProductPageState class:

  void _showCartDialog() async {
    await _loadProducts(); // Refresh quantities from DB

    showDialog(
      context: context,
      builder: (context) {
        final cartItems = selectedProducts.entries
            .where((entry) => entry.value)
            .map((entry) => allProducts.firstWhere((p) => p['id'] == entry.key))
            .toList();

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Cart'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: cartItems.length,
                  itemBuilder: (context, index) {
                    final item = cartItems[index];
                    int id = item['id'];

                    // ✅ Updated line: pull correct quantity after refresh
                    double available = double.tryParse(item['quantity'].toString()) ?? 0;
                    double quantity = productQuantities[id] ?? 1.0;
                    final unit = item['unit'] ?? '';
                    final allowDecimal = isDecimalAllowed(unit);


                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () {
                                if (quantity > 1) {
                                  setState(() {
                                    productQuantities[id] = quantity - 1;
                                    _quantityControllers[id]?.text = productQuantities[id]!.toString();
                                  });
                                  setDialogState(() {});
                                }
                              },
                            ),
                            SizedBox(
                              width: 50,
                              child: TextFormField(
                                initialValue: quantity.toString(),
                                keyboardType: allowDecimal
                                    ? const TextInputType.numberWithOptions(decimal: true)
                                    : TextInputType.number,
                                inputFormatters: allowDecimal
                                    ? []
                                    : [FilteringTextInputFormatter.digitsOnly],
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(border: InputBorder.none),
                                onChanged: (value) {
                                  final parsed = double.tryParse(value);
                                  if (parsed != null && parsed <= available) {
                                    setState(() => productQuantities[id] = parsed);
                                    setDialogState(() {});
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Only $available items available')),
                                    );
                                  }
                                },
                              )
                              ,
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () {
                                if (quantity + 1 <= available) {
                                  setState(() {
                                    productQuantities[id] = allowDecimal ? (quantity + 1) : (quantity + 1).floorToDouble();

                                    _quantityControllers[id]?.text = productQuantities[id]!.toString();
                                  });
                                  setDialogState(() {});
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Only $available items available')),
                                  );
                                }
                              },
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setState(() => selectedProducts[id] = false);
                                setDialogState(() {});
                              },
                            ),
                          ],
                        ),
                        const Divider(),
                      ],
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                )
              ],
            );
          },
        );
      },
    );
  }



}
