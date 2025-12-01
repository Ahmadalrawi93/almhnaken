// File: match_found_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'game_screen.dart';
import 'ad_manager.dart';

class MatchFoundScreen extends StatefulWidget {
  final String roomId;
  const MatchFoundScreen({super.key, required this.roomId});

  @override
  State<MatchFoundScreen> createState() => _MatchFoundScreenState();
}

class _MatchFoundScreenState extends State<MatchFoundScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _currentUser = FirebaseAuth.instance.currentUser;
  final AdManager _adManager = AdManager.instance;

  bool _hasNavigated = false;
  late StreamSubscription _roomSubscription;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();
    _startListeningToRoom();
    _adManager.loadNativeAd(onAdLoaded: () {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _startListeningToRoom() {
    _roomSubscription = _firestore
        .collection('rooms')
        .doc(widget.roomId)
        .snapshots()
        .listen((snapshot) async {
          final roomData = snapshot.data();
          final players = List<String>.from(roomData?['players'] ?? []);
          final String status = roomData?['status'] ?? 'waiting';

          if (status == 'matched' &&
              players.length == 2 &&
              !_hasNavigated &&
              mounted) {
            _navigationTimer?.cancel();
            _navigationTimer = Timer(const Duration(seconds: 3), () {
              _navigateToGameScreen();
            });
            setState(() {});
          }
        });
  }

  void _navigateToGameScreen() {
    if (mounted && !_hasNavigated) {
      _hasNavigated = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => GameScreen(roomId: widget.roomId),
        ),
      );
    }
  }

  Future<void> _leaveAndCleanUp() async {
    if (_currentUser != null) {
      await _firestore.collection('rooms').doc(widget.roomId).delete();
    }
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _roomSubscription.cancel();
    _navigationTimer?.cancel();
    _adManager.disposeNativeAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _leaveAndCleanUp();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF55198B),
        appBar: AppBar(
          title: const Text('أونلاين', style: TextStyle(color: Colors.white)),
          centerTitle: true,
          backgroundColor: const Color(0xFF55198B),
          elevation: 0,
          leading: IconButton(
            icon: Icon(MdiIcons.arrowLeft, color: Colors.white),
            onPressed: _leaveAndCleanUp,
          ),
        ),
        body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('rooms').doc(widget.roomId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          final roomData = snapshot.data!.data() as Map<String, dynamic>?;
          if (roomData == null) {
            return const Center(
              child: Text(
                'خطأ: بيانات الغرفة غير متوفرة',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          final players = List<String>.from(roomData['players'] ?? []);
          final String status = roomData['status'] ?? 'waiting';

          if (status == 'matched' && players.length == 2) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'تم العثور على خصم!',
                    style: TextStyle(
                      fontSize: 24,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildPlayerCard(players[0]),
                      const SizedBox(width: 20),
                      const Text(
                        'VS',
                        style: TextStyle(
                          fontSize: 40,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 20),
                      _buildPlayerCard(players[1]),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'جاري بدء اللعبة...',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ],
              ),
            );
          } else {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 20),
                  const Text(
                    'جاري البحث عن خصم...',
                    style: TextStyle(fontSize: 20, color: Colors.white),
                  ),
                  const Spacer(),
                  const Spacer(),
                  // Ad space
                  if (_adManager.getNativeAdWidget() != null)
                    _adManager.getNativeAdWidget()!,
                  const Spacer(),
                  const Spacer(),
                ],
              ),
            );
          }
        },
      ),
    )
    );

  }

  Widget _buildPlayerCard(String userId) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator(color: Colors.white);
        }
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return const Text('خطأ', style: TextStyle(color: Colors.red));
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final username = userData['playerName'] ?? 'لاعب';
        final points = userData['points'] ?? 0;
        final avatar = userData['avatarFileName'] ?? '1.png';
        const double avatarRadius = 60;

        return Column(
          children: [
            CircleAvatar(
              radius: avatarRadius,
              backgroundColor: Colors.white24,
              child: ClipOval(
                child: Image.asset(
                  'iconUser/$avatar',
                  fit: BoxFit.contain,
                  width: avatarRadius * 2,
                  height: avatarRadius * 2,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.person,
                    size: avatarRadius,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              username,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'النقاط: $points',
              style: const TextStyle(color: Colors.orange, fontSize: 16),
            ),
          ],
        );
      },
    );
  }
}
