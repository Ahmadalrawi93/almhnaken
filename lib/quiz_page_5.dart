import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:string_similarity/string_similarity.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'top5_quiz.dart';
import 'points_provider.dart';
import 'ad_manager.dart';
import 'firebase_notification_service.dart';

class QuizPage5 extends StatefulWidget {
  const QuizPage5({super.key});

  @override
  State<QuizPage5> createState() => _QuizPage5State();
}

class _QuizPage5State extends State<QuizPage5> {
  final TextEditingController _answerController = TextEditingController();
  final AdManager _adManager = AdManager.instance;
  final FirebaseNotificationService _notificationService =
      FirebaseNotificationService();

  late Top5Question _currentQuestion;
  final List<String?> _revealedAnswers = List.filled(10, null);
  int _lives = 3;
  int _wrongAnswersCount = 0; // عدد الإجابات الخاطئة
  bool _isLoading = true;
  bool _isGameOver = false;
  bool _isBlocked = false;
  Duration _remainingTime = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _clearOldCache(); // تنظيف الكاش القديم
    _loadBlockedState();
    _adManager.loadRewardedAd();
  }

  // تنظيف الكاش القديم (24 ساعة) وإعادة تعيينه
  Future<void> _clearOldCache() async {
    final prefs = await SharedPreferences.getInstance();
    final blockedTimestamp = prefs.getInt('quiz5_blocked_timestamp');

    if (blockedTimestamp != null) {
      final blockedDateTime = DateTime.fromMillisecondsSinceEpoch(
        blockedTimestamp,
      );
      final difference = DateTime.now().difference(blockedDateTime);

      // إذا كان الحظر أكثر من ساعة، احذفه
      if (difference.inHours > 1) {
        await prefs.remove('quiz5_blocked_timestamp');
        print(
          '✅ تم تنظيف الكاش القديم - الحظر كان: ${difference.inHours} ساعة',
        );
      }
    }
  }

  Future<void> _loadBlockedState() async {
    final prefs = await SharedPreferences.getInstance();
    final blockedTimestamp = prefs.getInt('quiz5_blocked_timestamp');

    if (blockedTimestamp != null) {
      final blockedDateTime = DateTime.fromMillisecondsSinceEpoch(
        blockedTimestamp,
      );
      final difference = DateTime.now().difference(blockedDateTime);

      // التحقق: هل الوقت لم ينته بعد؟ (أقل من ساعة)
      if (difference.inHours < 1) {
        // المستخدم لا يزال محظوراً - عرض شاشة الانتظار
        setState(() {
          _isBlocked = true;
          _isLoading = false; // مهم جداً! إيقاف شاشة التحميل
          _remainingTime = const Duration(hours: 1) - difference;
        });
        _startTimer();
        print(
          '🔒 المستخدم محظور - الوقت المتبقي: ${_remainingTime.inMinutes} دقيقة',
        );
      } else {
        // الوقت انتهى - حذف الحظر وتحميل السؤال الجديد
        print('✅ انتهى الحظر - تحميل سؤال جديد');
        await prefs.remove('quiz5_blocked_timestamp');
        _loadQuiz();
      }
    } else {
      // لا يوجد حظر - تحميل السؤال
      _loadQuiz();
    }
  }

  void _startTimer() {
    _timer?.cancel(); // إلغاء أي مؤقت سابق
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_remainingTime.inSeconds > 0) {
        setState(() {
          _remainingTime = _remainingTime - const Duration(seconds: 1);
        });
      } else {
        // انتهى الوقت!
        timer.cancel();
        print('⏰ انتهى وقت الحظر!');

        // حذف الحظر من التخزين
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('quiz5_blocked_timestamp');

        // إعادة تعيين الحالة وتحميل السؤال الجديد
        setState(() {
          _isBlocked = false;
        });
        _loadQuiz();
      }
    });
  }

  void _loadQuiz() async {
    final prefs = await SharedPreferences.getInstance();
    int currentIndex = prefs.getInt('quiz5_question_index') ?? 0;

    // التأكد من أن الـ index ضمن النطاق
    if (currentIndex >= top5QuizQuestions.length) {
      currentIndex = 0;
      await prefs.setInt('quiz5_question_index', 0);
    }

    setState(() {
      _isLoading = true;
      // استخدام الـ index بدلاً من random
      _currentQuestion = top5QuizQuestions[currentIndex];

      // إعادة تعيين حالة اللعبة بالكامل
      _revealedAnswers.fillRange(0, _revealedAnswers.length, null);
      _lives = 3;
      _wrongAnswersCount = 0;
      _isGameOver = false;
      _answerController.clear();

      _isLoading = false;
    });
    print(
      '🎮 تم تحميل السؤال رقم $currentIndex: ${_currentQuestion.questionText}',
    );
  }

  @override
  void dispose() {
    _answerController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _checkAnswer() {
    if (_isGameOver) return;

    final userAnswer = _answerController.text.trim().toLowerCase();
    if (userAnswer.isEmpty) return;

    int? foundIndex;
    for (int i = 0; i < _currentQuestion.answers.length; i++) {
      if (_revealedAnswers[i] == null) {
        for (String variant in _currentQuestion.answers[i]) {
          if (userAnswer.similarityTo(variant.toLowerCase()) >= 0.8) {
            foundIndex = i;
            break;
          }
        }
      }
      if (foundIndex != null) break;
    }

    if (foundIndex != null) {
      final int index = foundIndex;
      setState(() {
        _revealedAnswers[index] = _currentQuestion.answers[index][0];
      });
      _answerController.clear();
      Provider.of<PointsProvider>(context, listen: false).addPoints(1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('إجابة صحيحة!'),
          backgroundColor: Colors.green,
        ),
      );

      if (!_revealedAnswers.contains(null)) {
        _handleGameOver(won: true);
      }
    } else {
      setState(() {
        _wrongAnswersCount++; // زيادة عدد الإجابات الخاطئة
        if (_lives > 0) {
          _lives--;
          // لا نستدعي _handleGameOver عند انتهاء الأرواح
          // لأننا نريد أن يظهر زر كشف الإجابات
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('إجابة خاطئة! حاول مرة أخرى'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _revealAnswers() {
    if (_isGameOver && _lives > 0) return;
    _adManager.showRewardedAd(
      onAdRewarded: (reward) {
        setState(() {
          for (int i = 0; i < _currentQuestion.answers.length; i++) {
            if (_revealedAnswers[i] == null) {
              _revealedAnswers[i] = _currentQuestion.answers[i][0];
            }
          }
        });
        _handleGameOver(won: false);
      },
      onAdFailed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل تحميل الإعلان، حاول مرة أخرى.')),
        );
      },
    );
  }

  void _handleGameOver({required bool won}) async {
    final prefs = await SharedPreferences.getInstance();
    int currentIndex = prefs.getInt('quiz5_question_index') ?? 0;
    int nextIndex = currentIndex + 1;
    if (nextIndex >= top5QuizQuestions.length) {
      nextIndex = 0;
    }
    await prefs.setInt('quiz5_question_index', nextIndex);

    // حفظ وقت الحظر (لكن لا نفعّل الحظر بعد)
    await prefs.setInt(
      'quiz5_blocked_timestamp',
      DateTime.now().millisecondsSinceEpoch,
    );

    // فقط تعيين انتهاء اللعبة (زر "السؤال التالي" سيظهر)
    setState(() {
      _isGameOver = true;
    });

    // إظهار رسالة نجاح
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Text('⚽', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  won
                      ? '🎉 أحسنت! أجبت على جميع الأسئلة'
                      : '✅ تم كشف جميع الإجابات',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // وظيفة للانتقال للسؤال التالي - تفعيل شاشة الانتظار
  void _goToNextQuestion() async {
    // جدولة إشعار بعد ساعة واحدة
    print('📱 جدولة إشعار بعد ساعة واحدة...');
    try {
      await _notificationService.scheduleNotificationToUsers(
        title: 'المحنكين - Top 10 ⚽',
        body: 'انتهت فترة الاستراحة! السؤال التالي في انتظارك 🏆',
        payload: 'quiz5', // لتوجيه المستخدم لهذه الصفحة
      );
      print('✅ تم جدولة الإشعار بنجاح');
    } catch (e) {
      print('❌ خطأ في جدولة الإشعار: $e');
    }

    // تفعيل شاشة الانتظار
    setState(() {
      _isBlocked = true;
      _remainingTime = const Duration(hours: 1);
    });
    _startTimer();
  }

  Widget _buildLives() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: CircleAvatar(
            radius: 10,
            backgroundColor: index < _lives ? Colors.green : Colors.grey[700],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pointsProvider = Provider.of<PointsProvider>(context);
    return Scaffold(
      backgroundColor: const Color(0xFF55198B),
      appBar: AppBar(
        title: const Text('Top 10', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(MdiIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _isBlocked
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // كرة القدم
                    const Text('⚽', style: TextStyle(fontSize: 80)),
                    const SizedBox(height: 30),
                    // العنوان
                    const Text(
                      'استراحة المحنك',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 4,
                      width: 60,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.amber, Colors.orange],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 30),
                    // الرسالة
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 2,
                        ),
                      ),
                      child: const Column(
                        children: [
                          Text(
                            'وقت استراحة قصيرة',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'عُد بعد ساعة واحدة للسؤال التالي',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    // العداد التنازلي
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.green.withOpacity(0.3),
                            Colors.green.withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.6),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${_remainingTime.inHours.toString().padLeft(2, '0')}:${(_remainingTime.inMinutes % 60).toString().padLeft(2, '0')}:${(_remainingTime.inSeconds % 60).toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 52,
                              fontWeight: FontWeight.bold,
                              fontFeatures: [FontFeature.tabularFigures()],
                              letterSpacing: 4,
                              shadows: [
                                Shadow(color: Colors.green, blurRadius: 10),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'الوقت المتبقي',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    // رسالة الإشعار
                    const Text(
                      '🔔 سنرسل لك إشعاراً عند انتهاء الوقت',
                      style: TextStyle(color: Colors.white60, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 16.0,
                ),
                child: Column(
                  children: [
                    Text(
                      _currentQuestion.questionText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 10,
                      itemBuilder: (context, index) {
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 3.0),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10.0,
                            vertical: 8.0,
                          ),
                          decoration: BoxDecoration(
                            color: _revealedAnswers[index] != null
                                ? Colors.blueGrey[700]
                                : Colors.black.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _revealedAnswers[index] ?? '- - - - - - -',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _answerController,
                      enabled: !_isGameOver,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        hintText: 'اكتب الجواب هنا',
                        hintStyle: const TextStyle(color: Colors.black54),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isGameOver
                            ? _goToNextQuestion
                            : (_lives == 0
                                  ? null
                                  : _checkAnswer), // معطل إذا انتهت الأرواح
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isGameOver
                              ? Colors.orange
                              : (_lives == 0 ? Colors.grey : Colors.green),
                          disabledBackgroundColor: Colors.grey[700],
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: _isGameOver ? 3 : 0,
                        ),
                        child: Text(
                          _isGameOver ? 'السؤال التالي ⚽' : 'تأكيد الجواب',
                          style: TextStyle(
                            fontSize: 18,
                            color: _lives == 0 && !_isGameOver
                                ? Colors.white54
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildLives(),
                    const SizedBox(height: 24),
                    // زر كشف الإجابات - يظهر بعد 3 إجابات خاطئة وقبل انتهاء اللعبة
                    if (!_isGameOver && _wrongAnswersCount >= 3)
                      Column(
                        children: [
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.amber.withOpacity(0.6),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amber.withOpacity(0.2),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _revealAnswers,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.withOpacity(0.15),
                                foregroundColor: Colors.amber,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '💡',
                                        style: TextStyle(fontSize: 24),
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'كشف الإجابات',
                                        style: TextStyle(
                                          color: Colors.amber,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'شاهد إعلان لكشف الإجابة',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
