import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme.dart';
import 'community_feed_screen.dart';
import 'incident_api.dart';

class CommunityPostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> report;

  const CommunityPostDetailScreen({
    super.key,
    required this.report,
  });

  @override
  State<CommunityPostDetailScreen> createState() => _CommunityPostDetailScreenState();
}

class _CommunityPostDetailScreenState extends State<CommunityPostDetailScreen> {
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  bool _isSubmitting = false;
  late String _postId;

  // Local interaction states
  bool _isLiked = false;
  int _likesCount = 0;
  bool _isBookmarked = false;
  int _bookmarksCount = 12;
  int _repostCount = 4;
  bool _isReposted = false;

  // Media attachments state for reply
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
    _postId = widget.report['id'].toString();
    _isLiked = widget.report['isLiked'] ?? false;
    _likesCount = widget.report['likes'] ?? 0;
    _replyFocusNode.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  void _toggleLike() {
    HapticFeedback.lightImpact();
    setState(() {
      _isLiked = !_isLiked;
      if (_isLiked) {
        _likesCount++;
      } else {
        _likesCount = _likesCount > 0 ? _likesCount - 1 : 0;
      }
    });

    // Update global ValueNotifier
    final list = List<Map<String, dynamic>>.from(communityReportsNotifier.value);
    final idx = list.indexWhere((r) => r['id'].toString() == _postId);
    if (idx != -1) {
      list[idx]['isLiked'] = _isLiked;
      list[idx]['likes'] = _likesCount;
      communityReportsNotifier.value = list;
    }

    IncidentApi.instance.react(_postId, 'like').catchError((e) {
      debugPrint('Sync like failed: $e');
    });
  }

  void _toggleRepost() {
    HapticFeedback.lightImpact();
    setState(() {
      _isReposted = !_isReposted;
      if (_isReposted) {
        _repostCount++;
      } else {
        _repostCount = _repostCount > 0 ? _repostCount - 1 : 0;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isReposted ? 'Post reposted to your community feed!' : 'Repost removed'),
        duration: const Duration(seconds: 2),
      ),
    );

    IncidentApi.instance.react(_postId, 'repost').catchError((e) {
      debugPrint('Sync repost failed: $e');
    });
  }

  void _toggleBookmark() {
    HapticFeedback.lightImpact();
    setState(() {
      _isBookmarked = !_isBookmarked;
      if (_isBookmarked) {
        _bookmarksCount++;
      } else {
        _bookmarksCount--;
      }
    });
  }

  Future<void> _submitReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    final authorName = widget.report['userName'] ?? 'Ayettey Ebenezer';
    final authorInitials = widget.report['initials'] ?? (authorName.split(' ').map((w) => w[0]).take(2).join().toUpperCase());

    final newReply = {
      'id': 'cpr-local-${DateTime.now().millisecondsSinceEpoch}',
      'author_name': authorName,
      'author_initials': authorInitials,
      'content': text,
      'imageAsset': _selectedMediaFile?.path,
      'created_at': DateTime.now().toIso8601String(),
    };

    // Prepend/append locally to global state notifier
    final list = List<Map<String, dynamic>>.from(communityReportsNotifier.value);
    final idx = list.indexWhere((r) => r['id'].toString() == _postId);
    if (idx != -1) {
      final updated = Map<String, dynamic>.from(list[idx]);
      final repliesList = List<Map<String, dynamic>>.from(updated['replies'] ?? []);
      repliesList.add(newReply);
      updated['replies'] = repliesList;
      updated['commentsCount'] = repliesList.length;
      list[idx] = updated;
      communityReportsNotifier.value = list;
    }

    _replyController.clear();
    _replyFocusNode.unfocus();
    setState(() {
      _selectedMediaFile = null;
      _isSubmitting = false;
    });

    // Sync with backend API (fire and forget)
    try {
      await IncidentApi.instance.addReply(_postId, text);
    } catch (e) {
      debugPrint('Syncing reply with backend failed: $e');
    }
  }

  Widget _buildAttachedMedia(String path) {
    Widget imageWidget;
    if (!path.startsWith('http') && !path.startsWith('assets/')) {
      imageWidget = Image.file(
        File(path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: 240,
        errorBuilder: (context, error, stackTrace) => Container(
          color: const Color(0xFF1E293B),
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image, color: Colors.grey, size: 36),
        ),
      );
    } else if (path.startsWith('assets/')) {
      imageWidget = Image.asset(
        path,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 240,
        errorBuilder: (context, error, stackTrace) => Container(
          color: const Color(0xFF1E293B),
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image, color: Colors.grey, size: 36),
        ),
      );
    } else {
      imageWidget = Image.network(
        path,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 240,
        errorBuilder: (context, error, stackTrace) => Container(
          color: const Color(0xFF1E293B),
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image, color: Colors.grey, size: 36),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 6),
          width: double.infinity,
          height: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(child: imageWidget),
              // Bottom dark gradient overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.75),
                        Colors.black.withOpacity(0.4),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: const Text(
                    'Tap to view full attached document report',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'From local-eaws-network.org',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: communityReportsNotifier,
      builder: (context, reports, child) {
        // Find latest state of current post
        final currentReport = reports.firstWhere(
          (r) => r['id'].toString() == _postId,
          orElse: () => widget.report,
        );

        final List<Map<String, dynamic>> replies =
            List<Map<String, dynamic>>.from(currentReport['replies'] ?? []);

        final initials = currentReport['initials'] ?? 'GC';
        final userName = currentReport['userName'] ?? 'Ghana Citizen';
        final handle = '@${userName.toLowerCase().replaceAll(' ', '_')}';
        final avatarColor = currentReport['avatarColor'] ?? const Color(0xFF8B5CF6);
        final titleText = currentReport['title'] ?? '';
        final imageAsset = currentReport['imageAsset'];

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary, size: 22),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Post',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(LucideIcons.moreHorizontal, color: AppTheme.textPrimary, size: 22),
                onPressed: () {
                  // Show option sheet
                  showModalBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (context) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(LucideIcons.flag, color: AppTheme.errorColor),
                            title: const Text('Report Post'),
                            onTap: () {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Report submitted successfully.')),
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(LucideIcons.copy),
                            title: const Text('Copy Post Link'),
                            onTap: () {
                              Navigator.pop(context);
                              Clipboard.setData(ClipboardData(text: 'https://eaws-app/post/$_postId'));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Link copied to clipboard!')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: const Color(0xFFF3F4F6)),
            ),
          ),
          body: Stack(
            children: [
              // Scrollable post + comment section
              Positioned.fill(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 90),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Author Row
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: avatarColor.withOpacity(0.15),
                              child: Text(
                                initials,
                                style: TextStyle(
                                  color: avatarColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        userName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      if (currentReport['isVerified'] == true) ...[
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.verified,
                                          color: Color(0xFF10B981),
                                          size: 16,
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    handle,
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Post Content Text
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          titleText,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppTheme.textPrimary,
                            height: 1.45,
                          ),
                        ),
                      ),

                      // Attached Media
                      if (imageAsset != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildAttachedMedia(imageAsset),
                        ),

                      // Timestamp & Views Row
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Text(
                          '${currentReport['timeAgo']} · 08/13/2026 · ${(_likesCount * 31 + 45).toString()} Views',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Divider(color: Color(0xFFF3F4F6), height: 1, thickness: 1),
                      ),

                      // Interaction/Action bar
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildActionIcon(
                              icon: LucideIcons.messageCircle,
                              count: replies.length,
                              color: Colors.grey[600]!,
                              onTap: () => _replyFocusNode.requestFocus(),
                            ),
                            _buildActionIcon(
                              icon: LucideIcons.repeat,
                              count: _repostCount,
                              color: _isReposted ? Colors.green : Colors.grey[600]!,
                              onTap: _toggleRepost,
                            ),
                            _buildActionIcon(
                              icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                              count: _likesCount,
                              color: _isLiked ? Colors.red : Colors.grey[600]!,
                              onTap: _toggleLike,
                            ),
                            _buildActionIcon(
                              icon: _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                              count: _bookmarksCount,
                              color: _isBookmarked ? Colors.blue : Colors.grey[600]!,
                              onTap: _toggleBookmark,
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.share, size: 20),
                              color: Colors.grey[600],
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Sharing update...')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Divider(color: Color(0xFFF3F4F6), height: 1, thickness: 1),
                      ),

                      // Comments/Replies Feed List
                      if (replies.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(40),
                          child: const Center(
                            child: Column(
                              children: [
                                Icon(LucideIcons.messageCircle, color: Colors.grey, size: 36),
                                SizedBox(height: 10),
                                Text(
                                  'Be the first to reply',
                                  style: TextStyle(color: Colors.grey, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: replies.length,
                          itemBuilder: (context, index) {
                            final reply = replies[index];
                            final authorName = reply['author_name'] ?? 'Ghana Citizen';
                            final authorHandle = '@${authorName.toLowerCase().replaceAll(' ', '_')}';
                            final authorInitials = reply['author_initials'] ?? 'GC';

                            // Determine if this is the last reply in the thread list
                            final isLast = index == replies.length - 1;

                            return IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Left side thread line
                                  Container(
                                    width: 56,
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Column(
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: const Color(0xFFEDE9FE),
                                          child: Text(
                                            authorInitials,
                                            style: const TextStyle(
                                              color: Color(0xFF8B5CF6),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        if (!isLast)
                                          Expanded(
                                            child: Container(
                                              margin: const EdgeInsets.symmetric(vertical: 4),
                                              width: 2,
                                              color: const Color(0xFFE5E7EB),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                  // Reply Content
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(0, 8, 16, 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                authorName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: AppTheme.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                authorHandle,
                                                style: const TextStyle(
                                                  color: AppTheme.textSecondary,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            reply['content'] ?? '',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: AppTheme.textPrimary,
                                              height: 1.4,
                                            ),
                                          ),
                                          if (reply['imageAsset'] != null) ...[
                                            const SizedBox(height: 8),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: Container(
                                                height: 140,
                                                width: double.infinity,
                                                color: Colors.black12,
                                                child: Image(
                                                  image: reply['imageAsset'].toString().startsWith('http') || reply['imageAsset'].toString().startsWith('assets/')
                                                      ? NetworkImage(reply['imageAsset']) as ImageProvider
                                                      : FileImage(File(reply['imageAsset'])),
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                          // Mini X-style reply action buttons
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              _buildMiniActionIcon(LucideIcons.messageCircle, 0, onTap: () => _replyFocusNode.requestFocus()),
                                              _buildMiniActionIcon(
                                                LucideIcons.repeat,
                                                reply['reposts'] ?? 0,
                                                color: reply['isReposted'] == true ? Colors.green : null,
                                                onTap: () {
                                                  HapticFeedback.lightImpact();
                                                  setState(() {
                                                    final isR = reply['isReposted'] == true;
                                                    reply['isReposted'] = !isR;
                                                    reply['reposts'] = isR ? (reply['reposts'] ?? 1) - 1 : (reply['reposts'] ?? 0) + 1;
                                                  });
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text(reply['isReposted'] == true ? 'Reply reposted to community feed!' : 'Repost removed'),
                                                      duration: const Duration(seconds: 2),
                                                    ),
                                                  );
                                                },
                                              ),
                                              _buildMiniActionIcon(
                                                reply['isLiked'] == true ? Icons.favorite : Icons.favorite_border,
                                                reply['likes'] ?? 0,
                                                color: reply['isLiked'] == true ? Colors.red : null,
                                                onTap: () {
                                                  HapticFeedback.lightImpact();
                                                  setState(() {
                                                    final isL = reply['isLiked'] == true;
                                                    reply['isLiked'] = !isL;
                                                    reply['likes'] = isL ? (reply['likes'] ?? 1) - 1 : (reply['likes'] ?? 0) + 1;
                                                  });
                                                },
                                              ),
                                              _buildMiniActionIcon(LucideIcons.eye, 24),
                                              GestureDetector(
                                                onTap: () {
                                                  HapticFeedback.lightImpact();
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('Sharing update...'), duration: Duration(seconds: 2)),
                                                  );
                                                },
                                                child: const Icon(LucideIcons.share, size: 14, color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),

              // Sticky Bottom Comment Bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.white,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    10,
                    16,
                    MediaQuery.of(context).padding.bottom + 10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Media preview (shown when file is selected)
                      if (_selectedMediaFile != null) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Stack(
                            children: [
                              Container(
                                height: 80,
                                width: 80,
                                margin: const EdgeInsets.only(bottom: 8, left: 44),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
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
                                        child: Icon(Icons.play_circle_outline,
                                            color: Colors.white, size: 28))
                                    : null,
                              ),
                              Positioned(
                                top: 0,
                                left: 48,
                                child: GestureDetector(
                                  onTap: () => setState(() => _selectedMediaFile = null),
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close,
                                        color: Colors.white, size: 11),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Single unified pill: avatar + field + button
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Author avatar
                          const CircleAvatar(
                            radius: 16,
                            backgroundColor: Color(0xFFEDE9FE),
                            child: Text(
                              'GC',
                              style: TextStyle(
                                color: Color(0xFF8B5CF6),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Pill containing field + Reply button
                          Expanded(
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(21),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextField(
                                      controller: _replyController,
                                      focusNode: _replyFocusNode,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF111827),
                                      ),
                                      decoration: const InputDecoration(
                                        hintText: 'Post your reply…',
                                        hintStyle: TextStyle(
                                          color: Color(0xFF9CA3AF),
                                          fontSize: 14,
                                        ),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ),
                                  // Reply button lives inside the pill
                                  _isSubmitting
                                      ? const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 12),
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Color(0xFF8B5CF6)),
                                          ),
                                        )
                                      : GestureDetector(
                                          onTap: _submitReply,
                                          child: Container(
                                            margin: const EdgeInsets.all(5),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 0),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF8B5CF6),
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            alignment: Alignment.center,
                                            child: const Text(
                                              'Reply',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Media toolbar — only shown when focused
                      if (_replyFocusNode.hasFocus) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(width: 42),
                            IconButton(
                              icon: const Icon(LucideIcons.image,
                                  color: Color(0xFF8B5CF6), size: 20),
                              onPressed: () => _pickImage(ImageSource.gallery),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(6),
                              tooltip: 'Gallery',
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.camera,
                                  color: Color(0xFF8B5CF6), size: 20),
                              onPressed: () => _pickImage(ImageSource.camera),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(6),
                              tooltip: 'Camera',
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.video,
                                  color: Color(0xFF8B5CF6), size: 20),
                              onPressed: () => _pickVideo(ImageSource.gallery),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(6),
                              tooltip: 'Video',
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
        );
      },
    );
  }


  Widget _buildActionIcon({
    required IconData icon,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 4),
          Text(
            count > 0 ? count.toString() : '',
            style: TextStyle(
              fontSize: 12.5,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniActionIcon(IconData icon, int count, {VoidCallback? onTap, Color? color}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? Colors.grey[600]),
          if (count > 0) ...[
            const SizedBox(width: 3),
            Text(
              count.toString(),
              style: TextStyle(fontSize: 10, color: color ?? Colors.grey[600], fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
