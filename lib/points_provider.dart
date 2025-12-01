import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PointsProvider with ChangeNotifier {
  int _points = 0;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription? _pointsSubscription;

  int get points => _points;

  PointsProvider() {
    // Listen for changes in authentication state (login/logout)
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  void _onAuthStateChanged(User? user) {
    // Cancel any existing listener to prevent memory leaks
    _pointsSubscription?.cancel();

    if (user != null) {
      // If user is logged in, create a new real-time listener on their document
      _pointsSubscription = _firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists) {
          // When data changes in Firestore, update the local points value
          _points = snapshot.data()?['points'] ?? 0;
        } else {
          // If the user's document doesn't exist for some reason, default to 0
          _points = 0;
        }
        // Notify all listening widgets to rebuild with the new points value
        notifyListeners();
      }, onError: (error) {
        // Handle potential errors, e.g., permission denied
        print("Error listening to points: $error");
        _points = 0;
        notifyListeners();
      });
    } else {
      // If user logs out, reset points to 0
      _points = 0;
      notifyListeners();
    }
  }

  // When the provider is removed from the widget tree, cancel the subscription
  @override
  void dispose() {
    _pointsSubscription?.cancel();
    super.dispose();
  }

  // The following methods are kept for convenience if you need to manually
  // trigger a points change from somewhere other than the game.
  // The listener will automatically catch the update from Firestore.

  Future<void> addPoints(int amount) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).update({
      'points': FieldValue.increment(amount),
    });
  }

  Future<void> subtractPoints(int amount) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userRef = _firestore.collection('users').doc(user.uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      final currentPoints = snapshot.data()?['points'] ?? 0;
      final newPoints = (currentPoints - amount).clamp(0, double.infinity).toInt();
      transaction.update(userRef, {'points': newPoints});
    });
  }
}