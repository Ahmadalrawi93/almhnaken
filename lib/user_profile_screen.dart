// File: user_profile_screen.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _birthDateController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  User? _currentUser;
  String? _initialName;
  String? _initialGender;
  String? _currentGender;
  String? _initialBirthDateString;
  String? _currentBirthDateString;
  String? _currentAvatarFileName;
  String? _initialAvatarFileName;

  bool _isSaving = false;
  bool _isSigningOut = false;
  String? _nameErrorMessage;
  String? _birthDateErrorMessage;

  final List<String> _availableAvatars = List.generate(
    12,
    (index) => 'iconUser/${index + 1}.png',
  );

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _loadUserData();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الرجاء تسجيل الدخول لعرض ملفك الشخصي.'),
          ),
        );
      });
    }
  }

  Future<void> _loadUserData() async {
    if (_currentUser == null) return;

    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .get();
      if (userDoc.exists) {
        final Map<String, dynamic> userData = userDoc.data()!;
        debugPrint('Loaded User Data: $userData');

        setState(() {
          _nameController.text =
              userData['playerName'] ?? _currentUser!.displayName ?? '';
          _initialName = _nameController.text;
          _currentGender = userData['gender'] as String?;
          _initialGender = _currentGender;
          final birthDateTimestamp = userData['birthDate'] as Timestamp?;
          if (birthDateTimestamp != null) {
            final date = birthDateTimestamp.toDate();
            _birthDateController.text =
                '${date.day}/${date.month}/${date.year}';
            _currentBirthDateString = _birthDateController.text;
            _initialBirthDateString = _currentBirthDateString;
          }
          _currentAvatarFileName = userData['avatarFileName'] as String?;
          _initialAvatarFileName = _currentAvatarFileName;
        });
      } else {
        await _firestore.collection('users').doc(_currentUser!.uid).set({
          'email': _currentUser!.email,
          'playerName': _currentUser!.displayName ?? 'لاعب جديد',
          'avatarFileName': '1.png',
          'gender': null,
          'birthDate': null,
          'points': 0,
        });
        setState(() {
          _nameController.text = _currentUser!.displayName ?? 'لاعب جديد';
          _initialName = _nameController.text;
          _currentAvatarFileName = '1.png';
          _initialAvatarFileName = _currentAvatarFileName;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تحميل بيانات المستخدم: ${e.toString()}'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  Future<void> _selectAvatar() async {
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
        _currentAvatarFileName = selectedAvatarPath;
      });
    }
  }

  Future<void> _selectBirthDate(BuildContext context) async {
    DateTime initialDate = DateTime.now();
    if (_birthDateController.text.isNotEmpty) {
      try {
        final parts = _birthDateController.text.split('/');
        if (parts.length == 3) {
          initialDate = DateTime(
            int.parse(parts[2]),
            int.parse(parts[1]),
            int.parse(parts[0]),
          );
        }
      } catch (e) {
        // ignore
      }
    }

    DateTime? pickedDate = initialDate;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext context) => Container(
        height: 216,
        padding: const EdgeInsets.only(top: 6.0),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: SafeArea(
          top: false,
          child: CupertinoDatePicker(
            initialDateTime: initialDate,
            mode: CupertinoDatePickerMode.date,
            use24hFormat: true,
            onDateTimeChanged: (DateTime newDate) {
              pickedDate = newDate;
            },
            minimumDate: DateTime(1900),
            maximumDate: DateTime.now(),
          ),
        ),
      ),
    );

    if (pickedDate != null) {
      setState(() {
        _birthDateController.text =
            '${pickedDate!.day}/${pickedDate!.month}/${pickedDate!.year}';
      });
    }
  }

  bool _hasChanges() {
    bool nameChanged = _nameController.text.trim() != _initialName;
    bool avatarChanged = _currentAvatarFileName != _initialAvatarFileName;
    bool genderChanged = _currentGender != _initialGender;
    bool birthDateChanged =
        _birthDateController.text.trim() != _initialBirthDateString;
    return nameChanged || avatarChanged || genderChanged || birthDateChanged;
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_hasChanges()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا توجد تغييرات لحفظها.')));
      return;
    }

    setState(() {
      _isSaving = true;
      _nameErrorMessage = null;
      _birthDateErrorMessage = null;
    });

    final newName = _nameController.text.trim();
    final newGender = _currentGender;
    final newAvatarFileName = _currentAvatarFileName;

    DateTime? parsedBirthDate;
    if (_birthDateController.text.trim().isNotEmpty) {
      final parts = _birthDateController.text.trim().split('/');
      if (parts.length == 3) {
        try {
          final day = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final year = int.parse(parts[2]);
          if (day > 0 &&
              day <= 31 &&
              month > 0 &&
              month <= 12 &&
              year > 1900 &&
              year <= DateTime.now().year) {
            parsedBirthDate = DateTime(year, month, day);
          }
        } catch (_) {}
      }
    }

    if (_birthDateController.text.trim().isNotEmpty &&
        parsedBirthDate == null) {
      setState(() {
        _birthDateErrorMessage = 'تنسيق التاريخ غير صحيح';
        _isSaving = false;
      });
      return;
    }

    try {
      if (newName != _initialName) {
        final querySnapshot = await _firestore
            .collection('users')
            .where('playerName', isEqualTo: newName)
            .limit(1)
            .get();

        if (querySnapshot.docs.isNotEmpty &&
            querySnapshot.docs.first.id != _currentUser!.uid) {
          setState(() {
            _nameErrorMessage = 'اسم اللاعب هذا مستخدم بالفعل. اختر اسماً آخر.';
            _isSaving = false;
          });
          return;
        }
      }

      await _firestore.collection('users').doc(_currentUser!.uid).update({
        'playerName': newName,
        'avatarFileName': newAvatarFileName,
        'gender': newGender,
        'birthDate': parsedBirthDate != null
            ? Timestamp.fromDate(parsedBirthDate)
            : null,
      });

      await _currentUser!.updateDisplayName(newName);

      setState(() {
        _initialName = newName;
        _initialAvatarFileName = newAvatarFileName;
        _initialGender = newGender;
        _initialBirthDateString = _birthDateController.text;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ التغييرات بنجاح!')));
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل حفظ التغييرات: ${e.message}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ غير متوقع: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _isSigningOut = true;
    });
    try {
      await _auth.signOut();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تسجيل الخروج بنجاح.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تسجيل الخروج: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isSigningOut = false;
      });
    }
  }

  Widget _getAvatarWidget() {
    if (_currentAvatarFileName != null) {
      return ClipOval(
        child: Image.asset(
          'iconUser/$_currentAvatarFileName',
          width: 120,
          height: 120,
          fit: BoxFit.contain,
        ),
      );
    }
    return Icon(MdiIcons.accountCircle, size: 70, color: Colors.white);
  }

  @override
  Widget build(BuildContext context) {
    bool hasChanges = _hasChanges();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          _nameController.text.isEmpty ? 'ملف اللاعب' : _nameController.text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
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
        child: _currentUser == null
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      MdiIcons.accountAlert,
                      size: 80,
                      color: Color(0xFF55198B),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'الرجاء تسجيل الدخول لعرض ملفك الشخصي.',
                      style: TextStyle(color: Color(0xFF55198B), fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: _selectAvatar,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.3),
                                      spreadRadius: 2,
                                      blurRadius: 5,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: CircleAvatar(
                                  radius: 60,
                                  backgroundColor: const Color(0xFF55198B),
                                  child: _getAvatarWidget(),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.amber,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: const Icon(
                                    MdiIcons.pencil,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                        _buildProfileField(
                          label: 'اسم اللاعب',
                          child: TextFormField(
                            controller: _nameController,
                            style: const TextStyle(
                              color: Color(0xFF55198B),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              hintText: 'أدخل اسم اللاعب',
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              border: InputBorder.none,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'الرجاء إدخال اسم اللاعب';
                              }
                              if (_nameErrorMessage != null &&
                                  value.trim() == _nameController.text.trim()) {
                                return _nameErrorMessage;
                              }
                              return null;
                            },
                            onChanged: (value) {
                              setState(() {
                                _nameErrorMessage = null;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildProfileField(
                          label: 'البريد الإلكتروني',
                          child: Text(
                            _currentUser?.email ?? 'غير متوفر',
                            style: const TextStyle(
                              color: Color(0xFF55198B),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildProfileField(
                          label: 'الجنس',
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _currentGender,
                              hint: const Text('اختر الجنس'),
                              items: const [
                                DropdownMenuItem(
                                  value: 'ذكر',
                                  child: Text('ذكر'),
                                ),
                                DropdownMenuItem(
                                  value: 'أنثى',
                                  child: Text('أنثى'),
                                ),
                              ],
                              onChanged: (String? newValue) {
                                setState(() {
                                  _currentGender = newValue;
                                });
                              },
                              style: const TextStyle(
                                color: Color(0xFF55198B),
                                fontSize: 16,
                              ),
                              icon: const Icon(
                                MdiIcons.menuDown,
                                color: Color(0xFF55198B),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildProfileField(
                          label: 'تاريخ الميلاد',
                          child: InkWell(
                            onTap: () => _selectBirthDate(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 15.0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _birthDateController.text.isEmpty
                                        ? 'اضغط لاختيار التاريخ'
                                        : _birthDateController.text,
                                    style: TextStyle(
                                      color: _birthDateController.text.isEmpty
                                          ? Colors.grey.shade400
                                          : const Color(0xFF55198B),
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Icon(
                                    MdiIcons.calendar,
                                    color: Color(0xFF55198B),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_birthDateErrorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: 8.0,
                              right: 12.0,
                            ),
                            child: Text(
                              _birthDateErrorMessage!,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        const SizedBox(height: 40),
                        if (hasChanges)
                          SizedBox(
                            width: double.infinity,
                            child: _isSaving
                                ? const Center(
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF55198B),
                                    ),
                                  )
                                : ElevatedButton(
                                    onPressed: _saveChanges,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF55198B),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 15,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      elevation: 5,
                                    ),
                                    child: const Text(
                                      'حفظ التغييرات',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                          ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: _isSigningOut
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.red,
                                  ),
                                )
                              : ElevatedButton(
                                  onPressed: _signOut,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 5,
                                  ),
                                  child: const Text(
                                    'تسجيل الخروج',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildProfileField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$label:',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: child,
        ),
      ],
    );
  }
}
