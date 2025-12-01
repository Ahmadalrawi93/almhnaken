// File: quiz_page_3.dart
// بلوكات
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math';

import 'ad_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'points_provider.dart';

// Enum to represent different types of balls
enum BallType { question, twoPoints, specialQuestion }

// نموذج مبسط لسؤال لاعب مع حقل نص السؤال والإجابة الصحيحة
class PlayerQuestion {
  final String questionText;
  final String correctAnswer;

  const PlayerQuestion({
    required this.questionText,
    required this.correctAnswer,
  });

  factory PlayerQuestion.fromMap(Map<String, dynamic> map) {
    final List<dynamic>? answers = map['answers'] as List<dynamic>?;
    final String candidate1 = (map['correctAnswer'] ?? '').toString();
    final String candidate2 = (map['correct'] ?? '').toString();
    final String candidate3 = (map['answer'] ?? '').toString();
    final String candidate4 = answers != null && answers.isNotEmpty
        ? answers.first.toString()
        : '';
    final String candidate5 = (map['rightAnswer'] ?? '').toString();
    final String candidate6 = (map['trueAnswer'] ?? '').toString();
    final String candidate7 = (map['option1'] ?? map['optionA'] ?? '')
        .toString();
    final String picked =
        [
              candidate1,
              candidate2,
              candidate3,
              candidate4,
              candidate5,
              candidate6,
              candidate7,
            ]
            .map((s) => s.trim())
            .firstWhere((s) => s.isNotEmpty, orElse: () => 'الإجابة');
    return PlayerQuestion(
      questionText: (map['questionText'] ?? map['text'] ?? '').toString(),
      correctAnswer: picked,
    );
  }
}

class QuizPage3 extends StatefulWidget {
  const QuizPage3({super.key});

  @override
  _QuizPage3State createState() => _QuizPage3State();
}

class _QuizPage3State extends State<QuizPage3> {
  final TextEditingController _player1Controller = TextEditingController();
  final TextEditingController _player2Controller = TextEditingController();
  String _player1Name = '';
  String _player2Name = '';
  int _player1Points = 0;
  int _player2Points = 0;
  bool _gameStarted = false;
  bool _gameEnded = false;
  bool _isPlayer1Turn = true;
  int _currentBallIndex = -1;
  int _timeRemaining = 30;
  Timer? _questionTimer;

  String _player1Avatar = '2.png';
  String _player2Avatar = '3.png';
  final List<String> _availableAvatars = List.generate(
    12,
    (index) => 'iconUser/${index + 1}.png',
  );

  List<PlayerQuestion> _allQuestions = [];
  List<PlayerQuestion> _roundQuestions = [];
  final List<bool> _questionAnswered = List.filled(20, false);
  List<BallType> _ballTypes = [];
  String _specialEffectMessage = '';
  IconData _specialEffectIcon = MdiIcons.star;
  bool _isLoading = true;
  Widget? _bannerAdWidget;

  @override
  void initState() {
    super.initState();
    _loadQuestionsFromDb();
    AdManager.instance.loadInterstitialAd();
    AdManager.instance.loadBannerAd(onAdLoaded: () {
      if (mounted) {
        setState(() {
          _bannerAdWidget = AdManager.instance.getBannerAdWidget();
        });
      }
    });
  }

  Future<void> _loadQuestionsFromDb() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('playerQuestions')
          .get();
      final loaded = snapshot.docs
          .map((doc) => PlayerQuestion.fromMap(doc.data()))
          .toList();
      if (!mounted) return;
      setState(() {
        _allQuestions = loaded;
        _isLoading = false;
      });
      // تجهيز الجولة الأولى بعد التحميل
      _resetGame();
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

  @override
  void dispose() {
    _player1Controller.dispose();
    _player2Controller.dispose();
    _questionTimer?.cancel();
    AdManager.instance.disposeBannerAd();
    super.dispose();
  }

  Future<void> _selectAvatar(int playerNumber) async {
    final selectedAvatarPath = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text(
              'اختر الصورة الرمزية',
              style: TextStyle(
                color: Color(0xFF55198B),
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _availableAvatars.length,
                itemBuilder: (context, index) {
                  final imagePath = _availableAvatars[index];
                  final fileName = imagePath.split('/').last;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context, fileName);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF55198B),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.3),
                            spreadRadius: 1,
                            blurRadius: 3,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: const Color(0xFF55198B),
                        child: ClipOval(
                          child: Image.asset(
                            imagePath,
                            width: 50,
                            height: 50,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'إلغاء',
                  style: TextStyle(color: Color(0xFF55198B)),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selectedAvatarPath != null) {
      setState(() {
        if (playerNumber == 1) {
          _player1Avatar = selectedAvatarPath;
        } else {
          _player2Avatar = selectedAvatarPath;
        }
      });
    }
  }

  void _generateRoundQuestions() {
    final random = Random();
    // خلط جميع الأسئلة
    _allQuestions.shuffle(random);
    // اختيار أول 20 سؤالًا فقط لضمان عدم التكرار في الجولة الواحدة
    _roundQuestions = _allQuestions.take(20).toList();
  }

  void _generateBallTypes() {
    _ballTypes = List.filled(20, BallType.question);
    final random = Random();
    final List<int> indices = List.generate(20, (index) => index)
      ..shuffle(random);

    // Add 2 'twoPoints' balls
    _ballTypes[indices[0]] = BallType.twoPoints;
    _ballTypes[indices[1]] = BallType.twoPoints;

    // Add 2 'specialQuestion' balls
    _ballTypes[indices[2]] = BallType.specialQuestion;
    _ballTypes[indices[3]] = BallType.specialQuestion;
  }

  void _startGame() {
    setState(() {
      _player1Name = _player1Controller.text.isEmpty
          ? 'اللاعب 1'
          : _player1Controller.text;
      _player2Name = _player2Controller.text.isEmpty
          ? 'اللاعب 2'
          : _player2Controller.text;
      _gameStarted = true;
      _gameEnded = false;
      _player1Points = 0;
      _player2Points = 0;
      _isPlayer1Turn = true;
      _currentBallIndex = -1;
      _specialEffectMessage = '';
      _specialEffectIcon = MdiIcons.star;
      _questionAnswered.fillRange(0, 20, false);
      _generateRoundQuestions(); // توليد أسئلة جديدة للجولة
      _generateBallTypes();
    });
  }

  void _startQuestionTimer() {
    _questionTimer?.cancel();
    _timeRemaining = 30;
    _questionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeRemaining > 0) {
        if (mounted) {
          setState(() {
            _timeRemaining--;
          });
        }
      } else {
        _questionTimer?.cancel();
        // لا يتم الانتقال مباشرة، بل يبقى اللاعب على شاشة السؤال
      }
    });
  }

  void _goToNextTurn({required bool answered}) {
    _questionTimer?.cancel();

    if (_questionAnswered.every((element) => element)) {
      _endGame();
      return;
    }

    setState(() {
      _currentBallIndex = -1; // العودة إلى شاشة الكرات
      _isPlayer1Turn = !_isPlayer1Turn;
      _timeRemaining = 30;
      _specialEffectMessage = '';
      _specialEffectIcon = MdiIcons.star;
    });
  }

  void _checkAnswer({required bool isCorrect}) {
    _questionTimer?.cancel();
    final currentBallType = _ballTypes[_currentBallIndex];

    if (_isPlayer1Turn) {
      if (currentBallType == BallType.twoPoints) {
        if (isCorrect) {
          _player1Points += 2;
        } else {
          _player2Points++;
        }
      } else if (currentBallType == BallType.specialQuestion) {
        if (isCorrect) {
          _player1Points++;
          _player2Points = (_player2Points - 1)
              .clamp(0, double.infinity)
              .toInt();
        }
      } else {
        // Regular question
        if (isCorrect) {
          _player1Points++;
        } else {
          _player2Points++;
        }
      }
    } else {
      // Player 2's turn
      if (currentBallType == BallType.twoPoints) {
        if (isCorrect) {
          _player2Points += 2;
        } else {
          _player1Points++;
        }
      } else if (currentBallType == BallType.specialQuestion) {
        if (isCorrect) {
          _player2Points++;
          _player1Points = (_player1Points - 1)
              .clamp(0, double.infinity)
              .toInt();
        }
      } else {
        // Regular question
        if (isCorrect) {
          _player2Points++;
        } else {
          _player1Points++;
        }
      }
    }
    _goToNextTurn(answered: true);
  }

  void _applySpecialBallEffect(BallType type) {
    if (type == BallType.twoPoints) {
      _specialEffectMessage = 'سؤال بنقطتين!';
      _specialEffectIcon = MdiIcons.starCircle;
    } else if (type == BallType.specialQuestion) {
      _specialEffectMessage = 'وكّع صاحبك!';
      _specialEffectIcon = MdiIcons.swordCross;
    }
    setState(() {
      _startQuestionTimer();
    });
  }

  void _endGame() {
    setState(() {
      _gameEnded = true;
    });
    // final pointsProvider = Provider.of<PointsProvider>(context, listen: false);
    // pointsProvider.addPoints(_player1Points + _player2Points);
  }

  void _showAdAndResetGame() {
    AdManager.instance.showInterstitialAd(
      onAdDismissed: () {
        _resetGame();
      },
    );
  }

  void _resetGame() {
    setState(() {
      _gameStarted = false;
      _gameEnded = false;
      _player1Controller.clear();
      _player2Controller.clear();
      _player1Points = 0;
      _player2Points = 0;
      _isPlayer1Turn = true;
      _currentBallIndex = -1;
      _specialEffectMessage = '';
      _specialEffectIcon = MdiIcons.star;
      _questionAnswered.fillRange(0, 20, false);
      _generateRoundQuestions(); // إعادة توليد أسئلة جديدة للجولة القادمة
      _generateBallTypes();
    });
  }

  Widget _buildStartScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPlayerInput(
                controller: _player1Controller,
                label: 'اسم اللاعب 1',
                imageAsset: _player1Avatar,
                onAvatarTap: () => _selectAvatar(1),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPlayerInput(
                controller: _player2Controller,
                label: 'اسم اللاعب 2',
                imageAsset: _player2Avatar,
                onAvatarTap: () => _selectAvatar(2),
              ),
            ],
          ),
          const SizedBox(height: 50),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 250,
                height: 50,
                child: ElevatedButton(
                  onPressed: _startGame,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('ابدأ', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 50),
          _buildRulesSection(),
        ],
      ),
    );
  }

  Widget _buildPlayerInput({
    required TextEditingController controller,
    required String label,
    required String imageAsset,
    required VoidCallback onAvatarTap,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.white,
                child: CircleAvatar(
                  radius: 38,
                  backgroundColor: const Color(0xFF55198B), // A fallback color
                  child: ClipOval(
                    child: Image.asset(
                      'iconUser/$imageAsset',
                      fit: BoxFit.contain, // Use contain to prevent cropping
                      width: 76,
                      height: 76,
                    ),
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.amber,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                padding: const EdgeInsets.all(4),
                child: const Icon(MdiIcons.pencil, color: Colors.white, size: 16),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 180, // Reduced width
          child: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.black),
            decoration: InputDecoration(
              hintText: label,
              hintStyle: const TextStyle(color: Colors.black54),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildRulesSection() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'قواعد اللعبة:',
            style: TextStyle(
              color: Colors.black,
              fontSize: 18.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'الشخص الذي عليه مؤشر الدور هو من يمسك الهاتف ليسأل اللاعب الثاني اذا اجاب جواب صحيح يحصل على نقطة اما في حال اجاب بخطا الخصم ياخذ نقطة وهناك كرات خاصة في اثارة اكثر',
            style: TextStyle(color: Colors.black87, fontSize: 16.0),
            textAlign: TextAlign.justify,
          ),
        ],
      ),
    );
  }

  Widget _buildGameScreen() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildPlayerScore(
                  _player1Name, _player1Points, !_isPlayer1Turn, 'iconUser/$_player1Avatar'),
              _buildPlayerScore(
                  _player2Name, _player2Points, _isPlayer1Turn, 'iconUser/$_player2Avatar'),
            ],
          ),
        ),
        if (_currentBallIndex != -1)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(MdiIcons.timer, color: Colors.white, size: 30),
                const SizedBox(width: 8),
                Text(
                  '$_timeRemaining',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        if (_currentBallIndex == -1)
          _buildQuestionBalls()
        else
          _buildQuestionView(),
      ],
    );
  }

  Widget _buildPlayerScore(
      String name, int score, bool isActive, String imageAsset, {double avatarRadius = 30}) { // Increased default radius
    return Column(
      children: [
        CircleAvatar(
          radius: avatarRadius + 4, // Make space for highlight and border
          backgroundColor: isActive ? Colors.amber : Colors.transparent,
          child: CircleAvatar(
            radius: avatarRadius + 2,
            backgroundColor: Colors.black, // White border
            child: CircleAvatar(
              radius: avatarRadius,
              backgroundColor: Colors.white, // Fallback color
              child: ClipOval(
                child: Image.asset(
                  imageAsset,
                  fit: BoxFit.contain,
                  width: avatarRadius * 2,
                  height: avatarRadius * 2,
                ),
              ),
            ),
          ),
        ),
        Text(
          name,
          style: TextStyle(
            color: isActive ? Colors.amber : Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          '$score',
          style: TextStyle(
            color: isActive ? Colors.amber : Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (isActive) // Changed condition
          const Padding(
            padding: EdgeInsets.only(top: 4.0),
            child: Text(
              'امسك الهاتف',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }

  Widget _buildQuestionBalls() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: 20,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: _questionAnswered[index]
                  ? null
                  : () {
                      setState(() {
                        _currentBallIndex = index;
                        _questionAnswered[index] = true;
                      });
                      if (_ballTypes[index] == BallType.question) {
                        _startQuestionTimer();
                      } else {
                        _applySpecialBallEffect(_ballTypes[index]);
                      }
                    },
              child: Container(
                decoration: BoxDecoration(
                  color: _questionAnswered[index]
                      ? Colors.grey[800]
                      : const Color(0xFF8B53C6),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: _questionAnswered[index]
                      ? null
                      : [
                          const BoxShadow(
                            color: Colors.white30,
                            blurRadius: 5,
                            offset: Offset(0, 3),
                          ),
                        ],
                ),
                child: Center(
                  child: Text(
                    _questionAnswered[index] ? '✓' : '${index + 1}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: _questionAnswered[index] ? 30 : 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildQuestionView() {
    if (_currentBallIndex < 0 || _currentBallIndex >= _roundQuestions.length) {
      return const Text(
        'حدث خطأ غير متوقع.',
        style: TextStyle(color: Colors.red),
      );
    }

    final question = _roundQuestions[_currentBallIndex];

    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_specialEffectMessage.isNotEmpty) ...[
                Column(
                  children: [
                    Icon(_specialEffectIcon, size: 50, color: Colors.amber),
                    const SizedBox(height: 10),
                    Text(
                      _specialEffectMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ],
              Text(
                question.questionText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () => _checkAnswer(isCorrect: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 5,
                ),
                child: Text(
                  question.correctAnswer,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _checkAnswer(isCorrect: false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 5,
                ),
                child: const Text('جواب خطأ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEndGameScreen() {
    final isTie = _player1Points == _player2Points;
    final winnerIsPlayer1 = _player1Points > _player2Points;

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF55198B).withOpacity(0.9),
            const Color(0xFF55198B).withOpacity(0.7),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'انتهت الجولة!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),
            if (isTie)
              Column(
                children: const [
                  Icon(MdiIcons.handshake, color: Colors.blueAccent, size: 80),
                  SizedBox(height: 10),
                  Text(
                    'تعادل!',
                    style: TextStyle(
                      color: Colors.blueAccent,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            else ...[
              const Icon(MdiIcons.trophy, color: Colors.amber, size: 80),
              const SizedBox(height: 10),
              const Text(
                'الفائز هو:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                winnerIsPlayer1 ? _player1Name : _player2Name,
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPlayerScore(
                  _player1Name,
                  _player1Points,
                  winnerIsPlayer1,
                  'iconUser/$_player1Avatar',
                  avatarRadius: 45, // Larger avatar
                ),
                _buildPlayerScore(
                  _player2Name,
                  _player2Points,
                  !winnerIsPlayer1,
                  'iconUser/$_player2Avatar',
                  avatarRadius: 45, // Larger avatar
                ),
              ],
            ),
            const SizedBox(height: 60),
            ElevatedButton(
              onPressed: _showAdAndResetGame,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF55198B),
                padding: const EdgeInsets.symmetric(
                  horizontal: 50,
                  vertical: 20,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 10,
              ),
              child: const Text('جولة جديدة', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF55198B),
      appBar: AppBar(
        title: Text(
          _gameStarted ? 'بلوكات' : 'بلوكات',
          style: const TextStyle(color: Colors.white),
        ),
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
                  '${Provider.of<PointsProvider>(context).points}',
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
      body: Column(
        children: [
          Expanded(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: _gameEnded
                  ? _buildEndGameScreen()
                  : (_gameStarted ? _buildGameScreen() : _buildStartScreen()),
            ),
          ),
          if (_bannerAdWidget != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: _bannerAdWidget,
            )
        ],
      ),
    );
  }
}