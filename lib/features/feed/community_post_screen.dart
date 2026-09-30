import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme.dart';
import '../../core/user_session.dart';
import '../../core/user_data_store.dart';
import 'community_feed_screen.dart';
import 'incident_api.dart';

/// Free-form community post composer — like X/Twitter, but for your neighbourhood.
/// No category or severity required. Just type and share.
class CommunityPostScreen extends StatefulWidget {
  const CommunityPostScreen({super.key});

  @override
  State<CommunityPostScreen> createState() => _CommunityPostScreenState();
}

class _CommunityPostScreenState extends State<CommunityPostScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isSubmitting = false;
  int _charCount = 0;
  static const int _maxChars = 280;

  // Media attachments state
  File? _selectedMediaFile;
  bool _isImage = true;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (file != null) {
        setState(() {
          _selectedMediaFile = File(file.path);
          _isImage = true;
        });
      }
    } catch (e) {
      print('Error picking image: $e');
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 60),
      );
      if (file != null) {
        setState(() {
          _selectedMediaFile = File(file.path);
          _isImage = false;
        });
      }
    } catch (e) {
      print('Error picking video: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _charCount = _controller.text.length);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _counterColor {
    if (_charCount > _maxChars) return AppTheme.errorColor;
    if (_charCount > _maxChars * 0.85) return const Color(0xFFF59E0B);
    return AppTheme.textSecondary;
  }

  double get _progress => (_charCount / _maxChars).clamp(0.0, 1.0);

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_charCount > _maxChars) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post is too long. Please shorten it.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    // Build local card immediately so the user sees their post right away
    final localPost = <String, dynamic>{
      'id': 'cp-local-${DateTime.now().millisecondsSinceEpoch}',
      'post_type': 'community',
      'userName': UserSession.instance.displayName,
      'initials': UserSession.instance.initials,
      'avatarColor': const Color(0xFF8B5CF6),
      'isVerified': true,
      'timeAgo': 'Just now',
      'createdAt': DateTime.now().toIso8601String(),
      'category': 'COMMUNITY',
      'categoryColor': const Color(0xFF8B5CF6),
      'title': text,
      'description': '',
      'content': text,
      'severity': 'COMMUNITY',
      'location': '',
      'likes': 0,
      'commentsCount': 0,
      'replies': <Map<String, dynamic>>[],
      'isLiked': false,
      'imageAsset': _selectedMediaFile?.path,
      'isVideo': !_isImage,
      'userId': UserDataStore.instance.userKey, // Explicit attribution for my_reports_screen
    };

    // Save to user's isolated local store so it appears in My Reports immediately
    await UserDataStore.instance.saveUserReport(localPost);

    // Prepend locally so it shows immediately
    final currentList = List<Map<String, dynamic>>.from(communityReportsNotifier.value);
    currentList.insert(0, localPost);
    communityReportsNotifier.value = currentList;

    // Fire-and-forget to backend — failure just means it won't persist across restarts
    try {
      final saved = await IncidentApi.instance.createCommunityPost(
        content: text,
        imageUrl: _selectedMediaFile?.path,
      );
      // Update the local placeholder with the real server ID
      final list = List<Map<String, dynamic>>.from(communityReportsNotifier.value);
      final idx = list.indexWhere((r) => r['id'] == localPost['id']);
      if (idx != -1) {
        list[idx] = {
          ...localPost,
          'id': saved['id'] ?? localPost['id'],
          if (saved['image_url'] != null) 'imageAsset': saved['image_url'],
        };
        communityReportsNotifier.value = list;
      }
    } catch (e) {
      print('EAWS CommunityPost backend sync failed (local shown): $e');
    }

    setState(() => _isSubmitting = false);
    if (mounted) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 10),
              Text('Your update is live!', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          backgroundColor: const Color(0xFF8B5CF6),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPost = _charCount > 0 && _charCount <= _maxChars && !_isSubmitting;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.x, color: AppTheme.textPrimary, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Share Update',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AnimatedOpacity(
              opacity: canPost ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: ElevatedButton(
                onPressed: canPost ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Post'),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFF3F4F6)),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  // User avatar
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF8B5CF6).withOpacity(0.15),
                    child: Text(
                      UserSession.instance.initials,
                      style: const TextStyle(
                        color: Color(0xFF8B5CF6),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Compose area
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UserSession.instance.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _controller,
                            autofocus: true,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            style: const TextStyle(
                              fontSize: 16,
                              color: AppTheme.textPrimary,
                              height: 1.5,
                            ),
                            decoration: const InputDecoration(
                              hintText: "What's happening in your community?",
                              hintStyle: TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 16,
                                height: 1.5,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                            ),
                          ),
                          if (_selectedMediaFile != null) ...[
                            const SizedBox(height: 12),
                            Stack(
                              children: [
                                Container(
                                  height: 180,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    image: _isImage
                                        ? DecorationImage(
                                            image: FileImage(_selectedMediaFile!),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                    color: Colors.black12,
                                  ),
                                  child: !_isImage
                                      ? const Center(
                                          child: Icon(
                                            Icons.play_circle_outline,
                                            color: Colors.white,
                                            size: 50,
                                          ),
                                        )
                                      : null,
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedMediaFile = null;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tip banner right above the toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            color: const Color(0xFFF9FAFB),
            child: const Row(
              children: [
                Icon(LucideIcons.info, size: 14, color: AppTheme.textSecondary),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Not an emergency? Chat here. Use 🚨 Report for incidents.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),

          // Bottom bar — char counter + media actions
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF3F4F6), width: 1)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.image, color: Color(0xFF8B5CF6), size: 22),
                  onPressed: () => _pickImage(ImageSource.gallery),
                  tooltip: 'Add Photo',
                ),
                IconButton(
                  icon: const Icon(LucideIcons.camera, color: Color(0xFF8B5CF6), size: 22),
                  onPressed: () => _pickImage(ImageSource.camera),
                  tooltip: 'Take Photo',
                ),
                IconButton(
                  icon: const Icon(LucideIcons.video, color: Color(0xFF8B5CF6), size: 22),
                  onPressed: () => _pickVideo(ImageSource.gallery),
                  tooltip: 'Add Video',
                ),
                const Spacer(),
                // Circular progress + count
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: _progress,
                        strokeWidth: 2.5,
                        backgroundColor: const Color(0xFFE5E7EB),
                        color: _counterColor,
                      ),
                      if (_charCount > _maxChars * 0.75)
                        Text(
                          '${_maxChars - _charCount}',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: _counterColor,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
