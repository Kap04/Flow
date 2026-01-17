import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_blocking_service.dart';

class AppBlockingScreen extends StatefulWidget {
  @override
  _AppBlockingScreenState createState() => _AppBlockingScreenState();
}

class _AppBlockingScreenState extends State<AppBlockingScreen> {
  final AppBlockingService _service = AppBlockingService();
  List<BlockableApp> _apps = [];
  Set<String> _blockedApps = {};
  bool _isLoading = true;
  bool _hasUsageStatsPermission = false;
  bool _hasSystemAlertPermission = false;
  bool _hasAccessibilityPermission = false;
  
  // Category expansion states
  bool _socialExpanded = false;
  bool _videoExpanded = false;
  bool _gamesExpanded = false;
  bool _otherExpanded = false;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    await _checkPermissions();
    if (_hasUsageStatsPermission && _hasSystemAlertPermission && _hasAccessibilityPermission) {
      await _loadApps();
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _checkPermissions() async {
    _hasUsageStatsPermission = await _service.hasUsageStatsPermission();
    _hasSystemAlertPermission = await _service.hasSystemAlertPermission();
    _hasAccessibilityPermission = await _service.hasAccessibilityPermission();
  }

  Future<void> _loadApps() async {
    try {
      final apps = await _service.getBlockableApps();
      setState(() {
        _apps = apps;
        _blockedApps = apps.where((app) => app.isBlocked).map((app) => app.packageName).toSet();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading apps: $e')),
      );
    }
  }

  Future<void> _toggleAppBlock(BlockableApp app) async {
    try {
      if (app.isBlocked) {
        await _service.unblockApp(app.packageName);
        setState(() {
          _blockedApps.remove(app.packageName);
          app.isBlocked = false;
        });
      } else {
        await _service.blockApp(app.packageName);
        setState(() {
          _blockedApps.add(app.packageName);
          app.isBlocked = true;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error toggling app block: $e')),
      );
    }
  }

  Map<String, List<BlockableApp>> _categorizeApps() {
    final categories = <String, List<BlockableApp>>{
      'social': [],
      'video': [],
      'games': [],
      'other': [],
    };

    for (final app in _apps) {
      categories[app.category]?.add(app);
    }

    return categories;
  }



  Widget _buildPermissionCard() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Required Permissions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildPermissionItem(
              'Usage Stats',
              'Monitor app usage to detect when blocked apps are opened',
              _hasUsageStatsPermission,
              _service.requestUsageStatsPermission,
            ),
            const SizedBox(height: 12),
            _buildPermissionItem(
              'Draw Over Apps',
              'Show blocking overlay on top of blocked applications',
              _hasSystemAlertPermission,
              _service.requestSystemAlertPermission,
            ),
            const SizedBox(height: 12),
            _buildPermissionItem(
              'Accessibility Service',
              'Block apps even when Flow is closed',
              _hasAccessibilityPermission,
              _service.requestAccessibilityPermission,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection(String categoryKey, String categoryName, IconData icon, List<BlockableApp> apps, bool isExpanded, Function(bool) onExpansionChanged) {
    if (apps.isEmpty) return const SizedBox.shrink();

    final blockedCount = apps.where((app) => app.isBlocked).length;

    return Card(
      color: Colors.grey[900],
      child: Column(
        children: [
          ListTile(
            leading: Icon(icon, color: Colors.white, size: 24),
            title: Text(
              categoryName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '${apps.length} apps${blockedCount > 0 ? ' • $blockedCount blocked' : ''}',
              style: TextStyle(
                color: blockedCount > 0 ? const Color(0xFF6366f1) : Colors.grey[400],
                fontSize: 12,
              ),
            ),
            trailing: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.white,
            ),
            onTap: () => onExpansionChanged(!isExpanded),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                children: apps.map((app) => _buildAppTile(app)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPermissionItem(String title, String description, bool granted, Function() onRequest) {
    return Row(
      children: [
        Icon(
          granted ? Icons.check_circle : Icons.cancel,
          color: granted ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (!granted)
          TextButton(
            onPressed: () async {
              await onRequest();
              await _checkPermissions();
              setState(() {});
            },
            child: const Text('Grant'),
          ),
      ],
    );
  }



  Widget _buildAppTile(BlockableApp app) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // App icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[700],
            ),
            child: app.icon != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      app.icon!,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                    ),
                  )
                : Icon(
                    Icons.android,
                    color: Colors.grey[400],
                    size: 20,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              app.appName,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Switch(
            value: app.isBlocked,
            onChanged: (value) => _toggleAppBlock(app),
            activeColor: const Color(0xFF6366f1),
            inactiveThumbColor: Colors.grey[600],
            inactiveTrackColor: Colors.grey[800],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Block Apps', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6366f1)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Block distracting apps during your flow sessions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  if (!_hasUsageStatsPermission || !_hasSystemAlertPermission || !_hasAccessibilityPermission)
                    _buildPermissionCard(),
                  
                  if (_hasUsageStatsPermission && _hasSystemAlertPermission && _hasAccessibilityPermission) ...[
                    const SizedBox(height: 20),
                    if (_blockedApps.isNotEmpty)
                      Card(
                        color: const Color(0xFF6366f1).withOpacity(0.1),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(Icons.block, color: Color(0xFF6366f1)),
                              const SizedBox(width: 12),
                              Text(
                                '${_blockedApps.length} apps blocked',
                                style: const TextStyle(
                                  color: Color(0xFF6366f1),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    const SizedBox(height: 20),
                    
                    Builder(builder: (context) {
                      final categorizedApps = _categorizeApps();
                      return Column(
                        children: [
                          _buildCategorySection(
                            'social',
                            'Social Media',
                            Icons.people,
                            categorizedApps['social']!,
                            _socialExpanded,
                            (expanded) => setState(() => _socialExpanded = expanded),
                          ),
                          const SizedBox(height: 12),
                          _buildCategorySection(
                            'video',
                            'Video & Streaming',
                            Icons.play_circle,
                            categorizedApps['video']!,
                            _videoExpanded,
                            (expanded) => setState(() => _videoExpanded = expanded),
                          ),
                          const SizedBox(height: 12),
                          _buildCategorySection(
                            'games',
                            'Games',
                            Icons.games,
                            categorizedApps['games']!,
                            _gamesExpanded,
                            (expanded) => setState(() => _gamesExpanded = expanded),
                          ),
                          const SizedBox(height: 12),
                          _buildCategorySection(
                            'other',
                            'Other Apps',
                            Icons.apps,
                            categorizedApps['other']!,
                            _otherExpanded,
                            (expanded) => setState(() => _otherExpanded = expanded),
                          ),
                        ],
                      );
                    }),
                  ],
                ],
              ),
            ),
    );
  }
}