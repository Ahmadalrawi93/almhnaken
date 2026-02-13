import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'points_provider.dart';
import 'quiz_state_provider.dart';
import 'questions.dart';
import 'register_screen.dart';
import 'login_screen.dart';
import 'leaderboard_screen.dart';
import 'user_profile_screen.dart';
import 'online_lobby_screen.dart';
import 'create_room_screen.dart';
import 'join_room_screen.dart';
import 'ad_manager.dart';
import 'firebase_notification_service.dart';
import 'rewarded.dart';
import 'services/update_service.dart';
import 'models/banner_model.dart';

// GlobalKey للnavigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // تهيئة Firebase
    await Firebase.initializeApp();
    debugPrint('✅ Firebase تم تهيئته بنجاح');
  } catch (e) {
    debugPrint('❌ خطأ في تهيئة Firebase: $e');
    // الاستمرار حتى لو فشلت تهيئة Firebase
  }

  try {
    // تهيئة Firebase Cloud Messaging للإشعارات الخلفية
    await FirebaseNotificationService().initialize();
    debugPrint('✅ Firebase Messaging تم تهيئته بنجاح');
    
    // تسجيل المستخدم لتلقي إشعارات اللعب الأونلاين
    await FirebaseNotificationService().subscribeToTopic('online_players');
  } catch (e) {
    debugPrint('❌ خطأ في تهيئة Firebase Messaging: $e');
    // الاستمرار حتى لو فشلت تهيئة الإشعارات
  }

  try {
    AdManager.instance.initialize();
    // Pre-load an interstitial ad at app startup.
    AdManager.instance.loadInterstitialAd();
    debugPrint('✅ AdManager تم تهيئته بنجاح');
  } catch (e) {
    debugPrint('❌ خطأ في تهيئة AdManager: $e');
    // الاستمرار حتى لو فشلت تهيئة الإعلانات
  }

  final pointsProvider = PointsProvider();
  final quizStateProvider = QuizStateProvider();
  
  try {
    await quizStateProvider.loadState();
  } catch (e) {
    debugPrint('❌ خطأ في تحميل حالة Quiz: $e');
    // الاستمرار حتى لو فشل تحميل الحالة
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: pointsProvider),
        ChangeNotifierProvider.value(value: quizStateProvider),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey, // إضافة GlobalKey
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController();
  late Stream<DocumentSnapshot> _userStream;
  late Timer _timer;
  bool _hasShownUpdateDialog = false;
  List<BannerModel> _banners = [];
  bool _bannersLoaded = false;

  @override
  void initState() {
    super.initState();
    _userStream = FirebaseAuth.instance.currentUser != null
        ? FirebaseFirestore.instance
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser!.uid)
              .snapshots()
        : Stream.empty();

    _loadBanners();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });
  }

  Future<void> _loadBanners() async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection('banners')
              .orderBy('order')
              .limit(5)
              .get();

      if (!mounted) return;

      // فلترة البانرات النشطة وترتيبها
      final List<BannerModel> activeBanners = snapshot.docs
          .map((doc) => BannerModel.fromFirestore(doc.data(), doc.id))
          .where((banner) => banner.isActive)
          .toList();

      setState(() {
        _banners = activeBanners;
        _bannersLoaded = true;
      });

      // تهيئة Timer بعد تحميل البانرات
      if (_banners.isNotEmpty) {
        _timer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
          if (_pageController.hasClients) {
            int nextPage = _pageController.page!.round() + 1;
            if (nextPage >= _banners.length) {
              nextPage = 0;
            }
            _pageController.animateToPage(
              nextPage,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeIn,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('خطأ في تحميل البانرات: $e');
      if (mounted) {
        setState(() {
          _bannersLoaded = true;
        });
      }
    }
  }

  @override
  void dispose() {
    if (_banners.isNotEmpty) {
      _timer.cancel();
    }
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    if (_hasShownUpdateDialog) return;
    try {
      final UpdateInfo? info = await UpdateService().checkForUpdate();
      if (!mounted || info == null) return;
      _hasShownUpdateDialog = true;
      await _showUpdateDialog(info);
    } catch (e) {
      debugPrint('خطأ أثناء التحقق من التحديث: $e');
    }
  }

  Future<void> _showUpdateDialog(UpdateInfo info) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تحديث جديد متاح'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('نسخة التطبيق الحالية: ${info.currentVersion}'),
                const SizedBox(height: 8),
                Text('آخر نسخة متاحة: ${info.latestVersion}'),
                if (info.message != null && info.message!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      info.message!,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
              ],
            ),
            actions: <Widget>[
              if (!info.forceUpdate)
                TextButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await UpdateService().markVersionAsNotified(
                      info.latestVersion,
                    );
                  },
                  child: const Text('لاحقاً'),
                ),
              ElevatedButton(
                onPressed: () async {
                  await _openUpdateLink(info);
                  if (!info.forceUpdate &&
                      Navigator.of(dialogContext).canPop()) {
                    Navigator.of(dialogContext).pop();
                    await UpdateService().markVersionAsNotified(
                      info.latestVersion,
                    );
                  }
                },
                child: const Text('تحديث الآن'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openUpdateLink(UpdateInfo info) async {
    final Uri uri = Uri.parse(info.effectiveStoreUrl);
    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح صفحة التحديث. حاول مرة أخرى.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ أثناء فتح صفحة التحديث: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pointsProvider = Provider.of<PointsProvider>(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFF55198B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'الــمـحـنـكـيـن',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(MdiIcons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
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
      drawer: StreamBuilder<DocumentSnapshot>(
        stream: _userStream,
        builder: (context, snapshot) {
          String? userName;
          String? userAvatarFileName;

          if (snapshot.hasData && snapshot.data!.exists) {
            final userData = snapshot.data!.data() as Map<String, dynamic>;
            userName = userData['playerName'];
            userAvatarFileName = userData['avatarFileName'];
          }

          return Directionality(
            textDirection: TextDirection.rtl,
            child: SizedBox(
              width: screenWidth * 0.75,
              child: ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(20.0),
                ),
                child: Drawer(
                  child: Container(
                    color: Colors.white,
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: <Widget>[
                        Container(
                          padding: EdgeInsets.only(
                            top: MediaQuery.of(context).padding.top,
                            bottom: 16.0,
                          ),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF55198B), Color(0xFF8E44AD)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 40,
                                  backgroundColor: Colors.transparent,
                                  child: ClipOval(
                                    child:
                                        userAvatarFileName != null &&
                                            userAvatarFileName.isNotEmpty
                                        ? Image.asset(
                                            'iconUser/$userAvatarFileName',
                                            fit: BoxFit.contain,
                                            width: 80,
                                            height: 80,
                                          )
                                        : const Icon(
                                            Icons.person,
                                            size: 40,
                                            color: Colors.white,
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                userName ?? 'المحنكين',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, thickness: 1),
                        ListTile(
                          leading: const Icon(
                            MdiIcons.accountPlus,
                            color: Colors.black,
                          ),
                          title: const Text(
                            'تسجيل حساب',
                            style: TextStyle(color: Colors.black, fontSize: 18),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const RegisterScreen(),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(
                            MdiIcons.login,
                            color: Colors.black,
                          ),
                          title: const Text(
                            'تسجيل الدخول',
                            style: TextStyle(color: Colors.black, fontSize: 18),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const LoginScreen(),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(
                            MdiIcons.trophyAward,
                            color: Colors.black,
                          ),
                          title: const Text(
                            'قائمة المتصدرين',
                            style: TextStyle(color: Colors.black, fontSize: 18),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const LeaderboardScreen(),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(
                            MdiIcons.account,
                            color: Colors.black,
                          ),
                          title: const Text(
                            'ملفي الشخصي',
                            style: TextStyle(color: Colors.black, fontSize: 18),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const UserProfileScreen(),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(
                            MdiIcons.gift,
                            color: Colors.black,
                          ),
                          title: const Text(
                            'المكافات',
                            style: TextStyle(color: Colors.black, fontSize: 18),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const RewardedScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      body: SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  children: [
                    GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16.0,
                      mainAxisSpacing: 16.0,
                      padding: EdgeInsets.only(
                        left: 16.0,
                        right: 16.0,
                        top: 16.0,
                        bottom:
                            MediaQuery.of(context).padding.bottom +
                            20, // إضافة مساحة إضافية للشريط السفلي
                      ),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      // To make the cards taller (and the image bigger), make this value smaller (e.g., 1.1, 1.0)
                      childAspectRatio: 1.0,
                      children: <Widget>[
                        _buildCard(
                          imagePath: 'image/ofline.png',
                          text: 'اوفــلايــن',
                          color: Colors.white,
                          iconAndTextColor: const Color(0xFF55198B),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const QuestionsScreen(),
                            ),
                          ),
                        ),
                        _buildCard(
                          imagePath: 'image/online.png',
                          text: 'اونـلايـن',
                          color: Colors.white,
                          iconAndTextColor: const Color(0xFF55198B),
                          onTap: () => _handleOnlineTap(context),
                        ),
                        _buildCard(
                          imagePath: 'image/join.png',
                          text: 'انضم لصديقك',
                          color: Colors.white,
                          iconAndTextColor: const Color(0xFF55198B),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const JoinRoomScreen(),
                            ),
                          ),
                        ),
                        _buildCard(
                          imagePath: 'image/join.png',
                          text: 'انشئ غرفة خاصة',
                          color: Colors.white,
                          iconAndTextColor: const Color(0xFF55198B),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CreateRoomScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 10.0,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: screenHeight * 0.15,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: _bannersLoaded
                              ? (_banners.isNotEmpty
                                    ? PageView.builder(
                                        controller: _pageController,
                                        itemCount: _banners.length,
                                        itemBuilder: (context, index) {
                                          final banner = _banners[index];
                                          return _buildDynamicBanner(banner);
                                        },
                                      )
                                    : Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: const [
                                              Icon(
                                                Icons.image_not_supported,
                                                color: Colors.white70,
                                                size: 40,
                                              ),
                                              SizedBox(height: 8),
                                              Text(
                                                'لا توجد بانرات متاحة حالياً',
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 14,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ))
                              : const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const UserProfileScreen(),
                              ),
                            ),
                            child: const Icon(
                              MdiIcons.accountCircle,
                              size: 50,
                              color: Colors.white,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const LeaderboardScreen(),
                              ),
                            ),
                            child: const Icon(
                              MdiIcons.trophyAward,
                              size: 50,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      // إضافة مساحة إضافية للهواتف الحديثة
                      SizedBox(
                        height: MediaQuery.of(context).padding.bottom + 20,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicBanner(BannerModel banner) {
    return GestureDetector(
      onTap: banner.linkUrl != null && banner.linkUrl!.isNotEmpty
          ? () async {
              try {
                await launchUrl(
                  Uri.parse(banner.linkUrl!),
                  mode: LaunchMode.externalApplication,
                );
              } catch (e) {
                debugPrint('خطأ في فتح الرابط: $e');
              }
            }
          : null,
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: CachedNetworkImage(
            imageUrl: banner.imageUrl,
            fit: BoxFit.fill,
            placeholder: (context, url) => Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Icon(Icons.error_outline, color: Colors.white, size: 40),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildCard({
    IconData? icon,
    String? imagePath,
    required String text,
    required Color color,
    required Color iconAndTextColor,
    Function()? onTap,
  }) {
    assert(
      icon != null || imagePath != null,
      'Either icon or imagePath must be provided.',
    );
    assert(
      icon == null || imagePath == null,
      'Cannot provide both icon and imagePath.',
    );

    if (imagePath != null) {
      return InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(20.0)),
                child: Image.asset(imagePath, fit: BoxFit.cover),
              ),
            ),
            Padding(
              padding: EdgeInsets.zero,
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  // To make the image bigger, make this font size smaller
                  fontSize: 14.0,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    } else {
      // Original Icon card
      return Card(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon!, size: 50.0, color: iconAndTextColor),
              const SizedBox(height: 8.0),
              Text(
                text,
                style: TextStyle(
                  color: iconAndTextColor,
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
  }

  // دالة التعامل مع الضغط على زر الأونلاين
  void _handleOnlineTap(BuildContext context) {
    // التحقق من تسجيل الدخول
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      // المستخدم مسجل دخول، الانتقال إلى شاشة الأونلاين
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const OnlineLobbyScreen()),
      );
    } else {
      // المستخدم غير مسجل دخول، عرض التنبيه الجميل
      _showAuthRequiredDialog(context);
    }
  }

  // عرض التنبيه الجميل للتحقق من تسجيل الدخول
  void _showAuthRequiredDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 10,
            insetPadding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom:
                  MediaQuery.of(context).padding.bottom +
                  20, // مساحة إضافية للشريط السفلي
            ),
            child: Container(
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF55198B), Color(0xFF8B53C6)],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // صورة المحنكين
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: ClipOval(
                      child: CachedNetworkImage(
                        imageUrl:
                            'https://raw.githubusercontent.com/Ahmadalrawi93/almhnaken-assets/main/images/voice.png',
                        fit: BoxFit.cover,
                        width: 70,
                        height: 70,
                        placeholder: (context, url) => const SizedBox(
                          width: 70,
                          height: 70,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => const Icon(
                          Icons.person,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // العنوان
                  const Text(
                    'تسجيل الدخول مطلوب',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),

                  // النص التوضيحي
                  const Text(
                    'يجب عليك تسجيل الدخول لحسابك للتمكن من اللعب أونلاين',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // الأزرار
                  Row(
                    children: [
                      // زر الغاء
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white24,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'إلغاء',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),

                      // زر إنشاء حساب جديد
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const RegisterScreen(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF55198B),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'إنشاء حساب',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// سيتم استخدام Firebase Cloud Messaging للإشعارات الخلفية
