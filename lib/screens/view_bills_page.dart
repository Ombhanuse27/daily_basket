import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class ViewBillsPage extends StatefulWidget {
  const ViewBillsPage({super.key});

  @override
  State<ViewBillsPage> createState() => _ViewBillsPageState();
}

class _ViewBillsPageState extends State<ViewBillsPage> {
  String? adminId;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      adminId = prefs.getString('admin_id');
      if (adminId == null) {
        // Handle case where user is not logged in or adminId is missing
        print("Admin ID not found in SharedPreferences.");
      }
    } catch (e) {
      print("Error initializing user: $e");
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _updatePaymentStatus(String billId) async {
    if (adminId == null) return;

    // Show confirmation dialog
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Payment'),
          content: const Text('Are you sure you want to mark this bill as Paid?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        // *** UPDATED: Now updates the 'sales' collection ***
        await FirebaseFirestore.instance
            .collection('admins')
            .doc(adminId)
            .collection('sales') // Changed from 'bills' to 'sales'
            .doc(billId)
            .update({'paymentStatus': 'Paid'});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment status updated to Paid.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        print("Error updating status: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update status: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // Logic for a single bill card
  Widget _buildBillCard(DocumentSnapshot bill) {
    final data = bill.data() as Map<String, dynamic>;

    final String customerName = data['customerName'] ?? 'N/A';
    // *** UPDATED: Uses 'grandTotal' from the sales document ***
    final double totalAmount = (data['grandTotal'] ?? 0.0).toDouble(); // Changed from 'totalAmount'
    final String paymentStatus = data['paymentStatus'] ?? 'Unknown';
    final Timestamp timestamp = data['billDate'] ?? Timestamp.now();
    final String formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(timestamp.toDate());
    final bool isPaid = paymentStatus == 'Paid';

    return Card(
      elevation: 3,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isPaid ? Colors.green.shade100 : Colors.red.shade100,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        title: Text(
          customerName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          'Amount: ₹${totalAmount.toStringAsFixed(2)}\nDate: $formattedDate',
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Chip(
              label: Text(
                paymentStatus,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: isPaid ? Colors.green : Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            if (!isPaid)
              Expanded(
                child: TextButton(
                  onPressed: () => _updatePaymentStatus(bill.id),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Mark Paid', style: TextStyle(fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Bills'),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : adminId == null
          ? const Center(
        child: Text(
          'Could not load bills. User not identified.',
          style: TextStyle(color: Colors.red),
        ),
      )
          : StreamBuilder<QuerySnapshot>(
        // *** UPDATED: Fetches from the 'sales' collection ***
        stream: FirebaseFirestore.instance
            .collection('admins')
            .doc(adminId)
            .collection('sales') // Changed from 'bills' to 'sales'
            .orderBy('billDate', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No bills found.',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final bills = snapshot.data!.docs;

          // Responsive layout switches between ListView and GridView
          return LayoutBuilder(
            builder: (context, constraints) {
              const double breakpoint = 600.0;
              // Use ListView for mobile/narrow screens
              if (constraints.maxWidth < breakpoint) {
                return ListView.builder(
                  padding: const EdgeInsets.all(12.0),
                  itemCount: bills.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: _buildBillCard(bills[index]),
                    );
                  },
                );
              }
              // Use GridView for desktop/wide screens
              else {
                return GridView.builder(
                  padding: const EdgeInsets.all(16.0),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 450, // Max width for each card
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 3, // Adjust aspect ratio for wider cards
                  ),
                  itemCount: bills.length,
                  itemBuilder: (context, index) {
                    return _buildBillCard(bills[index]);
                  },
                );
              }
            },
          );
        },
      ),
    );
  }
}