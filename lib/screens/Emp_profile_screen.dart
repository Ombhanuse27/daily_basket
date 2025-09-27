import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

class EmpProfileScreen extends StatefulWidget {
  const EmpProfileScreen({super.key});

  @override
  State<EmpProfileScreen> createState() => _EmpProfileScreenState();
}

class _EmpProfileScreenState extends State<EmpProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers for editable fields
  final _nameController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmNewPasswordController = TextEditingController();

  // Non-editable display values
  String _displayName = '';
  String _displayEmail = '';
  String _currentPasswordFromDb = '';
  String profilePhotoUrl = '';

  // State management
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _isEditMode = false; // <-- KEY state for switching between View and Edit
  bool isUploadingImage = false;
  String? _adminId;
  String? _employeeId;

  // Password visibility toggles
  bool _isCurrentPasswordVisible = false;
  bool _isNewPasswordVisible = false;

  // Cloudinary configuration
  static const String CLOUD_NAME = "da9xvfoye";
  static const String UPLOAD_PRESET = "ml_default";

  @override
  void initState() {
    super.initState();
    _loadEmployeeData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmNewPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployeeData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _adminId = prefs.getString('admin_id');
      _employeeId = prefs.getString('employee_id');

      if (_adminId == null || _employeeId == null) {
        _showSnackBar('Could not find employee details. Please log in again.', isError: true);
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('admins').doc(_adminId)
          .collection('employees').doc(_employeeId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        _displayName = data['name'] ?? '';
        _displayEmail = data['email'] ?? '';
        _nameController.text = _displayName; // Initialize controller for edit mode
        _currentPasswordFromDb = data['password'] ?? '';
        profilePhotoUrl = data['profilePhoto'] ?? '';
      }
    } catch (e) {
      _showSnackBar('Failed to load profile data: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _uploadImageToCloudinary(File imageFile) async {
    try {
      final url = Uri.parse('https://api.cloudinary.com/v1_1/$CLOUD_NAME/image/upload');
      final request = http.MultipartRequest('POST', url);
      request.fields['upload_preset'] = UPLOAD_PRESET;
      request.fields['folder'] = 'employee_photos';
      final safeEmail = _displayEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      request.fields['public_id'] = 'profile_emp_${safeEmail}_$timestamp';
      final multipartFile = await http.MultipartFile.fromPath('file', imageFile.path);
      request.files.add(multipartFile);
      final response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonResponse = json.decode(responseData);
        return jsonResponse['secure_url'];
      } else {
        final responseData = await response.stream.bytesToString();
        final errorJson = json.decode(responseData);
        throw Exception('Upload failed: ${errorJson['error']['message']}');
      }
    } catch (e) {
      throw Exception('Error uploading to Cloudinary: $e');
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (pickedFile == null) return;

    if (!mounted) return;
    setState(() => isUploadingImage = true);

    try {
      final file = File(pickedFile.path);
      final uniqueUploadedUrl = await _uploadImageToCloudinary(file);
      if (uniqueUploadedUrl != null) {
        await FirebaseFirestore.instance
            .collection('admins').doc(_adminId)
            .collection('employees').doc(_employeeId)
            .update({'profilePhoto': uniqueUploadedUrl});
        if (mounted) setState(() => profilePhotoUrl = uniqueUploadedUrl);
        _showSnackBar("Profile photo updated!", isError: false);
      }
    } catch (e) {
      _showSnackBar("Error updating photo: $e", isError: true);
    } finally {
      if (mounted) setState(() => isUploadingImage = false);
    }
  }

  Future<void> _updateProfile() async {
    FocusScope.of(context).unfocus();
    if (_isEditMode && !_formKey.currentState!.validate()) return;

    setState(() => _isUpdating = true);

    try {
      final Map<String, dynamic> dataToUpdate = {};
      if (_nameController.text.trim() != _displayName) {
        dataToUpdate['name'] = _nameController.text.trim();
      }

      final currentPassword = _currentPasswordController.text;
      final newPassword = _newPasswordController.text;
      if (currentPassword.isNotEmpty || newPassword.isNotEmpty) {
        if (currentPassword != _currentPasswordFromDb) {
          throw Exception('Incorrect current password.');
        }
        if (newPassword.length < 4) {
          throw Exception('New password must be at least 4 characters.');
        }
        dataToUpdate['password'] = newPassword;
      }

      if (dataToUpdate.isEmpty) {
        _showSnackBar('No changes to save.');
        setState(() => _isUpdating = false);
        return;
      }

      await FirebaseFirestore.instance
          .collection('admins').doc(_adminId)
          .collection('employees').doc(_employeeId)
          .update(dataToUpdate);

      _showSnackBar('Profile updated successfully!', isError: false);
      // Update local state after successful save
      if(dataToUpdate.containsKey('name')) {
        _displayName = dataToUpdate['name'];
      }
      if(dataToUpdate.containsKey('password')){
        _currentPasswordFromDb = dataToUpdate['password'];
      }
      _switchToViewMode(reset: false); // Switch to view mode without resetting fields
    } catch (e) {
      _showSnackBar('Failed to update profile: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _switchToEditMode() {
    setState(() => _isEditMode = true);
  }

  void _switchToViewMode({bool reset = true}) {
    setState(() {
      _isEditMode = false;
      if (reset) {
        _nameController.text = _displayName; // Reset to original name if cancelled
      }
      // Clear password fields in both cases
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmNewPasswordController.clear();
    });
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : Colors.teal.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildProfileBody(),
    );
  }

  Widget _buildProfileBody() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildProfileHeader(),
        const SizedBox(height: 24),
        _buildPersonalInfoCard(),
        const SizedBox(height: 16),
        _buildPasswordCard(),
        const SizedBox(height: 32),
        _buildActionButtons(),
      ],
    );
  }

  Widget _buildProfileHeader() {
    return Column(
      children: [
        GestureDetector(
          onTap: isUploadingImage ? null : _pickAndUploadImage,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 55,
                backgroundColor: Colors.teal.shade200,
                child: CircleAvatar(
                  radius: 52,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage:
                  profilePhotoUrl.isNotEmpty ? NetworkImage(profilePhotoUrl) : null,
                  child: isUploadingImage
                      ? const CircularProgressIndicator(color: Colors.white)
                      : profilePhotoUrl.isEmpty
                      ? Icon(Icons.person, size: 60, color: Colors.grey.shade500)
                      : null,
                ),
              ),
              if (!isUploadingImage)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.teal,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                )
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _displayName,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          _displayEmail,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildPersonalInfoCard() {
    return Card(
      elevation: 2,
      shadowColor: Colors.grey.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Personal Information", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: _isEditMode ? _buildEditableInfo() : _buildReadOnlyInfo(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadOnlyInfo() {
    return Column(
      key: const ValueKey('readOnly'),
      children: [
        _buildInfoRow(Icons.person_outline_rounded, "Full Name", _displayName),
        const Divider(height: 24),
        _buildInfoRow(Icons.alternate_email_rounded, "Email Address", _displayEmail),
      ],
    );
  }

  Widget _buildEditableInfo() {
    return Column(
      key: const ValueKey('editable'),
      children: [
        _buildTextFormField(
          controller: _nameController,
          labelText: 'Full Name',
          prefixIcon: Icons.person_outline_rounded,
          validator: (value) => value == null || value.isEmpty ? 'Name cannot be empty' : null,
        ),
        const SizedBox(height: 16),
        _buildTextFormField(
          controller: TextEditingController(text: _displayEmail),
          labelText: 'Email Address',
          prefixIcon: Icons.alternate_email_rounded,
          enabled: false,
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey.shade500),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        )
      ],
    );
  }

  Widget _buildPasswordCard() {
    return Card(
      elevation: 2,
      shadowColor: Colors.grey.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        key: GlobalKey(), // Prevents state issues when rebuilding
        leading: const Icon(Icons.lock_outline_rounded, color: Colors.teal),
        title: const Text("Change Password", style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              children: [
                _buildTextFormField(
                  controller: _currentPasswordController,
                  labelText: 'Current Password',
                  prefixIcon: Icons.lock_clock_outlined,
                  isPassword: true,
                  isCurrentPassword: true,
                ),
                const SizedBox(height: 16),
                _buildTextFormField(
                  controller: _newPasswordController,
                  labelText: 'New Password',
                  prefixIcon: Icons.lock_person_outlined,
                  isPassword: true,
                ),
                const SizedBox(height: 16),
                _buildTextFormField(
                  controller: _confirmNewPasswordController,
                  labelText: 'Confirm New Password',
                  prefixIcon: Icons.lock_person_outlined,
                  isPassword: true,
                  validator: (value) {
                    if (_newPasswordController.text.isNotEmpty && value != _newPasswordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: _isEditMode ? _buildSaveAndCancelButtons() : _buildEditButton(),
    );
  }

  Widget _buildEditButton() {
    return SizedBox(
      key: const ValueKey('editButton'),
      height: 50,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _switchToEditMode,
        icon: const Icon(Icons.edit_outlined),
        label: const Text("EDIT PROFILE"),
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.teal,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildSaveAndCancelButtons() {
    return Row(
      key: const ValueKey('saveCancelButtons'),
      children: [
        Expanded(
          child: SizedBox(
            height: 50,
            child: OutlinedButton(
              onPressed: _isUpdating ? null : () => _switchToViewMode(reset: true),
              child: const Text("CANCEL"),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey.shade400),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isUpdating ? null : _updateProfile,
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.teal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isUpdating
                  ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
              )
                  : const Text("SAVE CHANGES"),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String labelText,
    required IconData prefixIcon,
    String? Function(String?)? validator,
    bool isPassword = false,
    bool isCurrentPassword = false,
    bool enabled = true,
  }) {
    bool isVisible = isCurrentPassword ? _isCurrentPasswordVisible : _isNewPasswordVisible;

    return TextFormField(
      controller: controller,
      obscureText: isPassword && !isVisible,
      validator: validator,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: labelText,
        prefixIcon: Icon(prefixIcon, color: Colors.grey.shade600),
        suffixIcon: isPassword
            ? IconButton(
          icon: Icon(isVisible
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined),
          onPressed: () {
            setState(() {
              if (isCurrentPassword) {
                _isCurrentPasswordVisible = !_isCurrentPasswordVisible;
              } else {
                _isNewPasswordVisible = !_isNewPasswordVisible;
              }
            });
          },
        )
            : null,
        filled: true,
        fillColor: enabled ? Colors.white : Colors.grey.shade200,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.teal.shade600, width: 2),
        ),
      ),
    );
  }
}