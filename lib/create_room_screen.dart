import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'room_game_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _roomCode;
  String? _roomId;
  bool _isLoading = false;

  Future<void> _createRoom() async {
    setState(() {
      _isLoading = true;
    });

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب عليك تسجيل الدخول أولاً لإنشاء غرفة'),
        ),
      );
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم العثور على بيانات المستخدم')),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final creatorData = {
        'uid': user.uid,
        'playerName': userDoc.data()?['playerName'] ?? 'لاعب غير معروف',
        'points': userDoc.data()?['points'] ?? 0,
        'avatarFileName':
            userDoc.data()?['avatarFileName'] ??
            '1.png', // Using correct field name
      };

      String newRoomCode;
      final roomsCollection = _firestore.collection('rooms');
      do {
        newRoomCode = (100000 + Random().nextInt(900000)).toString();
      } while ((await roomsCollection.doc(newRoomCode).get()).exists);

      await roomsCollection.doc(newRoomCode).set({
        'players': [creatorData],
        'createdAt': FieldValue.serverTimestamp(),
        'roomCode': newRoomCode,
        'gameState': 'waiting',
      });

      setState(() {
        _roomCode = newRoomCode;
        _roomId = newRoomCode; // حفظ room ID لاستخدامه عند الحذف
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل انشاء الغرفة: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _copyToClipboard() {
    if (_roomCode != null) {
      Clipboard.setData(ClipboardData(text: _roomCode!));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('!تم نسخ كود الغرفة')));
    }
  }

  void _joinGame() {
    final user = _auth.currentUser;
    if (_roomCode != null && user != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              RoomGameScreen(roomId: _roomCode!, currentPlayerId: user.uid),
        ),
      );
    }
  }

  // حذف الغرفة عند الرجوع
  Future<void> _deleteRoomAndGoBack() async {
    if (_roomId != null) {
      try {
        // التحقق من عدد اللاعبين في الغرفة
        final roomDoc = await _firestore.collection('rooms').doc(_roomId).get();
        if (roomDoc.exists) {
          final players = roomDoc.data()?['players'] as List<dynamic>?;
          // حذف الغرفة فقط إذا كان المنشئ هو اللاعب الوحيد
          if (players != null && players.length == 1) {
            await _firestore.collection('rooms').doc(_roomId).delete();
            print('🗑️ تم حذف الغرفة: $_roomId');
          }
        }
      } catch (e) {
        print('❌ خطأ في حذف الغرفة: $e');
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    // حذف الغرفة إذا لم ينضم أحد
    if (_roomId != null) {
      _firestore.collection('rooms').doc(_roomId).get().then((doc) {
        if (doc.exists) {
          final players = doc.data()?['players'] as List<dynamic>?;
          if (players != null && players.length == 1) {
            _firestore.collection('rooms').doc(_roomId).delete();
            print('🗑️ تم حذف الغرفة تلقائياً عند الخروج: $_roomId');
          }
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _deleteRoomAndGoBack();
        return false; // نمنع الرجوع الافتراضي لأننا نتعامل معه يدوياً
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'إنشاء غرفة خاصة',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(MdiIcons.arrowLeft, color: Colors.white),
            onPressed: _deleteRoomAndGoBack,
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
      backgroundColor: const Color(0xFF3E1169),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF55198B), Color(0xFF3E1169)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : _roomCode == null
                ? _buildCreateButton()
                : _buildRoomCodeDisplay(),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildCreateButton() {
    return Column(
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
          'تحدى أصدقائك',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'اضغط على الزر لإنشاء غرفة وبدء اللعب',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.white70),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFBC02D),
            foregroundColor: const Color(0xFF3E1169),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 15),
          ),
          onPressed: _createRoom,
          child: const Text(
            'أنشئ الغرفة',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildRoomCodeDisplay() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'تم إنشاء الغرفة بنجاح!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            'شارك هذا الكود مع صديقك:',
            style: TextStyle(fontSize: 16, color: Colors.white70),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 25),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _roomCode ?? '',
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(width: 15),
                IconButton(
                  icon: const Icon(MdiIcons.contentCopy, color: Colors.white),
                  onPressed: _copyToClipboard,
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 15),
            ),
            onPressed: _joinGame,
            child: const Text(
              'دخول',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
