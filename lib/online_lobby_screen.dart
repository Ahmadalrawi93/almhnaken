// File: online_lobby_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'match_found_screen.dart';
import 'ad_manager.dart'; // Import AdManager
import 'package:cached_network_image/cached_network_image.dart';

class OnlineLobbyScreen extends StatefulWidget {
  const OnlineLobbyScreen({super.key});

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _currentUser = FirebaseAuth.instance.currentUser;

  bool _isSearching = false;
  String? _currentRoomId; // لتخزين معرف الغرفة

  Widget? _bannerAdWidget;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    AdManager.instance.loadBannerAd(
      onAdLoaded: () {
        if (mounted) {
          setState(() {
            _bannerAdWidget = AdManager.instance.getBannerAdWidget();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    AdManager.instance.disposeBannerAd();
    super.dispose();
  }

  Future<void> _findOrCreateRoom() async {
    // التحقق من أن المستخدم مسجل دخول
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب أن تسجل الدخول لتتمكن من اللعب أونلاين'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final roomsSnapshot = await _firestore
          .collection('rooms')
          .where('isPublic', isEqualTo: true)
          .where('status', isEqualTo: 'waiting')
          .limit(1)
          .get();

      if (roomsSnapshot.docs.isNotEmpty) {
        final roomDoc = roomsSnapshot.docs.first;
        _currentRoomId = roomDoc.id;
        await _firestore.collection('rooms').doc(_currentRoomId).update({
          'players': FieldValue.arrayUnion([_currentUser.uid]),
          'status': 'matched',
        });
      } else {
        final newRoomRef = await _firestore.collection('rooms').add({
          'players': [_currentUser.uid],
          'isPublic': true,
          'status': 'waiting',
          'createdAt': FieldValue.serverTimestamp(),
          'scores': {},
          'errors': {},
          'currentQuestionIndex': 0,
        });
        _currentRoomId = newRoomRef.id;
      }
      _navigateToMatchFound(_currentRoomId!);
    } catch (e) {
      print('Error finding or creating a room: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('خطأ في الاتصال. حاول مرة أخرى.')),
        );
      }
    }
  }

  Future<void> _leaveAndCleanUp() async {
    if (_currentRoomId != null) {
      // حذف الغرفة من Firestore
      await _firestore.collection('rooms').doc(_currentRoomId).delete();
      _currentRoomId = null;
    }
    Navigator.of(context).pop();
  }

  void _navigateToMatchFound(String roomId) {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => MatchFoundScreen(roomId: roomId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF55198B),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    top: 10,
                    left: 10,
                    child: IconButton(
                      icon: Icon(MdiIcons.arrowLeft, color: Colors.white),
                      onPressed: _leaveAndCleanUp,
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Spacer(),
                        CachedNetworkImage(
                          imageUrl: 'https://raw.githubusercontent.com/Ahmadalrawi93/almhnaken-assets/main/images/voice.png',
                          width: 200,
                          height: 200,
                          placeholder: (context, url) => const SizedBox(width: 200, height: 200, child: Center(child: CircularProgressIndicator())),
                          errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white, size: 100),
                        ),
                        const SizedBox(height: 40),
                        if (_isSearching)
                          const Column(
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 20),
                              Text(
                                'جاري البحث عن خصم...',
                                style: TextStyle(
                                  fontSize: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          )
                        else
                          ElevatedButton(
                            onPressed: _findOrCreateRoom,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF3752B),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 40,
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: const Text(
                              'ابحث عن خصم',
                              style: TextStyle(
                                fontSize: 20,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Ad container section
          if (_bannerAdWidget != null)
            Container(
              alignment: Alignment.center,
              child: _bannerAdWidget,
              width: AdSize.banner.width.toDouble(),
              height: AdSize.banner.height.toDouble(),
            )
          else
            SizedBox(height: AdSize.banner.height.toDouble()),
        ],
      ),
    );
  }
}
