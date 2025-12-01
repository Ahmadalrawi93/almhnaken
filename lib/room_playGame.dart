import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:string_similarity/string_similarity.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'ad_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'sound_service.dart';

// A unified Question class to handle all question types from Firestore
class Question {
  final String text;
  final String image;
  final List<String> answers;

  Question({required this.text, required this.image, required this.answers});

  factory Question.fromMap(Map<String, dynamic> map) {
    // محاولة قراءة النص من حقول مختلفة لضمان التوافق
    String questionText =
        map['text'] ?? map['questionText'] ?? map['question'] ?? '';

    // محاولة قراءة الإجابات من حقول مختلفة
    final List<dynamic> arr =
        (map['correctAnswers'] ?? map['answers'] ?? []) as List<dynamic>;
    final List<String> answersList = arr.map((e) => e.toString()).toList();

    return Question(
      text: questionText,
      image: map['image'] ?? '',
      answers: answersList,
    );
  }

  Map<String, dynamic> toMap() {
    return {'text': text, 'image': image, 'answers': answers};
  }
}

// Enum to manage the current game mode within the room
enum GameMode { playerCareer, bank, blocks, finished }

// Enum for the Blocks game
enum BallType { question, twoPoints, specialQuestion }

class RoomPlayGameScreen extends StatefulWidget {
  final String roomId;
  const RoomPlayGameScreen({super.key, required this.roomId});

  @override
  State<RoomPlayGameScreen> createState() => _RoomPlayGameScreenState();
}

class _RoomPlayGameScreenState extends State<RoomPlayGameScreen> {
  final _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final AdManager _adManager = AdManager.instance;
  final _answerController = TextEditingController();

  StreamSubscription? _roomSubscription;
  GameMode _gameMode = GameMode.playerCareer;

  // --- Shared State ---
  Map<String, dynamic> _scores = {};
  List<Map<String, dynamic>> _players = [];

  // --- Player Career State ---
  Timer? _playerCareerTimer;
  final ValueNotifier<int> _playerCareerTimerValue = ValueNotifier<int>(45);
  String? _playerCareerCorrectAnswer;
  Question? _playerCareerCurrentQuestion;

  // --- Bank Game State ---
  Timer? _bankMainTimer;
  Timer? _bankRoundTimer;
  List<Question> _bankQuestions = []; // Using unified Question class
  int _bankMainTimeRemaining = 90;
  int _bankRoundTimeRemaining = 5;
  int _bankCurrentQuestionIndex = 0;
  int _bankInternalPoints = 0;
  bool _bankShowButton = false;
  String? _bankCurrentPlayerTurnId;

  // --- Blocks Game State ---
  List<Question> _blocksRoundQuestions = []; // Using unified Question class
  List<BallType> _blocksBallTypes = [];
  List<bool> _blocksQuestionAnswered = List.filled(10, false);
  String _blocksCurrentPlayerTurnId = '';
  int _blocksCurrentBallIndex = -1;
  Timer? _blocksQuestionTimer;
  int _blocksTimeRemaining = 30;
  String? _blocksLastAnswerStatus;
  Timer? _blocksStatusMessageTimer;
  String _blocksSpecialEffectMessage = '';
  IconData _blocksSpecialEffectIcon = MdiIcons.star;

  @override
  void initState() {
    super.initState();
    _loadPlayerCareerQuestionsIfNeeded(); // تحميل الأسئلة مباشرة
    _listenToRoom();
    _adManager.loadBannerAd(
      onAdLoaded: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    _answerController.dispose();
    _playerCareerTimer?.cancel();
    _playerCareerTimerValue.dispose();
    _bankMainTimer?.cancel();
    _bankRoundTimer?.cancel();
    _blocksQuestionTimer?.cancel();
    _blocksStatusMessageTimer?.cancel();
    _adManager.disposeBannerAd();
    super.dispose();
  }

  // --- Main State Listener ---
  void _listenToRoom() {
    _roomSubscription = _firestore
        .collection('rooms')
        .doc(widget.roomId)
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists || snapshot.data() == null || !mounted) {
            // If room is deleted, pop the screen
            if (mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
            return;
          }

          final roomData = snapshot.data()!;

          // التحقق من عدد اللاعبين
          final playersList = roomData['players'] as List<dynamic>?;
          if (playersList != null && playersList.length < 2) {
            // إذا كان هناك لاعب واحد فقط أو لا يوجد لاعبين، احذف الغرفة
            _firestore.collection('rooms').doc(widget.roomId).delete();
            if (mounted && Navigator.canPop(context)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('غادر الخصم! تم إلغاء المباراة'),
                  backgroundColor: Colors.orange,
                ),
              );
              Navigator.pop(context);
            }
            return;
          }

          setState(() {
            _scores = Map<String, dynamic>.from(roomData['scores'] ?? {});
            _players = List<Map<String, dynamic>>.from(
              roomData['players'] ?? [],
            );
          });

          final String gameState = roomData['gameState'] ?? 'player_career';
          GameMode newMode;
          switch (gameState) {
            case 'bank':
              newMode = GameMode.bank;
              _updateBankGameState(roomData);
              break;
            case 'blocks':
              newMode = GameMode.blocks;
              _updateBlocksGameState(roomData);
              break;
            case 'finished':
              newMode = GameMode.finished;
              _updateFinalScores();
              break;
            default: // player_career
              newMode = GameMode.playerCareer;
              _updatePlayerCareerState(roomData);
          }
          if (mounted) setState(() => _gameMode = newMode);
        });
  }

  // --- Player Career Logic ---

  Future<void> _loadPlayerCareerQuestionsIfNeeded() async {
    try {
      final roomRef = _firestore.collection('rooms').doc(widget.roomId);
      final roomDoc = await roomRef.get();
      final roomData = roomDoc.data();

      if (roomData != null &&
          (roomData['questionList'] == null ||
              roomData['questionList'].isEmpty)) {
        final questionsSnapshot = await _firestore
            .collection('footballQuestions')
            .get();

        if (questionsSnapshot.docs.isEmpty) {
          print('❌ لا توجد أسئلة في footballQuestions');
          return;
        }

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
          'correctAnswer': null,
        });

        print('✅ تم تحميل ${selectedQuestions.length} أسئلة بنجاح');
      }
    } catch (e) {
      print('❌ خطأ في تحميل الأسئلة: $e');
    }
  }

  Future<void> _fetchAndSetPlayerCareerQuestions() async {
    try {
      final roomRef = _firestore.collection('rooms').doc(widget.roomId);

      final roomDoc = await roomRef.get();
      if (roomDoc.exists && roomDoc.data()?['questionList'] != null) {
        // إذا كانت الأسئلة موجودة بالفعل، نحدث الحالة فقط
        print('✅ الأسئلة موجودة بالفعل في الغرفة');
        return;
      }

      print('🔄 جاري تحميل أسئلة جديدة من footballQuestions...');
      final snapshot = await _firestore.collection('footballQuestions').get();

      if (snapshot.docs.isEmpty) {
        print('❌ لا توجد أسئلة في footballQuestions!');
        return;
      }

      print('📚 تم العثور على ${snapshot.docs.length} سؤال');

      final allQuestions = snapshot.docs.map((doc) {
        final data = doc.data();
        print('📄 بيانات السؤال: $data');
        return Question.fromMap(data);
      }).toList();
      allQuestions.shuffle();

      final selectedQuestions = allQuestions.take(5).toList();

      final List<Map<String, dynamic>> questionListForFirestore = [];
      for (int i = 0; i < selectedQuestions.length; i++) {
        final questionMap = selectedQuestions[i].toMap();
        questionMap['order'] = i;
        questionListForFirestore.add(questionMap);
        print('➕ إضافة سؤال $i: ${questionMap['text']}');
      }

      await roomRef.update({
        'questionList': questionListForFirestore,
        'currentQuestionIndex': 0,
        'correctAnswer': null,
      });

      print('✅ تم حفظ ${questionListForFirestore.length} سؤال في الغرفة');
    } catch (e) {
      print('❌ خطأ في تحميل الأسئلة: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل في تحميل أسئلة مسيرة لاعب.')),
        );
      }
    }
  }

  void _updatePlayerCareerState(Map<String, dynamic> roomData) {
    final questions = roomData['questionList'] as List<dynamic>?;

    if (questions == null || questions.isEmpty) {
      // تحميل الأسئلة إذا لم تكن موجودة
      if (_players.isNotEmpty && _players[0]['uid'] == _currentUser!.uid) {
        _fetchAndSetPlayerCareerQuestions();
      }
      // لا نعيّن _playerCareerCurrentQuestion = null هنا
      // لأننا نريد الاحتفاظ بالسؤال الحالي أثناء التحميل
      return;
    }

    // ترتيب الأسئلة حسب order
    if (questions != null) {
      questions.sort(
        (a, b) => (a['order'] as int).compareTo(b['order'] as int),
      );
    }

    final correctAnswer = roomData['correctAnswer'] as String?;
    final questionIndex = roomData['currentQuestionIndex'] as int? ?? 0;

    if (questionIndex < questions.length) {
      final questionData = questions[questionIndex];
      final newQuestion = Question.fromMap(questionData);

      if (mounted) {
        setState(() {
          _playerCareerCurrentQuestion = newQuestion;
        });
      }
    }

    if (mounted) {
      setState(() => _playerCareerCorrectAnswer = correctAnswer);
    }

    if (correctAnswer == null) {
      if (_playerCareerTimer == null || !_playerCareerTimer!.isActive) {
        _startPlayerCareerTimer(45);
      }
    } else {
      _playerCareerTimer?.cancel();
      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          _nextPlayerCareerQuestion();
        }
      });
    }
  }

  void _startPlayerCareerTimer(int seconds) {
    _playerCareerTimer?.cancel();
    _playerCareerTimerValue.value = seconds;
    _playerCareerTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      if (_playerCareerTimerValue.value > 0) {
        _playerCareerTimerValue.value--;
      } else {
        timer.cancel();
        _nextPlayerCareerQuestion();
      }
    });
  }

  Future<void> _submitPlayerCareerAnswer() async {
    if (_currentUser == null ||
        _playerCareerCorrectAnswer != null ||
        _playerCareerCurrentQuestion == null) {
      return;
    }
    final userAnswer = _answerController.text.trim();
    if (userAnswer.isEmpty) return;

    final isCorrect = _playerCareerCurrentQuestion!.answers.any(
      (ans) => userAnswer.similarityTo(ans.toLowerCase()) >= 0.8,
    );

    if (isCorrect) {
      _playerCareerTimer?.cancel();
      _answerController.clear();
      await _firestore.collection('rooms').doc(widget.roomId).update({
        'scores.${_currentUser!.uid}': FieldValue.increment(1),
        'correctAnswer': _playerCareerCurrentQuestion!.answers.first,
      });
    }
  }

  Future<void> _nextPlayerCareerQuestion() async {
    final roomRef = _firestore.collection('rooms').doc(widget.roomId);
    final roomDoc = await roomRef.get();
    if (!roomDoc.exists) return;

    final currentQuestionIndex =
        roomDoc.data()?['currentQuestionIndex'] as int? ?? 0;
    if (currentQuestionIndex + 1 >= 5) {
      await _initializeBankGame();
    } else {
      await roomRef.update({
        'correctAnswer': null,
        'currentQuestionIndex': FieldValue.increment(1),
      });
    }
  }

  // --- Bank Game Logic ---
  Future<void> _initializeBankGame() async {
    _playerCareerTimer?.cancel();
    await _firestore.collection('rooms').doc(widget.roomId).update({
      'gameState': 'bank',
      'bank_playerTurnIndex': 0,
      'bank_mainTimeRemaining': 90,
      'bank_isRoundOver': false,
    });
  }

  void _updateBankGameState(Map<String, dynamic> roomData) async {
    if (_bankQuestions.isEmpty) {
      try {
        final questionsSnapshot = await _firestore
            .collection('bankQuestions')
            .get();
        if (questionsSnapshot.docs.isEmpty) {
          print('❌ لا توجد أسئلة في bankQuestions');
          return;
        }
        if (mounted) {
          setState(() {
            _bankQuestions =
                questionsSnapshot.docs
                    .map((doc) => Question.fromMap(doc.data()))
                    .toList()
                  ..shuffle();
          });
          print('✅ تم تحميل ${_bankQuestions.length} سؤال للبنك');
        }
      } catch (e) {
        print('❌ خطأ في تحميل أسئلة البنك: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('فشل في تحميل أسئلة البنك')),
          );
        }
        return;
      }
    }
    setState(() {
      final playerTurnIndex = roomData['bank_playerTurnIndex'] as int? ?? 0;
      if (_players.isNotEmpty && playerTurnIndex < _players.length) {
        final newPlayerTurnId = _players[playerTurnIndex]['uid'];
        if (_bankCurrentPlayerTurnId != newPlayerTurnId) {
          _bankCurrentPlayerTurnId = newPlayerTurnId;
          
          // تشغيل صوت تنبيه بداية الدور الجديد
          if (_bankCurrentPlayerTurnId == _currentUser?.uid) {
            SoundService().playTurnNotification();
          }
        }
      }
      if (roomData['bank_isRoundOver'] == true) _endBankGame();
      _bankMainTimeRemaining = roomData['bank_mainTimeRemaining'] as int? ?? 90;
    });
    if (_bankCurrentPlayerTurnId == _currentUser!.uid) {
      if (_bankMainTimer == null || !_bankMainTimer!.isActive) {
        _startBankMainTimer();
      }
    } else {
      _bankMainTimer?.cancel();
      _bankMainTimer = null;
    }
  }

  void _startBankMainTimer() {
    _bankMainTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_bankMainTimeRemaining > 0) {
        if (mounted) setState(() => _bankMainTimeRemaining--);
        await _firestore.collection('rooms').doc(widget.roomId).update({
          'bank_mainTimeRemaining': _bankMainTimeRemaining,
        });
      } else {
        _endBankTurn();
      }
    });
  }

  Future<void> _endBankTurn() async {
    _bankMainTimer?.cancel();
    _bankRoundTimer?.cancel();
    setState(() {
      _bankInternalPoints = 0;
      _bankShowButton = false;
    });
    final roomRef = _firestore.collection('rooms').doc(widget.roomId);
    final roomDoc = await roomRef.get();
    final playerTurnIndex =
        roomDoc.data()?['bank_playerTurnIndex'] as int? ?? 0;
    if (playerTurnIndex + 1 >= _players.length) {
      await roomRef.update({'bank_isRoundOver': true});
    } else {
      await roomRef.update({
        'bank_playerTurnIndex': FieldValue.increment(1),
        'bank_mainTimeRemaining': 90,
      });
      
      // تشغيل صوت تنبيه انتهاء الدور
      SoundService().playTurnNotification();
    }
  }

  void _endBankGame() {
    _bankMainTimer?.cancel();
    _bankRoundTimer?.cancel();
    _initializeBlocksGame();
  }

  Future<void> _checkBankAnswer() async {
    if (_currentUser!.uid != _bankCurrentPlayerTurnId) return;
    String userAnswer = _answerController.text.trim().toLowerCase();
    List<String> correctAnswers = _bankQuestions[_bankCurrentQuestionIndex]
        .answers
        .map((e) => e.toLowerCase())
        .toList();
    _answerController.clear();
    bool isCorrect = correctAnswers.any(
      (ans) => userAnswer.similarityTo(ans) >= 0.7,
    );
    _bankRoundTimer?.cancel();
    _bankShowButton = false;
    if (isCorrect) {
      setState(() {
        _bankInternalPoints = _bankInternalPoints == 0
            ? 2
            : _bankInternalPoints * 2;
        _bankShowButton = true;
      });
      _startBankRoundTimer();
    } else {
      setState(() => _bankInternalPoints = 0);
      _goToNextBankQuestion();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('إجابة خاطئة! نقاط البنك حذفت.')),
      );
    }
  }

  void _startBankRoundTimer() {
    _bankRoundTimer?.cancel();
    _bankRoundTimeRemaining = 5;
    _bankRoundTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_bankRoundTimeRemaining > 0) {
        if (mounted) setState(() => _bankRoundTimeRemaining--);
      } else {
        _goToNextBankQuestion();
      }
    });
  }

  Future<void> _bankPoints() async {
    _bankRoundTimer?.cancel();
    if (_bankInternalPoints > 0) {
      await _firestore.collection('rooms').doc(widget.roomId).update({
        'scores.${_currentUser!.uid}': FieldValue.increment(
          _bankInternalPoints,
        ),
      });
    }
    setState(() {
      _bankInternalPoints = 0;
      _bankShowButton = false;
    });
    _goToNextBankQuestion();
  }

  void _goToNextBankQuestion() {
    _bankRoundTimer?.cancel();
    setState(() {
      _bankShowButton = false;
      _answerController.clear();
      _bankCurrentQuestionIndex++;
      if (_bankCurrentQuestionIndex >= _bankQuestions.length) {
        _bankCurrentQuestionIndex = 0;
        _bankQuestions.shuffle();
      }
    });
  }

  // --- Blocks Game Logic ---
  Future<void> _initializeBlocksGame() async {
    try {
      final questionsSnapshot = await _firestore
          .collection('onlinePlayerQuestions')
          .get();
      if (questionsSnapshot.docs.isEmpty) {
        print("No questions found in onlinePlayerQuestions.");
        return;
      }
      final allQuestions = questionsSnapshot.docs
          .map((doc) => Question.fromMap(doc.data()))
          .toList();

      allQuestions.shuffle(Random());
      final roundQuestions = allQuestions.take(10).toList();

      if (roundQuestions.length < 10) {
        print("Warning: Not enough questions to start blocks game.");
        return;
      }

      final ballTypes = List.filled(10, BallType.question);
      final random = Random();
      final indices = List.generate(10, (i) => i)..shuffle(random);
      ballTypes[indices[0]] = BallType.twoPoints;
      ballTypes[indices[1]] = BallType.specialQuestion;

      await _firestore.collection('rooms').doc(widget.roomId).update({
        'gameState': 'blocks',
        'blocks_roundQuestions': roundQuestions.map((q) => q.toMap()).toList(),
        'blocks_ballTypes': ballTypes.map((b) => b.index).toList(),
        'blocks_questionAnswered': List.filled(10, false),
        'blocks_playerTurnIndex': 0,
        'blocks_currentBallIndex': -1,
        'blocks_timeRemaining': 30,
        'lastAnswerStatus': null,
      });
    } catch (e) {
      print("Error initializing blocks game: $e");
    }
  }

  void _updateBlocksGameState(Map<String, dynamic> roomData) {
    if (roomData['blocks_roundQuestions'] == null) return;
    final newQuestionAnswered =
        (roomData['blocks_questionAnswered'] as List<dynamic>)
            .map((a) => a as bool)
            .toList();
    if (newQuestionAnswered.every((a) => a)) {
      _firestore.collection('rooms').doc(widget.roomId).update({
        'gameState': 'finished',
      });
      return;
    }
    setState(() {
      final playerTurnIndex = roomData['blocks_playerTurnIndex'] as int? ?? 0;
      if (_players.isNotEmpty && playerTurnIndex < _players.length) {
        final newPlayerTurnId = _players[playerTurnIndex]['uid'];
        if (_blocksCurrentPlayerTurnId != newPlayerTurnId) {
          _blocksCurrentPlayerTurnId = newPlayerTurnId;
          
          // تشغيل صوت تنبيه بداية الدور الجديد
          if (_blocksCurrentPlayerTurnId == _currentUser?.uid) {
            SoundService().playTurnNotification();
          }
        }
      }
      _blocksRoundQuestions =
          (roomData['blocks_roundQuestions'] as List<dynamic>)
              .map((q) => Question.fromMap(q)) // Use unified Question class
              .toList();
      _blocksBallTypes = (roomData['blocks_ballTypes'] as List<dynamic>)
          .map((b) => BallType.values[b as int])
          .toList();
      _blocksQuestionAnswered = newQuestionAnswered;
      _blocksCurrentBallIndex =
          roomData['blocks_currentBallIndex'] as int? ?? -1;
      _blocksTimeRemaining = roomData['blocks_timeRemaining'] as int? ?? 30;

      // تحديث رسالة التأثير الخاص
      _setBlocksSpecialEffectMessage();

      final lastStatus = roomData['lastAnswerStatus'] as String?;
      if (lastStatus != null) {
        setState(() {
          _blocksLastAnswerStatus = lastStatus;
        });
        _firestore.collection('rooms').doc(widget.roomId).update({
          'lastAnswerStatus': null,
        });
        _blocksStatusMessageTimer?.cancel();
        _blocksStatusMessageTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _blocksLastAnswerStatus = null;
            });
          }
        });
      }
    });
    if (_currentUser?.uid == _blocksCurrentPlayerTurnId &&
        _blocksCurrentBallIndex != -1) {
      if (_blocksQuestionTimer == null || !_blocksQuestionTimer!.isActive) {
        _startBlocksQuestionTimer();
      }
    } else {
      _blocksQuestionTimer?.cancel();
    }
  }

  void _startBlocksQuestionTimer() {
    _blocksQuestionTimer?.cancel();
    _blocksQuestionTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_blocksTimeRemaining > 0) {
        if (_currentUser?.uid == _blocksCurrentPlayerTurnId) {
          final newTime = _blocksTimeRemaining - 1;
          if (mounted) {
            setState(() {
              _blocksTimeRemaining = newTime;
            });
          }
          await _firestore.collection('rooms').doc(widget.roomId).update({
            'blocks_timeRemaining': newTime,
          });
        }
      } else {
        timer.cancel();
        if (_currentUser?.uid == _blocksCurrentPlayerTurnId) {
          await _checkBlocksAnswer(submittedAnswer: '');
        }
      }
    });
  }

  void _onBallTapped(int index) {
    if (_currentUser!.uid != _blocksCurrentPlayerTurnId ||
        _blocksQuestionAnswered[index]) {
      return;
    }
    _firestore.collection('rooms').doc(widget.roomId).update({
      'blocks_currentBallIndex': index,
      'blocks_timeRemaining': 30,
    });
  }

  void _setBlocksSpecialEffectMessage() {
    if (_blocksCurrentBallIndex == -1) {
      _blocksSpecialEffectMessage = '';
      return;
    }
    final type = _blocksBallTypes[_blocksCurrentBallIndex];
    if (type == BallType.twoPoints) {
      _blocksSpecialEffectMessage = 'سؤال بنقطتين!';
      _blocksSpecialEffectIcon = MdiIcons.starCircle;
    } else if (type == BallType.specialQuestion) {
      _blocksSpecialEffectMessage = 'وكّع صاحبك!';
      _blocksSpecialEffectIcon = MdiIcons.swordCross;
    } else {
      _blocksSpecialEffectMessage = '';
      _blocksSpecialEffectIcon = MdiIcons.star;
    }
  }

  Future<void> _checkBlocksAnswer({required String submittedAnswer}) async {
    _blocksQuestionTimer?.cancel();
    if (_blocksCurrentBallIndex == -1) return;
    final question = _blocksRoundQuestions[_blocksCurrentBallIndex];
    final ballType = _blocksBallTypes[_blocksCurrentBallIndex];
    final isCorrect = question.answers.any(
      (ans) =>
          submittedAnswer.trim().toLowerCase().similarityTo(
            ans.toLowerCase(),
          ) >=
          0.8,
    );
    int myPointsChange = 0, opponentPointsChange = 0;
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
        (_players.indexWhere((p) => p['uid'] == _blocksCurrentPlayerTurnId) +
            1) %
        _players.length;
    var newAnsweredState = List<bool>.from(_blocksQuestionAnswered);
    newAnsweredState[_blocksCurrentBallIndex] = true;
    final opponentId = _players.firstWhere(
      (p) => p['uid'] != _currentUser!.uid,
    )['uid'];
    await _firestore.collection('rooms').doc(widget.roomId).update({
      'scores.${_currentUser!.uid}': FieldValue.increment(myPointsChange),
      if (opponentPointsChange != 0)
        'scores.$opponentId': FieldValue.increment(opponentPointsChange),
      'blocks_currentBallIndex': -1,
      'blocks_playerTurnIndex': nextTurnIndex,
      'blocks_questionAnswered': newAnsweredState,
      'lastAnswerStatus': isCorrect ? 'جواب صحيح' : 'جواب خطأ',
    });
    
    // تشغيل صوت تنبيه انتهاء الدور
    SoundService().playTurnNotification();
  }

  // --- Final Score Logic ---
  Future<void> _updateFinalScores() async {
    final roomRef = _firestore.collection('rooms').doc(widget.roomId);
    final roomDoc = await roomRef.get();
    if (roomDoc.exists && !(roomDoc.data()?['pointsAwarded'] ?? false)) {
      final scores = Map<String, dynamic>.from(roomDoc.data()?['scores'] ?? {});
      final WriteBatch batch = _firestore.batch();
      for (final playerId in scores.keys) {
        final scoreFromGame = scores[playerId] ?? 0;
        if (scoreFromGame > 0) {
          final userRef = _firestore.collection('users').doc(playerId);
          batch.update(userRef, {
            'points': FieldValue.increment(scoreFromGame),
          });
        }
      }
      batch.update(roomRef, {'pointsAwarded': true});
      await batch.commit();
    }
  }

  // --- Back Press Logic ---
  Future<void> _onBackPressed() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الخروج من اللعبة'),
        content: const Text(
          'هل أنت متأكد أنك تريد الخروج؟ سيتم حذف الغرفة وإنهاء اللعبة للجميع.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('البقاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('الخروج'),
          ),
        ],
      ),
    );

    if (shouldLeave ?? false) {
      // Stop all timers before leaving
      _playerCareerTimer?.cancel();
      _bankMainTimer?.cancel();
      _bankRoundTimer?.cancel();
      _blocksQuestionTimer?.cancel();
      _blocksStatusMessageTimer?.cancel();

      await _firestore.collection('rooms').doc(widget.roomId).delete();
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  // --- UI Build Logic ---
  @override
  Widget build(BuildContext context) {
    Widget content;
    switch (_gameMode) {
      case GameMode.playerCareer:
        content = _buildPlayerCareerUI();
        break;
      case GameMode.bank:
        content = _buildBankUI();
        break;
      case GameMode.blocks:
        content = _buildBlocksUI();
        break;
      case GameMode.finished:
        content = _buildWinnerScreen();
        break;
    }
    return WillPopScope(
      onWillPop: () async {
        await _onBackPressed();
        return false;
      },
      child: content,
    );
  }

  Widget _buildPlayerPanel(
    Map<String, dynamic> player, {
    bool isActive = false,
    bool isWinner = false,
  }) {
    if (player.isEmpty) return const SizedBox.shrink();
    final score = _scores[player['uid']] ?? 0;
    final username = player['playerName'] ?? 'لاعب';
    // دعم كلا الحقلين: avatarImage و avatarFileName
    final avatarFileName =
        (player['avatarImage'] ?? player['avatarFileName']) as String?;
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
              child: avatarFileName != null && avatarFileName.isNotEmpty
                  ? Image.asset(
                      'iconUser/$avatarFileName',
                      fit: BoxFit.contain,
                      width: avatarRadius * 2,
                      height: avatarRadius * 2,
                      errorBuilder: (c, o, s) => Icon(
                        Icons.person,
                        size: avatarRadius,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.person, size: avatarRadius, color: Colors.white),
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
  }

  Widget _buildPlayerCareerUI() {
    if (_currentUser == null || _players.length < 2) {
      return const Scaffold(
        backgroundColor: Color(0xFF55198B),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    final currentPlayerMap = _players.firstWhere(
      (p) => p['uid'] == _currentUser!.uid,
      orElse: () => {},
    );
    final otherPlayerMap = _players.firstWhere(
      (p) => p['uid'] != _currentUser!.uid,
      orElse: () => {},
    );
    final isAnswerCorrectlyGiven = _playerCareerCorrectAnswer != null;
    return Scaffold(
      backgroundColor: const Color(0xFF55198B),
      appBar: AppBar(
        title: const Text('مسيرة لاعب', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(MdiIcons.arrowLeft, color: Colors.white),
          onPressed: _onBackPressed,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: _buildPlayerPanel(currentPlayerMap)),
                Expanded(child: _buildPlayerPanel(otherPlayerMap)),
              ],
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<int>(
              valueListenable: _playerCareerTimerValue,
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
                    if (_playerCareerCurrentQuestion != null &&
                        _playerCareerCurrentQuestion!.image.isNotEmpty) ...[
                      Builder(
                        builder: (context) {
                          final imagePath = _playerCareerCurrentQuestion!.image;
                          Widget imageWidget;

                          if (imagePath.startsWith('http')) {
                            imageWidget = CachedNetworkImage(
                              imageUrl: imagePath,
                              height: MediaQuery.of(context).size.height * 0.3,
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
                              height: MediaQuery.of(context).size.height * 0.3,
                              fit: BoxFit.contain,
                              placeholder: (context, url) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.error),
                            );
                          } else {
                            imageWidget = SizedBox(
                              height: MediaQuery.of(context).size.height * 0.3,
                            );
                          }
                          return imageWidget;
                        },
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      _playerCareerCurrentQuestion?.text ??
                          'جاري تحميل السؤال...',
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
                          'الجواب الصحيح: $_playerCareerCorrectAnswer',
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
                  onPressed: _submitPlayerCareerAnswer,
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
      ),
    );
  }

  Widget _buildBankUI() {
    final bool isMyTurn = _currentUser?.uid == _bankCurrentPlayerTurnId;

    return Scaffold(
      backgroundColor: const Color(0xFF55198B),
      appBar: AppBar(
        title: const Text('البنك', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(MdiIcons.arrowLeft, color: Colors.white),
          onPressed: _onBackPressed,
        ),
      ),
      body: _bankQuestions.isEmpty
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
                            _players.firstWhere(
                              (p) => p['uid'] == _currentUser!.uid,
                            ),
                            isActive: isMyTurn,
                          ),
                          _buildPlayerPanel(
                            _players.firstWhere(
                              (p) => p['uid'] != _currentUser!.uid,
                            ),
                            isActive: !isMyTurn,
                          ),
                        ],
                      ),
                    const SizedBox(height: 50),
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
                              'المجموع: ${_scores[_currentUser?.uid] ?? 0}',
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
                              'نقاط البنك: $_bankInternalPoints',
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
                                '$_bankMainTimeRemaining',
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
                      if (_bankQuestions.isNotEmpty)
                        Text(
                          _bankQuestions[_bankCurrentQuestionIndex].text,
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
                        onSubmitted: (_) => _checkBankAnswer(),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _checkBankAnswer,
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
                      if (_bankShowButton)
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
                          child: Text('بنك ($_bankRoundTimeRemaining)'),
                        ),
                    ] else ...[
                      const Center(
                        child: Text(
                          'الخصم في دور الإجابة...',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBlocksUI() {
    return Scaffold(
      backgroundColor: const Color(0xFF55198B),
      appBar: AppBar(
        title: const Text('بلوكات', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(MdiIcons.arrowLeft, color: Colors.white),
          onPressed: _onBackPressed,
        ),
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
                  if (_players.length >= 2) ...[
                    _buildPlayerPanel(
                      _players.firstWhere((p) => p['uid'] == _currentUser!.uid),
                      isActive: _blocksCurrentPlayerTurnId == _currentUser!.uid,
                    ),
                    _buildPlayerPanel(
                      _players.firstWhere((p) => p['uid'] != _currentUser!.uid),
                      isActive: _blocksCurrentPlayerTurnId != _currentUser!.uid,
                    ),
                  ],
                ],
              ),
            ),
            if (_blocksLastAnswerStatus != null)
              AnimatedOpacity(
                opacity: _blocksLastAnswerStatus != null ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: _blocksLastAnswerStatus == 'جواب صحيح'
                        ? Colors.green.withOpacity(0.8)
                        : Colors.red.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _blocksLastAnswerStatus!,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            if (_blocksCurrentBallIndex != -1)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(MdiIcons.timer, color: Colors.white, size: 30),
                    const SizedBox(width: 8),
                    Text(
                      '$_blocksTimeRemaining',
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
              child: _blocksCurrentBallIndex == -1
                  ? _buildBlocksQuestionBalls()
                  : _buildBlocksQuestionView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlocksQuestionBalls() {
    bool isMyTurn = _currentUser?.uid == _blocksCurrentPlayerTurnId;
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
              color: _blocksQuestionAnswered[index]
                  ? Colors.grey[800]
                  : const Color(0xFF8B53C6),
              borderRadius: BorderRadius.circular(15),
              border: isMyTurn && !_blocksQuestionAnswered[index]
                  ? Border.all(color: Colors.amber, width: 2)
                  : null,
              boxShadow: _blocksQuestionAnswered[index]
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 5,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: Center(
              child: Text(
                _blocksQuestionAnswered[index] ? '✓' : '${index + 1}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _blocksQuestionAnswered[index] ? 30 : 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBlocksQuestionView() {
    if (_blocksCurrentBallIndex < 0 ||
        _blocksCurrentBallIndex >= _blocksRoundQuestions.length) {
      return const Center(
        child: Text('...جار التحميل', style: TextStyle(color: Colors.white)),
      );
    }

    bool isMyTurn = _currentUser?.uid == _blocksCurrentPlayerTurnId;
    final question = _blocksRoundQuestions[_blocksCurrentBallIndex];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_blocksSpecialEffectMessage.isNotEmpty)
            Column(
              children: [
                Icon(_blocksSpecialEffectIcon, size: 50, color: Colors.amber),
                const SizedBox(height: 10),
                Text(
                  _blocksSpecialEffectMessage,
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
            question.text,
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
                  _checkBlocksAnswer(submittedAnswer: _answerController.text),
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
    // الحصول على معرف الخصم
    final opponentPlayer = _players.firstWhere(
      (p) => p['uid'] != _currentUser!.uid,
      orElse: () => {},
    );
    final opponentId = opponentPlayer['uid'] as String?;

    int myScore = _scores[_currentUser!.uid] ?? 0;
    int opponentScore = opponentId != null ? (_scores[opponentId] ?? 0) : 0;
    bool iAmWinner = myScore > opponentScore;
    bool isTie = myScore == opponentScore;

    String winnerId = iAmWinner ? _currentUser!.uid : (opponentId ?? '');
    String loserId = iAmWinner ? (opponentId ?? '') : _currentUser!.uid;
    int winnerScore = iAmWinner ? myScore : opponentScore;
    int loserScore = iAmWinner ? opponentScore : myScore;

    return Scaffold(
      backgroundColor: const Color(0xFF3A106C),
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
              if (!isTie && winnerId.isNotEmpty)
                _buildWinnerPlayerPanel(winnerId, winnerScore, true),
              const SizedBox(height: 30),
              if (!isTie && loserId.isNotEmpty)
                _buildWinnerPlayerPanel(loserId, loserScore, false),
              if (isTie)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (_currentUser != null)
                      _buildWinnerPlayerPanel(
                        _currentUser!.uid,
                        myScore,
                        false,
                      ),
                    if (opponentId != null)
                      _buildWinnerPlayerPanel(opponentId, opponentScore, false),
                  ],
                ),
              const SizedBox(height: 60),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
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

  Widget _buildWinnerPlayerPanel(String userId, int score, bool isWinner) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox(width: 80, height: 120); // Placeholder size
        }
        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final username = userData['playerName'] ?? 'لاعب';
        // دعم كلا الحقلين: avatarImage (من التسجيل) و avatarFileName (من الملف الشخصي)
        final avatar =
            userData['avatarImage'] ?? userData['avatarFileName'] ?? '1.png';

        final double avatarRadius = isWinner ? 60 : 40;

        return Column(
          children: [
            Container(
              decoration: isWinner
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
}
