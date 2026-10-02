import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../core/insforge_client.dart';

class MediaUploadsScreen extends StatefulWidget {
  const MediaUploadsScreen({super.key});

  @override
  State<MediaUploadsScreen> createState() => _MediaUploadsScreenState();
}

class _MediaUploadsScreenState extends State<MediaUploadsScreen> {
  final List<Map<String, dynamic>> _uploadQueue = [];

  Future<void> _captureAndUploadImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.camera);
      if (image == null) return;

      final file = File(image.path);
      final String filename =
          'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String fileSize =
          '${(file.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB';

      final newItem = {
        'name': filename,
        'size': fileSize,
        'progress': 0.0,
        'status': 'Uploading',
        'file': file,
      };

      setState(() {
        _uploadQueue.insert(0, newItem);
      });

      await _uploadEvidence(file, newItem);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not capture image: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _uploadEvidence(File file, Map<String, dynamic> item) async {
    if (mounted) {
      setState(() {
        item['status'] = 'Uploading';
        item['progress'] = 0.0;
      });
    }
    try {
      final reportsData = await EawsApiClient.instance.get(
        '/incidents/my-reports',
      );
      final reports = reportsData is Map ? reportsData['incidents'] : null;
      if (reports is! List || reports.isEmpty || reports.first is! Map) {
        throw StateError('Create an incident before attaching evidence.');
      }
      final incidentId = (reports.first as Map)['id']?.toString();
      if (incidentId == null || incidentId.isEmpty) {
        throw const FormatException(
          'The latest incident did not include an ID.',
        );
      }
      final filename = item['name'] as String;
      final upload = await InsForgeClient.instance.uploadFile(
        bucket: 'sos_evidence',
        file: file,
        filename: filename,
        contentType: 'image/jpeg',
      );
      final storagePath = upload['key']?.toString() ?? filename;
      await EawsApiClient.instance.post(
        '/incidents/${Uri.encodeComponent(incidentId)}/media',
        body: {
          'media_type': 'image',
          'storage_bucket': 'sos_evidence',
          'storage_path': storagePath,
          'mime_type': 'image/jpeg',
          'file_size_bytes': await file.length(),
        },
      );
      if (mounted) {
        setState(() {
          item['progress'] = 1.0;
          item['status'] = 'Completed';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => item['status'] = 'Failed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Evidence upload failed: $error'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  void _showVideoUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Video evidence upload is not available yet.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () {
            HapticFeedback.lightImpact();
            // Just pop if there is nav stack
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Use the bottom bar to switch screens!'),
                  backgroundColor: AppTheme.primaryColor,
                ),
              );
            }
          },
        ),
        title: const Text(
          'Media Uploads',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: AppTheme.textPrimary),
            onPressed: () {
              HapticFeedback.lightImpact();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Auto-Upload Warning Active Card matching Screenshot 3
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFECACA), width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.info,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Evidence uploads',
                          style: TextStyle(
                            color: Color(0xFF991B1B),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Captured photos upload to configured storage and are attached to your latest incident. Delivery to responders is not verified.',
                          style: TextStyle(
                            color: Color(0xFFB91C1C),
                            fontSize: 13,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // 2. CAPTURE EVIDENCE
            const Text(
              'CAPTURE EVIDENCE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildCaptureCard(
                    'Take Photo',
                    'Capture incident',
                    LucideIcons.camera,
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildCaptureCard(
                    'Record Video',
                    'Up to 60 sec',
                    LucideIcons.video,
                    Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // 3. UPLOAD QUEUE
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'UPLOAD QUEUE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  '${_uploadQueue.length} items',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              children: [
                ..._uploadQueue.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: _buildUploadQueueItem(
                      item['name'] as String,
                      item['size'] as String,
                      item['progress'] as double,
                      item['status'] as String,
                      onRetry: () =>
                          _uploadEvidence(item['file'] as File, item),
                    ),
                  );
                }),
                if (_uploadQueue.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No evidence uploaded in this session.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),

            // 4. SETTINGS SECTION
            const Text(
              'UPLOAD SETTINGS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Wi-Fi-only upload and compression are not implemented. Each captured photo is uploaded immediately.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureCard(
    String label,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          HapticFeedback.mediumImpact();
          if (label == 'Take Photo') {
            _captureAndUploadImage();
          } else {
            _showVideoUnavailable();
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadQueueItem(
    String filename,
    String size,
    double progress,
    String status, {
    required VoidCallback onRetry,
  }) {
    Color statusBg = const Color(0xFFFFFBEB);
    Color statusText = const Color(0xFFD97706);
    if (status == 'Completed') {
      statusBg = const Color(0xFFD1FAE5);
      statusText = const Color(0xFF059669);
    } else if (status == 'Failed') {
      statusBg = const Color(0xFFFEE2E2);
      statusText = const Color(0xFFDC2626);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: const Color(0xFFFEE2E2),
            ),
            child: const Icon(
              LucideIcons.image,
              color: AppTheme.primaryColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),

          // File metadata & progress
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      filename,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (status == 'Uploading') ...[
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Color(0xFFD97706),
                              ),
                            ),
                            const SizedBox(width: 5),
                          ] else if (status == 'Completed') ...[
                            const Icon(
                              Icons.check,
                              color: Color(0xFF059669),
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            status,
                            style: TextStyle(
                              color: statusText,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      size,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                        color: statusText,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Linear Progress Bar matching Screenshot 3
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: const Color(0xFFF3F4F6),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      status == 'Failed'
                          ? Colors.red
                          : (status == 'Completed'
                                ? Colors.green
                                : Colors.orange),
                    ),
                  ),
                ),
                if (status == 'Failed') ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: onRetry,
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
