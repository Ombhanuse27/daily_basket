import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseService {
  static final _db = FirebaseFirestore.instance;


  /// 🔍 Fetch pending users (not activated yet)
  static Future<List<Map<String, dynamic>>> fetchPendingUsers() async {
    final snapshot = await _db
        .collection('admins')
        .where('isActivated', isEqualTo: false)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  /// ✅ Approve a pending user and assign an activation key
  static Future<void> approveUser(
      String docId, String activationKey, DateTime expiryDate) async {
    final userRef = _db.collection('admins').doc(docId);

    await userRef.update({
      'activationKey': activationKey,
      'isActivated': true,
      'expiryDate': expiryDate,
    });
  }

  /// 📥 Fetch key reissue requests made by expired users
  static Future<List<Map<String, dynamic>>> fetchKeyRequests() async {
    final query = await _db
        .collection('key_requests')
        .orderBy('requestedAt', descending: true)
        .get();

    return query.docs.map((doc) {
      return {
        ...doc.data(),
        'id': doc.id,
      };
    }).toList();
  }




}