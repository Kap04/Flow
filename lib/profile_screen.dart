import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'app_drawer.dart';
import 'package:image_picker/image_picker.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _picker = ImagePicker();
  bool _editing = false;
  final _nameController = TextEditingController();
  String? _photoUrl;
  num _focusScore = 0;
  Map<DateTime, int> _dailyMinutes = {}; // aggregated minutes per day
  bool _loading = true;
  DateTime? _selectedDay;
  String? _selectedDayInfo;
  Offset? _lastTapPosition;
  OverlayEntry? _tooltipEntry;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
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
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sessions')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .get();

    final Map<DateTime, int> agg = {};
    for (final d in snap.docs) {
      final data = d.data();
      final ts = (data['createdAt'] as Timestamp?)?.toDate() ?? (data['startTime'] as Timestamp?)?.toDate();
      final dur = (data['duration'] as num?)?.toInt() ?? 0;
      if (ts == null) continue;
      final day = DateTime(ts.year, ts.month, ts.day);
      agg[day] = (agg[day] ?? 0) + dur;
    }

    setState(() {
      _dailyMinutes = agg;
      _loading = false;
    });
  }

  Future<void> _pickAndUploadPhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final file = File(picked.path);

    // Use local signing server. On Android emulator use 10.0.2.2 to reach host machine.
    final signUrl = Uri.parse('http://10.0.2.2:3000/sign');

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

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({'photoURL': secureUrl}, SetOptions(merge: true));
      try {
        await user.updatePhotoURL(secureUrl);
      } catch (_) {}
      setState(() => _photoUrl = secureUrl);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    }
  }

  Future<void> _saveName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({'displayName': name}, SetOptions(merge: true));
    try {
      await user.updateDisplayName(name);
    } catch (_) {}
    setState(() => _editing = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name updated')));
  }

  Color _colorForMinutes(int m) {
    // buckets: 0 none, 30-60 light, 60-120 mid, >120 dark
    if (m <= 0) return Colors.transparent;
    if (m < 30) return const Color(0xFFEAF6FF); // really light
    if (m < 60) return const Color(0xFFCCE9FF); // light
    if (m < 120) return const Color(0xFF66B8FF); // mid
    return const Color(0xFF0066CC); // dark
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
                        onTap: _pickAndUploadPhoto,
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.grey[800],
                          backgroundImage: _photoUrl != null ? CachedNetworkImageProvider(_photoUrl!) : null,
                          child: _photoUrl == null ? const Icon(Icons.person, size: 40, color: Colors.white54) : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _editing
                                      ? TextField(controller: _nameController, style: const TextStyle(color: Colors.white, fontSize: 18))
                                      : Text(_nameController.text.isEmpty ? (user?.displayName ?? 'Unnamed') : _nameController.text, style: const TextStyle(color: Colors.white, fontSize: 18)),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.white54),
                                  onPressed: () => setState(() => _editing = !_editing),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('Focus score', style: TextStyle(color: Colors.white54)),
                            Text(_focusScore.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
                    
                    // Start from 17 weeks ago, aligned to Monday
                    final startDate = todayNormalized.subtract(Duration(days: (totalWeeks * 7) - 1));
                    final mondayStart = startDate.subtract(Duration(days: startDate.weekday - 1));
                    
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
                      monthWidgets.add(SizedBox(width: labelWidthPx, child: Text(mon, style: const TextStyle(color: Colors.white54, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis)));
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
                              border: isSelected
                                  ? Border.all(color: Colors.yellowAccent, width: 2)
                                  : (withinAppLifetime && mins == 0 ? Border.all(color: Colors.grey.shade300) : (isToday ? Border.all(color: Colors.white24) : null)),
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
                          _legendBox(const Color(0xFFEAF6FF)),
                          const SizedBox(width: 3),
                          _legendBox(const Color(0xFFCCE9FF)),
                          const SizedBox(width: 3),
                          _legendBox(const Color(0xFF66B8FF)),
                          const SizedBox(width: 3),
                          _legendBox(const Color(0xFF0066CC)),
                          const SizedBox(width: 6),
                          const Text('More', style: TextStyle(color: Colors.white54, fontSize: 9)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => GoRouter.of(context).go('/history'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
                      child: const Text('Session history', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
    );
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
