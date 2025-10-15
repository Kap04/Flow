import 'dart:io';

import 'package:flutter/material.dart';
import 'app_drawer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_selector/file_selector.dart';
// removed unused mime import
import 'cloudinary_helper.dart';

class SoundsScreen extends ConsumerStatefulWidget {
  const SoundsScreen({super.key});

  @override
  ConsumerState<SoundsScreen> createState() => _SoundsScreenState();
}

class _SoundsScreenState extends ConsumerState<SoundsScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _playingId;
  bool _isPlaying = false;
  Map<String, double> _downloadProgress = {};
  Set<String> _downloaded = {};
  String? _selectedSoundId;

  @override
  void initState() {
    super.initState();
    _scanDownloadedFiles();
    _loadSelectedSound();
  }

  Future<void> _loadSelectedSound() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      setState(() {
        _selectedSoundId = doc.data()?['selectedSoundId'] as String?;
      });
    } catch (e) {
      // ignore: avoid_print
      print('sounds: failed to load selectedSoundId: $e');
    }
  }

  // Cloudinary config (you can change these or input at runtime). Use unsigned preset for quick uploads.
  String? cloudinaryCloudName;
  String? cloudinaryUploadPreset;

  Future<bool> _ensureCloudinaryConfig() async {
    if (cloudinaryCloudName != null && cloudinaryUploadPreset != null) return true;
    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (ctx) {
        final cloudCtrl = TextEditingController();
        final presetCtrl = TextEditingController();
        return AlertDialog(
          title: const Text('Cloudinary config'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: cloudCtrl, decoration: const InputDecoration(labelText: 'dfxguyeb1')),
              TextField(controller: presetCtrl, decoration: const InputDecoration(labelText: 'upload preset (unsigned)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(ctx).pop({'cloud': cloudCtrl.text.trim(), 'preset': presetCtrl.text.trim()}), child: const Text('Save')),
          ],
        );
      },
    );
    if (result == null) return false;
    cloudinaryCloudName = result['cloud'];
    cloudinaryUploadPreset = result['preset'];
    return cloudinaryCloudName != null && cloudinaryUploadPreset != null && cloudinaryCloudName!.isNotEmpty && cloudinaryUploadPreset!.isNotEmpty;
  }

  Future<void> _scanDownloadedFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = dir.listSync().whereType<File>();
    setState(() {
      _downloaded = files.map((f) => f.path.split(Platform.pathSeparator).last).toSet();
    });
  }

  // NOTE: We no longer attempt to resolve a storagePath via Firebase Storage.
  // Provide a public `downloadUrl` in the Firestore `sounds` document (e.g. GitHub Releases URL)
  // when you upload the audio file. This avoids requiring a Firebase Storage billing plan.

  Future<File> _localFileForId(String id, String ext) async {
    final dir = await getApplicationDocumentsDirectory();
    final filename = '$id.$ext';
    return File('${dir.path}${Platform.pathSeparator}$filename');
  }

  Future<void> _downloadSound(String id, String? downloadUrl, String? storagePath) async {
    try {
      final url = downloadUrl;
      if (url == null) throw Exception('No download URL');

      final uri = Uri.parse(url);
      final client = http.Client();
      final req = http.Request('GET', uri);
      final resp = await client.send(req);
      final total = resp.contentLength ?? 0;
      final ext = uri.pathSegments.isNotEmpty && uri.pathSegments.last.contains('.') ? uri.pathSegments.last.split('.').last : 'mp3';
      final file = await _localFileForId(id, ext);
      final sink = file.openWrite();
      int received = 0;
      await for (final chunk in resp.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) setState(() => _downloadProgress[id] = received / total);
      }
      await sink.close();
      setState(() {
        _downloadProgress.remove(id);
        _downloaded.add(file.path.split(Platform.pathSeparator).last);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download complete')));
    } catch (e) {
      // ignore: avoid_print
      print('sounds: download failed for $id: $e');
      setState(() => _downloadProgress.remove(id));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download failed')));
    }
  }

  Future<void> _playSound(Map<String, dynamic> data, String id) async {
    try {
      // prefer local file
      final possibleExt = (data['downloadUrl'] is String && (data['downloadUrl'] as String).contains('.'))
          ? (data['downloadUrl'] as String).split('.').last
          : (data['storagePath'] is String && (data['storagePath'] as String).contains('.'))
              ? (data['storagePath'] as String).split('.').last
              : 'mp3';
      final local = await _localFileForId(id, possibleExt);
      if (await local.exists()) {
        await _audioPlayer.stop();
        await _audioPlayer.play(DeviceFileSource(local.path));
        setState(() {
          _playingId = id;
          _isPlaying = true;
        });
        _audioPlayer.onPlayerComplete.listen((_) {
          setState(() {
            _playingId = null;
            _isPlaying = false;
          });
        });
        return;
      }

      final url = data['downloadUrl'];
      if (url == null) throw Exception('No URL');
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(url));
      setState(() {
        _playingId = id;
        _isPlaying = true;
      });
      _audioPlayer.onPlayerComplete.listen((_) {
        setState(() {
          _playingId = null;
          _isPlaying = false;
        });
      });
    } catch (e) {
      // ignore: avoid_print
      print('sounds: play failed for $id: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Playback failed')));
    }
  }

  Future<void> _stopPlayback() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    setState(() {
      _playingId = null;
      _isPlaying = false;
    });
  }

  Future<void> _setPreferred(String soundId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({'selectedSoundId': soundId}, SetOptions(merge: true));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set as preferred session sound')));
    setState(() {
      _selectedSoundId = soundId;
    });
  }

  Widget _buildItem(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final id = doc.id;
    final title = data['title'] ?? data['name'] ?? 'Untitled';
    final desc = data['description'] ?? '';
    final downloadUrl = data['downloadUrl'] ?? data['url'];
    final storagePath = data['storagePath'];
    final guessedFilename = '$id.${(downloadUrl is String && downloadUrl.contains('.')) ? downloadUrl.split('.').last : (storagePath is String && storagePath.contains('.') ? storagePath.split('.').last : 'mp3')}';
    final isDownloaded = _downloaded.contains(guessedFilename);

    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: id == _selectedSoundId ? const BorderSide(color: Colors.lightBlueAccent, width: 2) : BorderSide.none,
      ),
      child: ListTile(
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: desc.isNotEmpty ? Text(desc, style: const TextStyle(color: Colors.white70)) : null,
  onTap: () => _setPreferred(id),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_playingId == id)
              IconButton(icon: const Icon(Icons.stop, color: Colors.white), onPressed: _stopPlayback)
            else
              IconButton(icon: const Icon(Icons.play_arrow, color: Colors.white), onPressed: () => _playSound(data, id)),

            if (isDownloaded)
              IconButton(icon: const Icon(Icons.file_download_done, color: Colors.greenAccent), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Already downloaded'))))
            else if (_downloadProgress.containsKey(id))
              SizedBox(width: 36, height: 36, child: CircularProgressIndicator(value: _downloadProgress[id]))
            else
              IconButton(icon: const Icon(Icons.download, color: Colors.white), onPressed: () => _downloadSound(id, downloadUrl, storagePath)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Music / Sounds', style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('sounds').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No sounds found.', style: TextStyle(color: Colors.white70)));
          final docs = snapshot.data!.docs;
          return ListView.builder(itemCount: docs.length, itemBuilder: (ctx, i) => _buildItem(docs[i]));
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.upload_file),
        onPressed: () async {
          // Ask whether to use server-signed upload (recommended) by prompting for sign server URL.
          final signUrlResult = await showDialog<String?>(
            context: context,
            builder: (ctx) {
              final ctrl = TextEditingController();
              return AlertDialog(
                title: const Text('Signing server (optional)'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Enter signing server URL to perform server-signed uploads (recommended for production). Leave empty to use unsigned preset.'),
                  TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'https://yourserver.com/sign')),
                ]),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim().isEmpty ? null : ctrl.text.trim()), child: const Text('Continue')),
                ],
              );
            },
          );

          final useSignServer = signUrlResult != null && signUrlResult.isNotEmpty;

          // If not using sign server, ensure we have cloud name and unsigned preset
          if (!useSignServer) {
            final ok = await _ensureCloudinaryConfig();
            if (!ok) return;
          } else {
            // ask for cloud name if not known
            if (cloudinaryCloudName == null || cloudinaryCloudName!.isEmpty) {
              final cloud = await showDialog<String?>(
                context: context,
                builder: (ctx) {
                  final ctrl = TextEditingController();
                  return AlertDialog(
                    title: const Text('Cloud name'),
                    content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'cloud name')),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Save')),
                    ],
                  );
                },
              );
              if (cloud == null || cloud.isEmpty) return;
              cloudinaryCloudName = cloud;
            }
          }

          final XTypeGroup audioGroup = XTypeGroup(label: 'audio', extensions: ['mp3', 'm4a', 'ogg', 'wav']);
          final fileResult = await openFile(acceptedTypeGroups: [audioGroup]);
          if (fileResult == null) return;
          final file = File(fileResult.path);
          final snack = ScaffoldMessenger.of(context);
          snack.showSnackBar(const SnackBar(content: Text('Uploading to Cloudinary...')));

          String? url;
          final helper = CloudinaryHelper(cloudName: cloudinaryCloudName! , uploadPreset: cloudinaryUploadPreset);
          if (useSignServer) {
            try {
              final signUri = Uri.parse(signUrlResult!);
              url = await helper.uploadSigned(file, signServerUrl: signUri, extraParams: {'folder': 'flow_sounds'});
            } catch (e) {
              // ignore: avoid_print
              print('sounds: signed upload failed: $e');
              url = null;
            }
          } else {
            // Unsigned flow
            try {
              url = await helper.uploadUnsigned(file);
            } catch (e) {
              // ignore: avoid_print
              print('sounds: unsigned upload failed: $e');
              url = null;
            }
          }

          if (url == null) {
            snack.showSnackBar(const SnackBar(content: Text('Upload failed')));
            return;
          }

          // create Firestore doc
          final title = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'uploaded_audio';
          await FirebaseFirestore.instance.collection('sounds').add({
            'title': title,
            'description': '',
            'downloadUrl': url,
            'createdAt': FieldValue.serverTimestamp(),
          });
          snack.showSnackBar(const SnackBar(content: Text('Upload complete')));
        },
      ),
    );
  }
}
