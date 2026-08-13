import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  @override
  void initState() {
    super.initState();
    _postId = widget.report['id'].toString();
    _isLiked = widget.report['isLiked'] ?? false;
    _likesCount = widget.report['likes'] ?? 0;
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
        _likesCount--;
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
  }

  void _toggleRepost() {
    HapticFeedback.lightImpact();
    setState(() {
      _isReposted = !_isReposted;
      if (_isReposted) {
        _repostCount++;
      } else {
        _repostCount--;
      }
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

    final newReply = {
      'id': 'cpr-local-${DateTime.now().millisecondsSinceEpoch}',
      'author_name': 'Ghana Citizen',
      'author_initials': 'GC',
      'content': text,
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
    setState(() => _isSubmitting = false);

    // Sync with backend API (fire and forget)
    try {
      await IncidentApi.instance.addReply(_postId, text);
    } catch (e) {
      debugPrint('Syncing reply with backend failed: $e');
    }
  }

  Widget _buildAttachedMedia(String path) {
    ImageProvider imageProvider;
    if (!path.startsWith('http') && !path.startsWith('assets/')) {
      imageProvider = FileImage(File(path));
    } else if (path.startsWith('assets/')) {
      imageProvider = AssetImage(path);
    } else {
      imageProvider = NetworkImage(path);
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
            image: DecorationImage(
              image: imageProvider,
              fit: BoxFit.cover,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
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
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEDE9FE),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Update',
                                style: TextStyle(
                                  color: Color(0xFF8B5CF6),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
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
                                          const SizedBox(height: 8),
                                          // Mini X-style reply action buttons
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              _buildMiniActionIcon(LucideIcons.messageCircle, 0),
                                              _buildMiniActionIcon(LucideIcons.repeat, 0),
                                              _buildMiniActionIcon(Icons.favorite_border, 1),
                                              _buildMiniActionIcon(LucideIcons.eye, 24),
                                              const Icon(LucideIcons.share, size: 14, color: Colors.grey),
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
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    MediaQuery.of(context).padding.bottom + 8,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFF3F4F6), width: 1)),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 16,
                        backgroundColor: Color(0xFFEDE9FE),
                        child: Text(
                          'GC',
                          style: TextStyle(
                            color: Color(0xFF8B5CF6),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: TextField(
                            controller: _replyController,
                            focusNode: _replyFocusNode,
                            maxLines: null,
                            decoration: const InputDecoration(
                              hintText: 'Post your reply',
                              hintStyle: TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 14.5,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _isSubmitting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B5CF6)),
                            )
                          : TextButton(
                              onPressed: _submitReply,
                              child: const Text(
                                'Reply',
                                style: TextStyle(
                                  color: Color(0xFF8B5CF6),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
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

  Widget _buildMiniActionIcon(IconData icon, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 3),
        if (count > 0)
          Text(
            count.toString(),
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
      ],
    );
  }
}
