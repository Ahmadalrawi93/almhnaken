// File: quiz_page_2.dart
// البنك
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'dart:async';
import 'package:string_similarity/string_similarity.dart';
import 'points_provider.dart';
import 'dart:math';

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

class QuizPage2 extends StatefulWidget {
  const QuizPage2({super.key});

  @override
  _QuizPage2State createState() => _QuizPage2State();
}

class _QuizPage2State extends State<QuizPage2> {
  final TextEditingController _answerController = TextEditingController();
  List<BankQuestion> _questions = [];
  bool _isLoading = true;

  Timer? _mainTimer;
  int _mainTimeRemaining = 90;

  Timer? _bankTimer;
  int _bankTimeRemaining = 5;

  int _currentQuestionIndex = 0;
  int _internalPoints = 0;
  int _totalBankedPoints = 0;
  bool _showBankButton = false;
  bool _gameEnded = false;
  bool _isGameStarted = false;

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
  }

  Future<void> _fetchQuestions() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('bankQuestions')
          .get();
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
      // Handle error, maybe show a message to the user
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('فشل في تحميل الأسئلة.')));
      }
    }
  }

  @override
  void dispose() {
    _mainTimer?.cancel();
    _bankTimer?.cancel();
    _answerController.dispose();
    super.dispose();
  }

  void _shuffleQuestions() {
    final random = Random();
    _questions.shuffle(random);
  }

  void _startGame() {
    if (_questions.isEmpty) return; // Don't start if no questions
    setState(() {
      _isGameStarted = true;
      _mainTimeRemaining = 90;
      _currentQuestionIndex = 0;
      _internalPoints = 0;
      _totalBankedPoints = 0;
      _gameEnded = false;
    });
    _shuffleQuestions();
    _startMainTimer();
  }

  void _startMainTimer() {
    _mainTimer?.cancel(); // Cancel any existing timer
    _mainTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_mainTimeRemaining > 0) {
        if (mounted) {
          setState(() {
            _mainTimeRemaining--;
          });
        }
      } else {
        _endRound();
      }
    });
  }

  void _endRound() {
    _mainTimer?.cancel();
    _bankTimer?.cancel();
    _bankPointsAndReset(addPointsToTotal: true);
    if (mounted) {
      Provider.of<PointsProvider>(
        context,
        listen: false,
      ).addPoints(_totalBankedPoints);
      setState(() {
        _gameEnded = true;
      });
    }
  }

  void _checkAnswer() {
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

    if (isCorrect) {
      setState(() {
        if (_internalPoints == 0) {
          _internalPoints = 2;
        } else {
          _internalPoints *= 2;
        }
      });
      _startBankTimer();
    } else {
      _bankPointsAndReset(addPointsToTotal: false);
      _goToNextQuestion();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('إجابة خاطئة! النقاط في البنك حذفت.')),
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
        timer.cancel();
        _goToNextQuestion();
      }
    });
  }

  void _bankPointsAndReset({required bool addPointsToTotal}) {
    _bankTimer?.cancel();
    if (addPointsToTotal) {
      _totalBankedPoints += _internalPoints;
    }
    setState(() {
      _internalPoints = 0;
      _showBankButton = false;
    });
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

  @override
  Widget build(BuildContext context) {
    final pointsProvider = Provider.of<PointsProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF55198B),
      appBar: AppBar(
        title: const Text('البنك', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(MdiIcons.arrowLeft, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                const Icon(MdiIcons.trophy, color: Colors.amber),
                const SizedBox(width: 8.0),
                Text(
                  '${pointsProvider.points}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          MdiIcons.timer,
                          color: Colors.white,
                          size: 40,
                        ),
                        const SizedBox(width: 8.0),
                        Text(
                          '$_mainTimeRemaining',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Column(
                          children: [
                            const Text(
                              'نقاط البنك',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16.0,
                              ),
                            ),
                            Text(
                              '$_internalPoints',
                              style: const TextStyle(
                                color: Colors.green,
                                fontSize: 32.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Column(
                          children: [
                            const Text(
                              'المجموع',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16.0,
                              ),
                            ),
                            Text(
                              '$_totalBankedPoints',
                              style: const TextStyle(
                                color: Colors.amber,
                                fontSize: 32.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 50),
                    if (!_isGameStarted)
                      ElevatedButton(
                        onPressed: _startGame,
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
                        child: const Text('ابدأ الجولة'),
                      )
                    else if (!_gameEnded && _questions.isNotEmpty) ...[
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
                          onPressed: () {
                            _bankPointsAndReset(addPointsToTotal: true);
                            _goToNextQuestion();
                          },
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
                      const Text(
                        'انتهت الجولة!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _startGame,
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
                        child: const Text('ابدأ جولة جديدة'),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
