import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
// removed duplicate cloud_firestore import
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'app_drawer.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _picker = ImagePicker();
  bool _editing = false;
  final _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  String? _photoUrl;
  num _focusScore = 0;
  Map<DateTime, int> _dailyMinutes = {}; // aggregated minutes per day
  int _streak = 0;
  bool _loading = true;
  DateTime? _selectedDay;
  String? _selectedDayInfo;
  Offset? _lastTapPosition;
  OverlayEntry? _tooltipEntry;
  
  // Tag breakdown pie chart state
  Map<String, int> _tagBreakdown = {};
  bool _showLastWeek = true; // true = last week, false = last month
  bool _loadingTags = true;
  
  // Focus trend line chart state
  List<FlSpot> _focusTrendData = [];
  double _avgFocusScore = 0;
  double _previousAvgFocusScore = 0;
  int? _selectedSpotIndex;
  bool _loadingTrend = true;
  DateTime? _selectedDate;
  double? _selectedFocusScore;

  @override
  void initState() {
    super.initState();
    // Defer heavy profile loading until after the first frame to avoid blocking
    // UI startup work and reduce skipped frames at app launch.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data() ?? {};
    setState(() {
      _photoUrl = (data['photoURL'] as String?) ?? user.photoURL;
      _nameController.text = (data['displayName'] as String?) ?? (user.displayName ?? '');
      _focusScore = (data['focusScore'] as num?) ?? 0;
    });

    // Load sessions for last 90 days and aggregate
    final since = DateTime.now().subtract(const Duration(days: 90));
    
    final Map<DateTime, int> agg = {};
    
    // Load from regular sessions (Pomodoro timer)
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sessions')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .get();

    for (final d in snap.docs) {
      final data = d.data();
      final ts = (data['createdAt'] as Timestamp?)?.toDate() ?? (data['startTime'] as Timestamp?)?.toDate();
      final dur = (data['duration'] as num?)?.toInt() ?? 0;
      if (ts == null) continue;
      final day = DateTime(ts.year, ts.month, ts.day);
      agg[day] = (agg[day] ?? 0) + dur;
    }
    
    // Load from sprint_sessions (Time Blocks)
    final sprintSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sprint_sessions')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .get();
    
    print('📅 Heat Map: Found ${sprintSnap.docs.length} sprint sessions');

    for (final d in sprintSnap.docs) {
      final data = d.data();
      final ts = (data['timestamp'] as Timestamp?)?.toDate() ?? (data['createdAt'] as Timestamp?)?.toDate();
      final dur = (data['actualMinutes'] as num?)?.toInt() ?? 0;
      final completed = data['completed'] ?? false;
      print('  Session: date=$ts, duration=$dur, completed=$completed');
      if (ts == null || !completed) continue;
      final day = DateTime(ts.year, ts.month, ts.day);
      agg[day] = (agg[day] ?? 0) + dur;
    }

    setState(() {
      _dailyMinutes = agg;
      _streak = _computeStreak(agg);
      _loading = false;
    });
    
    // Load tag breakdown and focus trend
    await _loadTagBreakdown();
    await _loadFocusTrend();
  }
  
  Future<void> _loadFocusTrend() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    setState(() => _loadingTrend = true);
    
    // Get last 30 days of data
    final now = DateTime.now();
    final since = now.subtract(const Duration(days: 30));
    
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sessions')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('createdAt')
        .get();
    
    final sprintSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sprint_sessions')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('timestamp')
        .get();
    
    // Combine and sort all sessions by date
    final Map<DateTime, List<int>> dailySessions = {};
    
    for (final d in snap.docs) {
      final data = d.data();
      final ts = (data['createdAt'] as Timestamp?)?.toDate();
      final dur = (data['duration'] as num?)?.toInt() ?? 0;
      if (ts == null || dur == 0) continue;
      final day = DateTime(ts.year, ts.month, ts.day);
      dailySessions.putIfAbsent(day, () => []).add(dur);
    }
    
    for (final d in sprintSnap.docs) {
      final data = d.data();
      final ts = (data['timestamp'] as Timestamp?)?.toDate();
      final dur = (data['actualMinutes'] as num?)?.toInt() ?? 0;
      final completed = data['completed'] ?? false;
      if (ts == null || dur == 0 || !completed) continue;
      final day = DateTime(ts.year, ts.month, ts.day);
      dailySessions.putIfAbsent(day, () => []).add(dur);
    }
    
    // Create spots for all 30 days (fill missing days with 0)
    final List<FlSpot> spots = [];
    final Map<DateTime, double> dailyAverages = {};
    
    for (final day in dailySessions.keys) {
      final sessions = dailySessions[day]!;
      final avgDuration = sessions.reduce((a, b) => a + b) / sessions.length;
      dailyAverages[day] = avgDuration;
    }
    
    // Create spots for all 30 days
    for (int i = 0; i < 30; i++) {
      final day = DateTime.now().subtract(Duration(days: 29 - i));
      final dayKey = DateTime(day.year, day.month, day.day);
      final avgDuration = dailyAverages[dayKey] ?? 0;
      spots.add(FlSpot(i.toDouble(), avgDuration));
    }
    
    // Calculate overall average and previous period average for comparison
    final allDaysWithData = dailySessions.keys.toList()..sort();
    final recentDays = allDaysWithData.length >= 7 ? allDaysWithData.sublist(allDaysWithData.length - 7) : allDaysWithData;
    final previousDays = allDaysWithData.length >= 14 ? allDaysWithData.sublist(allDaysWithData.length - 14, allDaysWithData.length - 7) : [];
    
    double recentAvg = 0;
    if (recentDays.isNotEmpty) {
      final recentSessions = recentDays.expand((day) => dailySessions[day]!).toList();
      recentAvg = recentSessions.reduce((a, b) => a + b) / recentSessions.length;
    }
    
    double previousAvg = 0;
    if (previousDays.isNotEmpty) {
      final previousSessions = previousDays.expand((day) => dailySessions[day]!).toList();
      previousAvg = previousSessions.reduce((a, b) => a + b) / previousSessions.length;
    }
    
    setState(() {
      _focusTrendData = spots;
      _avgFocusScore = recentAvg;
      _previousAvgFocusScore = previousAvg;
      _loadingTrend = false;
    });
  }
  
  Future<void> _loadTagBreakdown() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    setState(() => _loadingTags = true);
    
    final days = _showLastWeek ? 7 : 30;
    final since = DateTime.now().subtract(Duration(days: days));
    
    final Map<String, int> breakdown = {};
    
    // Load from regular sessions (Pomodoro timer)
    final sessionsSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sessions')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .get();
    
    print('📊 Tag Breakdown - Regular sessions: ${sessionsSnap.docs.length}');
    
    for (final d in sessionsSnap.docs) {
      final data = d.data();
      String tag = (data['tag'] as String?) ?? 'Unset';
      if (tag.trim().isEmpty) tag = 'Unset';
      
      final duration = (data['duration'] as num?)?.toInt() ?? 0;
      print('  Pomodoro: tag=$tag, duration=$duration');
      if (duration > 0) {
        breakdown[tag] = (breakdown[tag] ?? 0) + duration;
      }
    }
    
    // Load from sprint_sessions (Time Blocks)
    final sprintSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sprint_sessions')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .get();
    
    print('📊 Tag Breakdown - Sprint sessions: ${sprintSnap.docs.length}');
    
    for (final d in sprintSnap.docs) {
      final data = d.data();
      String tag = (data['tag'] as String?) ?? 'Unset';
      if (tag.trim().isEmpty) tag = 'Unset';
      
      final duration = (data['actualMinutes'] as num?)?.toInt() ?? 
                      (data['duration'] as num?)?.toInt() ?? 0;
      final completed = data['completed'] ?? false;
      
      print('  Sprint: tag=$tag, duration=$duration, completed=$completed, data=$data');
      
      if (duration > 0 && completed) {
        breakdown[tag] = (breakdown[tag] ?? 0) + duration;
        print('    ✅ Added to breakdown: $tag now has ${breakdown[tag]} minutes');
      } else {
        print('    ❌ Skipped: duration=$duration, completed=$completed');
      }
    }
    
    print('📊 Final breakdown: $breakdown');
    
    setState(() {
      _tagBreakdown = breakdown;
      _loadingTags = false;
    });
  }

  int _computeStreak(Map<DateTime, int> agg) {
    // Count consecutive days with at least one minute of session, starting from today.
    int streak = 0;
    final now = DateTime.now();
    DateTime day = DateTime(now.year, now.month, now.day);
    while (true) {
      final minutes = agg[day] ?? 0;
      if (minutes > 0) {
        streak += 1;
        day = day.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  Future<void> _pickAndUploadPhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final file = File(picked.path);

    // Use local signing server. On Android emulator use 10.0.2.2 to reach host machine.
    final signUrl = Uri.parse('https://flow-sigining.vercel.app/sign');

    try {
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
      final signResp = await http.post(
        signUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'timestamp': timestamp, 'folder': 'profile_photos'}),
      );
      if (signResp.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signing failed')));
        return;
      }

      final Map<String, dynamic> signJson = jsonDecode(signResp.body) as Map<String, dynamic>;
      final signature = signJson['signature'] as String?;
      final apiKey = signJson['api_key'] as String?;
      if (signature == null || apiKey == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid sign response')));
        return;
      }

      // Upload to Cloudinary
      final cloudName = 'dfxguyeb1';
      final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/auto/upload');
      final req = http.MultipartRequest('POST', uri);
      req.files.add(await http.MultipartFile.fromPath('file', file.path));
      req.fields['api_key'] = apiKey;
      req.fields['timestamp'] = timestamp.toString();
      req.fields['signature'] = signature;
      req.fields['folder'] = 'profile_photos';

      final streamed = await req.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed')));
        return;
      }

      final Map<String, dynamic> uploaded = jsonDecode(resp.body) as Map<String, dynamic>;
      final String secureUrl = uploaded['secure_url'] as String? ?? uploaded['url'] as String? ?? '';
      if (secureUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No URL returned from Cloudinary')));
        return;
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({'photoURL': secureUrl, 'avatarId': 'custom', 'avatarProvider': 'custom'}, SetOptions(merge: true));
      try {
        await user.updatePhotoURL(secureUrl);
      } catch (_) {}
      setState(() => _photoUrl = secureUrl);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    }
  }

  Future<void> _selectGooglePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Prefer the photoURL coming from the google provider entry so we don't pick up any
    // photoURL that was previously set on the firebase user (which may be an app avatar).
    String? googlePhoto;
    try {
      final matches = user.providerData.where((p) => p.providerId == 'google.com');
      if (matches.isNotEmpty) {
        googlePhoto = matches.first.photoURL;
      } else {
        googlePhoto = null;
      }
    } catch (_) {
      googlePhoto = null;
    }
    if (googlePhoto == null || googlePhoto.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Google profile photo available')));
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({'photoURL': googlePhoto, 'avatarId': 'google', 'avatarProvider': 'google'}, SetOptions(merge: true));
      try { await user.updatePhotoURL(googlePhoto); } catch (_) {}
      setState(() => _photoUrl = googlePhoto);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Using Google profile photo')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to set Google photo: $e')));
    }
  }

  Future<void> _selectAvatarDoc(QueryDocumentSnapshot doc) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final data = doc.data() as Map<String, dynamic>;
    final url = (data['secureUrl'] ?? data['url'] ?? data['secure_url']) as String?;
    if (url == null || url.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Avatar missing url')));
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({'photoURL': url, 'avatarId': doc.id, 'avatarProvider': 'avatars'}, SetOptions(merge: true));
      try { await user.updatePhotoURL(url); } catch (_) {}
      setState(() => _photoUrl = url);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Avatar selected')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to set avatar: $e')));
    }
  }

  Future<void> _showAvatarPicker() async {
    final user = FirebaseAuth.instance.currentUser;
    final hasGoogle = user?.providerData.any((p) => p.providerId == 'google.com') ?? false;
    String? googlePhotoUrl;
    if (hasGoogle) {
      try {
        final matches = user!.providerData.where((p) => p.providerId == 'google.com');
        if (matches.isNotEmpty) googlePhotoUrl = matches.first.photoURL;
        else googlePhotoUrl = null;
      } catch (_) {
        googlePhotoUrl = null;
      }
    }

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        child: SizedBox(
          width: double.maxFinite,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Choose avatar', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.of(ctx).pop()),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Simplified picker: first '+' (upload), second Google photo (or signin hint), then avatars
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('avatars').orderBy('createdAt', descending: false).snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    final docs = snap.data?.docs ?? [];

                    // Build leading items: upload and google (google shown even if no photo but disabled)
                    List<Widget> leadingItems = [];
                    // Upload (+)
                    leadingItems.add(GestureDetector(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _pickAndUploadPhoto();
                      },
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.grey[800],
                        child: const Icon(Icons.add, color: Colors.white, size: 28),
                      ),
                    ));

                    // Google profile photo or prompt
                    leadingItems.add(GestureDetector(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        if (hasGoogle) {
                          _selectGooglePhoto();
                        } else {
                          // Show hint to sign in with Google
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in with Google to use your Google profile photo')));
                        }
                      },
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.grey[800],
                        backgroundImage: (hasGoogle && googlePhotoUrl != null && googlePhotoUrl.trim().isNotEmpty)
                            ? NetworkImage(googlePhotoUrl.trim())
                            : null,
                        child: (!hasGoogle || googlePhotoUrl == null || googlePhotoUrl.trim().isEmpty)
                            ? const Text('G', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                            : null,
                      ),
                    ));

                    // Combine leading items + avatars docs
                    final allWidgets = <Widget>[];
                    allWidgets.addAll(leadingItems);
                    for (final d in docs) {
                      final data = d.data() as Map<String, dynamic>;
                      final url = (data['secureUrl'] ?? data['url'] ?? data['secure_url']) as String?;
                      allWidgets.add(GestureDetector(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _selectAvatarDoc(d);
                        },
                        child: CircleAvatar(
                          radius: 36,
                          backgroundColor: Colors.grey[800],
                          backgroundImage: (url != null && url.trim().isNotEmpty) ? CachedNetworkImageProvider(url.trim()) : null,
                        ),
                      ));
                    }

                    if (allWidgets.isEmpty) return const Center(child: Text('No avatars available', style: TextStyle(color: Colors.white54)));
                    return GridView.count(
                      padding: const EdgeInsets.all(16),
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      children: allWidgets,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    try {
      await userRef.set({'displayName': name, 'uid': user.uid}, SetOptions(merge: true));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save name: $e')));
      return;
    }
    // Re-read the document to ensure leaderboard and other listeners pick up the change.
    try {
      await userRef.set({'lastUpdatedProfileAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    } catch (_) {}
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final freshAuth = FirebaseAuth.instance.currentUser;
      final fresh = await userRef.get();
      final freshName = (fresh.data()?['displayName'] as String?) ?? freshAuth?.displayName ?? name;
      // attempt to update the FirebaseAuth profile as well
      try {
        await user.updateDisplayName(freshName);
      } catch (e) {
        // ignore but log
        // ignore: avoid_print
        print('profile: updateDisplayName failed: $e');
      }
      setState(() {
        _editing = false;
        _nameController.text = freshName;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name updated')));
    } catch (e) {
      // if reload failed, still update local UI and inform user
      // ignore: avoid_print
      print('profile: save name post-update reload failed: $e');
      setState(() {
        _editing = false;
        _nameController.text = name;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Name updated (local) — refresh if needed: $e')));
    }
  }

  Color _colorForMinutes(int m) {
  // buckets: 0 none, <60 -> dark, 60-120 -> mid, >120 -> brightest
  if (m <= 0) return Colors.transparent;
  if (m < 60) return const Color.fromRGBO(0, 84, 153, 0.9); // darker, high-contrast low activity
  if (m < 120) return const Color.fromRGBO(0, 140, 255, 0.85); // brighter mid bucket
  // highest bucket: very bright saturated blue with good contrast on dark bg
  return const Color.fromRGBO(0, 180, 255, 0.95);
  }

  Widget _legendBox(Color color, [bool outline = false]) {
    if (outline) {
      return Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.transparent, border: Border.all(color: Colors.grey.shade700), borderRadius: BorderRadius.circular(2)));
    }
    return Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)));
  }

  String _monthShort(int m) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[(m - 1).clamp(0, 11)];
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Profile'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      backgroundColor: Colors.black,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _showAvatarPicker,
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.grey[800],
                          backgroundImage: _photoUrl != null ? CachedNetworkImageProvider(_photoUrl!) : null,
                          child: _photoUrl == null ? const Icon(Icons.person, size: 40, color: Colors.white54) : null,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _editing
                                      ? TextField(
                                          controller: _nameController,
                                          focusNode: _nameFocus,
                                          autofocus: true,
                                          style: const TextStyle(color: Colors.white, fontSize: 18),
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (_) => _saveName(),
                                        )
                                      : Text(_nameController.text.isEmpty ? (user?.displayName ?? 'Unnamed') : _nameController.text, style: const TextStyle(color: Colors.white, fontSize: 18)),
                                ),
                                IconButton(
                                  icon: _editing ? const Icon(Icons.check, color: Colors.white54) : const Icon(Icons.edit, color: Colors.white54),
                                  onPressed: () async {
                                    if (_editing) {
                                      await _saveName();
                                    } else {
                                      setState(() => _editing = true);
                                      // focus the field after frame
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        _nameFocus.requestFocus();
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      const Text('Focus score', style: TextStyle(color: Colors.white54)),
                                      Text(_focusScore.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      const Text('Streak', style: TextStyle(color: Colors.white54)),
                                      Text('$_streak', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('Last 90 days', style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 12),
                  // GitHub-style heatmap: weeks as columns, Mon->Sun rows. Shows exactly 17 weeks.
                  Builder(builder: (context) {
                    // Show exactly 17 weeks (119 days) consistently
                    const totalWeeks = 16;
                    final today = DateTime.now();
                    final todayNormalized = DateTime(today.year, today.month, today.day);
                    
                    // Start so that the grid shows the most recent `totalWeeks` weeks
                    // and the final column includes the current week (so 'today' can appear).
                    // Find the Monday of the current week, then go back (totalWeeks - 1) weeks.
                    final thisWeekMonday = todayNormalized.subtract(Duration(days: todayNormalized.weekday - 1));
                    final mondayStart = thisWeekMonday.subtract(Duration(days: (totalWeeks - 1) * 7));
                    
                    const columnWidth = 16.0;
                    const spacing = 4.0;

                    // build month labels - always show all 17 weeks
                    List<Widget> monthWidgets = [];
                    int w = 0;
                    while (w < totalWeeks) {
                      final weekStart = mondayStart.add(Duration(days: w * 7));
                      final mon = _monthShort(weekStart.month);
                      int span = 1;
                      while (w + span < totalWeeks) {
                        final nextWeekStart = mondayStart.add(Duration(days: (w + span) * 7));
                        if (nextWeekStart.month == weekStart.month) span++; else break;
                      }
                      final labelWidthPx = (span * columnWidth + (span - 1) * spacing).ceilToDouble();
                      // Only show the month label if there's enough horizontal space
                      // to display it without truncation (mobile-friendly).
                      final labelStyle = const TextStyle(color: Colors.white54, fontSize: 10);
                      final tp = TextPainter(text: TextSpan(text: mon, style: labelStyle), textDirection: TextDirection.ltr)..layout();
                      if (labelWidthPx >= tp.width + 4) {
                        monthWidgets.add(SizedBox(
                          width: labelWidthPx,
                          child: Center(child: Text(mon, style: labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ));
                      } else {
                        // Keep the spacer so columns align, but don't draw a truncated label.
                        monthWidgets.add(SizedBox(width: labelWidthPx));
                      }
                      w += span;
                    }

                    // build grid columns - always show all 17 weeks
                    List<Widget> cols = [];
                    for (int ww = 0; ww < totalWeeks; ww++) {
                      List<Widget> rows = [];
                      for (int weekday = 0; weekday < 7; weekday++) {
                        final day = mondayStart.add(Duration(days: ww * 7 + weekday));
                        final key = DateTime(day.year, day.month, day.day);
                        final withinAppLifetime = !day.isBefore(DateTime(2024, 7, 1)) && !day.isAfter(todayNormalized); // Adjust start date as needed
                        final mins = withinAppLifetime ? (_dailyMinutes[key] ?? 0) : 0;
                        final color = mins > 0 ? _colorForMinutes(mins) : Colors.transparent;
                        final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
                        final isSelected = _selectedDay != null && day.year == _selectedDay!.year && day.month == _selectedDay!.month && day.day == _selectedDay!.day;
                        rows.add(GestureDetector(
                          onTapDown: (tap) => _lastTapPosition = tap.globalPosition,
                          onTap: withinAppLifetime
                              ? () {
                                  setState(() {
                                    _selectedDay = day;
                                    _selectedDayInfo = '${mins} min on ${_monthShort(day.month)} ${day.day}';
                                  });
                                  _showTooltipAt(_lastTapPosition, _selectedDayInfo ?? '');
                                }
                              : null,
                          child: Container(
                            width: columnWidth,
                            height: columnWidth,
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                // Do not show a selection border on tap (mobile touch UX).
                border: (withinAppLifetime && mins == 0)
                  ? Border.all(color: Colors.grey.shade300)
                  : (isToday ? Border.all(color: Colors.white24) : null),
                            ),
                          ),
                        ));
                      }
                      cols.add(Column(children: rows, mainAxisSize: MainAxisSize.min));
                      if (ww != totalWeeks - 1) cols.add(SizedBox(width: spacing));
                    }

                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(8)),
                      child: IntrinsicWidth(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(mainAxisSize: MainAxisSize.min, children: monthWidgets),
                          const SizedBox(height: 6),
                          SizedBox(height: (columnWidth + spacing) * 7, child: Row(mainAxisSize: MainAxisSize.min, children: cols)),
                        ]),
                      ),
                    );
                  }),
                  // Legend placed below the heatmap, bottom-right
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Less', style: TextStyle(color: Colors.white54, fontSize: 9)),
                          const SizedBox(width: 6),
                          _legendBox(Colors.transparent, true),
                          const SizedBox(width: 6),
                          _legendBox(const Color.fromRGBO(0, 84, 153, 0.9)),
                          const SizedBox(width: 3),
                          _legendBox(const Color.fromRGBO(0, 140, 255, 0.85)),
                          const SizedBox(width: 3),
                          _legendBox(const Color.fromRGBO(0, 180, 255, 0.95)),
                          const SizedBox(width: 6),
                          const Text('More', style: TextStyle(color: Colors.white54, fontSize: 9)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 32),
                  
                  // Tag Breakdown Pie Chart Section
                  _buildTagBreakdownSection(),
                  
                  const SizedBox(height: 48),
                  
                  // Focus Trend Line Chart Section
                  _buildFocusTrendSection(),
                  
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => GoRouter.of(context).push('/history'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
                      child: const Text('Session history', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
  
  Widget _buildTagBreakdownSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tag Breakdown',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        
        // Time period selector - segmented control style
        Center(
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSegmentButton('Last Week', _showLastWeek),
                _buildSegmentButton('Last Month', !_showLastWeek),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Pie chart
        if (_loadingTags)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40.0),
              child: CircularProgressIndicator(color: Colors.white54),
            ),
          )
        else if (_tagBreakdown.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(
                children: [
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey[800]!, width: 40),
                    ),
                    child: Center(
                      child: Text(
                        'No sessions',
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No sessions in ${_showLastWeek ? 'last week' : 'last month'}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            ),
          )
        else
          Column(
            children: [
              SizedBox(
                height: 220,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 60,
                    sections: _buildPieChartSections(),
                    borderData: FlBorderData(show: false),
                    pieTouchData: PieTouchData(enabled: false),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Horizontal legend
              Wrap(
                spacing: 16,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: _buildLegendItems(),
              ),
            ],
          ),
      ],
    );
  }
  
  Widget _buildSegmentButton(String label, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showLastWeek = label == 'Last Week';
        });
        _loadTagBreakdown();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey[800] : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[500],
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
  
  List<PieChartSectionData> _buildPieChartSections() {
    final colors = _getTagColors();
    final total = _tagBreakdown.values.fold(0, (sum, val) => sum + val);
    if (total == 0) return [];
    
    final sortedEntries = _tagBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sortedEntries.map((entry) {
      final percentage = (entry.value / total * 100);
      return PieChartSectionData(
        color: colors[entry.key] ?? Colors.grey,
        value: entry.value.toDouble(),
        title: percentage >= 5 ? '${percentage.toStringAsFixed(0)}%' : '',
        radius: 50,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }
  
  List<Widget> _buildLegendItems() {
    final colors = _getTagColors();
    final sortedEntries = _tagBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sortedEntries.map((entry) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: colors[entry.key] ?? Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${entry.key} (${entry.value}m)',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      );
    }).toList();
  }
  
  Map<String, Color> _getTagColors() {
    // Cool colors palette for tags
    final coolColors = [
      const Color(0xFF6A5ACD), // Slate blue
      const Color(0xFF4169E1), // Royal blue
      const Color(0xFF00CED1), // Dark turquoise
      const Color(0xFF20B2AA), // Light sea green
      const Color(0xFF9370DB), // Medium purple
      const Color(0xFF5F9EA0), // Cadet blue
      const Color(0xFF87CEEB), // Sky blue
      const Color(0xFF48D1CC), // Medium turquoise
      const Color(0xFF7B68EE), // Medium slate blue
      const Color(0xFF00BFFF), // Deep sky blue
    ];
    
    final Map<String, Color> colorMap = {};
    final tags = _tagBreakdown.keys.toList();
    
    for (int i = 0; i < tags.length; i++) {
      colorMap[tags[i]] = coolColors[i % coolColors.length];
    }
    
    return colorMap;
  }
  
  // Focus Trend Line Chart Section
  Widget _buildFocusTrendSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Focus Trend',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        if (_loadingTrend)
          const Center(child: CircularProgressIndicator(color: Colors.white70))
        else if (_focusTrendData.isEmpty)
          Container(
            height: 200,
            alignment: Alignment.center,
            child: const Text(
              'No focus data available',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          )
        else ...[
          // Info header - shows selected data or average
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _selectedDate != null && _selectedFocusScore != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDate(_selectedDate!),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_selectedFocusScore!.toStringAsFixed(0)}m focus',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      const Text(
                        'Average Focus',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_avgFocusScore.toStringAsFixed(0)}m',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildTrendArrow(),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          // Line Chart
          Container(
            height: 200,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        // Only show months at the ends
                        if (value == 0) {
                          final date = DateTime.now().subtract(const Duration(days: 29));
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              _formatMonthYear(date),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          );
                        } else if (value == 29) {
                          final date = DateTime.now();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              _formatMonthYear(date),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: 29,
                minY: 0,
                maxY: _focusTrendData.map((e) => e.y).reduce((a, b) => a > b ? a : b) * 1.2,
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (_) => [],
                  ),
                  touchCallback: (event, response) {
                    if (event is FlTapUpEvent && response != null && response.lineBarSpots != null && response.lineBarSpots!.isNotEmpty) {
                      final spot = response.lineBarSpots!.first;
                      final dayIndex = spot.x.toInt();
                      // Snap to nearest 10-day interval (0, 10, 20)
                      final snappedIndex = (dayIndex / 10).round() * 10;
                      final clampedIndex = snappedIndex.clamp(0, 29);
                      
                      final date = DateTime.now().subtract(Duration(days: 29 - clampedIndex));
                      final focusScore = _focusTrendData[clampedIndex].y;
                      
                      setState(() {
                        _selectedSpotIndex = clampedIndex;
                        _selectedDate = date;
                        _selectedFocusScore = focusScore;
                      });
                    } else if (event is FlPanEndEvent || event is FlLongPressEnd) {
                      setState(() {
                        _selectedSpotIndex = null;
                        _selectedDate = null;
                        _selectedFocusScore = null;
                      });
                    }
                  },
                  handleBuiltInTouches: true,
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: _focusTrendData,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: const Color(0xFF4169E1),
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF4169E1).withOpacity(0.2),
                          const Color(0xFF4169E1).withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
  
  // Trend arrow based on leaderboard implementation
  Widget _buildTrendArrow() {
    final bool isPositive = _avgFocusScore >= _previousAvgFocusScore;
    final Color arrowColor = isPositive ? const Color(0xFF4CAF50) : const Color(0xFFEF5350);
    final IconData arrowIcon = isPositive ? Icons.arrow_upward : Icons.arrow_downward;
    final double rotationAngle = isPositive ? math.pi / 4 : -math.pi / 4; // 45° or -45°
    
    return Transform.rotate(
      angle: rotationAngle,
      child: Icon(
        arrowIcon,
        color: arrowColor,
        size: 18,
      ),
    );
  }
  
  String _formatMonthYear(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.year}';
  }
  
  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _showTooltipAt(Offset? globalPos, String text) {
    _removeTooltip();
    if (globalPos == null) return;
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(builder: (context) {
      // try to clamp tooltip near the tap position and keep it on screen
      final mq = MediaQuery.of(context).size;
      const tooltipWidth = 140.0;
      const tooltipHeight = 40.0;
      double left = globalPos.dx - (tooltipWidth / 2);
      double top = globalPos.dy - tooltipHeight - 8; // above the tapped point
      // clamp to screen
      left = left.clamp(8.0, mq.width - tooltipWidth - 8.0);
      top = top.clamp(8.0, mq.height - tooltipHeight - 8.0);
      return Positioned(
        left: left,
        top: top,
        width: tooltipWidth,
        height: tooltipHeight,
        child: Material(
          color: Colors.transparent,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.78), borderRadius: BorderRadius.circular(6), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)]),
            child: Text(text, style: const TextStyle(color: Color(0xFFEEEEEE), fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ),
      );
    });
    _tooltipEntry = entry;
    overlay?.insert(entry);
    Future.delayed(const Duration(seconds: 2), () => _removeTooltip());
  }

  void _removeTooltip() {
    try {
      _tooltipEntry?.remove();
    } catch (_) {}
    _tooltipEntry = null;
  }
}
