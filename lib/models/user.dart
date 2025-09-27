import 'package:cloud_firestore/cloud_firestore.dart'; // 🔥 Required for Timestamp

class UserModel {
  final int? id;
  final String name;
  final String email;
  final String password;
  final String activationKey;
  final bool isActivated;
  final DateTime expiryDate;

  UserModel({
    this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.activationKey,
    required this.isActivated,
    required this.expiryDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'password': password,
      'activationKey': activationKey,
      'isActivated': isActivated,
      'expiryDate': Timestamp.fromDate(expiryDate),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'],
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      password: map['password'] ?? '',
      activationKey: map['activationKey'] ?? '',
      isActivated: map['isActivated'] == true || map['isActivated'] == 1,
      expiryDate: map['expiryDate'] is Timestamp
          ? (map['expiryDate'] as Timestamp).toDate()
          : DateTime.tryParse(map['expiryDate'] ?? '') ?? DateTime.now(),
    );
  }



}