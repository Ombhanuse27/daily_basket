import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

// *** ADD THIS IMPORT TO NAVIGATE TO THE BILLS PAGE ***
import 'view_bills_page.dart';

// Enum to manage which view is currently selected.
enum DataView { statistics, sales }

class StockAndSalesPage extends StatefulWidget {
  const StockAndSalesPage({super.key});

  @override
  State<StockAndSalesPage> createState() => _StockAndSalesPageState();
}

class _StockAndSalesPageState extends State<StockAndSalesPage> {
  List<Map<String, dynamic>> productStats = [];
  List<Map<String, dynamic>> allSalesData = [];
  List<Map<String, dynamic>> filteredSalesData = [];
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';
  bool isLoading = true;

  // State for the new view switcher
  DataView _currentView = DataView.statistics;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => isLoading = true);
    await _loadSalesData();
    await _loadStats();
    if (mounted) setState(() => isLoading = false);
  }

  // --- CALCULATED GETTERS (Unchanged) ---
  double get totalProfit {
    return allSalesData.fold(0.0, (sum, sale) {
      final profitPerItem = (sale['rate'] ?? 0.0) - (sale['originalRate'] ?? 0.0);
      final totalProfitForSale = profitPerItem * (sale['quantity'] ?? 0.0);
      return sum + totalProfitForSale;
    });
  }
  double get totalRevenue => allSalesData.fold(0.0, (sum, sale) => sum + (sale['subtotal'] ?? 0.0));
  double get monthlyRevenue {
    final now = DateTime.now();
    return allSalesData.where((sale) {
      final saleDate = DateTime.tryParse(sale['saleDate'] ?? '');
      return saleDate != null && saleDate.month == now.month && saleDate.year == now.year;
    }).fold(0.0, (sum, sale) => sum + (sale['subtotal'] ?? 0.0));
  }
  double get filteredSalesAmount => filteredSalesData.fold(0.0, (sum, sale) => sum + (sale['subtotal'] ?? 0.0));
  List<Map<String, dynamic>> get filteredStats {
    if (searchQuery.isEmpty) return productStats;
    return productStats.where((item) => (item['name'] as String).toLowerCase().contains(searchQuery.toLowerCase())).toList();
  }

  // --- DATA LOADING & FILTERING LOGIC (Unchanged) ---
  Future<void> _loadStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final adminId = prefs.getString('admin_id');
      if (adminId == null) return;
      final productsSnapshot = await FirebaseFirestore.instance.collection('admins').doc(adminId).collection('products').get();
      final salesDocs = allSalesData;
      List<Map<String, dynamic>> stats = [];
      for (var productDoc in productsSnapshot.docs) {
        final productData = productDoc.data();
        final productId = productDoc.id;
        final productSales = salesDocs.where((sale) => sale['productId'] == productId);
        double totalSold = 0, totalRevenue = 0, totalProfit = 0;
        for (var sale in productSales) {
          final quantity = (sale['quantity'] ?? 0).toDouble();
          final rate = (sale['rate'] ?? 0).toDouble();
          final originalRate = (sale['originalRate'] ?? 0).toDouble();
          totalSold += quantity;
          totalRevenue += (rate * quantity);
          totalProfit += (rate - originalRate) * quantity;
        }
        stats.add({
          'id': productId, 'name': productData['name'] ?? 'Unknown',
          'type': productData['category'] ?? 'Unknown', 'unit': productData['unit'] ?? '',
          'rate': (productData['rate'] ?? '0').toString(),
          'originalRate': (productData['originalRate'] ?? '0').toString(),
          'stockLeft': double.tryParse(productData['quantity']?.toString() ?? '0') ?? 0,
          'totalSold': totalSold, 'profit': totalProfit, 'revenue': totalRevenue,
          'image': productData['imagePath'] ?? '',
        });
      }
      if (mounted) setState(() => productStats = stats);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading stats: $e')));
    }
  }

  Future<void> _loadSalesData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final adminId = prefs.getString('admin_id');
      if (adminId == null) return;
      final salesSnapshot = await FirebaseFirestore.instance.collection('admins').doc(adminId).collection('sales').orderBy('timestamp', descending: true).get();
      final sales = salesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'productId': data['productId'] ?? '',
          'productName': data['productName'] ?? 'Unknown',
          'rate': (data['rate'] ?? 0).toDouble(),
          'originalRate': (data['originalRate'] ?? 0).toDouble(),
          'quantity': (data['quantity'] ?? 0).toDouble(),
          'unit': data['unit'] ?? '',
          'subtotal': (data['subtotal'] ?? 0).toDouble(),
          'imagePath': data['imagePath'] ?? '',
          'saleDate': data['saleDate'] ?? DateTime.now().toIso8601String(),
          'customerName': data['customerName'] ?? 'N/A',
        };
      }).toList();
      if (mounted) {
        setState(() {
          allSalesData = sales;
          _applySalesFilter();
        });
      }
    } catch (e) {
      print('Error loading sales data: $e');
    }
  }

  void _applySalesFilter() {
    if (_startDate == null || _endDate == null) {
      filteredSalesData = List.from(allSalesData);
    } else {
      filteredSalesData = allSalesData.where((sale) {
        final saleDate = DateTime.parse(sale['saleDate']);
        final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        return !saleDate.isBefore(start) && !saleDate.isAfter(end);
      }).toList();
    }
    setState(() {});
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Sales'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_view_month),
              title: const Text('Filter by Month'),
              onTap: () async {
                Navigator.pop(context);
                final pickedDate = await showDatePicker(context: context, initialDate: _startDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
                if (pickedDate != null) {
                  setState(() {
                    _startDate = DateTime(pickedDate.year, pickedDate.month, 1);
                    _endDate = DateTime(pickedDate.year, pickedDate.month + 1, 0);
                    _applySalesFilter();
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Filter by Date Range'),
              onTap: () async {
                Navigator.pop(context);
                final pickedRange = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (pickedRange != null) {
                  setState(() {
                    _startDate = pickedRange.start;
                    _endDate = pickedRange.end;
                    _applySalesFilter();
                  });
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _startDate = null;
                _endDate = null;
                _applySalesFilter();
              });
            },
            child: const Text('Clear Filter'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
  }

  String _getFilterLabel() {
    if (_startDate == null) return 'Filter: All Time';
    final formatter = DateFormat('dd MMM yyyy');
    if (_startDate!.day == 1 && _endDate!.day == DateTime(_endDate!.year, _endDate!.month + 1, 0).day) {
      return 'Filter: ${DateFormat('MMMM yyyy').format(_startDate!)}';
    }
    return 'Filter: ${formatter.format(_startDate!)} - ${formatter.format(_endDate!)}';
  }

  Future<void> _exportToPDF() async {
    final regularFontData = await rootBundle.load("assets/fonts/NotoSans-Regular.ttf");
    final ttfRegular = pw.Font.ttf(regularFontData);
    final boldFontData = await rootBundle.load("assets/fonts/NotoSans-Bold.ttf");
    final ttfBold = pw.Font.ttf(boldFontData);

    final theme = pw.ThemeData.withFont(
      base: ttfRegular,
      bold: ttfBold,
    );

    final pdf = pw.Document();

    pdf.addPage(pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Header(level: 0, child: pw.Text("Product Statistics Report", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
          pw.Text("Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}"),
          pw.SizedBox(height: 20),
          pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headers: ["Name", "Category", "Stock", "Sold", "Rate", "Original Rate", "Revenue", "Profit"],
              data: filteredStats.map((item) => [
                item['name'], item['type'], '${item['stockLeft']} ${item['unit']}', '${item['totalSold']} ${item['unit']}',
                "₹${item['rate']}", "₹${item['originalRate']}", "₹${(item['revenue'] ?? 0).toStringAsFixed(2)}", "₹${(item['profit'] ?? 0).toStringAsFixed(2)}",
              ]).toList()
          ),
          pw.SizedBox(height: 20),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
            pw.Text("Total Revenue (All Time): ₹${totalRevenue.toStringAsFixed(2)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(width: 20),
            pw.Text("Total Profit (All Time): ₹${totalProfit.toStringAsFixed(2)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.green)),
          ]),
        ]
    ));

    if (filteredSalesData.isNotEmpty) {
      pdf.addPage(pw.MultiPage(
          theme: theme,
          build: (context) => [
            pw.Header(level: 0, child: pw.Text("Sales Details Report", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
            pw.Text(_getFilterLabel().replaceAll('Filter: ', 'Period: ')),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headers: ["Date", "Customer", "Product", "Qty", "Rate", "Subtotal"],
                data: filteredSalesData.map((sale) => [
                  DateFormat('dd-MM-yy').format(DateTime.parse(sale['saleDate'])), sale['customerName'], sale['productName'],
                  "${sale['quantity']} ${sale['unit']}", "₹${sale['rate'].toStringAsFixed(2)}", "₹${sale['subtotal'].toStringAsFixed(2)}",
                ]).toList()
            ),
            pw.SizedBox(height: 20),
            pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text("Total Sales Amount (Filtered): ₹${filteredSalesAmount.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold))
            )
          ]
      ));
    }
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Stock & Sales", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAllData, tooltip: "Refresh Data")],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildSummarySection(constraints.maxWidth > 800),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search products in statistics...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Colors.grey[200],
                    ),
                    onChanged: (value) => setState(() => searchQuery = value),
                  ),
                  const SizedBox(height: 16),
                  _buildViewSwitcher(),
                  const SizedBox(height: 16),
                  if (_currentView == DataView.statistics)
                    _buildProductStatsView(constraints)
                  else
                    _buildSalesHistoryView(),
                  const SizedBox(height: 24),

                  // *** NEW BUTTON ADDED HERE ***
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ViewBillsPage()),
                      );
                    },
                    icon: const Icon(Icons.list_alt_rounded),
                    label: const Text("View All Bills"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 12), // Spacing between buttons
                  // ***************************

                  ElevatedButton.icon(
                    onPressed: _exportToPDF,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text("Export Report to PDF"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildViewSwitcher() {
    return SegmentedButton<DataView>(
      segments: const [
        ButtonSegment(value: DataView.statistics, label: Text("Statistics"), icon: Icon(Icons.inventory_2_outlined)),
        ButtonSegment(value: DataView.sales, label: Text("Sales History"), icon: Icon(Icons.receipt_long_outlined)),
      ],
      selected: {_currentView},
      onSelectionChanged: (Set<DataView> newSelection) {
        setState(() {
          _currentView = newSelection.first;
        });
      },
      style: SegmentedButton.styleFrom(
        foregroundColor: Colors.grey.shade600,
        selectedForegroundColor: Colors.white,
        selectedBackgroundColor: Colors.deepPurple,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSummarySection(bool isWideScreen) {
    final cards = [
      _buildSummaryCard("Total Profit", "₹${totalProfit.toStringAsFixed(2)}", Icons.trending_up_rounded, Colors.green, "All-time profit from all sales"),
      _buildSummaryCard("Total Revenue", "₹${totalRevenue.toStringAsFixed(2)}", Icons.monetization_on_rounded, Colors.blue, "All-time revenue from all sales"),
      _buildSummaryCard("This Month's Revenue", "₹${monthlyRevenue.toStringAsFixed(2)}", Icons.calendar_month_rounded, Colors.orange, "Revenue from this calendar month"),
    ];
    return isWideScreen
        ? Row(children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: c))).toList())
        : Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: cards);
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(icon, color: color, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                    Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductStatsView(BoxConstraints constraints) {
    if (constraints.maxWidth > 800) {
      return _buildStatsDataTable();
    }
    return _buildStatsCardList();
  }

  Widget _buildStatsDataTable() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(Colors.grey[200]),
          columns: const [
            DataColumn(label: Text("Product")),
            DataColumn(label: Text("Stock Left"), numeric: true),
            DataColumn(label: Text("Total Sold"), numeric: true),
            DataColumn(label: Text("Revenue"), numeric: true),
            DataColumn(label: Text("Profit"), numeric: true),
          ],
          rows: filteredStats.map((item) => DataRow(cells: [
            DataCell(Row(
              children: [
                buildProductImage(item['image'], size: 35),
                const SizedBox(width: 12),
                Text(item['name'] ?? '-'),
              ],
            )),
            DataCell(Text('${item['stockLeft']} ${item['unit']}')),
            DataCell(Text('${item['totalSold']} ${item['unit']}')),
            DataCell(Text("₹${(item['revenue'] ?? 0).toStringAsFixed(2)}")),
            DataCell(Text("₹${(item['profit'] ?? 0).toStringAsFixed(2)}",
              style: TextStyle(
                color: (item['profit'] ?? 0) >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                fontWeight: FontWeight.bold,
              ),
            )),
          ])).toList(),
        ),
      ),
    );
  }

  Widget _buildStatsCardList() {
    if (filteredStats.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: Text("No product statistics found.", style: TextStyle(color: Colors.grey))));
    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filteredStats.length,
      itemBuilder: (context, index) {
        final item = filteredStats[index];
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                Row(
                  children: [
                    buildProductImage(item['image'], size: 50),
                    const SizedBox(width: 12),
                    Expanded(child: Text(item['name'] ?? 'Unknown', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                  ],
                ),
                const Divider(height: 20),
                _buildStatRow("Stock Left:", '${item['stockLeft']} ${item['unit']}', Colors.blueGrey),
                _buildStatRow("Total Sold:", '${item['totalSold']} ${item['unit']}', Colors.blueGrey),
                _buildStatRow("Total Revenue:", "₹${(item['revenue'] ?? 0).toStringAsFixed(2)}", Colors.black87),
                _buildStatRow("Total Profit:", "₹${(item['profit'] ?? 0).toStringAsFixed(2)}", (item['profit'] ?? 0) >= 0 ? Colors.green.shade700 : Colors.red.shade700),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: valueColor, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildSalesHistoryView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Row(
            children: [
              Expanded(child: Text(_getFilterLabel(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple), overflow: TextOverflow.ellipsis)),
              IconButton(icon: const Icon(Icons.filter_list_rounded), onPressed: _showFilterDialog, tooltip: 'Filter Sales'),
            ],
          ),
        ),
        if (filteredSalesData.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off_rounded, size: 60, color: Colors.grey),
                  SizedBox(height: 12),
                  Text("No sales found for the selected period.", style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredSalesData.length,
            itemBuilder: (context, index) {
              final sale = filteredSalesData[index];
              return Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: buildProductImage(sale['imagePath'], size: 45),
                  title: Text(sale['productName'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Sold to: ${sale['customerName']} on ${DateFormat('dd MMM yy').format(DateTime.parse(sale['saleDate']))}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("₹${(sale['subtotal'] ?? 0).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                      Text('${sale['quantity']} ${sale['unit']}'),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget buildProductImage(String? imagePath, {double size = 40}) {
    if (imagePath != null && (imagePath.startsWith("assets/") || imagePath.startsWith("http"))) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: imagePath.startsWith("assets/")
            ? Image.asset(imagePath, width: size, height: size, fit: BoxFit.cover)
            : Image.network(imagePath, width: size, height: size, fit: BoxFit.cover,
          loadingBuilder: (context, child, li) => li == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          errorBuilder: (c, e, s) => Image.asset('assets/images/img_4.png', width: size, height: size, fit: BoxFit.cover),
        ),
      );
    } else if (imagePath != null && File(imagePath).existsSync()) {
      return ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(imagePath), width: size, height: size, fit: BoxFit.cover));
    } else {
      return ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/images/img_4.png', width: size, height: size, fit: BoxFit.cover));
    }
  }
}