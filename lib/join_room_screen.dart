import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'ad_manager.dart';
import 'room_game_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({super.key});
  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final _roomCodeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdManager.bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isBannerAdReady = true;
          });
        },
        onAdFailedToLoad: (ad, err) {
          _isBannerAdReady = false;
          ad.dispose();
        },
      ),
    );
    _bannerAd?.load();
  }

  Future<void> _joinRoom() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
    });

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب عليك تسجيل الدخول أولاً للانضمام لغرفة'),
        ),
      );
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final roomCode = _roomCodeController.text.trim();
    final roomRef = _firestore.collection('rooms').doc(roomCode);

    try {
      final roomDoc = await roomRef.get();

      if (!mounted) return;

      if (!roomDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الغرفة غير موجودة. تحقق من الكود.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      } else {
        List<dynamic> players = roomDoc.data()?['players'] ?? [];
        if (players.any((player) => player['uid'] == user.uid)) {
          // User is already in the room, just navigate
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  RoomGameScreen(roomId: roomCode, currentPlayerId: user.uid),
            ),
          );
        } else if (players.length >= 2) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('هذه الغرفة ممتلئة بالفعل.'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        } else {
          final userDoc = await _firestore
              .collection('users')
              .doc(user.uid)
              .get();
          if (!userDoc.exists) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('لم يتم العثور على بيانات المستخدم'),
              ),
            );
            setState(() {
              _isLoading = false;
            });
            return;
          }

          final joinerData = {
            'uid': user.uid,
            'playerName': userDoc.data()?['playerName'] ?? 'لاعب غير معروف',
            'points': userDoc.data()?['points'] ?? 0,
            'avatarFileName':
                userDoc.data()?['avatarFileName'] ??
                '1.png', // Using correct field name
          };

          await roomRef.update({
            'players': FieldValue.arrayUnion([joinerData]),
          });

          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    RoomGameScreen(roomId: roomCode, currentPlayerId: user.uid),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _roomCodeController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الانضمام لغرفة',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(MdiIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      backgroundColor: const Color(0xFF3E1169),
      body: Column(
        children: [
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF55198B), Color(0xFF3E1169)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CachedNetworkImage(
                          imageUrl: 'https://raw.githubusercontent.com/Ahmadalrawi93/almhnaken-assets/main/images/voice.png',
                          height: 120,
                          color: Colors.white.withOpacity(0.9),
                          colorBlendMode: BlendMode.modulate,
                          placeholder: (context, url) => const SizedBox(width: 120, height: 120, child: Center(child: CircularProgressIndicator())),
                          errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white, size: 60),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'أدخل كود الغرفة',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 30),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: TextFormField(
                            controller: _roomCodeController,
                            textAlign: TextAlign.center,
                            maxLength: 6,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 16,
                            ),
                            decoration: InputDecoration(
                              counterText: "",
                              hintText: '123456',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 36,
                                letterSpacing: 16,
                              ),
                              enabledBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white54),
                              ),
                              focusedBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Color(0xFFFBC02D)),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().length != 6) {
                                return 'الكود يجب أن يتكون من 6 أرقام';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 40),
                        if (_isLoading)
                          const CircularProgressIndicator(color: Colors.white)
                        else
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFBC02D),
                              foregroundColor: const Color(0xFF3E1169),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 80,
                                vertical: 15,
                              ),
                            ),
                            onPressed: _joinRoom,
                            child: const Text(
                              'انضمام',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isBannerAdReady)
            SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
        ],
      ),
    );
  }
}
