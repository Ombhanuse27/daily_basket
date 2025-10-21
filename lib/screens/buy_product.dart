import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class BuyProductPage extends StatefulWidget {
  const BuyProductPage({super.key});

  @override
  State<BuyProductPage> createState() => _BuyProductPageState();
}

Widget buildProductImage(String? imagePath, {double size = 70}) {
  if (imagePath != null && imagePath.startsWith("assets/")) {
    return Image.asset(imagePath, width: size, height: size, fit: BoxFit.cover);
  } else if (imagePath != null && imagePath.startsWith("http")) {
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

class _BuyProductPageState extends State<BuyProductPage> {
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> allProducts = [];
  List<String> categories = [];
  String? selectedCategory;
  String searchQuery = "";

  Map<String, bool> selectedProducts = {};
  Map<String, double> productQuantities = {};
  final Map<String, TextEditingController> _quantityControllers = {};

  // User and Admin info
  String? currentUserEmail;
  String? adminId;
  String? employeeId;
  bool isEmployee = false;
  bool isLoading = true;
  String? shopName;
  String? shopAddress;

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      currentUserEmail = prefs.getString('user_email');
      adminId = prefs.getString('admin_id');
      employeeId = prefs.getString('employee_id');
      isEmployee = prefs.getBool('is_employee') ?? false;

      if (currentUserEmail == null) {
        _showAccessDeniedMessage('No user email found. Please login again.');
        return;
      }

      if (adminId == null) {
        await _fallbackUserInitialization();
      }

      if (adminId != null) {
        await _loadAdminDetails();
        await _loadCategories();
        await _loadProducts();
      } else {
        _showAccessDeniedMessage('Access denied. You are not authorized to view this page.');
      }
    } catch (e) {
      print('Error initializing user: $e');
      _showAccessDeniedMessage('Error loading user data. Please try again.');
    } finally {
      if(mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadAdminDetails() async {
    if (adminId == null) return;
    try {
      final adminDoc = await FirebaseFirestore.instance.collection('admins').doc(adminId).get();
      if (adminDoc.exists) {
        shopName = adminDoc.data()?['shopName'] ?? 'Your Shop';
        shopAddress = adminDoc.data()?['address'] ?? 'Your Address';
      }
    } catch (e) {
      print('Error loading admin details: $e');
    }
  }

  Future<void> _fallbackUserInitialization() async {
    final adminSnapshot = await FirebaseFirestore.instance
        .collection('admins')
        .where('email', isEqualTo: currentUserEmail)
        .limit(1)
        .get();

    if (adminSnapshot.docs.isNotEmpty) {
      adminId = adminSnapshot.docs.first.id;
      isEmployee = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('admin_id', adminId!);
      await prefs.setBool('is_employee', false);
    } else {
      final employeeResult = await _findEmployeeAndAdmin();
      if (employeeResult != null) {
        adminId = employeeResult['adminId'];
        employeeId = employeeResult['employeeId'];
        isEmployee = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('admin_id', adminId!);
        await prefs.setString('employee_id', employeeId!);
        await prefs.setBool('is_employee', true);
      }
    }
  }

  void _showAccessDeniedMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<Map<String, String>?> _findEmployeeAndAdmin() async {
    try {
      final adminsSnapshot = await FirebaseFirestore.instance
          .collection('admins')
          .get();

      for (var adminDoc in adminsSnapshot.docs) {
        final employeesSnapshot = await FirebaseFirestore.instance
            .collection('admins')
            .doc(adminDoc.id)
            .collection('employees')
            .where('email', isEqualTo: currentUserEmail)
            .limit(1)
            .get();

        if (employeesSnapshot.docs.isNotEmpty) {
          return {
            'adminId': adminDoc.id,
            'employeeId': employeesSnapshot.docs.first.id,
          };
        }
      }
    } catch (e) {
      print('Error finding employee: $e');
    }
    return null;
  }

  Future<void> _loadCategories() async {
    if (adminId == null) return;

    try {
      final categorySnapshot = await FirebaseFirestore.instance
          .collection('admins')
          .doc(adminId)
          .collection('categories')
          .get();

      final catList = categorySnapshot.docs.map((doc) => doc['name'] as String).toList();
      if(mounted) setState(() => categories = catList);
    } catch (e) {
      print('Error loading categories: $e');
    }
  }

  Future<void> _loadProducts() async {
    if (adminId == null) return;

    try {
      final productSnapshot = await FirebaseFirestore.instance
          .collection('admins')
          .doc(adminId)
          .collection('products')
          .orderBy('createdAt', descending: true)
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
          'type': data['category'] ?? '',
          'image': data['imagePath'] ?? '',
          'allowDecimal': data['allowDecimal'] ?? false,
          'gst': data['gst'] ?? '0',
        };
      }).toList();

      if(mounted) {
        setState(() {
          allProducts = fetchedProducts;
          products = selectedCategory == null
              ? fetchedProducts
              : fetchedProducts.where((item) => item['type'] == selectedCategory).toList();

          for (var item in fetchedProducts) {
            final id = item['id'] as String;
            selectedProducts.putIfAbsent(id, () => false);
            productQuantities.putIfAbsent(id, () => 1.0);
            _quantityControllers.putIfAbsent(id, () => TextEditingController(text: '1'));
          }
        });
      }
    } catch (e) {
      print('Error loading products: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading products: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  double _calculateTotalAmount() {
    double total = 0;
    for (var entry in selectedProducts.entries) {
      if (!entry.value) continue;
      final product = allProducts.firstWhere((p) => p['id'] == entry.key, orElse: () => {});
      if (product.isEmpty) continue;
      double qty = productQuantities[entry.key] ?? 1.0;
      double rate = double.tryParse(product['rate'].toString()) ?? 0;
      total += qty * rate;
    }
    return total;
  }

  void _showCustomerDetailsDialog() {
    final customerNameController = TextEditingController();
    String paymentStatus = 'Paid';
    bool applyGst = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Confirm Purchase'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: customerNameController,
                      decoration: const InputDecoration(
                        labelText: 'Customer Name',
                        hintText: 'Enter customer name',
                        border: OutlineInputBorder(),
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    const Text('Payment Status:', style: TextStyle(fontWeight: FontWeight.bold)),
                    RadioListTile<String>(
                      title: const Text('Paid'),
                      value: 'Paid',
                      groupValue: paymentStatus,
                      onChanged: (value) => setDialogState(() => paymentStatus = value!),
                    ),
                    RadioListTile<String>(
                      title: const Text('Unpaid'),
                      value: 'Unpaid',
                      groupValue: paymentStatus,
                      onChanged: (value) => setDialogState(() => paymentStatus = value!),
                    ),
                    CheckboxListTile(
                      title: const Text("Apply GST"),
                      value: applyGst,
                      onChanged: (bool? value) {
                        setDialogState(() {
                          applyGst = value ?? false;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: Colors.green,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = customerNameController.text.trim();
                    if (name.isNotEmpty) {
                      Navigator.of(context).pop();
                      _generatePdfBill(name, paymentStatus, applyGst);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a customer name.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Confirm & Print Bill'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // **** MAIN BILL GENERATION FUNCTION (MODIFIED) ****
  Future<void> _generatePdfBill(String customerName, String paymentStatus, bool applyGst) async {
    if (adminId == null) return;

    final selectedItems = allProducts.where((p) => selectedProducts[p['id']] == true).toList();

    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No items selected.')));
      return;
    }

    try {
      final invoiceId = 'INV-${DateTime.now().millisecondsSinceEpoch}';
      List<Map<String, dynamic>> billItemsForDb = [];
      double subTotal = 0;
      double totalCgst = 0;
      double totalSgst = 0;

      final batch = FirebaseFirestore.instance.batch();

      for (var item in selectedItems) {
        String productId = item['id'];
        double qty = productQuantities[productId] ?? 1.0;
        double currentQty = double.tryParse(item['quantity'].toString()) ?? 0;
        double rate = double.tryParse(item['rate'].toString()) ?? 0;
        double itemSubtotal = rate * qty;
        subTotal += itemSubtotal;

        final productRef = FirebaseFirestore.instance.collection('admins').doc(adminId).collection('products').doc(productId);
        batch.update(productRef, {'quantity': (currentQty - qty).toString()});

        billItemsForDb.add({
          'productName': item['name'], 'quantity': qty, 'unit': item['unit'],
          'rate': rate, 'subtotal': itemSubtotal, 'gst': item['gst'],
        });

        if (applyGst) {
          double gstRate = double.tryParse(item['gst'].toString()) ?? 0.0;
          if (gstRate > 0) {
            double gstAmount = itemSubtotal * (gstRate / 100);
            totalCgst += gstAmount / 2;
            totalSgst += gstAmount / 2;
          }
        }
      }

      double grandTotal = subTotal + totalCgst + totalSgst;

      // Create the data map for the sale
      Map<String, dynamic> saleData = {
        'invoiceId': invoiceId, 'customerName': customerName, 'paymentStatus': paymentStatus,
        'subTotal': subTotal, 'totalCgst': totalCgst, 'totalSgst': totalSgst,
        'grandTotal': grandTotal, 'gstApplied': applyGst,
        'billDate': Timestamp.now(), 'soldBy': currentUserEmail, 'items': billItemsForDb,
      };

      // Save the sale document to the 'sales' collection
      final saleRef = FirebaseFirestore.instance.collection('admins').doc(adminId).collection('sales').doc();
      batch.set(saleRef, saleData);

      await batch.commit();

      // --- PDF Generation ---
      final pdf = pw.Document();
      final font = await PdfGoogleFonts.poppinsRegular();
      final boldFont = await PdfGoogleFonts.poppinsBold();

      pdf.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(base: font, bold: boldFont),
          build: (context) => [
            _buildModernHeader(invoiceId),
            pw.SizedBox(height: 1 * PdfPageFormat.cm),
            _buildCustomerAddress(customerName),
            pw.SizedBox(height: 1 * PdfPageFormat.cm),
            _buildModernInvoiceTable(selectedItems),
            pw.Divider(),
            _buildModernTotal(paymentStatus, applyGst, subTotal, totalCgst, totalSgst, grandTotal),
            pw.SizedBox(height: 1 * PdfPageFormat.cm),
            _buildModernFooter(),
          ],
        ),
      );

      await Printing.layoutPdf(onLayout: (format) => pdf.save());

      setState(() {
        selectedProducts.updateAll((key, value) => false);
        productQuantities.updateAll((key, value) => 1.0);
        for (var controller in _quantityControllers.values) {
          controller.text = '1';
        }
      });
      await _loadProducts();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Purchase completed successfully!'), backgroundColor: Colors.green));

    } catch (e) {
      print("Error generating bill: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error processing purchase: $e'), backgroundColor: Colors.red));
    }
  }

  // ---- NEW: MODERN PDF UI BUILDER WIDGETS ----

  pw.Widget _buildModernHeader(String invoiceId) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Flex(
          direction: pw.Axis.horizontal,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(shopName ?? "Your Shop", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 24)),
                pw.Text(shopAddress ?? "Your Address"),
              ],
            ),
            pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text("INVOICE", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 32, color: PdfColors.grey800)),
                  pw.Text(invoiceId, style: const pw.TextStyle(color: PdfColors.grey600)),
                ]
            )
          ],
        ),
        pw.SizedBox(height: 1 * PdfPageFormat.cm),
        pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text("Date: ${DateFormat('dd MMMM, yyyy').format(DateTime.now())}"),
              pw.Text("Time: ${DateFormat('hh:mm a').format(DateTime.now())}"),
            ]
        ),
        pw.Divider(color: PdfColors.grey400),
      ],
    );
  }

  pw.Widget _buildCustomerAddress(String customerName) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Billed To:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(customerName),
          ],
        ),
        pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Sold By:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(currentUserEmail ?? 'N/A'),
            ]
        )
      ],
    );
  }

  /// Formats quantity to show .0 only if it's a decimal
  String formatQuantity(double qty) {
    if (qty == qty.truncateToDouble()) {
      return qty.toInt().toString();
    } else {
      return qty.toString();
    }
  }

  pw.Widget _buildModernInvoiceTable(List<Map<String, dynamic>> items) {
    const tableHeaders = ['#', 'Product', 'Quantity', 'Rate', 'Total'];

    return pw.TableHelper.fromTextArray(
      headers: tableHeaders,
      data: List<List<String>>.generate(items.length, (index) {
        final item = items[index];
        final qty = productQuantities[item['id']] ?? 1.0;
        final rate = double.tryParse(item['rate'].toString()) ?? 0.0;
        final total = qty * rate;
        return [
          (index + 1).toString(),
          item['name'],
          formatQuantity(qty),
          '₹${rate.toStringAsFixed(2)}',
          '₹${total.toStringAsFixed(2)}',
        ];
      }),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
      cellHeight: 30,
      cellAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      },
      border: pw.TableBorder.all(color: PdfColors.grey, width: 0.5),
    );
  }

  pw.Widget _buildModernTotal(String paymentStatus, bool applyGst, double subTotal, double totalCgst, double totalSgst, double grandTotal) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Row(
        children: [
          pw.Spacer(),
          pw.Expanded(
            flex: 2,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Subtotal:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('₹${subTotal.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                if (applyGst && (totalCgst > 0 || totalSgst > 0)) ...[
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('CGST:'),
                      pw.Text('₹${totalCgst.toStringAsFixed(2)}'),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('SGST:'),
                      pw.Text('₹${totalSgst.toStringAsFixed(2)}'),
                    ],
                  ),
                ],
                pw.Divider(),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: const pw.BoxDecoration(color: PdfColors.blueGrey50),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Grand Total:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                      pw.Text('₹${grandTotal.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 0.5 * PdfPageFormat.cm),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Payment Status:'),
                    pw.Text(
                      paymentStatus,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        color: paymentStatus == 'Paid' ? PdfColors.green : PdfColors.orange,
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildModernFooter() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Divider(),
        pw.SizedBox(height: 2 * PdfPageFormat.mm),
        pw.Text('Thank you for your business!', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 1 * PdfPageFormat.mm),
        pw.Text("Generated on ${DateFormat('dd-MMM-yyyy hh:mm a').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
      ],
    );
  }


  // ---- END OF MODERN PDF WIDGETS ----

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Buy Products")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (adminId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Access Denied")),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "You are not authorized to view this page. Please contact your administrator.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red, fontSize: 16),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Buy Products ${isEmployee ? '(Employee)' : '(Admin)'}", style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      body: Column(
        children: [
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
                          label: const Text('All'), selected: isSelected, selectedColor: Colors.green,
                          onSelected: (_) => setState(() { selectedCategory = null; _loadProducts(); }),
                        ),
                      );
                    }
                    final cat = categories[index - 1];
                    final isSelected = cat == selectedCategory;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(cat), selected: isSelected, selectedColor: Colors.green,
                        onSelected: (_) => setState(() { selectedCategory = isSelected ? null : cat; _loadProducts(); }),
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
                prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.grey[50],
              ),
              onChanged: (value) {
                searchQuery = value;
                setState(() {
                  products = allProducts
                      .where((item) => selectedCategory == null || item['type'] == selectedCategory)
                      .where((item) => item['name'].toString().toLowerCase().contains(searchQuery.toLowerCase()))
                      .toList();
                });
              },
            ),
          ),
          Expanded(
            child: products.isEmpty
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text("No products found.", style: TextStyle(fontSize: 16, color: Colors.grey)),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final item = products[index];
                String id = item['id'] as String;
                double available = double.tryParse(item['quantity'].toString()) ?? 0;

                final bool allowDecimal = item['allowDecimal'] as bool? ?? false;

                return Card(
                  elevation: 3,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: buildProductImage(item['image'], size: 80),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text("Rate: ₹${item['rate']}", style: TextStyle(fontSize: 14, color: Colors.green[700], fontWeight: FontWeight.w600)),
                              Text("Category: ${item['type']}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              Text(
                                "Available: ${item['quantity']} ${item['unit']}",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: available > 0 ? Colors.grey[600] : Colors.red,
                                  fontWeight: available > 0 ? FontWeight.normal : FontWeight.bold,
                                ),
                              ),
                              if (available > 0) ...[
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Checkbox(
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          value: selectedProducts[id] ?? false,
                                          onChanged: (value) {
                                            setState(() => selectedProducts[id] = value ?? false);
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                                content: Text('${item['name']} ${value == true ? 'added to' : 'removed from'} cart'),
                                                duration: const Duration(seconds: 1),
                                              ));
                                            }
                                          },
                                        ),
                                        const Text('Select', style: TextStyle(fontSize: 13)),
                                      ],
                                    ),
                                    Container(
                                      height: 34,
                                      decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.remove, size: 16),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
                                            onPressed: () {
                                              final currentQty = productQuantities[id] ?? 1.0;
                                              if (currentQty > 1) {
                                                final newQty = currentQty - 1;
                                                setState(() {
                                                  productQuantities[id] = newQty;
                                                  _quantityControllers[id]?.text = formatQuantity(newQty);
                                                });
                                              }
                                            },
                                          ),
                                          SizedBox(
                                            width: 45,
                                            child: TextField(
                                              controller: _quantityControllers[id],
                                              keyboardType: allowDecimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
                                              inputFormatters: allowDecimal ? [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))] : [FilteringTextInputFormatter.digitsOnly],
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(fontSize: 13),
                                              decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero),
                                              onChanged: (value) {
                                                final parsed = double.tryParse(value);
                                                if (parsed != null && parsed > 0 && parsed <= available) {
                                                  setState(() => productQuantities[id] = parsed);
                                                } else if (parsed != null && parsed > available) {
                                                  _quantityControllers[id]?.text = formatQuantity(available);
                                                  setState(() => productQuantities[id] = available);
                                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Only $available items available')));
                                                }
                                              },
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.add, size: 16),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
                                            onPressed: () {
                                              final currentQty = productQuantities[id] ?? 1.0;
                                              final newQty = currentQty + 1;
                                              if (newQty <= available) {
                                                setState(() {
                                                  productQuantities[id] = newQty;
                                                  _quantityControllers[id]?.text = formatQuantity(newQty);
                                                });
                                              } else {
                                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Only $available items available')));
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.red[200]!)),
                                  child: const Text('Out of Stock', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ],
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), spreadRadius: 1, blurRadius: 5, offset: const Offset(0, -3))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("Subtotal: ₹${_calculateTotalAmount().toStringAsFixed(2)}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.shopping_cart), label: const Text("Cart"),
                        onPressed: () {
                          if (selectedProducts.values.any((v) => v == true)) { _showCartDialog(); }
                          else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cart is empty.'))); }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.receipt_long), label: const Text("Buy & Generate Bill"),
                        onPressed: () {
                          if (selectedProducts.values.any((v) => v == true)) { _showCustomerDetailsDialog(); }
                          else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one product.'))); }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCartDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final cartItems = allProducts.where((p) => selectedProducts[p['id']] == true).toList();

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.shopping_cart_checkout_rounded, color: Colors.green),
                  const SizedBox(width: 8),
                  Text('Shopping Cart (${cartItems.length})'),
                ],
              ),
              contentPadding: const EdgeInsets.only(top: 16.0),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: cartItems.isEmpty
                          ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48.0),
                        child: Center(child: Text('Your cart is empty')),
                      )
                          : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        itemCount: cartItems.length,
                        itemBuilder: (context, index) {
                          final item = cartItems[index];
                          final id = item['id'] as String;
                          final available = double.tryParse(item['quantity'].toString()) ?? 0;
                          final quantity = productQuantities[id] ?? 1.0;
                          final unit = item['unit'] ?? '';
                          final rate = double.tryParse(item['rate'].toString()) ?? 0;

                          return Card(
                            elevation: 1,
                            margin: const EdgeInsets.symmetric(vertical: 5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      ClipRRect(borderRadius: BorderRadius.circular(8), child: buildProductImage(item['image'], size: 50)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                            Text('₹${rate.toStringAsFixed(2)} / $unit', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        height: 32,
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey[300]!),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            IconButton(
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              constraints: const BoxConstraints(),
                                              icon: const Icon(Icons.remove, size: 16),
                                              onPressed: () {
                                                if (quantity > 1) {
                                                  setState(() {
                                                    final newQty = quantity - 1;
                                                    productQuantities[id] = newQty;
                                                    _quantityControllers[id]?.text = formatQuantity(newQty);
                                                  });
                                                  setDialogState(() {});
                                                }
                                              },
                                            ),
                                            Text(formatQuantity(quantity), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                            IconButton(
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              constraints: const BoxConstraints(),
                                              icon: const Icon(Icons.add, size: 16),
                                              onPressed: () {
                                                if (quantity + 1 <= available) {
                                                  final newQty = quantity + 1;
                                                  setState(() {
                                                    productQuantities[id] = newQty;
                                                    _quantityControllers[id]?.text = formatQuantity(newQty);
                                                  });
                                                  setDialogState(() {});
                                                } else {
                                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Only $available items available')));
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Text('₹${(rate * quantity).toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                            onPressed: () {
                                              setState(() => selectedProducts[id] = false);
                                              setDialogState(() {});
                                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item['name']} removed from cart')));
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (cartItems.isNotEmpty) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Amount:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            Text(
                              '₹${_calculateTotalAmount().toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                if (cartItems.isNotEmpty)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showCustomerDetailsDialog();
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    child: const Text('Proceed to Buy'),
                  ),
              ],
            );
          },
        );
      },
    ).then((_) => setState(() {}));
  }
}