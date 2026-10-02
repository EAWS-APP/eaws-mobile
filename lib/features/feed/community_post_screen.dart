import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'incident_api.dart';

class CommunityPostScreen extends StatefulWidget {
  const CommunityPostScreen({super.key});

  @override
  State<CommunityPostScreen> createState() => _CommunityPostScreenState();
}

class _CommunityPostScreenState extends State<CommunityPostScreen> {
  final TextEditingController _contentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      await IncidentApi.instance.createCommunityPost(content);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Community update was not sent. Retry when connected. ($error)',
          ),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Community Update'),
        actions: [
          TextButton(
            onPressed: _isSubmitting || _contentController.text.trim().isEmpty
                ? null
                : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Post'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Share a non-emergency update with your community.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contentController,
              autofocus: true,
              minLines: 5,
              maxLines: 12,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What would you like your neighbours to know?',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            const Text(
              'For an immediate threat, use Report an Incident or SOS instead.',
              style: TextStyle(
                color: AppTheme.errorColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _isSubmitting || _contentController.text.trim().isEmpty
                  ? null
                  : _submit,
              child: Text(_isSubmitting ? 'Posting…' : 'Share update'),
            ),
          ],
        ),
      ),
    );
  }
}
