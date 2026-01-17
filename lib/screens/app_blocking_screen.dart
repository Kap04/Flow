import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_blocking_service.dart';

class AppBlockingScreen extends StatefulWidget {
  const AppBlockingScreen({Key? key}) : super(key: key);

  @override
  State<AppBlockingScreen> createState() => _AppBlockingScreenState();
}

class _AppBlockingScreenState extends State<AppBlockingScreen> {
  List<BlockableApp> _allApps = [];
  List<String> _blockedApps = [];
  bool _isLoading = true;
  bool _hasPermissions = false;

  @override
  void initState() {
    super.initState();
    _initializeBlockingScreen();
  }

  Future<void> _initializeBlockingScreen() async {
    setState(() => _isLoading = true);
    
    // Check permissions first
    _hasPermissions = await AppBlockingService.hasAllPermissions();
    
    if (!_hasPermissions) {
      // Request permissions
      final granted = await AppBlockingService.requestPermissions();
      _hasPermissions = granted;
    }

    if (_hasPermissions) {
      // Load apps and blocked status
      await _loadApps();
      
      // Ensure blocking service is running
      final isRunning = await AppBlockingService.isServiceRunning();
      if (!isRunning) {
        await AppBlockingService.startBlockingService();
      }
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _loadApps() async {
    try {
      // Get all blockable apps
      final apps = await AppBlockingService.getBlockableApps();
      
      // Get currently blocked apps
      final blockedApps = await AppBlockingService.getBlockedApps();
      
      // Update blocked status for each app
      for (var app in apps) {
        app.isBlocked = blockedApps.contains(app.packageName);
      }
      
      // Sort apps: social media first, then others
      apps.sort((a, b) {
        const priorityOrder = ['social', 'communication', 'video', 'games', 'news', 'other'];
        final aIndex = priorityOrder.indexOf(a.category);
        final bIndex = priorityOrder.indexOf(b.category);
        
        if (aIndex != bIndex) {
          return aIndex.compareTo(bIndex);
        }
        return a.appName.compareTo(b.appName);
      });
      
      setState(() {
        _allApps = apps;
        _blockedApps = blockedApps;
      });
    } catch (e) {
      print('Error loading apps: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading apps: $e')),
        );
      }
    }
  }

  Future<void> _toggleAppBlocking(BlockableApp app) async {
    // Show loading indicator
    setState(() => _isLoading = true);
    
    try {
      bool success;
      if (app.isBlocked) {
        success = await AppBlockingService.unblockApp(app.packageName);
      } else {
        success = await AppBlockingService.blockApp(app.packageName);
      }
      
      if (success) {
        setState(() {
          app.isBlocked = !app.isBlocked;
          if (app.isBlocked) {
            _blockedApps.add(app.packageName);
          } else {
            _blockedApps.remove(app.packageName);
          }
        });
        
        // Show feedback
        final action = app.isBlocked ? 'blocked' : 'unblocked';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${app.appName} $action successfully'),
              backgroundColor: app.isBlocked ? Colors.red[600] : Colors.green[600],
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to ${app.isBlocked ? 'unblock' : 'block'} ${app.appName}'),
              backgroundColor: Colors.red[600],
            ),
          );
        }
      }
    } catch (e) {
      print('Error toggling app blocking: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red[600],
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildPermissionRequest() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.security,
              size: 80,
              color: Colors.orange[600],
            ),
            const SizedBox(height: 24),
            Text(
              'Permissions Required',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'To block apps effectively, Flow needs special permissions:\n\n'
              '• Usage Access - Monitor app launches\n'
              '• Accessibility Service - Block app access\n'
              '• Display over other apps - Show blocking overlay\n'
              '• Notification Access - Block notifications',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                final granted = await AppBlockingService.requestPermissions();
                if (granted) {
                  _initializeBlockingScreen();
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Permissions are required for app blocking to work'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('Grant Permissions'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppList() {
    if (_allApps.isEmpty) {
      return const Center(
        child: Text('No blockable apps found'),
      );
    }

    return ListView.builder(
      itemCount: _allApps.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final app = _allApps[index];
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: app.icon != null 
              ? Image.memory(app.icon!, width: 40, height: 40)
              : Icon(Icons.android, size: 40, color: Colors.grey[600]),
            title: Text(
              app.appName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _getCategoryDisplayName(app.category),
              style: TextStyle(color: Colors.grey[600]),
            ),
            trailing: Switch(
              value: app.isBlocked,
              onChanged: _isLoading ? null : (value) => _toggleAppBlocking(app),
              activeColor: Colors.red[600],
              inactiveThumbColor: Colors.grey[400],
            ),
          ),
        );
      },
    );
  }

  String _getCategoryDisplayName(String category) {
    switch (category) {
      case 'social': return 'Social Media';
      case 'communication': return 'Communication';
      case 'video': return 'Video & Streaming';
      case 'games': return 'Games';
      case 'news': return 'News';
      default: return 'Other';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Block Apps'),
        backgroundColor: Colors.grey[900],
        actions: [
          if (_blockedApps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red[600],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_blockedApps.length} blocked',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : !_hasPermissions
          ? _buildPermissionRequest()
          : _buildAppList(),
    );
  }
}