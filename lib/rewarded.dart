import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ad_manager.dart';
import 'points_provider.dart';
import 'firebase_notification_service.dart';

class RewardedScreen extends StatefulWidget {
  const RewardedScreen({super.key});

  @override
  State<RewardedScreen> createState() => _RewardedScreenState();
}

class _RewardedScreenState extends State<RewardedScreen> {
  static const int _rewardCooldownHours = 12;
  static const String _dailyRewardKey = 'last_daily_reward_claim';
  static const String _adRewardKey = 'last_ad_reward_claim';

  final FirebaseNotificationService _notificationService =
      FirebaseNotificationService();
  Duration _dailyRewardRemaining = Duration.zero;
  Duration _adRewardRemaining = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
    AdManager.instance.loadRewardedAd();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _updateTimers(); // Initial update
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimers();
    });
  }

  Future<void> _updateTimers() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    // Daily Reward Timer
    final dailyClaimTimestamp = prefs.getInt(_dailyRewardKey) ?? 0;
    final dailyNextAvailable = DateTime.fromMillisecondsSinceEpoch(
      dailyClaimTimestamp,
    ).add(const Duration(hours: _rewardCooldownHours));
    if (now.isBefore(dailyNextAvailable)) {
      setState(() {
        _dailyRewardRemaining = dailyNextAvailable.difference(now);
      });
    } else {
      setState(() {
        _dailyRewardRemaining = Duration.zero;
      });
    }

    // Ad Reward Timer
    final adClaimTimestamp = prefs.getInt(_adRewardKey) ?? 0;
    final adNextAvailable = DateTime.fromMillisecondsSinceEpoch(
      adClaimTimestamp,
    ).add(const Duration(hours: _rewardCooldownHours));
    if (now.isBefore(adNextAvailable)) {
      setState(() {
        _adRewardRemaining = adNextAvailable.difference(now);
      });
    } else {
      setState(() {
        _adRewardRemaining = Duration.zero;
      });
    }
  }

  Future<void> _claimDailyReward() async {
    if (_dailyRewardRemaining > Duration.zero) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('المكافأة غير متاحة بعد.')));
      return;
    }

    Provider.of<PointsProvider>(context, listen: false).addPoints(5);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dailyRewardKey, DateTime.now().millisecondsSinceEpoch);

    // جدولة إشعار تذكير بعد 12 ساعة
    try {
      await _notificationService.scheduleNotificationToUsers(
        title: 'مكافأة الحضور جاهزة! 🎁',
        body: 'مكافأتك اليومية أصبحت متاحة! احصل على 5 نقاط مجاناً ⚽',
        payload: 'rewards',
      );
      print('✅ تم جدولة إشعار مكافأة الحضور');
    } catch (e) {
      print('❌ خطأ في جدولة إشعار مكافأة الحضور: $e');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تهانينا! لقد حصلت على 5 نقاط.')),
    );
    _updateTimers();
  }

  void _claimAdReward() {
    if (_adRewardRemaining > Duration.zero) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('المكافأة غير متاحة بعد.')));
      return;
    }

    AdManager.instance.showRewardedAd(
      onAdRewarded: (reward) async {
        Provider.of<PointsProvider>(context, listen: false).addPoints(5);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_adRewardKey, DateTime.now().millisecondsSinceEpoch);

        // جدولة إشعار تذكير بعد 12 ساعة
        try {
          await _notificationService.scheduleNotificationToUsers(
            title: 'مكافأة الإعلان جاهزة! 📺',
            body: 'شاهد إعلاناً واحصل على 5 نقاط إضافية الآن! 🏆',
            payload: 'rewards',
          );
          print('✅ تم جدولة إشعار مكافأة الإعلان');
        } catch (e) {
          print('❌ خطأ في جدولة إشعار مكافأة الإعلان: $e');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تهانينا! لقد حصلت على 5 نقاط بعد مشاهدة الإعلان.'),
          ),
        );
        _updateTimers();
      },
      onAdFailed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل تحميل الإعلان. حاول مرة أخرى.')),
        );
        AdManager.instance.loadRewardedAd(); // Pre-load for next attempt
      },
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative) return '00:00:00';
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'المكافئات',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF55198B), Color(0xFF8B53C6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(MdiIcons.arrowLeft, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildRewardCard(
                icon: MdiIcons.gift,
                title: 'مكافأة الحضور',
                subtitle: 'احصل على 5 نقاط مجانًا كل 12 ساعة.',
                remainingTime: _dailyRewardRemaining,
                onPressed: _claimDailyReward,
              ),
              const SizedBox(height: 20),
              _buildRewardCard(
                icon: MdiIcons.moviePlay,
                title: 'شاهد واربح',
                subtitle: 'شاهد إعلانًا واحصل على 5 نقاط إضافية كل 12 ساعة.',
                remainingTime: _adRewardRemaining,
                onPressed: _claimAdReward,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRewardCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Duration remainingTime,
    required VoidCallback onPressed,
  }) {
    bool isAvailable = remainingTime <= Duration.zero;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            colors: isAvailable
                ? [Colors.green.shade50, Colors.green.shade100]
                : [Colors.grey.shade100, Colors.grey.shade200],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(icon, size: 40, color: const Color(0xFF55198B)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF55198B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isAvailable ? onPressed : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isAvailable
                      ? const Color(0xFF55198B)
                      : Colors.grey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  isAvailable
                      ? 'احصل على المكافأة'
                      : 'الوقت المتبقي: ${_formatDuration(remainingTime)}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
