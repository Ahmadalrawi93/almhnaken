// File: online_blocks.dart
// Rebuilt from scratch based on new criteria.

import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:math';
import 'package:string_similarity/string_similarity.dart';

import 'main.dart'; // Import for HomeScreen
import 'ad_manager.dart';
import 'sound_service.dart';

// Define the data model for a question right in this file.
class OnlinePlayerQuestion {
  final String questionText;
  final List<String> correctAnswers;

  OnlinePlayerQuestion({
    required this.questionText,
    required this.correctAnswers,
  });

  // Factory constructor to create a question from a Firestore map
  factory OnlinePlayerQuestion.fromMap(Map<String, dynamic> map) {
    final List<dynamic> arr =
        (map['correctAnswers'] ?? map['answers'] ?? []) as List<dynamic>;
    final List<String> answers = arr.map((e) => e.toString()).toList();
    return OnlinePlayerQuestion(
      questionText:
          (map['questionText'] ??
                  map['question'] ??
                  map['text'] ??
                  'Error: Missing question text')
              .toString(),
      correctAnswers: answers,
    );
  }

  // Method to convert a question instance to a map for Firestore
  Map<String, dynamic> toMap() {
    return {'questionText': questionText, 'correctAnswers': correctAnswers};
  }
}

// Enum to represent different types of balls
enum BallType { question, twoPoints, specialQuestion }

class OnlineBlocksScreen extends StatefulWidget {
  final String roomId;

  const OnlineBlocksScreen({super.key, required this.roomId});

  @override
  State<OnlineBlocksScreen> createState() => _OnlineBlocksScreenState();
}

class _OnlineBlocksScreenState extends State<OnlineBlocksScreen> {
  final AdManager _adManager = AdManager.instance;
  final _firestore = FirebaseFirestore.instance;
  final _currentUser = FirebaseAuth.instance.currentUser;
  final TextEditingController _answerController = TextEditingController();

  StreamSubscription? _roomSubscription;
  Timer? _questionTimer;
  Timer? _statusMessageTimer;

  // Local state mirrored from Firestore
  List<OnlinePlayerQuestion> _roundQuestions = [];
  List<BallType> _ballTypes = [];
  List<bool> _questionAnswered = List.filled(10, false);
  Map<String, int> _totalScores = {};
  String _currentPlayerTurnId = '';
  int _currentBallIndex = -1;
  int _timeRemaining = 30;
  String _specialEffectMessage = '';
  IconData _specialEffectIcon = MdiIcons.star;
  String? _lastAnswerStatusMessage;
  String? _lastConsumedStatus; // To prevent flickering status message

  List<String> _players = [];
  String? _opponentId;
  bool _isLoading = true;
  bool _showWinnerScreen = false;

  @override
  void initState() {
    super.initState();
    _adManager.loadBannerAd(
      onAdLoaded: () {
        if (mounted) {
          setState(() {});
        }
      },
    );

    if (_currentUser == null) {
      // Handle user not logged in
      return;
    }
    _listenToRoomState();
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    _questionTimer?.cancel();
    _statusMessageTimer?.cancel();
    _answerController.dispose();
    _adManager.disposeBannerAd();
    super.dispose();
  }

  void _listenToRoomState() {
    _roomSubscription = _firestore
        .collection('rooms')
        .doc(widget.roomId)
        .snapshots()
        .listen((snapshot) async {
          if (!snapshot.exists || snapshot.data() == null) {
            if (mounted) setState(() => _isLoading = false);
            return;
          }
          final roomData = snapshot.data()!;

          // Initialize game data if it doesn't exist, only by the first player.
          if (roomData['blocks_roundQuestions'] == null &&
              _currentUser!.uid ==
                  (roomData['players'] as List<dynamic>).first) {
            await _initializeGame();
            return; // Wait for next snapshot
          }

          // If game data is still not ready, show loading.
          if (roomData['blocks_roundQuestions'] == null) {
            if (mounted) setState(() => _isLoading = true);
            return;
          }

          final newQuestionAnswered =
              (roomData['blocks_questionAnswered'] as List<dynamic>)
                  .map((a) => a as bool)
                  .toList();

          final allAnswered = newQuestionAnswered.every((a) => a);

          if (mounted) {
            // Update final scores ONCE when the game ends.
            if (allAnswered && !_showWinnerScreen) {
              _updateFinalScores();
            }

            setState(() {
              _players = List<String>.from(roomData['players'] ?? []);
              if (_players.isNotEmpty) {
                _opponentId = _players.firstWhere(
                  (id) => id != _currentUser!.uid,
                  orElse: () => '',
                );
              }

              final playerTurnIndex =
                  roomData['blocks_playerTurnIndex'] as int? ?? 0;
              if (_players.isNotEmpty && playerTurnIndex < _players.length) {
                final newPlayerTurnId = _players[playerTurnIndex];
                if (_currentPlayerTurnId != newPlayerTurnId) {
                  _currentPlayerTurnId = newPlayerTurnId;
                  
                  // تشغيل صوت تنبيه بداية الدور الجديد
                  if (_currentPlayerTurnId == _currentUser?.uid) {
                    SoundService().playTurnNotification();
                  }
                }
              }

              // Use the scores from the bank round as the source of truth.
              _totalScores = Map<String, int>.from(
                roomData['totalBankedScores'] ?? {},
              );

              _roundQuestions =
                  (roomData['blocks_roundQuestions'] as List<dynamic>)
                      .map((q) => OnlinePlayerQuestion.fromMap(q))
                      .toList();

              _ballTypes = (roomData['blocks_ballTypes'] as List<dynamic>)
                  .map((b) => BallType.values[b as int])
                  .toList();

              _questionAnswered = newQuestionAnswered;

              _currentBallIndex =
                  roomData['blocks_currentBallIndex'] as int? ?? -1;
              _timeRemaining = roomData['blocks_timeRemaining'] as int? ?? 30;

              // Handle the status message display logic to prevent flickering.
              final lastStatus = roomData['lastAnswerStatus'] as String?;
              if (lastStatus != null) {
                if (mounted) {
                  setState(() {
                    _lastAnswerStatusMessage = lastStatus;
                  });
                }
                _firestore.collection('rooms').doc(widget.roomId).update({
                  'lastAnswerStatus': null,
                });
                _statusMessageTimer?.cancel();
                _statusMessageTimer = Timer(const Duration(seconds: 3), () {
                  if (mounted) {
                    setState(() {
                      _lastAnswerStatusMessage = null;
                    });
                  }
                });
              }

              _setSpecialEffectMessage();
              _isLoading = false;
              _showWinnerScreen = allAnswered;
            });
          }

          if (_currentUser?.uid == _currentPlayerTurnId &&
              _currentBallIndex != -1) {
            if (_questionTimer == null || !_questionTimer!.isActive) {
              _startQuestionTimer();
            }
          } else {
            _questionTimer?.cancel();
          }
        });
  }

  Future<void> _updateFinalScores() async {
    final roomRef = _firestore.collection('rooms').doc(widget.roomId);
    final roomDoc = await roomRef.get();

    // Check if points have already been awarded for this room to prevent double updates.
    if (roomDoc.exists && !(roomDoc.data()?['pointsAwarded'] ?? false)) {
      final scores = Map<String, int>.from(
        roomDoc.data()?['totalBankedScores'] ?? {},
      );

      final WriteBatch batch = _firestore.batch();

      for (final playerId in scores.keys) {
        final scoreFromGame = scores[playerId] ?? 0;
        if (scoreFromGame != 0) {
          final userRef = _firestore.collection('users').doc(playerId);
          // Increment the user's main points by the score they got in the game.
          batch.update(userRef, {
            'points': FieldValue.increment(scoreFromGame),
          });
        }
      }

      // Mark this room so points aren't awarded again.
      batch.update(roomRef, {'pointsAwarded': true});

      try {
        await batch.commit();
      } catch (e) {
        // Handle potential error during batch commit
        print('Error updating final scores: $e');
      }
    }
  }

  Future<void> _initializeGame() async {
    // Fetch questions from Firestore
    try {
      final questionsSnapshot = await _firestore
          .collection('onlinePlayerQuestions')
          .get();
      if (questionsSnapshot.docs.isEmpty) {
        // Handle case where no questions are in the database
        // Maybe fallback to a default set or show an error
        print("No questions found in the database.");
        return;
      }
      final allQuestions = questionsSnapshot.docs
          .map((doc) => OnlinePlayerQuestion.fromMap(doc.data()))
          .toList();

      allQuestions.shuffle(Random());
      _roundQuestions = allQuestions.take(10).toList();

      // Ensure we have exactly 10 questions. If not, something is wrong.
      if (_roundQuestions.length < 10) {
        print("Warning: Not enough questions in the database to start a game.");
        // You might want to handle this more gracefully
        return;
      }

      _ballTypes = List.filled(10, BallType.question);
      final random = Random();
      final indices = List.generate(10, (i) => i)..shuffle(random);
      _ballTypes[indices[0]] = BallType.twoPoints;
      _ballTypes[indices[1]] = BallType.specialQuestion;

      // DO NOT initialize scores here. They carry over from the bank round.
      await _firestore.collection('rooms').doc(widget.roomId).update({
        'blocks_roundQuestions': _roundQuestions.map((q) => q.toMap()).toList(),
        'blocks_ballTypes': _ballTypes.map((b) => b.index).toList(),
        'blocks_questionAnswered': List.filled(10, false),
        'blocks_playerTurnIndex': 0,
        'blocks_currentBallIndex': -1,
        'blocks_timeRemaining': 30,
        'lastAnswerStatus': null,
        'pointsAwarded': false, // Initialize the flag
      });
    } catch (e) {
      print("Error initializing game and fetching questions: $e");
      // Handle error, maybe by showing a message to the user.
    }
  }

  void _startQuestionTimer() {
    _questionTimer?.cancel();
    _questionTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_timeRemaining > 0) {
        if (_currentUser?.uid == _currentPlayerTurnId) {
          final newTime = _timeRemaining - 1;
          if (mounted) {
            setState(() {
              _timeRemaining = newTime;
            });
          }
          await _firestore.collection('rooms').doc(widget.roomId).update({
            'blocks_timeRemaining': newTime,
          });
        }
      } else {
        timer.cancel();
        if (_currentUser!.uid == _currentPlayerTurnId) {
          await _checkAnswer(submittedAnswer: '');
        }
      }
    });
  }

  void _onBallTapped(int index) {
    if (_currentUser!.uid != _currentPlayerTurnId || _questionAnswered[index])
      return;

    _firestore.collection('rooms').doc(widget.roomId).update({
      'blocks_currentBallIndex': index,
      'blocks_timeRemaining': 30,
    });
  }

  Future<void> _checkAnswer({required String submittedAnswer}) async {
    _questionTimer?.cancel();
    if (_currentBallIndex == -1) return;

    final question = _roundQuestions[_currentBallIndex];
    final ballType = _ballTypes[_currentBallIndex];
    final bool isCorrect = question.correctAnswers.any(
      (ans) =>
          submittedAnswer.trim().toLowerCase().similarityTo(
            ans.toLowerCase(),
          ) >=
          0.8,
    );

    int myPointsChange = 0;
    int opponentPointsChange = 0;

    if (isCorrect) {
      switch (ballType) {
        case BallType.twoPoints:
          myPointsChange = 2;
          break;
        case BallType.specialQuestion:
          myPointsChange = 1;
          opponentPointsChange = -1;
          break;
        case BallType.question:
          myPointsChange = 1;
          break;
      }
    }

    _answerController.clear();

    final nextTurnIndex =
        (_players.indexOf(_currentPlayerTurnId) + 1) % _players.length;

    var newAnsweredState = List<bool>.from(_questionAnswered);
    newAnsweredState[_currentBallIndex] = true;

    // Points are now updated in the 'totalBankedScores' field.
    await _firestore.collection('rooms').doc(widget.roomId).update({
      'totalBankedScores.${_currentUser!.uid}': FieldValue.increment(
        myPointsChange,
      ),
      if (opponentPointsChange != 0)
        'totalBankedScores.$_opponentId': FieldValue.increment(
          opponentPointsChange,
        ),
      'blocks_currentBallIndex': -1,
      'blocks_playerTurnIndex': nextTurnIndex,
      'blocks_questionAnswered': newAnsweredState,
      'lastAnswerStatus': isCorrect ? 'جواب صحيح' : 'جواب خطأ',
    });
    
    // تشغيل صوت تنبيه انتهاء الدور
    SoundService().playTurnNotification();
  }

  void _setSpecialEffectMessage() {
    if (_currentBallIndex == -1) {
      _specialEffectMessage = '';
      return;
    }
    final type = _ballTypes[_currentBallIndex];
    if (type == BallType.twoPoints) {
      _specialEffectMessage = 'سؤال بنقطتين!';
      _specialEffectIcon = MdiIcons.starCircle;
    } else if (type == BallType.specialQuestion) {
      _specialEffectMessage = 'وكّع صاحبك!';
      _specialEffectIcon = MdiIcons.swordCross;
    } else {
      _specialEffectMessage = '';
      _specialEffectIcon = MdiIcons.star;
    }
  }

  void _navigateToHome() {
    // Attempt to delete the room. It's okay if it fails (e.g., if the other player already deleted it).
    _firestore
        .collection('rooms')
        .doc(widget.roomId)
        .delete()
        .catchError((_) {});

    _adManager.showInterstitialAd(
      onAdDismissed: () {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (Route<dynamic> route) => false,
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF55198B),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_showWinnerScreen) {
      return _buildWinnerScreen();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF55198B),
      appBar: AppBar(
        title: const Text('بلوكات', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 10.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentUser != null)
                    _buildPlayerScore(
                      _currentUser!.uid,
                      _totalScores[_currentUser!.uid] ?? 0,
                      _currentPlayerTurnId == _currentUser!.uid,
                      false, // Not winner screen
                    ),
                  if (_opponentId != null && _opponentId!.isNotEmpty)
                    _buildPlayerScore(
                      _opponentId!,
                      _totalScores[_opponentId!] ?? 0,
                      _currentPlayerTurnId == _opponentId,
                      false, // Not winner screen
                    ),
                ],
              ),
            ),
            if (_lastAnswerStatusMessage != null)
              AnimatedOpacity(
                opacity: _lastAnswerStatusMessage != null ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: _lastAnswerStatusMessage == 'جواب صحيح'
                        ? Colors.green.withOpacity(0.8)
                        : Colors.red.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _lastAnswerStatusMessage!,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            if (_currentBallIndex != -1)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(MdiIcons.timer, color: Colors.white, size: 30),
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
            Expanded(
              child: _currentBallIndex == -1
                  ? _buildQuestionBalls()
                  : _buildQuestionView(),
            ),
            // Ad Banner
            _adManager.getBannerAdWidget() ?? const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerScore(
    String userId,
    int score,
    bool isActive,
    bool isWinner,
  ) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox(width: 80, height: 120); // Placeholder size
        }
        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final username = userData['playerName'] ?? 'لاعب';
        final avatar = userData['avatarFileName'] ?? '1.png';

        final double avatarRadius = isWinner ? 60 : 40;

        return Column(
          children: [
            Container(
              decoration: isActive
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.amber, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.7),
                          blurRadius: 15,
                          spreadRadius: 3,
                        ),
                      ],
                    )
                  : null,
              child: CircleAvatar(
                radius: avatarRadius,
                backgroundColor: Colors.white24,
                child: ClipOval(
                  child: Image.asset(
                    'iconUser/$avatar',
                    fit: BoxFit.contain, // Ensures the whole image is visible
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
            ),
            const SizedBox(height: 8),
            Text(
              username,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'النقاط: $score',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuestionBalls() {
    bool isMyTurn = _currentUser?.uid == _currentPlayerTurnId;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: 10,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: isMyTurn ? () => _onBallTapped(index) : null,
          child: Container(
            decoration: BoxDecoration(
              color: _questionAnswered[index]
                  ? Colors.grey[800]
                  : const Color(0xFF8B53C6),
              borderRadius: BorderRadius.circular(15),
              border: isMyTurn && !_questionAnswered[index]
                  ? Border.all(color: Colors.amber, width: 2)
                  : null,
              boxShadow: _questionAnswered[index]
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
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
    );
  }

  Widget _buildQuestionView() {
    if (_currentBallIndex < 0 || _currentBallIndex >= _roundQuestions.length) {
      return const Center(
        child: Text('...جار التحميل', style: TextStyle(color: Colors.white)),
      );
    }

    bool isMyTurn = _currentUser?.uid == _currentPlayerTurnId;
    final question = _roundQuestions[_currentBallIndex];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_specialEffectMessage.isNotEmpty)
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
          if (isMyTurn) ...[
            TextField(
              controller: _answerController,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[800],
                hintText: 'اكتب إجابتك هنا...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () =>
                  _checkAnswer(submittedAnswer: _answerController.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade800,
                foregroundColor: Colors.white,
              ),
              child: const Text('تأكيد الجواب'),
            ),
          ] else ...[
            const Text(
              '...الخصم يجيب على السؤال',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _buildWinnerScreen() {
    int myScore = _totalScores[_currentUser!.uid] ?? 0;
    int opponentScore = _totalScores[_opponentId] ?? 0;
    bool iAmWinner = myScore > opponentScore;
    bool isTie = myScore == opponentScore;

    String winnerId = iAmWinner ? _currentUser!.uid : _opponentId!;
    String loserId = iAmWinner ? _opponentId! : _currentUser!.uid;
    int winnerScore = iAmWinner ? myScore : opponentScore;
    int loserScore = iAmWinner ? opponentScore : myScore;

    return Scaffold(
      backgroundColor: const Color(0xFF3A106C), // Darker shade for drama
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isTie ? 'تعادل!' : '🏆 الفائز 🏆',
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      blurRadius: 10.0,
                      color: Colors.amber,
                      offset: Offset(0, 0),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              if (!isTie) _buildPlayerScore(winnerId, winnerScore, true, true),
              const SizedBox(height: 30),
              if (!isTie) _buildPlayerScore(loserId, loserScore, false, false),
              if (isTie)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildPlayerScore(_currentUser!.uid, myScore, true, false),
                    _buildPlayerScore(_opponentId!, opponentScore, true, false),
                  ],
                ),
              const SizedBox(height: 60),
              ElevatedButton(
                onPressed: _navigateToHome, // Corrected navigation
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF55198B),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 50,
                    vertical: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  'العودة للرئيسية',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
