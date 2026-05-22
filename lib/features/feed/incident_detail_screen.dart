import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme.dart';
import 'community_feed_screen.dart';
import 'reactions_comments_screen.dart';

class IncidentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> report;
  final Function(Map<String, dynamic> updatedReport) onUpdate;

  const IncidentDetailScreen({
    super.key,
    required this.report,
    required this.onUpdate,
  });

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  late Map<String, dynamic> _localReport;

  @override
  void initState() {
    super.initState();
    _localReport = Map<String, dynamic>.from(widget.report);
  }

  void _navigateToReactionsComments() async {
    final updated = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => ReactionsCommentsScreen(
          report: _localReport,
          onUpdate: (updatedReport) {
            setState(() {
              _localReport = updatedReport;
            });
            widget.onUpdate(updatedReport);
          },
        ),
      ),
    );
    if (updated != null) {
      setState(() {
        _localReport = updated;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final int commentCount = _localReport['commentsCount'] ?? 
        (_localReport['comments'] is List ? (_localReport['comments'] as List).length : (_localReport['comments'] ?? 0));

    final List<Map<String, dynamic>> commentsList = 
        _localReport['comments'] is List ? List<Map<String, dynamic>>.from(_localReport['comments']) : [];

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Stack(
        children: [
          // 1. Scrollable Body Content
          Positioned.fill(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top padding spacer matching the header height
                  SizedBox(height: MediaQuery.of(context).padding.top + 70),

                  // Image section with translucent severity tag
                  if (_localReport['category'] == 'FLOOD') ...[
                    _buildIncidentHeaderImage(
                      'https://images.unsplash.com/photo-1547683905-f686c993aae5?auto=format&fit=crop&q=80&w=800',
                      _localReport['severity'],
                    ),
                  ] else if (_localReport['category'] == 'FIRE') ...[
                    _buildIncidentHeaderImage(
                      'https://images.unsplash.com/photo-1508873699372-7aeab60b44ab?auto=format&fit=crop&q=80&w=800',
                      _localReport['severity'],
                    ),
                  ] else ...[
                    _buildIncidentHeaderImage(
                      'https://images.unsplash.com/photo-1488521787991-ed7bbaae773c?auto=format&fit=crop&q=80&w=800',
                      _localReport['severity'],
                    ),
                  ],

                  // Details container
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Time + distance row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _localReport['timeAgo'],
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Text(
                              '0.4 km away',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Title
                        Text(
                          _localReport['title'],
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Citizen details (Initials avatar + Verified capsule tag)
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: _localReport['avatarColor'].withOpacity(0.15),
                              child: Text(
                                _localReport['initials'],
                                style: TextStyle(
                                  color: _localReport['avatarColor'],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _localReport['userName'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  // Green Verified Badge matching screen 3 capsule styling
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE6FDF4),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFF10B981), width: 1),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(
                                          Icons.verified,
                                          color: Color(0xFF10B981),
                                          size: 13,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Verified Citizen',
                                          style: TextStyle(
                                            color: Color(0xFF10B981),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Description text
                        Text(
                          _localReport['description'],
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // LOCATION SECTION
                        const Text(
                          'LOCATION',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Location pin details box
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                          ),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.mapPin, color: AppTheme.primaryColor, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _localReport['location'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Mocked Map Visual box matching screen 2 OSM box
                        Container(
                          height: 160,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                            image: const DecorationImage(
                              image: NetworkImage(
                                'https://images.unsplash.com/photo-1524661135-423995f22d0b?auto=format&fit=crop&q=80&w=800',
                              ),
                              fit: BoxFit.cover,
                            ),
                          ),
                          child: Stack(
                            children: [
                              // Center Red Location Map Pin Overlay
                              const Center(
                                child: Icon(
                                  Icons.location_on,
                                  color: AppTheme.primaryColor,
                                  size: 40,
                                ),
                              ),
                              // Bottom left coordinate bubble
                              Positioned(
                                bottom: 10,
                                left: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    '5.6037° N, 0.1870° W',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // REPORTED DETAILS CARD
                        const Text(
                          'REPORTED DETAILS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                          ),
                          child: Column(
                            children: [
                              _buildDetailRow(Icons.access_time, 'Reported At', '16:32 GMT - Today'),
                              const Divider(height: 1),
                              _buildDetailRow(LucideIcons.fileText, 'Incident Type', _localReport['category']),
                              const Divider(height: 1),
                              _buildDetailRow(
                                LucideIcons.alertTriangle,
                                'Severity',
                                _localReport['severity'],
                                isSeverity: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // COMMUNITY VALIDATION
                        if (_localReport['status'] != 'RESOLVED') ...[
                          const Text(
                            'COMMUNITY VALIDATION',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textSecondary,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFBFDBFE), width: 1.5),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(LucideIcons.helpCircle, color: Color(0xFF2563EB), size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'Is this still happening?',
                                      style: TextStyle(
                                        color: Color(0xFF1E3A8A),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () {
                                          HapticFeedback.lightImpact();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Thanks! You verified this is still active.'), backgroundColor: Color(0xFF2563EB)),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: const Color(0xFF2563EB),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            side: const BorderSide(color: Color(0xFFBFDBFE)),
                                          ),
                                        ),
                                        child: const Text('Yes, still here'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () {
                                          HapticFeedback.lightImpact();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Thanks! You reported this as cleared.'), backgroundColor: Color(0xFF10B981)),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: const Color(0xFF10B981),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            side: const BorderSide(color: Color(0xFFA7F3D0)),
                                          ),
                                        ),
                                        child: const Text('No, it\'s cleared'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // COMMUNITY RESPONSE (INTERACTIVE STATS BOXES)
                        const Text(
                          'COMMUNITY RESPONSE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Row displaying: 24 Reactions, 8 Comments, 312 Views
                        Row(
                          children: [
                            Expanded(
                              child: _buildResponseStatCard(
                                count: '${_localReport['likes'] ?? 24}',
                                label: 'Reactions',
                                icon: Icons.thumb_up,
                                onTap: _navigateToReactionsComments,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildResponseStatCard(
                                count: '$commentCount',
                                label: 'Comments',
                                icon: LucideIcons.messageSquare,
                                onTap: _navigateToReactionsComments,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildResponseStatCard(
                                count: '${_localReport['views'] ?? 312}',
                                label: 'Views',
                                icon: LucideIcons.eye,
                                onTap: () {},
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // COMMENTS SECTION
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'COMMENTS',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textSecondary,
                                letterSpacing: 1.1,
                              ),
                            ),
                            GestureDetector(
                              onTap: _navigateToReactionsComments,
                              child: const Text(
                                'View all',
                                style: TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Preview comments list
                        if (commentsList.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                            ),
                            child: const Center(
                              child: Text(
                                'No comments yet. Tap to start discussion.',
                                style: TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            itemCount: commentsList.length > 2 ? 2 : commentsList.length,
                            itemBuilder: (context, index) {
                              final comment = commentsList[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
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
                                          radius: 12,
                                          backgroundColor: comment['avatarColor'].withOpacity(0.15),
                                          child: Text(
                                            comment['initials'],
                                            style: TextStyle(
                                              color: comment['avatarColor'],
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          comment['userName'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          comment['timeAgo'],
                                          style: const TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      comment['content'],
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                        const SizedBox(height: 12),

                        // Red bottom buttons matching screen 2 layout
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              HapticFeedback.heavyImpact();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Transmitting incident report directly to EAWS local dispatch authorities...'),
                                  backgroundColor: AppTheme.successColor,
                                ),
                              );
                            },
                            icon: const Icon(LucideIcons.send, size: 16),
                            label: const Text('Report to Authorities'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Alert link copied to clipboard!'),
                                  backgroundColor: AppTheme.primaryColor,
                                ),
                              );
                            },
                            icon: const Icon(Icons.share, size: 16),
                            label: const Text('Share Alert'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primaryColor,
                              side: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Fixed Top Curved Red Header Notch
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).padding.top + 60,
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
                bottom: 8,
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
                        'Incident Report',
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
                          content: Text('Sharing alert...'),
                          backgroundColor: AppTheme.primaryColor,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentHeaderImage(String imageUrl, String label) {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: NetworkImage(imageUrl),
          fit: BoxFit.cover,
        ),
      ),
      child: Stack(
        children: [
          // Semi-dark gradient overlay
          Container(
            color: Colors.black.withOpacity(0.08),
          ),
          // Top Left Translucent Severity Tag
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    label == 'CRITICAL' ? LucideIcons.alertTriangle : LucideIcons.flame,
                    color: label == 'CRITICAL' ? Colors.red : Colors.orange,
                    size: 14,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
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

  Widget _buildDetailRow(IconData icon, String label, String value, {bool isSeverity = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 18),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (isSeverity)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: value == 'CRITICAL' ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                value,
                style: TextStyle(
                  color: value == 'CRITICAL' ? Colors.red : Colors.orange,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            Text(
              value,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResponseStatCard({
    required String count,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
        ),
        child: Column(
          children: [
            Text(
              count,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
