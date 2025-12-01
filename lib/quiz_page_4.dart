// File: quiz_page_4.dart
// مسيرة لاعب
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'dart:async';
import 'package:string_similarity/string_similarity.dart'; // ✅ تم إضافة هذا الاستيراد
import 'points_provider.dart';
import 'quiz_state_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ad_manager.dart'; // Import the AdManager
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

class QuizPage4 extends StatefulWidget {
  const QuizPage4({super.key});

  @override
  _QuizPage4State createState() => _QuizPage4State();
}

class _QuizPage4State extends State<QuizPage4> {
  final TextEditingController _answerController = TextEditingController();
  List<Question> _questions = [];
  bool _isLoading = true;

  bool _isBlocked = false;
  Timer? _timer;
  int _remainingTime = 60; // Default to 60
  DateTime? _blockedStartTime;
  int _incorrectAnswerCount = 0;
  bool _isAnsweredCorrectly = false;
  bool _showRevealButton = false;
  bool _answerWasRevealed = false;
  String _revealedAnswer = ''; // To store the revealed answer

  @override
  void initState() {
    super.initState();
    _loadQuestionsFromDb();
    _loadBlockedState();
    AdManager.instance
        .loadInterstitialAd(); // Keep for other scenarios if needed
    AdManager.instance.loadRewardedAd();
  }

  Future<void> _loadQuestionsFromDb() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('footballQuestions')
          .get();
      final loaded = snapshot.docs
          .map((doc) => Question.fromMap(doc.data()))
          .toList();
      if (!mounted) return;
      setState(() {
        _questions = loaded;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تحميل الأسئلة: ${e.toString()}')),
      );
    }
  }

  Future<void> _loadBlockedState() async {
    final prefs = await SharedPreferences.getInstance();
    final blockedStartTime = prefs.getInt('quiz_blockedStartTime');
    if (blockedStartTime != null) {
      _blockedStartTime = DateTime.fromMillisecondsSinceEpoch(blockedStartTime);
      final elapsed = DateTime.now().difference(_blockedStartTime!).inSeconds;
      if (elapsed < 60) {
        setState(() {
          _isBlocked = true;
          _remainingTime = 60 - elapsed;
        });
        _startTimer();
      } else {
        _isBlocked = false;
        prefs.remove('quiz_blockedStartTime');
        Provider.of<QuizStateProvider>(context, listen: false).resetLives();
      }
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _checkAnswer() async {
    final quizStateProvider = Provider.of<QuizStateProvider>(
      context,
      listen: false,
    );
    String userAnswer = _answerController.text.trim().toLowerCase();
    List<String> correctAnswers =
        _questions[quizStateProvider.currentQuestionIndex].answers
            .map((e) => e.toLowerCase())
            .toList();

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
        _isAnsweredCorrectly = true;
        _revealedAnswer = correctAnswers.first; // عرض الجواب الصحيح
      });
    } else {
      _incorrectAnswerCount++;
      quizStateProvider.loseLife();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('إجابة خاطئة!')));

      if (quizStateProvider.remainingLives <= 0) {
        await _startBlocking();
      }

      // After 3 incorrect answers, show the reveal button
      if (_incorrectAnswerCount >= 3) {
        setState(() {
          _showRevealButton = true;
        });
      }
    }
  }

  void _showRevealAd() {
    final quizStateProvider = Provider.of<QuizStateProvider>(
      context,
      listen: false,
    );
    final correctAnswer =
        _questions[quizStateProvider.currentQuestionIndex].answers.first;

    AdManager.instance.showRewardedAd(
      onAdRewarded: (reward) {
        setState(() {
          _isAnsweredCorrectly = true;
          _showRevealButton = false;
          _answerWasRevealed = true;
          _revealedAnswer = correctAnswer; // Show the correct answer
        });
      },
      onAdFailed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل تحميل الإعلان، حاول مرة أخرى.')),
        );
      },
    );
  }

  Future<void> _startBlocking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'quiz_blockedStartTime',
      DateTime.now().millisecondsSinceEpoch,
    );
    if (mounted) {
      setState(() {
        _isBlocked = true;
        _remainingTime = 60;
      });
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel(); // Cancel any existing timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_remainingTime > 0) {
        if (mounted) {
          setState(() {
            _remainingTime--;
          });
        }
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('quiz_blockedStartTime');
        _isBlocked = false;
        timer.cancel();
        Provider.of<QuizStateProvider>(context, listen: false).resetLives();
        if (mounted) {
          setState(() {});
        }
      }
    });
  }

  void _goToNextQuestion() {
    final quizStateProvider = Provider.of<QuizStateProvider>(
      context,
      listen: false,
    );

    // Only add points if the answer was NOT revealed by the ad
    if (!_answerWasRevealed) {
      Provider.of<PointsProvider>(context, listen: false).addPoints(3);
    }

    if (quizStateProvider.currentQuestionIndex < _questions.length - 1) {
      quizStateProvider.nextQuestion();
      _answerController.clear();
      setState(() {
        _isBlocked = false;
        _isAnsweredCorrectly = false;
        _incorrectAnswerCount = 0;
        _showRevealButton = false;
        _answerWasRevealed = false;
        _revealedAnswer = '';
      });
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('انتهت الأسئلة!'),
          content: const Text('لقد أجبت على جميع الأسئلة بنجاح.'),
          actions: [
            TextButton(
              onPressed: () {
                quizStateProvider.resetState();
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              child: const Text('العودة للشاشة الرئيسية'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildLives() {
    final quizStateProvider = Provider.of<QuizStateProvider>(context);
    List<Widget> balls = [];
    for (int i = 0; i < 3; i++) {
      balls.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: CircleAvatar(
            radius: 8,
            backgroundColor: i < quizStateProvider.remainingLives
                ? Colors.green
                : Colors.grey,
          ),
        ),
      );
    }
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: balls);
  }

  @override
  Widget build(BuildContext context) {
    final pointsProvider = Provider.of<PointsProvider>(context);
    final quizStateProvider = Provider.of<QuizStateProvider>(context);
    final bool hasQuestion =
        _questions.isNotEmpty &&
        quizStateProvider.currentQuestionIndex < _questions.length;
    final Question? currentQuestion = hasQuestion
        ? _questions[quizStateProvider.currentQuestionIndex]
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF55198B),
      appBar: AppBar(
        title: const Text('مسيرة لاعب', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            : _questions.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    'لا توجد أسئلة متاحة حالياً.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (currentQuestion != null) ...[
                      Builder(
                        builder: (context) {
                          final imagePath = currentQuestion.image;
                          Widget imageWidget;

                          if (imagePath.startsWith('http')) {
                            imageWidget = CachedNetworkImage(
                              imageUrl: imagePath,
                              height: 300,
                              width: 300,
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
                              height: 300,
                              width: 300,
                              fit: BoxFit.contain,
                              placeholder: (context, url) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.error),
                            );
                          } else {
                            imageWidget = Container(
                              height: 300,
                              width: 300,
                              color: Colors.grey[300],
                            );
                          }
                          return imageWidget;
                        },
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (currentQuestion != null)
                      Text(
                        currentQuestion.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
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
                    ),
                    const SizedBox(height: 20),
                    if (_isAnsweredCorrectly) ...[
                      // عرض الجواب الصحيح باللون الأخضر
                      if (_revealedAnswer.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            border: Border.all(color: Colors.green, width: 2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'الجواب الصحيح: $_revealedAnswer',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ElevatedButton(
                        onPressed: _goToNextQuestion,
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
                        child: const Text('التالي'),
                      ),
                    ] else
                      ElevatedButton(
                        onPressed: _isBlocked ? null : _checkAnswer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isBlocked
                              ? Colors.grey
                              : Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 50,
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          _isBlocked
                              ? 'انتظر ($_remainingTime ثانية)'
                              : 'تأكيد الجواب',
                        ),
                      ),
                    const SizedBox(height: 20),
                    _buildLives(),
                    const SizedBox(height: 20),
                    if (_showRevealButton)
                      Column(
                        children: [
                          ElevatedButton(
                            onPressed: _showRevealAd,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 50,
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('كشف الاجابة'),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'قد يظهر لك اعلان',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    if (_answerWasRevealed && _revealedAnswer.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Text(
                          'الجواب الصحيح: $_revealedAnswer',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class Question {
  final String text;
  final String image;
  final List<String> answers;

  const Question({
    required this.text,
    required this.image,
    required this.answers,
  });

  factory Question.fromMap(Map<String, dynamic> map) {
    final List<dynamic> rawAnswers = (map['answers'] ?? []) as List<dynamic>;
    return Question(
      text: (map['text'] ?? map['questionText'] ?? '').toString(),
      image: (map['image'] ?? map['imagePath'] ?? '').toString(),
      answers: rawAnswers.map((e) => e.toString()).toList(),
    );
  }
}
