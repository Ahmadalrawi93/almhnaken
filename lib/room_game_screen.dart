import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'room_playGame.dart'; // Changed to the new game screen

// Question model defined directly in the file
class Question {
  final String text;
  final String? image;
  final List<dynamic> answers;

  Question({required this.text, this.image, required this.answers});

  factory Question.fromMap(Map<String, dynamic> map) {
    return Question(
      text: map['text'] ?? '',
      image: map['image'],
      answers: map['answers'] ?? [],
    );
  }
}

// Player model remains the same
class Player {
  final String uid;
  final String name;
  final int points;
  final String avatarFileName;

  Player({
    required this.uid,
    required this.name,
    required this.points,
    required this.avatarFileName,
  });

  factory Player.fromMap(Map<String, dynamic> data) {
    return Player(
      uid: data['uid'] ?? '',
      name: data['playerName'] ?? 'لاعب غير معروف',
      points: data['points'] ?? 0,
      avatarFileName: data['avatarFileName'] ?? '1.png',
    );
  }
}

class RoomGameScreen extends StatefulWidget {
  final String roomId;
  final String currentPlayerId;

  const RoomGameScreen({
    super.key,
    required this.roomId,
    required this.currentPlayerId,
  });

  @override
  State<RoomGameScreen> createState() => _RoomGameScreenState();
}

class _RoomGameScreenState extends State<RoomGameScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late DocumentReference _roomRef;
  List<Player> _players = [];
  bool _isCreator = false;
  bool _isStartingGame = false;

  @override
  void initState() {
    super.initState();
    _roomRef = _firestore.collection('rooms').doc(widget.roomId);
    _listenToRoomUpdates();
  }

  void _listenToRoomUpdates() {
    _roomRef.snapshots().listen((snapshot) {
      if (!mounted) return;
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data() as Map<String, dynamic>;
        final playerList = (data['players'] as List<dynamic>?) ?? [];

        setState(() {
          _players = playerList.map((playerData) => Player.fromMap(playerData)).toList();
          if (_players.isNotEmpty) {
            _isCreator = _players.first.uid == widget.currentPlayerId;
          }
        });

        final String? gameState = data['gameState'] as String?;
        if (gameState == 'player_career_started') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => RoomPlayGameScreen(roomId: widget.roomId), // Navigate to the new screen
                ),
              );
            }
          });
        }
      } else {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الغرفة')),
        );
      }
    });
  }

  Future<void> _startGame() async {
    setState(() { _isStartingGame = true; });

    try {
      final questionsSnapshot = await _firestore.collection('questions').get();
      final allQuestions = questionsSnapshot.docs
          .map((doc) => Question.fromMap(doc.data()))
          .toList();

      final random = Random();
      final List<Map<String, dynamic>> selectedQuestions = [];
      final List<Question> tempQuestions = List.from(allQuestions);

      for (int i = 0; i < 5 && tempQuestions.isNotEmpty; i++) {
        final index = random.nextInt(tempQuestions.length);
        final question = tempQuestions.removeAt(index);
        selectedQuestions.add({
          'text': question.text,
          'image': question.image,
          'answers': question.answers,
        });
      }
      selectedQuestions.shuffle();
      for (int i = 0; i < selectedQuestions.length; i++) {
        selectedQuestions[i]['order'] = i;
      }

      await _roomRef.update({
        'questionList': selectedQuestions,
        'currentQuestionIndex': 0,
        'scores': { for (var p in _players) p.uid : 0 },
        'gameState': 'player_career_started',
      });

    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في بدء اللعبة: ${e.toString()}')),
        );
        setState(() { _isStartingGame = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('غرفة اللعب', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(MdiIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: const [],
      ),
      backgroundColor: const Color(0xFF3E1169),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF55198B), Color(0xFF3E1169)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'كود الغرفة: ${widget.roomId}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildPlayerSlot(playerIndex: 0),
                const Text('VS', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                _buildPlayerSlot(playerIndex: 1),
              ],
            ),
            const SizedBox(height: 60),
            _buildStatusSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerSlot({required int playerIndex}) {
    final player = _players.length > playerIndex ? _players[playerIndex] : null;

    if (player == null) {
      return const Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.white24,
            child: CircularProgressIndicator(color: Colors.white),
          ),
          SizedBox(height: 10),
          Text(
            'في انتظار لاعب...',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      );
    }

    return Column(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundColor: Colors.white24,
          child: ClipOval(
            child: Image.asset(
              'iconUser/${player.avatarFileName}',
              fit: BoxFit.contain,
              width: 100,
              height: 100,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.person, size: 60, color: Colors.white70);
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          player.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(MdiIcons.star, color: Colors.amber, size: 16),
            const SizedBox(width: 4),
            Text(
              player.points.toString(),
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusSection() {
    if (_players.length < 2) {
      return const Text(
        'في انتظار انضمام صديقك...',
        style: TextStyle(color: Color(0xFFFBC02D), fontSize: 18),
      );
    }

    if (_isCreator) {
      if (_isStartingGame) {
        return const CircularProgressIndicator(color: Colors.white);
      }
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 15),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        onPressed: _startGame,
        child: const Text('ابدأ اللعبة'),
      );
    } else {
      return const Text(
        'في انتظار منشئ الغرفة لبدء اللعبة...',
        style: TextStyle(color: Color(0xFFFBC02D), fontSize: 18),
      );
    }
  }
}