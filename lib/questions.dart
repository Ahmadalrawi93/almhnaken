// File: questions.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'points_provider.dart';
import 'quiz_page_1.dart';
import 'quiz_page_2.dart';
import 'quiz_page_3.dart';
import 'quiz_page_4.dart';
import 'quiz_page_5.dart';

class QuestionsScreen extends StatelessWidget {
  const QuestionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pointsProvider = Provider.of<PointsProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF55198B),
      appBar: AppBar(
        title: const Text(
          'صفحة الأسئلة',
          style: TextStyle(color: Colors.white),
        ),
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
      body: SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          GridView.count(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16.0,
                            mainAxisSpacing: 16.0,
                            childAspectRatio: 1.0,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: <Widget>[
                              _buildCard(
                                imagePath: 'image/mice.png',
                                text: 'صوت المعلق',
                                iconAndTextColor:
                                    Colors.white, // تم تغيير اللون إلى الأبيض
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => QuizPage1(),
                                    ),
                                  );
                                },
                              ),
                              _buildCard(
                                imagePath: 'image/bank.png',
                                text: 'البنك',
                                iconAndTextColor:
                                    Colors.white, // تم تغيير اللون إلى الأبيض
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => QuizPage2(),
                                    ),
                                  );
                                },
                              ),
                              _buildCard(
                                imagePath: 'image/block.png',
                                text: 'بلوكات',
                                iconAndTextColor:
                                    Colors.white, // تم تغيير اللون إلى الأبيض
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => QuizPage3(),
                                    ),
                                  );
                                },
                              ),
                              _buildCard(
                                imagePath: 'image/plyer.png',
                                text: 'مسيرة لاعب',
                                iconAndTextColor:
                                    Colors.white, // تم تغيير اللون إلى الأبيض
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => QuizPage4(),
                                    ),
                                  );
                                },
                              ),
                              _buildCard(
                                imagePath: 'image/top.png',
                                text: 'Top 10',
                                iconAndTextColor: Colors.white,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const QuizPage5(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
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
  }

  static Widget _buildCard({
    IconData? icon,
    String? imagePath,
    required String text,
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
      return Card(
        color: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
        child: InkWell(
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
                  style: TextStyle(
                    color: iconAndTextColor,
                    fontSize: 14.0,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Original Icon card
      return Card(
        color: Colors.transparent,
        elevation: 0,
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
}
