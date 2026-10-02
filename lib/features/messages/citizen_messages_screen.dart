import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../sos/sos_api.dart';

const bool _demoMode = bool.fromEnvironment('EAWS_DEMO_MODE');

class CitizenMessagesScreen extends StatefulWidget {
  final bool demoMode;

  const CitizenMessagesScreen({super.key, this.demoMode = _demoMode});

  @override
  State<CitizenMessagesScreen> createState() => _CitizenMessagesScreenState();
}

class _CitizenMessagesScreenState extends State<CitizenMessagesScreen> {
  List<Map<String, dynamic>> _threads = [];
  Timer? _refreshTimer;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.demoMode) {
      _refreshThreads();
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _refreshThreads(),
      );
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshThreads() async {
    try {
      final threads = await SosApi.instance.getMessageThreads();
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Messages could not be loaded. Check your connection and retry.';
      });
      debugPrint('Could not load citizen TEST conversations: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            onPressed: widget.demoMode ? _refreshThreads : null,
            tooltip: 'Refresh messages',
            icon: const Icon(LucideIcons.refreshCw),
          ),
        ],
      ),
      body: !widget.demoMode
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Message history is not connected to the production backend in this build.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _MessageLoadError(message: _error!, onRetry: _refreshThreads)
          : _threads.isEmpty
          ? const _EmptyMessages()
          : RefreshIndicator(
              onRefresh: _refreshThreads,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _threads.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final thread = _threads[index];
                  final lastMessage = thread['last_message'] as Map?;
                  final title =
                      thread['incident_title']?.toString() ??
                      'SOS conversation';
                  final incidentId = thread['incident_id']?.toString() ?? '';
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: incidentId.isEmpty
                          ? null
                          : () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => CitizenConversationScreen(
                                    incidentId: incidentId,
                                    incidentTitle: title,
                                  ),
                                ),
                              );
                              if (mounted) _refreshThreads();
                            },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Color(0xFFFEE2E2),
                              foregroundColor: AppTheme.primaryColor,
                              child: Icon(LucideIcons.messageSquare),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    lastMessage?['text']?.toString() ??
                                        'No messages yet',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '$incidentId · ${thread['incident_status'] ?? 'open'}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              LucideIcons.chevronRight,
                              color: AppTheme.textSecondary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class CitizenConversationScreen extends StatefulWidget {
  final String incidentId;
  final String incidentTitle;

  const CitizenConversationScreen({
    super.key,
    required this.incidentId,
    required this.incidentTitle,
  });

  @override
  State<CitizenConversationScreen> createState() =>
      _CitizenConversationScreenState();
}

class _CitizenConversationScreenState extends State<CitizenConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  Timer? _refreshTimer;
  bool _loading = true;
  bool _sending = false;
  String? _pendingMessageId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshMessages();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshMessages(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshMessages() async {
    try {
      final messages = await SosApi.instance.getMessages(widget.incidentId);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Conversation unavailable. Your messages have not been changed.';
      });
      debugPrint('Could not load citizen TEST chat: $error');
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (_sending || text.isEmpty || text.length > 2000) return;
    _pendingMessageId ??=
        'TEST-MOBILE-MESSAGE-${DateTime.now().toUtc().microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await SosApi.instance.sendMessage(
        incidentId: widget.incidentId,
        content: text,
        clientMessageId: _pendingMessageId!,
      );
      if (!mounted) return;
      _messageController.clear();
      _pendingMessageId = null;
      await _refreshMessages();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Message was not confirmed. Keep the draft and retry.';
        });
      }
      debugPrint('Could not send citizen TEST message: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _messageState(Map<String, dynamic> message) {
    if (message['sender_role'] == 'citizen') {
      return message['read_state'] == 'read'
          ? 'Read by dispatcher'
          : 'Received by dispatcher';
    }
    switch (message['delivery_state']) {
      case 'fetched_by_citizen_app':
        if (message['read_state'] == 'read') return 'Read in this app';
        return 'Received by this app';
      case 'awaiting_citizen_poll':
        return 'Waiting for this app';
      default:
        return 'Delivery status unavailable';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          widget.incidentTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(28),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                'TEST ONLY · No SMS or push notifications',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: _refreshMessages,
                  child: const Text('Retry'),
                ),
              ],
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? const Center(
                    child: Text('No messages yet. Send a message to dispatch.'),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isCitizen = message['sender_role'] == 'citizen';
                      final time = DateTime.tryParse(
                        message['created_at']?.toString() ?? '',
                      );
                      return Align(
                        alignment: isCitizen
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 320),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isCitizen
                                ? AppTheme.primaryColor
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message['content']?.toString() ?? '',
                                style: TextStyle(
                                  color: isCitizen
                                      ? Colors.white
                                      : AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${isCitizen ? 'You' : 'Control room'} · ${time?.toLocal().toString() ?? 'Time unavailable'} · ${_messageState(message)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isCitizen
                                      ? Colors.white70
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: !_sending,
                      maxLength: 2000,
                      minLines: 1,
                      maxLines: 4,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 16),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText: 'Message dispatch',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send TEST message',
                    onPressed:
                        _sending || _messageController.text.trim().isEmpty
                        ? null
                        : _sendMessage,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageLoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _MessageLoadError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Your conversations with dispatch will stay here.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppTheme.textSecondary),
      ),
    ),
  );
}
