// File: quiz_state_provider.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuizStateProvider with ChangeNotifier {
  int _currentQuestionIndex = 0;
  int _remainingLives = 3;

  int get currentQuestionIndex => _currentQuestionIndex;
  int get remainingLives => _remainingLives;

  Future<void> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    _currentQuestionIndex = prefs.getInt('quiz_currentQuestionIndex') ?? 0;
    _remainingLives = prefs.getInt('quiz_remainingLives') ?? 3;
    notifyListeners();
  }

  Future<void> saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('quiz_currentQuestionIndex', _currentQuestionIndex);
    await prefs.setInt('quiz_remainingLives', _remainingLives);
  }

  void nextQuestion() {
    _currentQuestionIndex++;
    _remainingLives = 3;
    saveState();
    notifyListeners();
  }

  void loseLife() {
    _remainingLives--;
    saveState();
    notifyListeners();
  }

  // دالة جديدة لإعادة الكرات فقط
  void resetLives() {
    _remainingLives = 3;
    saveState();
    notifyListeners();
  }

  void resetState() {
    _currentQuestionIndex = 0;
    _remainingLives = 3;
    saveState();
    notifyListeners();
  }
}
