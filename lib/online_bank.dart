// File: online_bank.dart

import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:string_similarity/string_similarity.dart';
import 'online_blocks.dart'; // Import the new screen
import 'ad_manager.dart';
import 'sound_service.dart';

class BankQuestion {
  final String questionText;
  final List<String> answers;

  BankQuestion({required this.questionText, required this.answers});

  factory BankQuestion.fromMap(Map<String, dynamic> map) {
    return BankQuestion(
      questionText: map['questionText'] ?? '',
      answers: List<String>.from(map['answers'] ?? []),
    );
  }
}

class OnlineBankScreen extends StatefulWidget {
  final String roomId;

  const OnlineBankScreen({super.key, required this.roomId});

  @override
  State<OnlineBankScreen> createState() => _OnlineBankScreenState();
}

class _OnlineBankScreenState extends State<OnlineBankScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _currentUser = FirebaseAuth.instance.currentUser;
  final TextEditingController _answerController = TextEditingController();
  final AdManager _adManager = AdManager.instance;

  StreamSubscription? _roomSubscription;
  Timer? _mainTimer;
  Timer? _bankTimer;

  List<BankQuestion> _questions = [];
  bool _isLoading = true;
  int _mainTimeRemaining = 90;
  int _bankTimeRemaining = 5;
  int _currentQuestionIndex = 0;
  int _internalPoints = 0;
  bool _showBankButton = false;
  bool _isRoundOver = false;

  String? _currentPlayerTurnId;
  Map<String, int> _totalBankedScores = {};
  List<String> _players = [];
  String? _opponentId;

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
    _listenToRoomState();
    _adManager.loadNativeAd(
      onAdLoaded: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  Future<void> _fetchQuestions() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final snapshot = await _firestore.collection('bankQuestions').get();
      final questions = snapshot.docs
          .map((doc) => BankQuestion.fromMap(doc.data()))
          .toList();
      questions.shuffle();
      if (mounted) {
        setState(() {
          _questions = questions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('فشل في تحميل الأسئلة.')));
      }
    }
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    _mainTimer?.cancel();
    _bankTimer?.cancel();
    _answerController.dispose();
    _adManager.disposeNativeAd();
    super.dispose();
  }

  void _listenToRoomState() {
    _roomSubscription = _firestore
        .collection('rooms')
        .doc(widget.roomId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists || snapshot.data() == null || !mounted) return;
      final roomData = snapshot.data()!;

      final currentTime = roomData['mainTimeRemaining'] as int? ?? 90;

      setState(() {
        _players = List<String>.from(roomData['players'] ?? []);
        final playerTurnIndex = roomData['playerTurnIndex'] as int? ?? 0;
        if (_players.isNotEmpty && playerTurnIndex < _players.length) {
          _currentPlayerTurnId = _players[playerTurnIndex];
        }

        _opponentId = _players.firstWhere(
          (id) => id != _currentUser!.uid,
          orElse: () => '',
        );

        _totalBankedScores = Map<String, int>.from(
          roomData['totalBankedScores'] ?? {},
        );
        _isRoundOver = roomData['isBankRoundOver'] ?? false;
        _mainTimeRemaining = currentTime;
      });

      if (_currentPlayerTurnId == _currentUser!.uid) {
        if (_mainTimer == null || !_mainTimer!.isActive) {
          // It's the start of my turn.
          // If the time is wrong, correct it.
          if (currentTime > 90) {
            // Update Firestore, which will trigger this listener again
            // with the correct time.
            await _firestore
                .collection('rooms')
                .doc(widget.roomId)
                .update({'mainTimeRemaining': 90});
            // We don't start the timer here, we let the re-triggered
            // listener handle it with the correct time.
          } else {
            // Time is correct, start the timer.
            _startMainTimer();
            
            // تشغيل صوت تنبيه بداية الدور
            SoundService().playTurnNotification();
          }
        }
      } else {
        _mainTimer?.cancel();
        _mainTimer = null;
      }

      if (_isRoundOver) {
        _endGame();
      }
    });
  }

  void _shuffleQuestions() {
    if (_questions.isNotEmpty) {
      final random = Random();
      _questions.shuffle(random);
    }
  }

  void _startMainTimer() {
    _mainTimer?.cancel();
    _mainTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_mainTimeRemaining > 0) {
        if (mounted) {
          setState(() {
            _mainTimeRemaining--;
          });
        }
        await _firestore.collection('rooms').doc(widget.roomId).update({
          'mainTimeRemaining': _mainTimeRemaining,
        });
      } else {
        _endTurn();
      }
    });
  }

  Future<void> _endTurn() async {
    _mainTimer?.cancel();
    _bankTimer?.cancel();
    setState(() {
      _internalPoints = 0;
      _showBankButton = false;
    });

    final roomRef = _firestore.collection('rooms').doc(widget.roomId);
    final roomDoc = await roomRef.get();
    final playerTurnIndex = roomDoc.data()?['playerTurnIndex'] as int? ?? 0;

    if (playerTurnIndex + 1 >= _players.length) {
      await roomRef.update({'isBankRoundOver': true});
    } else {
      await roomRef.update({
        'playerTurnIndex': FieldValue.increment(1),
        'mainTimeRemaining': 90, // Reset timer for next player
      });
      
      // تشغيل صوت تنبيه انتهاء الدور
      SoundService().playTurnEndNotification();
    }
  }

  void _endGame() {
    _mainTimer?.cancel();
    _bankTimer?.cancel();

    if (mounted) {
      // Ensure we don't navigate multiple times
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => OnlineBlocksScreen(roomId: widget.roomId),
          ),
          (Route<dynamic> route) => false,
        );
      }
    }
  }

  Future<void> _checkAnswer() async {
    if (_currentUser!.uid != _currentPlayerTurnId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ليس دورك الآن.')));
      return;
    }
    if (_questions.isEmpty) return;

    String userAnswer = _answerController.text.trim().toLowerCase();
    List<String> correctAnswers = _questions[_currentQuestionIndex].answers
        .map((e) => e.toLowerCase())
        .toList();

    _answerController.clear();
    const double similarityThreshold = 0.7;
    bool isCorrect = false;

    for (String correctAnswer in correctAnswers) {
      final similarity = userAnswer.similarityTo(correctAnswer);
      if (similarity >= similarityThreshold) {
        isCorrect = true;
        break;
      }
    }

    _bankTimer?.cancel();
    _showBankButton = false;

    if (isCorrect) {
      int pointsToAdd = _internalPoints == 0 ? 2 : _internalPoints * 2;
      setState(() {
        _internalPoints = pointsToAdd;
        _showBankButton = true;
      });
      _startBankTimer();
    } else {
      setState(() {
        _internalPoints = 0;
        _showBankButton = false;
      });
      _goToNextQuestion();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('إجابة خاطئة! نقاط البنك حذفت.')),
      );
    }
  }

  void _startBankTimer() {
    _bankTimer?.cancel();
    _bankTimeRemaining = 5;
    setState(() {
      _showBankButton = true;
    });
    _bankTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_bankTimeRemaining > 0) {
        if (mounted) {
          setState(() {
            _bankTimeRemaining--;
          });
        }
      } else {
        _goToNextQuestion();
      }
    });
  }

  Future<void> _bankPoints() async {
    _bankTimer?.cancel();
    if (_internalPoints > 0) {
      await _firestore.collection('rooms').doc(widget.roomId).update({
        'totalBankedScores.${_currentUser!.uid}': FieldValue.increment(
          _internalPoints,
        ),
      });
    }
    setState(() {
      _internalPoints = 0;
      _showBankButton = false;
    });
    _goToNextQuestion();
  }

  void _goToNextQuestion() {
    _bankTimer?.cancel();
    setState(() {
      _showBankButton = false;
      _answerController.clear();
      _currentQuestionIndex++;
      if (_currentQuestionIndex >= _questions.length) {
        _currentQuestionIndex = 0;
        _shuffleQuestions();
      }
    });
  }

  Widget _buildPlayerPanel(String userId, int score, bool isCurrentPlayer) {
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
            Container(
              decoration: isCurrentPlayer
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.amber, width: 3),
                    )
                  : null,
              child: CircleAvatar(
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

  Widget _buildOpponentWaitingScreen() {
    final opponentPoints = _totalBankedScores[_opponentId] ?? 0;

    return Column(
      children: [
        const SizedBox(height: 20),
        const Text(
          'الخصم في دور الإجابة...',
          style: TextStyle(
            fontSize: 20,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white30, width: 2),
            ),
            child: Center(
              child: Text(
                '$_mainTimeRemaining',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'نقاط خصمك: $opponentPoints',
          style: const TextStyle(fontSize: 18, color: Colors.white),
        ),
        const SizedBox(height: 40),
        _adManager.getNativeAdWidget() ?? const SizedBox.shrink(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMyTurn = _currentUser?.uid == _currentPlayerTurnId;
    final myTotalPoints = _totalBankedScores[_currentUser?.uid] ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF55198B),
      appBar: AppBar(
        title: const Text('البنك', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Directionality(
              textDirection: TextDirection.rtl,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_players.length >= 2)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildPlayerPanel(
                            _currentUser!.uid,
                            myTotalPoints,
                            isMyTurn,
                          ),
                          _buildPlayerPanel(
                            _opponentId!,
                            _totalBankedScores[_opponentId] ?? 0,
                            !isMyTurn,
                          ),
                        ],
                      ),
                    const SizedBox(height: 50),
                    if (!_isRoundOver) ...[
                      if (isMyTurn) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white30),
                              ),
                              child: Text(
                                'المجموع: $myTotalPoints',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white30),
                              ),
                              child: Text(
                                'نقاط البنك: $_internalPoints',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: Colors.white30,
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '$_mainTimeRemaining',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        if (_questions.isNotEmpty)
                          Text(
                            _questions[_currentQuestionIndex].questionText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _answerController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'اكتب الجواب هنا',
                            hintStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: const Color(0xFF8B53C6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) => _checkAnswer(),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _checkAnswer,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 50,
                              vertical: 15,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('تأكيد الجواب'),
                        ),
                        const SizedBox(height: 20),
                        if (_showBankButton)
                          ElevatedButton(
                            onPressed: _bankPoints,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 50,
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text('بنك ($_bankTimeRemaining)'),
                          ),
                      ] else ...[
                        _buildOpponentWaitingScreen(),
                      ],
                    ] else ...[
                      const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
