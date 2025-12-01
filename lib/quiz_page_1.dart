// File: quiz_page_1.dart
// صوت المعلق
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:string_similarity/string_similarity.dart'; // ✅ تم إضافة هذا الاستيراد
import 'package:cloud_firestore/cloud_firestore.dart';
import 'points_provider.dart';
import 'quiz_state_provider.dart';
import 'ad_manager.dart'; // Import the ad manager
import 'package:cached_network_image/cached_network_image.dart';
import 'video_service.dart';

// نموذج بيانات لأسئلة "صوت المعلق" القادمة من قاعدة البيانات
class VideoQuestion {
  final String questionText;
  final String imagePath; // يمكن أن يكون مسار أصل أو رابط كامل
  final String videoPath; // يمكن أن يكون مسار أصل أو رابط كامل
  final List<String> answers;

  const VideoQuestion({
    required this.questionText,
    required this.imagePath,
    required this.videoPath,
    required this.answers,
  });

  factory VideoQuestion.fromMap(Map<String, dynamic> map) {
    final List<dynamic> rawAnswers = (map['answers'] ?? []) as List<dynamic>;
    return VideoQuestion(
      questionText: (map['questionText'] ?? '').toString(),
      imagePath: (map['imagePath'] ?? '').toString(),
      videoPath: (map['videoPath'] ?? '').toString(),
      answers: rawAnswers.map((e) => e.toString()).toList(),
    );
  }
}

class QuizPage1 extends StatefulWidget {
  const QuizPage1({super.key});

  @override
  _QuizPage1State createState() => _QuizPage1State();
}

class _QuizPage1State extends State<QuizPage1> {
  final VideoService _videoService = VideoService();
  VideoPlayerController? _controller;
  final TextEditingController _answerController = TextEditingController();
  List<VideoQuestion> _questions = [];

  bool _isBlocked = false;
  bool _isPlaying = false;
  bool _isAnsweredCorrectly = false;
  Timer? _timer;
  int _remainingTime = 30;
  DateTime? _blockedStartTime;
  int _incorrectAnswerCount = 0; // Counter for incorrect answers
  bool _showRevealButton = false; // Add this line
  bool _answerWasRevealed = false; // To track if the answer was revealed by ad
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
    AdManager.instance.loadInterstitialAd(); // Load the ad
    AdManager.instance.loadRewardedAd(); // Add this line
  }

  Future<void> _fetchQuestions() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('videoQuestions')
          .get();
      final loaded = snapshot.docs
          .map((doc) => VideoQuestion.fromMap(doc.data()))
          .toList();
      if (!mounted) return;
      setState(() {
        _questions = loaded;
        _isLoading = false;
      });
      if (_questions.isNotEmpty) {
        await _initControllerForCurrentQuestion();
      }
      await _loadBlockedState();
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

  Future<void> _initControllerForCurrentQuestion() async {
    final quizStateProvider = Provider.of<QuizStateProvider>(
      context,
      listen: false,
    );

    if (_questions.isEmpty) return;
    if (quizStateProvider.currentQuestionIndex >= _questions.length) {
      quizStateProvider.resetState();
    }

    final currentQuestion = _questions[quizStateProvider.currentQuestionIndex];
    final String path = currentQuestion.videoPath;
    VideoPlayerController controller;

    final videoId = _videoService.convertToVideoId(path);

    if (videoId != null) {
      // It's a YouTube URL, get the stream URL
      try {
        // Set a loading state for the controller
        if (mounted) setState(() {});
        final streamUrl = await _videoService.getStreamUrl(videoId);
        controller = VideoPlayerController.networkUrl(Uri.parse(streamUrl));
      } catch (e) {
        // Handle error if stream URL can't be fetched
        print('Could not get video stream: $e');
        // Fallback to a dummy controller or show an error
        // You should have an error video in your assets
        controller = VideoPlayerController.asset('videos/error.mp4');
      }
    } else if (path.startsWith('http')) {
      // It's another network URL (non-YouTube)
      controller = VideoPlayerController.networkUrl(Uri.parse(path));
    } else {
      // It's a local asset
      controller = VideoPlayerController.asset(path);
    }

    // تخلص من أي متحكم سابق
    await _controller?.dispose();
    _controller = controller;
    try {
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      print("Error initializing video controller: $e");
    }
  }

  Future<void> _loadBlockedState() async {
    final prefs = await SharedPreferences.getInstance();
    final blockedStartTime = prefs.getInt('quiz_blockedStartTime');
    if (blockedStartTime != null) {
      _blockedStartTime = DateTime.fromMillisecondsSinceEpoch(blockedStartTime);
      final elapsed = DateTime.now().difference(_blockedStartTime!).inSeconds;
      if (elapsed < 60) { // Changed from 30 to 60
        setState(() {
          _isBlocked = true;
          _remainingTime = 60 - elapsed; // Changed from 30 to 60
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
    _controller?.dispose();
    _answerController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      setState(() {
        _isPlaying = false;
      });
    } else {
      _controller!.play();
      setState(() {
        _isPlaying = true;
      });
    }
  }

  // ✅ تم تغيير هذه الدالة بالكامل لتشمل منطق التصحيح الإملائي
  void _checkAnswer() async {
    final quizStateProvider =
        Provider.of<QuizStateProvider>(context, listen: false);
    String userAnswer = _answerController.text.trim().toLowerCase();
    List<String> correctAnswers =
        _questions[quizStateProvider.currentQuestionIndex]
            .answers
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
      if (_controller != null && _controller!.value.isInitialized) {
        _controller!.play();
      }
      setState(() {
        _isAnsweredCorrectly = true;
      });
    } else {
      _incorrectAnswerCount++;
      quizStateProvider.loseLife();

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('إجابة خاطئة!')));

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
    _timer?.cancel();
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

  void _showRevealAd() {
    AdManager.instance.showRewardedAd(
      onAdRewarded: (reward) {
        setState(() {
          _isAnsweredCorrectly = true;
          _showRevealButton = false;
          _answerWasRevealed = true; // Mark answer as revealed
          _controller?.play();
        });
      },
      onAdFailed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل تحميل الإعلان، حاول مرة أخرى.')),
        );
      },
    );
  }

  void _goToNextQuestion() {
    final quizStateProvider =
        Provider.of<QuizStateProvider>(context, listen: false);

    // Add points only if the answer was not revealed
    if (!_answerWasRevealed) {
      Provider.of<PointsProvider>(context, listen: false).addPoints(3);
    }

    if (_questions.isNotEmpty &&
        quizStateProvider.currentQuestionIndex < _questions.length - 1) {
      quizStateProvider.nextQuestion();
      _answerController.clear();
      _isBlocked = false;
      _isPlaying = false;
      _isAnsweredCorrectly = false;
      _incorrectAnswerCount = 0;
      _showRevealButton = false;
      _answerWasRevealed = false; // Reset for the next question
      _initControllerForCurrentQuestion();
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
    final VideoQuestion? currentQuestion = hasQuestion
        ? _questions[quizStateProvider.currentQuestionIndex]
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF55198B),
      appBar: AppBar(
        title: const Text('صوت المعلق', style: TextStyle(color: Colors.white)),
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
                    SizedBox(
                      height: 250,
                      width: 250,
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          // الصورة تظهر عندما تكون الإجابة خاطئة
                          if (!_isAnsweredCorrectly) ...[
                            CachedNetworkImage(
                              imageUrl: 'https://raw.githubusercontent.com/Ahmadalrawi93/almhnaken-assets/main/images/voice.png',
                              height: 250,
                              width: 250,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                              errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white),
                            )
                          ],
                          // الفيديو يظهر فقط عند الإجابة الصحيحة
                          if (_isAnsweredCorrectly &&
                              _controller != null &&
                              _controller!.value.isInitialized)
                            AspectRatio(
                              aspectRatio: _controller!.value.aspectRatio,
                              child: VideoPlayer(_controller!),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // زر التشغيل يبقى منفصلاً لتشغيل الصوت فقط
                    IconButton(
                      icon: Icon(
                        _isPlaying ? MdiIcons.pauseCircle : MdiIcons.playCircle,
                        color: Colors.white,
                        size: 50,
                      ),
                      onPressed: _togglePlayPause,
                    ),
                    const SizedBox(height: 20),
                    if (currentQuestion != null)
                      Text(
                        currentQuestion.questionText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(height: 10),
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
                    if (_isAnsweredCorrectly)
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
                      )
                    else
                      ElevatedButton(
                        onPressed: _isBlocked ? null : _checkAnswer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _isBlocked ? Colors.grey : Colors.white,
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
                                color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}