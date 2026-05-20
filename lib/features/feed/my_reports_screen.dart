import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme.dart';
import 'community_feed_screen.dart';
import 'report_incident_screen.dart';
import 'incident_detail_screen.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _EditReportDialog extends StatefulWidget {
  final Map<String, dynamic> report;
  const _EditReportDialog({required this.report});

  @override
  State<_EditReportDialog> createState() => _EditReportDialogState();
}

class _EditReportDialogState extends State<_EditReportDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.report['title']);
    _descController = TextEditingController(text: widget.report['description']);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String currentStatus = widget.report['status'] ?? 'ACTIVE';
    final bool isActive = currentStatus != 'RESOLVED';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Edit Incident Report', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),

            // Read-only status indicator — citizens cannot change this
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.shieldAlert,
                    size: 18,
                    color: isActive ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status: ${isActive ? "Active" : "Resolved"}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isActive ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Status is managed by the EAWS Response Team.',
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () {
            if (_titleController.text.trim().isNotEmpty && _descController.text.trim().isNotEmpty) {
              Navigator.pop(context, {
                'title': _titleController.text.trim(),
                'desc': _descController.text.trim(),
              });
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text('Save Changes'),
        ),
      ],
    );
  }
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  // Ensure we add some mock personal reports initially to make the screen look full and rich
  @override
  void initState() {
    super.initState();
    _injectMockPersonalReportsIfNeeded();
  }

  void _injectMockPersonalReportsIfNeeded() {
    final list = List<Map<String, dynamic>>.from(communityReportsNotifier.value);
    final hasMine = list.any((r) => r['userName'] == 'Ghana Citizen' || r['userName'] == 'Anonymous Citizen');
    if (!hasMine) {
      // Pre-populate some premium mock personal reports to match screen 5 stats exactly
      final mockMine = [
        {
          'id': 101,
          'userName': 'Ghana Citizen',
          'initials': 'GC',
          'avatarColor': AppTheme.primaryColor,
          'isVerified': true,
          'timeAgo': '2 min ago',
          'category': 'FLOOD',
          'categoryColor': const Color(0xFFEF4444),
          'title': 'Rising water levels on Liberation Road',
          'description': 'Water has reached knee level near the traffic light. Vehicles are stalling.',
          'severity': 'CRITICAL',
          'location': 'Liberation Road, Accra',
          'status': 'ACTIVE', // ACTIVE status matches ACTIVE tag in screen 5
          'likes': 24,
          'commentsCount': 8,
          'views': 312,
          'isLiked': false,
          'comments': [
            {
              'id': 1,
              'userName': 'Ama Mensah',
              'initials': 'AM',
              'avatarColor': const Color(0xFFEF4444),
              'isVerified': true,
              'timeAgo': '1 min ago',
              'content': 'I just passed through there; it\'s really bad. Stay away!',
              'likes': 5,
            }
          ]
        },
        {
          'id': 102,
          'userName': 'Ghana Citizen',
          'initials': 'GC',
          'avatarColor': AppTheme.primaryColor,
          'isVerified': true,
          'timeAgo': '15 min ago',
          'category': 'FIRE',
          'categoryColor': const Color(0xFFF59E0B),
          'title': 'Bushfire spotted near Achimota Forest',
          'description': 'Thick smoke visible from the main road. Fire service has been called.',
          'severity': 'WARNING',
          'location': 'Achimota Forest, Accra',
          'status': 'ACTIVE',
          'likes': 12,
          'commentsCount': 5,
          'views': 188,
          'isLiked': false,
          'comments': []
        },
        {
          'id': 103,
          'userName': 'Ghana Citizen',
          'initials': 'GC',
          'avatarColor': AppTheme.primaryColor,
          'isVerified': true,
          'timeAgo': '3 days ago',
          'category': 'MEDICAL',
          'categoryColor': const Color(0xFF3B82F6),
          'title': 'Injured person near Tema Station',
          'description': 'Someone collapsed near the terminal. Ambulance is en-route.',
          'severity': 'MEDIUM',
          'location': 'Tema Station, Accra',
          'status': 'RESOLVED', // RESOLVED status matches RESOLVED tag in screen 5
          'likes': 6,
          'commentsCount': 2,
          'views': 87,
          'isLiked': false,
          'comments': []
        },
      ];
      list.addAll(mockMine);
      communityReportsNotifier.value = list;
    }
  }

  void _handleDeleteReport(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Report', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to permanently delete this incident report from the community feed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              HapticFeedback.heavyImpact();
              final updated = List<Map<String, dynamic>>.from(communityReportsNotifier.value);
              updated.removeWhere((r) => r['id'] == id);
              communityReportsNotifier.value = updated;
              Navigator.pop(context);
              
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Report deleted successfully'),
                  backgroundColor: AppTheme.primaryColor,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _handleEditReport(Map<String, dynamic> report) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditReportDialog(report: report),
    );

    if (result != null) {
      HapticFeedback.mediumImpact();
      final updatedList = List<Map<String, dynamic>>.from(communityReportsNotifier.value);
      final idx = updatedList.indexWhere((r) => r['id'] == report['id']);
      if (idx != -1) {
        updatedList[idx]['title'] = result['title'];
        updatedList[idx]['description'] = result['desc'];
        communityReportsNotifier.value = updatedList;
      }
    }
  }

  void _handleResolveReport(Map<String, dynamic> report) {
    if (report['status'] == 'RESOLVED') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This report has already been resolved.'),
          backgroundColor: const Color(0xFFF59E0B),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: Color(0xFF10B981), size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text('Mark as Resolved', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Are you sure you want to mark this incident as resolved?',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            SizedBox(height: 12),
            Text(
              'Do this only if the situation has cleared up or emergency services have handled it.',
              style: TextStyle(color: Colors.grey, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              HapticFeedback.mediumImpact();
              final updatedList = List<Map<String, dynamic>>.from(communityReportsNotifier.value);
              final idx = updatedList.indexWhere((r) => r['id'] == report['id']);
              if (idx != -1) {
                updatedList[idx]['status'] = 'RESOLVED';
                updatedList[idx]['withdrawalRequested'] = false; // clear if any
                communityReportsNotifier.value = updatedList;
              }
              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Report marked as resolved.'),
                  backgroundColor: Color(0xFF10B981),
                ),
              );
            },
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Resolve'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                        'My Reports',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white, size: 24),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ReportIncidentScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 2. Scrollable Body Content
          Positioned.fill(
            top: 120,
            child: ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: communityReportsNotifier,
              builder: (context, reports, child) {
                // Filter only my reports (posted by Ghana Citizen or Anonymous Citizen)
                final myReports = reports.where((r) {
                  return r['userName'] == 'Ghana Citizen' || 
                         r['userName'] == 'Anonymous Citizen' ||
                         r['id'] == 101 || r['id'] == 102 || r['id'] == 103;
                }).toList();

                final int totalCount = myReports.length;
                final int activeCount = myReports.where((r) => r['status'] != 'RESOLVED').length;
                final int resolvedCount = myReports.where((r) => r['status'] == 'RESOLVED').length;

                return Column(
                  children: [
                    // Stats Row matching screen 5 layout
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              count: '$totalCount',
                              label: 'Total',
                              color: const Color(0xFFFEE2E2),
                              textColor: const Color(0xFFEF4444),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              count: '$activeCount',
                              label: 'Active',
                              color: const Color(0xFFE6FDF4),
                              textColor: const Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              count: '$resolvedCount',
                              label: 'Resolved',
                              color: const Color(0xFFEFF6FF),
                              textColor: const Color(0xFF3B82F6),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Reports List header
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'MY REPORTS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ),

                    // Reports List Cards
                    Expanded(
                      child: myReports.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(LucideIcons.fileText, size: 64, color: Color(0xFFD1D5DB)),
                                  SizedBox(height: 16),
                                  Text(
                                    'You haven\'t filed any reports yet',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Tap Report New Incident below to start.',
                                    style: TextStyle(color: Colors.grey, fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                              itemCount: myReports.length,
                              itemBuilder: (context, index) {
                                final report = myReports[index];
                                final bool isResolved = report['status'] == 'RESOLVED';
                                // Determine badge state: Resolved > Active
                                Color badgeBg;
                                Color badgeBorder;
                                String badgeText;
                                if (isResolved) {
                                  badgeBg = const Color(0xFFEFF6FF);
                                  badgeBorder = const Color(0xFF3B82F6);
                                  badgeText = 'RESOLVED';
                                } else {
                                  badgeBg = const Color(0xFFE6FDF4);
                                  badgeBorder = const Color(0xFF10B981);
                                  badgeText = 'ACTIVE';
                                }

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.02),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Top Header row with category & status badges
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: report['categoryColor'],
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              report['category'],
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: badgeBg,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: badgeBorder, width: 1),
                                            ),
                                            child: Text(
                                              badgeText,
                                              style: TextStyle(
                                                color: badgeBorder,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),

                                      // Title
                                      Text(
                                        report['title'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),

                                      // Description
                                      Text(
                                        report['description'],
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 14),

                                      // Stats & time
                                      Row(
                                        children: [
                                          const Icon(Icons.access_time, size: 14, color: AppTheme.textSecondary),
                                          const SizedBox(width: 4),
                                          Text(
                                            report['timeAgo'],
                                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                          ),
                                          const Spacer(),
                                          const Icon(Icons.thumb_up, size: 13, color: AppTheme.textSecondary),
                                          const SizedBox(width: 4),
                                          Text('${report['likes']}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                          const SizedBox(width: 12),
                                          const Icon(LucideIcons.messageSquare, size: 13, color: AppTheme.textSecondary),
                                          const SizedBox(width: 4),
                                          Text('${report['commentsCount']}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                        ],
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 12.0),
                                        child: Divider(height: 1),
                                      ),

                                      // Cards Action Row: Edit, Withdraw, View
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          // Edit (only if not resolved)
                                          if (!isResolved)
                                            TextButton.icon(
                                              onPressed: () => _handleEditReport(report),
                                              icon: const Icon(Icons.edit, size: 16, color: AppTheme.textSecondary),
                                              label: const Text('Edit', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                                            ),
                                          // Resolve (only if active)
                                          if (!isResolved)
                                            TextButton.icon(
                                              onPressed: () => _handleResolveReport(report),
                                              icon: const Icon(Icons.check_circle, size: 16, color: Color(0xFF10B981)),
                                              label: const Text(
                                                'Resolve',
                                                style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          const Spacer(),
                                          // View
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              HapticFeedback.lightImpact();
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => IncidentDetailScreen(
                                                    report: report,
                                                    onUpdate: (updated) {
                                                      final list = List<Map<String, dynamic>>.from(communityReportsNotifier.value);
                                                      final idx = list.indexWhere((r) => r['id'] == report['id']);
                                                      if (idx != -1) {
                                                        list[idx] = updated;
                                                        communityReportsNotifier.value = list;
                                                      }
                                                    },
                                                  ),
                                                ),
                                              );
                                            },
                                            icon: const Icon(LucideIcons.eye, size: 14, color: Colors.white),
                                            label: const Text('View', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppTheme.primaryColor,
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              elevation: 0,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),

          // 3. Floating Bottom Button: "Report New Incident" matching screen 5 layout!
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.white,
              padding: EdgeInsets.only(
                top: 14,
                bottom: MediaQuery.of(context).padding.bottom + 14,
                left: 20,
                right: 20,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ReportIncidentScreen()),
                    );
                  },
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Report New Incident'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String count,
    required String label,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withOpacity(0.2), width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            count,
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor.withOpacity(0.8),
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
