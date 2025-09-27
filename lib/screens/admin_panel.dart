import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import '../services/firebase_service.dart';
import 'package:intl/intl.dart';


class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> with TickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _pendingUsers = [];
  List<Map<String, dynamic>> _keyRequests = [];
  String userEmail = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  void _loadData() async {
    final users = await FirebaseService.fetchPendingUsers();
    final requests = await FirebaseService.fetchKeyRequests();
    setState(() {
      _pendingUsers = users;
      _keyRequests = requests;
    });
  }

  String _generateActivationKey() {
    return "MYBZ-${Random().nextInt(999999).toString().padLeft(6, '0')}";
  }

  Future<void> _sendActivationEmail(
      String recipientEmail, String key, DateTime expiry) async {
    final String username = '90797f002@smtp-brevo.com'; // Your Brevo login
    final String password = 'KzvjCOs8pQq2RkNS';       // Your Brevo SMTP key
    final smtpServer = SmtpServer(
      'smtp-relay.brevo.com',
      port: 587,
      username: username,
      password: password,
      ignoreBadCertificate: false,
      ssl: false,
      allowInsecure: false,
    );

    final message = Message()
      ..from = Address('naikamar1029@gmail.com', 'DailyBasket Admin')
      ..recipients.add(recipientEmail)
      ..subject = '✅ Your DailyBasket Activation Key'
      ..text = '''
Hello,

Your activation key is:

🔑 $key

Expiry Date: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(expiry)}


Please use this key in the DailyBasket app.

Thank you,
DailyBasket Team
''';

    print("📨 Preparing to send email to: $recipientEmail");

    try {
      final sendReport = await send(message, smtpServer, timeout: const Duration(seconds: 15));

      print("✅ Email sending completed.");
      print("📬 SMTP Server: ${smtpServer.host}");
      print("📧 Email sent to: $recipientEmail");
      print("📦 Message status: ${sendReport.toString()}");

    } on MailerException catch (e) {
      print("❌ MailerException caught");
      for (var p in e.problems) {
        print("⚠️ Problem: ${p.code} - ${p.msg}");
      }
      print("❌ Exception details: $e");
    } catch (e) {
      print("❌ General Exception: $e");
    }
  }


  void _approveUser(String id, String email) async {
    final key = _generateActivationKey();
    final expiry = DateTime.now().add(const Duration(days: 2));

    await FirebaseService.approveUser(id, key, expiry);
    await _sendActivationEmail(email, key, expiry);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("✅ Approved $email")),
    );
    _loadData();
  }

  void _reissueKey(Map<String, dynamic> request) async {
    final key = _generateActivationKey();
    final expiry = DateTime.now().add(const Duration(days: 2)); // for testing


    final userSnapshot = await FirebaseFirestore.instance
        .collection('admins')
        .where('email', isEqualTo: request['email'])
        .get();

    if (userSnapshot.docs.isNotEmpty) {
      final userId = userSnapshot.docs.first.id;

      await FirebaseFirestore.instance
          .collection('admins')
          .doc(userId)
          .update({
        'activationKey': key,
        'expiryDate': expiry,
        'isActivated': true,
      }
      );

      // Update expiry date for all employees under this admin
      final employeesSnapshot = await FirebaseFirestore.instance
          .collection('admins')
          .doc(userId)
          .collection('employees')
          .get();

      // Batch update all employees' expiry dates
      WriteBatch batch = FirebaseFirestore.instance.batch();

      for (QueryDocumentSnapshot employeeDoc in employeesSnapshot.docs) {
        batch.update(employeeDoc.reference, {
          'expiryDate': expiry,
        });
      }

      // Commit the batch update
      await batch.commit();



      await FirebaseFirestore.instance
          .collection('key_requests')
          .doc(request['id'])
          .update({'status': 'approved'});

      await _sendActivationEmail(request['email'], key, expiry);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("🔑 Key re-issued to ${request['email']}")),
      );

      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Panel"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Pending Users"),
            Tab(text: "Key Requests"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Pending Users Tab
          _pendingUsers.isEmpty
              ? const Center(child: Text("No pending users."))
              : ListView.builder(
            itemCount: _pendingUsers.length,
            itemBuilder: (context, index) {
              final user = _pendingUsers[index];
              return ListTile(
                title: Text(user['name'] ?? 'Unnamed'),
                subtitle: Text(user['email']),
                trailing: ElevatedButton(
                  onPressed: () =>
                      _approveUser(user['id'], user['email']),
                  child: const Text("Approve"),
                ),
              );
            },
          ),

          // Key Requests Tab
          _keyRequests.isEmpty
              ? const Center(child: Text("No key requests."))
              : ListView.builder(
            itemCount: _keyRequests.length,
            itemBuilder: (context, index) {
              final req = _keyRequests[index];
              return ListTile(
                title: Text(req['email']),
                subtitle: Text("Status: ${req['status']}"),
                trailing: ElevatedButton(
                  onPressed: req['status'] == 'pending'
                      ? () => _reissueKey(req)
                      : null,
                  child: const Text("Issue Key"),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}


