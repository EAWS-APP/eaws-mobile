import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme.dart';
import '../../core/user_session.dart';
import '../../core/api_client.dart';
import '../feed/incident_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _pollingTimer;
  final ImagePicker _picker = ImagePicker();
  String? _selectedMediaUrl;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    // Fast 1-second interval for real-time responsiveness
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) _fetchMessages(silent: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _getUserId() {
    final authId = Supabase.instance.client.auth.currentUser?.id;
    if (authId != null && authId.isNotEmpty) return authId;

    final name = UserSession.instance.displayName.toLowerCase();
    if (name.contains('abena') || name.contains('osei')) return 'c-005';
    if (name.contains('ama') || name.contains('serwaa')) return 'c-002';
    if (name.contains('kwame') || name.contains('asante')) return 'c-003';
    if (name.contains('nana') || name.contains('mensah')) return 'c-004';
    if (name.contains('harrison')) return 'c-001';

    return 'c-005';
  }

  Future<void> _fetchMessages({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    try {
      final userId = _getUserId();
      final msgs = await IncidentApi.instance.getMessages(userId);
      if (mounted) {
        setState(() {
          _messages = msgs;
          _isLoading = false;
        });
        if (!silent) _scrollToBottom();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      print('Failed to fetch messages: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image != null) {
        setState(() {
          _selectedMediaUrl = 'https://images.unsplash.com/photo-1590486803833-1c5dc8ddd4c8?w=600&auto=format&fit=crop';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image attached. Type message or tap send.'), backgroundColor: AppTheme.primaryColor),
        );
      }
    } catch (e) {
      print('Error picking image: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _selectedMediaUrl == null) return;

    final userId = _getUserId();
    final mediaUrl = _selectedMediaUrl;
    _textController.clear();
    setState(() => _selectedMediaUrl = null);
    HapticFeedback.lightImpact();

    // Optimistic UI update
    final optimisticMsg = {
      'id': 'temp-${DateTime.now().millisecondsSinceEpoch}',
      'sender': 'citizen',
      'text': text,
      'type': mediaUrl != null ? 'image' : 'text',
      'media_url': mediaUrl,
      'is_deleted': false,
      'time': 'Just now',
    };
    setState(() {
      _messages.add(optimisticMsg);
    });
    _scrollToBottom();

    try {
      final added = await IncidentApi.instance.sendMessage(userId, text, mediaUrl: mediaUrl);
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == optimisticMsg['id']);
          if (idx != -1) _messages[idx] = added;
        });
      }
    } catch (e) {
      print('Failed to send message: $e');
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    final userId = _getUserId();

    try {
      await EawsApiClient.instance.delete('/messages/$userId/$messageId');
      _fetchMessages(silent: true);
    } catch (e) {
      print('Error deleting message: $e');
    }
  }

  void _showDeleteDialog(Map<String, dynamic> msg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessage(msg['id'].toString());
            },
            child: const Text('Delete', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        title: const Row(
          children: [
            Icon(LucideIcons.shieldAlert, size: 20, color: Colors.white),
            SizedBox(width: 8),
            Text('Control Room Messages', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.messageSquare, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('No messages yet', style: TextStyle(color: Colors.grey[600], fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Text('Direct communications with Dispatch will appear here.', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isCitizen = msg['sender'] == 'citizen';
                          return GestureDetector(
                            onLongPress: () {
                              if (msg['is_deleted'] != true) {
                                _showDeleteDialog(msg);
                              }
                            },
                            child: _buildMessageBubble(msg, isCitizen),
                          );
                        },
                      ),
          ),
          if (_selectedMediaUrl != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.grey.shade200,
              child: Row(
                children: [
                  const Icon(LucideIcons.image, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Image Attached', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 16),
                    onPressed: () => setState(() => _selectedMediaUrl = null),
                  )
                ],
              ),
            ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isCitizen) {
    final bool isDeleted = msg['is_deleted'] == true;

    return Align(
      alignment: isCitizen ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDeleted
              ? Colors.grey.shade300
              : isCitizen
                  ? AppTheme.primaryColor
                  : Colors.white,
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: isCitizen ? const Radius.circular(4) : const Radius.circular(20),
            bottomLeft: !isCitizen ? const Radius.circular(4) : const Radius.circular(20),
          ),
          border: isCitizen || isDeleted ? null : Border.all(color: Colors.grey.shade200),
          boxShadow: [
            if (!isCitizen && !isDeleted) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: isCitizen ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (isDeleted)
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.ban, size: 14, color: Colors.grey),
                  SizedBox(width: 6),
                  Text(
                    'This message was deleted',
                    style: TextStyle(color: Colors.black54, fontSize: 13, fontStyle: FontStyle.italic),
                  ),
                ],
              )
            else ...[
              if (msg['media_url'] != null && msg['media_url'].toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      msg['media_url'].toString(),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              if (msg['text'] != null && msg['text'].toString().isNotEmpty)
                Text(
                  msg['text'] ?? '',
                  style: TextStyle(
                    color: isCitizen ? Colors.white : Colors.black87,
                    fontSize: 14,
                  ),
                ),
            ],
            const SizedBox(height: 4),
            Text(
              msg['time'] ?? 'Just now',
              style: TextStyle(
                color: isDeleted
                    ? Colors.black45
                    : isCitizen
                        ? Colors.white70
                        : Colors.grey.shade500,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(LucideIcons.image, color: AppTheme.primaryColor),
            onPressed: _pickImage,
          ),
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                hintText: 'Type message to control room...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                isDense: true,
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppTheme.primaryColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
