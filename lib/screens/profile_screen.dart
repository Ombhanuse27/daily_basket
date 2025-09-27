import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_basket/services/email_service.dart';
import 'package:daily_basket/screens/login_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

// A custom clipper for creating the curved header effect.
class HeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.lineTo(0, size.height - 50);
    path.quadraticBezierTo(
        size.width / 2, size.height, size.width, size.height - 50);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _shopNameController = TextEditingController();
  String userEmail = '';
  String profilePhotoUrl = '';
  bool isLoading = true;
  bool isUploadingImage = false;

  // Cloudinary configuration
  static const String CLOUD_NAME = "da9xvfoye";
  static const String UPLOAD_PRESET = "ml_default";

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _shopNameController.dispose();
    super.dispose();
  }

  // --- DATA & LOGIC METHODS (Unchanged) ---
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  Future<void> _loadProfileData() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    userEmail = prefs.getString('user_email') ?? '';
    if (userEmail.isEmpty) {
      if (mounted) setState(() => isLoading = false);
      return;
    }
    final adminSnapshot = await FirebaseFirestore.instance
        .collection('admins')
        .where('email', isEqualTo: userEmail)
        .limit(1)
        .get();
    if (adminSnapshot.docs.isEmpty) {
      if (mounted) setState(() => isLoading = false);
      return;
    }
    final adminDoc = adminSnapshot.docs.first;
    final data = adminDoc.data();
    if (mounted) {
      setState(() {
        _nameController.text = data['name'] ?? '';
        _addressController.text = data['address'] ?? '';
        _shopNameController.text = data['shopName'] ?? '';
        profilePhotoUrl = data['profilePhoto'] ?? '';
        isLoading = false;
      });
    }
  }

  Future<void> _updateProfile() async {
    final adminSnapshot = await FirebaseFirestore.instance
        .collection('admins')
        .where('email', isEqualTo: userEmail)
        .limit(1)
        .get();
    if (adminSnapshot.docs.isEmpty) return;
    final adminId = adminSnapshot.docs.first.id;
    await FirebaseFirestore.instance.collection('admins').doc(adminId).set({
      'name': _nameController.text.trim(),
      'address': _addressController.text.trim(),
      'shopName': _shopNameController.text.trim(),
    }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("✅ Profile updated successfully"),
            backgroundColor: Colors.green),
      );
    }
  }

  Future<String?> _uploadImageToCloudinary(File imageFile) async {
    try {
      final url =
      Uri.parse('https://api.cloudinary.com/v1_1/$CLOUD_NAME/image/upload');
      final request = http.MultipartRequest('POST', url);
      request.fields['upload_preset'] = UPLOAD_PRESET;
      request.fields['folder'] = 'profile_photos';
      final safeEmail = userEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      request.fields['public_id'] = 'profile_${safeEmail}_$timestamp';
      final multipartFile =
      await http.MultipartFile.fromPath('file', imageFile.path);
      request.files.add(multipartFile);
      final response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonResponse = json.decode(responseData);
        return jsonResponse['secure_url'];
      } else {
        final responseData = await response.stream.bytesToString();
        final errorJson = json.decode(responseData);
        final errorMessage = errorJson['error']['message'];
        throw Exception('Upload failed: $errorMessage');
      }
    } catch (e) {
      throw Exception('Error uploading to Cloudinary: $e');
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (pickedFile == null) return;
    if (!mounted) return;
    setState(() => isUploadingImage = true);
    try {
      final file = File(pickedFile.path);
      final uniqueUploadedUrl = await _uploadImageToCloudinary(file);
      if (uniqueUploadedUrl != null) {
        final adminSnapshot = await FirebaseFirestore.instance
            .collection('admins')
            .where('email', isEqualTo: userEmail)
            .limit(1)
            .get();
        if (adminSnapshot.docs.isEmpty) {
          throw Exception("Admin user not found in database.");
        }
        final adminId = adminSnapshot.docs.first.id;
        await FirebaseFirestore.instance
            .collection('admins')
            .doc(adminId)
            .update({'profilePhoto': uniqueUploadedUrl});
        if (mounted) {
          setState(() {
            profilePhotoUrl = uniqueUploadedUrl;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("📷 Profile photo updated successfully!"),
                backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("❌ Error updating photo: $e"),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isUploadingImage = false);
      }
    }
  }

  Future<void> _deleteEmployee(String docId) async {
    final adminSnapshot = await FirebaseFirestore.instance
        .collection('admins')
        .where('email', isEqualTo: userEmail)
        .get();
    if (adminSnapshot.docs.isEmpty) return;
    final adminId = adminSnapshot.docs.first.id;
    await FirebaseFirestore.instance
        .collection('admins')
        .doc(adminId)
        .collection('employees')
        .doc(docId)
        .delete();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("🗑️ Employee successfully deleted"),
          backgroundColor: Colors.redAccent),
    );
  }

  // --- DIALOGS (Improved UI) ---
  void _showEditProfileDialog() {
    final tempNameController =
    TextEditingController(text: _nameController.text);
    final tempShopNameController =
    TextEditingController(text: _shopNameController.text);
    final tempAddressController =
    TextEditingController(text: _addressController.text);
    showDialog(
        context: context,
        builder: (BuildContext context) => Dialog(
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Edit Profile Details",
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
                      _buildStyledInput(
                          "Full Name", tempNameController, Icons.person_outline),
                      _buildStyledInput("Shop Name", tempShopNameController,
                          Icons.storefront_outlined),
                      _buildStyledInput(
                          "Address", tempAddressController, Icons.home_outlined,
                          maxLines: 3),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                              child: OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text("Cancel"))),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                _nameController.text = tempNameController.text;
                                _shopNameController.text =
                                    tempShopNameController.text;
                                _addressController.text =
                                    tempAddressController.text;
                                await _updateProfile();
                                if (mounted) Navigator.pop(context);
                              },
                              icon: const Icon(Icons.save),
                              label: const Text("Save"),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ))));
  }

  void _showAddEmployeeDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final mobileController = TextEditingController();
    final addressController = TextEditingController();
    final positionController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Add New Employee"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStyledInput(
                  "Name", nameController, Icons.person_outline),
              _buildStyledInput(
                  "Email", emailController, Icons.email_outlined),
              _buildStyledInput(
                  "Mobile Number", mobileController, Icons.phone_android_outlined,
                  keyboard: TextInputType.phone),
              _buildStyledInput(
                  "Address", addressController, Icons.home_outlined),
              _buildStyledInput(
                  "Position", positionController, Icons.work_outline),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              final mobile = mobileController.text.trim();
              if (email.isEmpty || !email.contains('@') || mobile.length < 4) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("❌ Invalid email or mobile number")));
                return;
              }
              final adminSnapshot = await FirebaseFirestore.instance
                  .collection('admins')
                  .where('email', isEqualTo: userEmail)
                  .get();
              if (adminSnapshot.docs.isEmpty) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("❌ Admin not found")));
                return;
              }
              final adminData = adminSnapshot.docs.first.data();
              final adminId = adminSnapshot.docs.first.id;
              final Timestamp adminExpiryTimestamp = adminData['expiryDate'];
              final DateTime expiryDate = adminExpiryTimestamp.toDate();
              final password =
                  '${email.substring(0, 4)}@${mobile.substring(mobile.length - 4)}';
              await FirebaseFirestore.instance
                  .collection('admins')
                  .doc(adminId)
                  .collection('employees')
                  .add({
                'name': nameController.text.trim(),
                'email': email,
                'mobile': mobile,
                'address': addressController.text.trim(),
                'position': positionController.text.trim(),
                'createdAt': Timestamp.now(),
                'password': password,
                'expiryDate': Timestamp.fromDate(expiryDate),
                'isActive': true,
              });
              await EmailService.sendEmployeeActivationEmail(
                  toEmail: email,
                  employeeName: nameController.text.trim(),
                  password: password,
                  expiryDate: expiryDate);
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("✅ Employee added and email sent")));
            },
            child: const Text("Add Employee"),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(String docId, String employeeName) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("⚠️ Confirm Deletion"),
        content: Text("Are you sure you want to delete $employeeName?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () {
                _deleteEmployee(docId);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child:
              const Text("Delete", style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  // --- UI WIDGET BUILDERS (New & Improved) ---
  Widget _buildStyledInput(
      String label, TextEditingController controller, IconData icon,
      {TextInputType keyboard = TextInputType.text, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey[100],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return ClipPath(
      clipper: HeaderClipper(),
      child: Container(
        height: 320,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green.shade400, Colors.green.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: isUploadingImage ? null : _pickAndUploadImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.white,
                      child: isUploadingImage
                          ? const CircularProgressIndicator()
                          : CircleAvatar(
                        radius: 56,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: profilePhotoUrl.isNotEmpty
                            ? NetworkImage(profilePhotoUrl)
                            : null,
                        child: profilePhotoUrl.isEmpty
                            ? Icon(Icons.person,
                            size: 60, color: Colors.grey.shade400)
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).primaryColor,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(6.0),
                          child:
                          Icon(Icons.camera_alt, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _nameController.text.isNotEmpty
                    ? _nameController.text
                    : "Admin User",
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(userEmail,
                  style: const TextStyle(fontSize: 16, color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(
      {required String title,
        required String content,
        required IconData icon,
        VoidCallback? onEdit}) {
    return Card(
      elevation: 2,
      shadowColor: Colors.grey.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, color: Colors.green, size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.grey, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(content.isNotEmpty ? content : 'Not set',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: content.isEmpty ? Colors.grey : null)),
                ],
              ),
            ),
            if (onEdit != null)
              IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined))
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeList() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('admins')
          .where('email', isEqualTo: userEmail)
          .limit(1)
          .get(),
      builder: (context, adminSnapshot) {
        if (adminSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!adminSnapshot.hasData || adminSnapshot.data!.docs.isEmpty) {
          return const Center(child: Text("Admin account not found."));
        }
        final adminId = adminSnapshot.data!.docs.first.id;
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('admins')
              .doc(adminId)
              .collection('employees')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.people_outline,
                          size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      const Text("No employees added yet.",
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                ),
              );
            }
            final docs = snapshot.data!.docs;
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final expiry = (data['expiryDate'] as Timestamp?)?.toDate();
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  shadowColor: Colors.grey.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.shade100,
                      child: Text((data['name'] ?? 'U')[0].toUpperCase(),
                          style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold)),
                    ),
                    title: Text(data['name'] ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        "${data['position'] ?? 'N/A'} • Expires: ${expiry?.toLocal().toString().split(' ').first ?? 'N/A'}"),
                    trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.redAccent),
                        onPressed: () => _showDeleteConfirmation(
                            doc.id, data['name'] ?? 'Employee')),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        backgroundColor: Colors.green.shade600,
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.logout),
              tooltip: "Logout",
              onPressed: _logout),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : userEmail.isEmpty
          ? const Center(child: Text("No user data found."))
          : SingleChildScrollView(
        child: Column(
          children: [
            _buildProfileHeader(),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoCard(
                      title: "Shop Name",
                      content: _shopNameController.text,
                      icon: Icons.storefront_outlined,
                      onEdit: _showEditProfileDialog),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                      title: "Address",
                      content: _addressController.text,
                      icon: Icons.location_on_outlined,
                      onEdit: _showEditProfileDialog),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Team Members",
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                              fontWeight: FontWeight.bold)),
                      FilledButton.icon(
                        onPressed: _showAddEmployeeDialog,
                        icon: const Icon(Icons.add),
                        label: const Text("Add"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildEmployeeList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}