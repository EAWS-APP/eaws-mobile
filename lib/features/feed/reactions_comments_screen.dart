import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme.dart';
import 'incident_api.dart';
import 'community_feed_screen.dart';

class ReactionsCommentsScreen extends StatefulWidget {
  final Map<String, dynamic> report;
  final Function(Map<String, dynamic> updatedReport) onUpdate;

  const ReactionsCommentsScreen({
    super.key,
    required this.report,
    required this.onUpdate,
  });

  @override
  State<ReactionsCommentsScreen> createState() => _ReactionsCommentsScreenState();
}

class _EditCommentDialog extends StatefulWidget {
  final Map<String, dynamic> comment;
  const _EditCommentDialog({required this.comment});

  @override
  State<_EditCommentDialog> createState() => _EditCommentDialogState();
}

class _EditCommentDialogState extends State<_EditCommentDialog> {
  late TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.comment['content']);
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Comment', style: TextStyle(fontWeight: FontWeight.bold)),
      content: TextField(
        controller: _editController,
        maxLines: 3,
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          hintText: 'Edit your comment...',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () {
            if (_editController.text.trim().isNotEmpty) {
              Navigator.pop(context, _editController.text.trim());
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ReactionsCommentsScreenState extends State<ReactionsCommentsScreen> {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late Map<String, dynamic> _localReport;

  @override
  void initState() {
    super.initState();
    _localReport = Map<String, dynamic>.from(widget.report);
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleSendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();

    final newComment = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'userName': 'Ghana Citizen',
      'initials': 'GC',
      'avatarColor': AppTheme.primaryColor,
      'isVerified': true,
      'timeAgo': 'Just now',
      'content': text,
      'likes': 0,
      'isLiked': false,
    };

    setState(() {
      final List<Map<String, dynamic>> commentsList = 
          _localReport['comments'] is List ? List<Map<String, dynamic>>.from(_localReport['comments']) : [];
      commentsList.add(newComment);
      _localReport['comments'] = commentsList;
      _localReport['commentsCount'] = commentsList.length;
    });

    _commentController.clear();
    widget.onUpdate(_localReport);

    try {
      await IncidentApi.instance.addComment(_localReport['id'].toString(), text);
    } catch (e) {
      print('EAWS Comment API unavailable, keeping local comment: $e');
    }

    // Auto-scroll to the bottom comment card
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleReaction(String type) async {
    HapticFeedback.mediumImpact();
    setState(() {
      if (type == 'like') {
        final bool isLiked = _localReport['isLiked'] ?? false;
        _localReport['isLiked'] = !isLiked;
        _localReport['likes'] = isLiked 
            ? ((_localReport['likes'] ?? 0) - 1) 
            : ((_localReport['likes'] ?? 0) + 1);
      } else if (type == 'alarmed') {
        final bool isAlarmed = _localReport['isAlarmed'] ?? false;
        _localReport['isAlarmed'] = !isAlarmed;
        _localReport['alarmed'] = isAlarmed 
            ? ((_localReport['alarmed'] ?? 0) - 1) 
            : ((_localReport['alarmed'] ?? 0) + 1);
      } else if (type == 'concerned') {
        final bool isConcerned = _localReport['isConcerned'] ?? false;
        _localReport['isConcerned'] = !isConcerned;
        _localReport['concerned'] = isConcerned 
            ? ((_localReport['concerned'] ?? 0) - 1) 
            : ((_localReport['concerned'] ?? 0) + 1);
      }
    });
    widget.onUpdate(_localReport);

    try {
      await IncidentApi.instance.react(_localReport['id'].toString(), type);
    } catch (e) {
      print('EAWS Reaction API unavailable, keeping local reaction: $e');
    }
  }

  void _toggleCommentLike(int commentId) {
    HapticFeedback.lightImpact();
    setState(() {
      final List<Map<String, dynamic>> commentsList = 
          _localReport['comments'] is List ? List<Map<String, dynamic>>.from(_localReport['comments']) : [];
      final idx = commentsList.indexWhere((c) => c['id'] == commentId);
      if (idx != -1) {
        final comment = commentsList[idx];
        final bool isLiked = comment['isLiked'] ?? false;
        comment['isLiked'] = !isLiked;
        comment['likes'] = isLiked ? (comment['likes'] - 1) : (comment['likes'] + 1);
      }
      _localReport['comments'] = commentsList;
    });
    widget.onUpdate(_localReport);
  }

  void _editComment(int commentId) async {
    final List<Map<String, dynamic>> commentsList = 
        _localReport['comments'] is List ? List<Map<String, dynamic>>.from(_localReport['comments']) : [];
    final idx = commentsList.indexWhere((c) => c['id'] == commentId);
    if (idx != -1) {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => _EditCommentDialog(comment: commentsList[idx]),
      );
      if (result != null && result.isNotEmpty) {
        HapticFeedback.lightImpact();
        setState(() {
          commentsList[idx]['content'] = result;
          commentsList[idx]['timeAgo'] = 'Edited just now';
          _localReport['comments'] = commentsList;
        });
        widget.onUpdate(_localReport);
      }
    }
  }

  void _deleteComment(int commentId) {
    HapticFeedback.heavyImpact();
    setState(() {
      final List<Map<String, dynamic>> commentsList = 
          _localReport['comments'] is List ? List<Map<String, dynamic>>.from(_localReport['comments']) : [];
      commentsList.removeWhere((c) => c['id'] == commentId);
      _localReport['comments'] = commentsList;
      _localReport['commentsCount'] = commentsList.length;
    });
    widget.onUpdate(_localReport);
  }

  @override
  Widget build(BuildContext context) {
    final bool isLiked = _localReport['isLiked'] ?? false;
    final bool isAlarmed = _localReport['isAlarmed'] ?? false;
    final bool isConcerned = _localReport['isConcerned'] ?? false;

    final int likes = _localReport['likes'] ?? 0;
    final int alarmed = _localReport['alarmed'] ?? 0;
    final int concerned = _localReport['concerned'] ?? 0;

    final List<Map<String, dynamic>> comments = 
        _localReport['comments'] is List ? List<Map<String, dynamic>>.from(_localReport['comments']) : [];

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Stack(
        children: [
          // 1. Sticky Red Notch Header Card
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: Container(
              decoration: const BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 10,
                right: 10,
                bottom: 12,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Reactions & Comments',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.white, size: 22),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sharing incident details...'),
                          backgroundColor: AppTheme.primaryColor,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 2. Scrollable content
          Positioned.fill(
            top: 120,
            bottom: 80,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Context card banner
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _localReport['categoryColor'],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _localReport['category'],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              _localReport['timeAgo'],
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _localReport['title'],
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(LucideIcons.mapPin, color: AppTheme.textSecondary, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              _localReport['location'],
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // REACTIONS SECTION
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      'REACTIONS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Interactive reactions pills row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Red support
                        Expanded(
                          child: _buildReactionPill(
                            label: 'Support',
                            count: likes,
                            activeColor: const Color(0xFFEF4444),
                            icon: Icons.thumb_up,
                            isActive: isLiked,
                            onTap: () => _toggleReaction('like'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Orange Alarmed
                        Expanded(
                          child: _buildReactionPill(
                            label: 'Alarmed',
                            count: alarmed,
                            activeColor: const Color(0xFFF59E0B),
                            icon: LucideIcons.alertTriangle,
                            isActive: isAlarmed,
                            onTap: () => _toggleReaction('alarmed'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Blue Concerned
                        Expanded(
                          child: _buildReactionPill(
                            label: 'Concerned',
                            count: concerned,
                            activeColor: const Color(0xFF3B82F6),
                            icon: LucideIcons.heart,
                            isActive: isConcerned,
                            onTap: () => _toggleReaction('concerned'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // COMMENTS STREAM HEADER
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'COMMENTS (${comments.length})',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const Icon(LucideIcons.messageSquare, size: 16, color: AppTheme.textSecondary),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Dynamic list of comments card
                  if (comments.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40.0),
                        child: Column(
                          children: const [
                            Icon(LucideIcons.messageCircle, size: 48, color: Color(0xFFD1D5DB)),
                            SizedBox(height: 12),
                            Text(
                              'No comments yet',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Be the first to share an update on this report.',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: comments.length,
                      itemBuilder: (context, index) {
                        final comment = comments[index];
                        final bool isCommentLiked = comment['isLiked'] ?? false;
                        final bool isMyComment = comment['userName'] == 'Ghana Citizen';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: comment['avatarColor'].withOpacity(0.15),
                                    child: Text(
                                      comment['initials'],
                                      style: TextStyle(
                                        color: comment['avatarColor'],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              comment['userName'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            if (comment['isVerified'] == true) ...[
                                              const SizedBox(width: 4),
                                              const Icon(
                                                Icons.verified,
                                                color: Color(0xFF10B981),
                                                size: 14,
                                              ),
                                            ],
                                          ],
                                        ),
                                        Text(
                                          comment['timeAgo'],
                                          style: const TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Edit & Delete actions for my own comments
                                  if (isMyComment) ...[
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 16, color: Colors.grey),
                                      onPressed: () => _editComment(comment['id']),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    const SizedBox(width: 12),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.primaryColor),
                                      onPressed: () => _deleteComment(comment['id']),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                comment['content'],
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13.5,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 10),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _toggleCommentLike(comment['id']),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isCommentLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                                      size: 14,
                                      color: isCommentLiked ? AppTheme.primaryColor : AppTheme.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${comment['likes']}',
                                      style: TextStyle(
                                        color: isCommentLiked ? AppTheme.primaryColor : AppTheme.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // 3. Bottom comment input text bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.white,
              padding: EdgeInsets.only(
                top: 10,
                bottom: MediaQuery.of(context).padding.bottom + 10,
                left: 16,
                right: 16,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _commentController,
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Add a comment...',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                        onSubmitted: (_) => _handleSendComment(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _handleSendComment,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.send, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionPill({
    required String label,
    required int count,
    required Color activeColor,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? Colors.transparent : const Color(0xFFE5E7EB),
            width: 1.5,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: activeColor.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isActive ? Colors.white : AppTheme.textSecondary,
              size: 20,
            ),
            const SizedBox(height: 6),
            Text(
              '$count $label',
              style: TextStyle(
                color: isActive ? Colors.white : AppTheme.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
