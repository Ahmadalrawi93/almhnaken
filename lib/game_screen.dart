// File: game_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:string_similarity/string_similarity.dart';
import 'online_bank.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'sound_service.dart';

// ADDED class definition
class Question {
  final String text;
  final String image;
  final List<String> answers;

  Question({required this.text, required this.image, required this.answers});

  factory Question.fromMap(Map<String, dynamic> map) {
    return Question(
      text: map['text'] ?? '',
      image: map['image'] ?? '',
      answers: List<String>.from(map['answers'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {'text': text, 'image': image, 'answers': answers};
  }
}

class GameScreen extends StatefulWidget {
  final String roomId;
  const GameScreen({super.key, required this.roomId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final _answerController = TextEditingController();

  StreamSubscription? _roomSubscription;
  Timer? _gameTimer;
  final ValueNotifier<int> _timerValue = ValueNotifier<int>(0);

  String? _correctAnswer;
  Question? _currentQuestion;
  bool _isTransitioning = false;

  Map<String, int> _scores = {};

  @override
  void initState() {
    super.initState();
    _loadQuestionsForRoom();
    _listenToRoom();
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    _answerController.dispose();
    _gameTimer?.cancel();
    _timerValue.dispose();
    super.dispose();
  }

  void _startGameTimer(int seconds) {
    _gameTimer?.cancel();
    _timerValue.value = seconds;
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_timerValue.value > 0) {
        _timerValue.value--;
      } else {
        _gameTimer?.cancel();
        _nextQuestion();
      }
    });
  }

  void _listenToRoom() {
    _roomSubscription = _firestore
        .collection('rooms')
        .doc(widget.roomId)
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists || snapshot.data() == null || !mounted) return;

          final roomData = snapshot.data()!;
          final String? correctAnswer = roomData['correctAnswer'] as String?;
          final int currentQuestionIndex =
              roomData['currentQuestionIndex'] as int? ?? 0;
          final List<dynamic>? questionList =
              roomData['questionList'] as List<dynamic>?;

          if (questionList != null) {
            questionList.sort(
              (a, b) => (a['order'] as int).compareTo(b['order'] as int),
            );
          }

          if (mounted) {
            setState(() {
              _scores = Map<String, int>.from(roomData['scores'] ?? {});
            });
          }

          if (currentQuestionIndex >= 5) {
            _gameTimer?.cancel();
            _endGameLogic();
            _startTransition();
            return;
          }

          if (mounted) {
            setState(() {
              _correctAnswer = correctAnswer;
              if (questionList != null &&
                  currentQuestionIndex < questionList.length) {
                final questionData = questionList[currentQuestionIndex];
                _currentQuestion = Question.fromMap(questionData);
              } else {
                _currentQuestion = null;
              }
            });
          }

          if (_correctAnswer == null) {
            if (_gameTimer == null || !_gameTimer!.isActive) {
              _startGameTimer(45);
            }
          } else {
            _gameTimer?.cancel();
            Timer(const Duration(seconds: 3), () {
              if (mounted) {
                _nextQuestion();
              }
            });
          }
        });
  }

  void _startTransition() {
    if (!mounted || _isTransitioning) return;

    setState(() {
      _isTransitioning = true;
    });

    final roomRef = _firestore.collection('rooms').doc(widget.roomId);
    roomRef.get().then((doc) {
      if (doc.exists) {
        final scores = Map<String, int>.from(doc.data()?['scores'] ?? {});
        roomRef.update({
          'totalBankedScores': scores,
          'isBankRoundOver': false,
          'mainTimeRemaining': 120,
          'playerTurnIndex': 0,
        });
      }
    });

    Timer(const Duration(seconds: 5), () {
      if (mounted) {
        // تشغيل صوت انتقال قبل الانتقال إلى المرحلة التالية
        SoundService().playTransitionSound();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => OnlineBankScreen(roomId: widget.roomId),
          ),
        );
      }
    });
  }

  Future<void> _endGameLogic() async {}

  Future<void> _submitAnswer() async {
    if (_currentUser == null ||
        _correctAnswer != null ||
        _currentQuestion == null)
      return;

    final userAnswer = _answerController.text.trim();
    if (userAnswer.isEmpty) return;

    final normalizedUserAnswer = userAnswer.toLowerCase();
    final bool isCorrect = _currentQuestion!.answers.any(
      (answer) =>
          normalizedUserAnswer.similarityTo(answer.toLowerCase()) >= 0.8,
    );

    if (isCorrect) {
      _gameTimer?.cancel();
      _answerController.clear();
      final roomRef = _firestore.collection('rooms').doc(widget.roomId);
      await roomRef.update({
        'scores.${_currentUser.uid}': FieldValue.increment(1),
        'correctAnswer': _currentQuestion?.answers.first,
      });
    }
  }

  Future<void> _nextQuestion() async {
    final roomRef = _firestore.collection('rooms').doc(widget.roomId);
    final roomDoc = await roomRef.get();
    if (!roomDoc.exists) return;

    final currentQuestionIndex =
        (roomDoc.data()?['currentQuestionIndex'] as int? ?? 0);

    final nextIndex = currentQuestionIndex + 1;

    await roomRef.update({
      'correctAnswer': null,
      'currentQuestionIndex': nextIndex,
    });
  }

  Future<void> _loadQuestionsForRoom() async {
    final roomRef = _firestore.collection('rooms').doc(widget.roomId);
    final roomDoc = await roomRef.get();
    final roomData = roomDoc.data();

    if (roomData != null &&
        (roomData['questionList'] == null ||
            roomData['questionList'].isEmpty)) {
      final questionsSnapshot = await _firestore
          .collection('footballQuestions')
          .get();
      final allQuestions = questionsSnapshot.docs
          .map((doc) => Question.fromMap(doc.data()))
          .toList();

      allQuestions.shuffle();
      final selectedQuestions = allQuestions.take(5).toList();

      final List<Map<String, dynamic>> questionListForFirestore = [];
      for (int i = 0; i < selectedQuestions.length; i++) {
        final questionMap = selectedQuestions[i].toMap();
        questionMap['order'] = i;
        questionListForFirestore.add(questionMap);
      }

      await roomRef.update({
        'questionList': questionListForFirestore,
        'currentQuestionIndex': 0,
      });
    }
  }

  Widget _buildPlayerPanel(String userId, int score) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox();
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final username = userData['playerName'] ?? 'لاعب';
        final avatarFileName = userData['avatarFileName'] as String?;

        return Column(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.white24,
              child: ClipOval(
                child: avatarFileName != null && avatarFileName.isNotEmpty
                    ? Image.asset(
                        'iconUser/$avatarFileName',
                        fit: BoxFit.contain,
                        width: 80,
                        height: 80,
                        errorBuilder: (c, o, s) => const Icon(
                          Icons.person,
                          size: 40,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.person, size: 40, color: Colors.white),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              username,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white30),
              ),
              child: Text(
                'النقاط: $score',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF55198B),
        body: Center(
          child: Text(
            'خطأ في تسجيل الدخول. يرجى إعادة التشغيل.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
    final currentPlayerId = _currentUser.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF55198B),
      appBar: AppBar(
        title: const Text('مسيرة لاعب', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('rooms').doc(widget.roomId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
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
          if (players.length < 2) {
            return const Center(
              child: Text(
                'جاري انتظار الخصم...',
                style: TextStyle(fontSize: 20, color: Colors.white),
              ),
            );
          }

          final scores = Map<String, int>.from(roomData['scores'] ?? {});
          final player1Id = players[0];
          final player2Id = players[1];
          final otherPlayerId = (player1Id == currentPlayerId)
              ? player2Id
              : player1Id;

          if (_isTransitioning) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 20),
                  const Text(
                    'جاري التحويل للتحدي التالي...',
                    style: TextStyle(fontSize: 20, color: Colors.white),
                  ),
                ],
              ),
            );
          }

          final isAnswerCorrectlyGiven = roomData['correctAnswer'] != null;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: _buildPlayerPanel(
                        currentPlayerId,
                        scores[currentPlayerId] ?? 0,
                      ),
                    ),
                    Expanded(
                      child: _buildPlayerPanel(
                        otherPlayerId,
                        scores[otherPlayerId] ?? 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<int>(
                  valueListenable: _timerValue,
                  builder: (context, value, _) {
                    return Text(
                      'المؤقت: $value ثانية',
                      style: const TextStyle(fontSize: 20, color: Colors.white),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_currentQuestion != null &&
                            _currentQuestion!.image.isNotEmpty) ...[
                          Builder(
                            builder: (context) {
                              final imagePath = _currentQuestion!.image;
                              Widget imageWidget;

                              if (imagePath.startsWith('http')) {
                                imageWidget = CachedNetworkImage(
                                  imageUrl: imagePath,
                                  height:
                                      MediaQuery.of(context).size.height * 0.3,
                                  fit: BoxFit.contain,
                                  placeholder: (context, url) => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                  errorWidget: (context, url, error) =>
                                      const Icon(Icons.error),
                                );
                              } else if (imagePath.isNotEmpty) {
                                final githubUrl =
                                    'https://raw.githubusercontent.com/Ahmadalrawi93/almhnaken-assets/main/images/$imagePath';
                                imageWidget = CachedNetworkImage(
                                  imageUrl: githubUrl,
                                  height:
                                      MediaQuery.of(context).size.height * 0.3,
                                  fit: BoxFit.contain,
                                  placeholder: (context, url) => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                  errorWidget: (context, url, error) =>
                                      const Icon(Icons.error),
                                );
                              } else {
                                imageWidget = SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.3,
                                );
                              }
                              return imageWidget;
                            },
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          _currentQuestion?.text ?? 'جاري تحميل السؤال...',
                          style: const TextStyle(
                            fontSize: 22,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        if (isAnswerCorrectlyGiven)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20.0),
                            child: Text(
                              'الجواب الصحيح: ${roomData['correctAnswer']}',
                              style: const TextStyle(
                                fontSize: 22,
                                color: Colors.lightGreenAccent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!isAnswerCorrectlyGiven) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _answerController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'اكتب إجابتك هنا',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white24,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _submitAnswer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: const Text(
                        'تأكيد الإجابة',
                        style: TextStyle(fontSize: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
