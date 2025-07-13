import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'db_helper.dart';

class StockAndSalesPage extends StatefulWidget {
  const StockAndSalesPage({super.key});

  @override
  State<StockAndSalesPage> createState() => _StockAndSalesPageState();
}

class _StockAndSalesPageState extends State<StockAndSalesPage> {
  List<Map<String, dynamic>> productStats = [];
  TextEditingController _searchController = TextEditingController();
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  double get totalProfit {
    return filteredStats.fold(0.0, (sum, item) {
      final profit = item['profit'] ?? 0.0;
      return sum + (profit is num ? profit.toDouble() : 0.0);
    });
  }

  double get totalRevenue {
    return filteredStats.fold(0.0, (sum, item) {
      final revenue = item['revenue'] ?? 0.0;
      return sum + (revenue is num ? revenue.toDouble() : 0.0);
    });
  }



  Future<void> _loadStats() async {
    final data = await DBHelper.getSalesSummary();
    setState(() => productStats = data);
  }

  List<Map<String, dynamic>> get filteredStats {
    return productStats.where((item) {
      final name = item['name']?.toLowerCase() ?? '';
      return name.contains(searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> _exportToPDF() async {
    final pdf = pw.Document();
    final headers = ["Name", "Type", "Unit", "Rate", "Original", "Stock", "Sold", "Profit", "Revenue"];

    final dataRows = filteredStats.map((item) => [
      item['name'],
      item['type'],
      item['unit'],
      "Rs:${item['rate']}",
      "Rs:${item['originalRate']}",
      item['stockLeft'].toString(),
      item['totalSold'].toString(),
      "Rs:${(item['profit'] ?? 0).toStringAsFixed(2)}",
      "Rs:${(item['revenue'] ?? 0).toStringAsFixed(2)}",
    ]).toList();

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Table.fromTextArray(
          headers: headers,
          data: dataRows,
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Stock & Sales"),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: "Search Product",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => searchQuery = value),
            ),
          ),

          Expanded(
            child: Card(
              elevation: 4,
              margin: const EdgeInsets.all(12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: MaterialStateColor.resolveWith((states) => Colors.deepPurple.shade100),
                    dataRowColor: MaterialStateColor.resolveWith((states) => Colors.grey.shade50),
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                      fontSize: 14,
                    ),
                    dataTextStyle: const TextStyle(fontSize: 13),
                    columnSpacing: 16,
                    columns: const [
                      DataColumn(label: Text("Image")),
                      DataColumn(label: Text("Name")),
                      DataColumn(label: Text("Type")),
                      DataColumn(label: Text("Unit")),
                      DataColumn(label: Text("Rate")),
                      DataColumn(label: Text("Original")),
                      DataColumn(label: Text("Stock")),
                      DataColumn(label: Text("Sold")),
                      DataColumn(label: Text("Profit")),
                      DataColumn(label: Text("Revenue")),
                    ],
                    rows: List<DataRow>.generate(
                      filteredStats.length,
                          (index) {
                        final item = filteredStats[index];
                        final isEven = index % 2 == 0;
                        return DataRow(
                          color: MaterialStateColor.resolveWith((states) =>
                          isEven ? Colors.grey.shade100 : Colors.white),
                          cells: [
                            DataCell(buildProductImage(item['image'], size: 40)),
                            DataCell(Text(item['name'] ?? '-')),
                            DataCell(Text(item['type'] ?? '-')),
                            DataCell(Text(item['unit'] ?? '-')),
                            DataCell(Text("₹${item['rate']}")),
                            DataCell(Text("₹${item['originalRate']}")),
                            DataCell(Text("${item['stockLeft']}")),
                            DataCell(Text("${item['totalSold']}")),
                            DataCell(Text("₹${(item['profit'] ?? 0).toStringAsFixed(2)}")),
                            DataCell(Text("₹${(item['revenue'] ?? 0).toStringAsFixed(2)}")),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: ElevatedButton.icon(
              onPressed: _exportToPDF,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text("Export to PDF",style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            ),
          ),
          const SizedBox(height: 10),
    Padding(
    padding: const EdgeInsets.all(8.0),
    child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
    Text(
    "Total Profit: ₹${totalProfit.toStringAsFixed(2)}",
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
    Text(
    "Total Revenue: ₹${totalRevenue.toStringAsFixed(2)}",
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
    ],
    ),
    ),

        ],
      ),
    );
  }

  Widget buildProductImage(String? imagePath, {double size = 40}) {
    if (imagePath != null && imagePath.startsWith("assets/")) {
      return Image.asset(imagePath, width: size, height: size, fit: BoxFit.cover);
    } else if (imagePath != null && File(imagePath).existsSync()) {
      return Image.file(File(imagePath), width: size, height: size, fit: BoxFit.cover);
    } else {
      return Image.asset('assets/images/img_4.png', width: size, height: size, fit: BoxFit.cover);
    }
  }
}
