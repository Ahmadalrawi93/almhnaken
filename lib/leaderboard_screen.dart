// File: leaderboard_screen.dart
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  // State for the floating rank widget
  bool _showFloatingRank = false;
  int _currentUserRank = -1;
  DocumentSnapshot? _currentUserDoc;
  bool _initialRankChecked = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'قائمة المتصدرين',
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
        child: StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('users')
              .orderBy('points', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF55198B)),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'حدث خطأ: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                child: Text(
                  'لا يوجد بيانات للمتصدرين حاليًا.',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }

            final leaderboardData = snapshot.data!.docs;

            // Find current user's rank and data
            final userIndex = leaderboardData.indexWhere((doc) => doc.id == _currentUserId);
            if (userIndex != -1) {
              _currentUserRank = userIndex + 1;
              _currentUserDoc = leaderboardData[userIndex];
            }

            // Decide whether to show the floating rank widget
            if (!_initialRankChecked) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _currentUserRank > 10) {
                  setState(() {
                    _showFloatingRank = true;
                    _initialRankChecked = true;
                  });
                }
              });
            }

            final topPlayers = leaderboardData.take(3).toList();
            final restOfPlayers = leaderboardData.skip(3).toList();

            return Stack(
              children: [
                SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      _buildTop3Section(topPlayers),
                      const SizedBox(height: 20),
                      _buildLeaderboardList(restOfPlayers),
                    ],
                  ),
                ),
                if (_showFloatingRank && _currentUserDoc != null)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: _buildFloatingRankCard(_currentUserDoc!, _currentUserRank),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTop3Section(List<DocumentSnapshot> topPlayers) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildTopPlayerCard(topPlayers.length > 1 ? topPlayers[1] : null, 2),
          _buildTopPlayerCard(topPlayers.isNotEmpty ? topPlayers[0] : null, 1),
          _buildTopPlayerCard(topPlayers.length > 2 ? topPlayers[2] : null, 3),
        ],
      ),
    );
  }

  Widget _buildTopPlayerCard(DocumentSnapshot? playerDoc, int rank) {
    final Map<String, dynamic>? data =
        playerDoc?.data() as Map<String, dynamic>?;
    final String name = data?['playerName'] ?? 'لا يوجد';
    final int points = data?['points'] ?? 0;
    final String? avatarFileName = data?['avatarFileName'] as String?;

    final Color cardColor = rank == 1
        ? Colors.amber
        : (rank == 2 ? Colors.grey.shade400 : Colors.brown.shade400);

    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomLeft,
          children: [
            Container(
              width: rank == 1 ? 100 : 80,
              height: rank == 1 ? 100 : 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cardColor,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: avatarFileName != null
                  ? ClipOval(
                      child: Image.asset(
                        'iconUser/$avatarFileName',
                        fit: BoxFit.contain,
                      ),
                    )
                  : Icon(
                      MdiIcons.accountCircle,
                      size: rank == 1 ? 60 : 50,
                      color: Colors.white,
                    ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF55198B),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Color(0xFF55198B),
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          '$points',
          style: const TextStyle(fontSize: 14, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildLeaderboardList(List<DocumentSnapshot> players) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: players.length,
      itemBuilder: (context, index) {
        final playerDoc = players[index];
        final bool isCurrentUser = playerDoc.id == _currentUserId;

        // If the current user's item is being built, hide the floating rank card.
        if (isCurrentUser && _showFloatingRank) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _showFloatingRank = false;
              });
            }
          });
        }

        return _buildPlayerListItem(playerDoc, index + 4, isCurrentUser);
      },
    );
  }

  Widget _buildPlayerListItem(DocumentSnapshot playerDoc, int rank, bool isCurrentUser) {
    final Map<String, dynamic>? data =
        playerDoc.data() as Map<String, dynamic>?;
    final String name = data?['playerName'] ?? 'لا يوجد';
    final int points = data?['points'] ?? 0;
    final String? avatarFileName = data?['avatarFileName'] as String?;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      color: isCurrentUser ? Colors.blue.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: isCurrentUser
            ? BorderSide(color: Colors.blue.shade400, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF55198B),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 15),
            CircleAvatar(
              radius: 25,
              backgroundColor: Colors.grey.shade300,
              child: avatarFileName != null
                  ? ClipOval(
                      child: Image.asset(
                        'iconUser/$avatarFileName',
                        fit: BoxFit.contain,
                        width: 50,
                        height: 50,
                      ),
                    )
                  : Icon(
                      MdiIcons.accountCircle,
                      size: 30,
                      color: Colors.white,
                    ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF55198B),
                ),
              ),
            ),
            Text(
              '$points',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF8B53C6),
              ),
            ),
            Icon(MdiIcons.trophy, color: Colors.amber),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingRankCard(DocumentSnapshot playerDoc, int rank) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: Colors.blue.shade50,
          border: Border.all(color: Colors.blue.shade400, width: 1.5),
        ),
        child: _buildPlayerListItem(playerDoc, rank, true),
      ),
    );
  }
}