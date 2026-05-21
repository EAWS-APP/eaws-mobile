import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme.dart';
import 'report_incident_screen.dart';
import 'incident_detail_screen.dart';
import 'my_reports_screen.dart';
import 'reactions_comments_screen.dart';
import 'incident_api.dart';

// Shared in-memory list of reports to support real-time dynamic posting during runtime
final ValueNotifier<List<Map<String, dynamic>>> communityReportsNotifier = ValueNotifier<List<Map<String, dynamic>>>([
  {
    'id': 1,
    'userName': 'Kwame Mensah',
    'initials': 'KM',
    'avatarColor': const Color(0xFFEF4444),
    'isVerified': true,
    'timeAgo': '2 min ago',
    'category': 'FLOOD',
    'categoryColor': const Color(0xFFEF4444),
    'title': 'Rising water levels on Liberation Road',
    'description': 'Water has reached knee level near the traffic light. Avoid the area and seek alternative bypass routes.',
    'imageAsset': 'assets/images/flood.jpg', // we will use fallback beautiful network image or elegant UI card
    'severity': 'CRITICAL',
    'location': 'Accra, Ghana',
    'likes': 24,
    'comments': 8,
    'isLiked': false,
  },
  {
    'id': 2,
    'userName': 'Ama Boateng',
    'initials': 'AB',
    'avatarColor': const Color(0xFFF59E0B),
    'isVerified': true,
    'timeAgo': '15 min ago',
    'category': 'FIRE',
    'categoryColor': const Color(0xFFF59E0B),
    'title': 'Bushfire spotted near Achimota Forest',
    'description': 'Thick smoke visible from the main road. Fire service has been called and dispatchers are en-route.',
    'imageAsset': 'assets/images/fire.jpg',
    'severity': 'WARNING',
    'location': 'Achimota, Accra',
    'likes': 12,
    'comments': 5,
    'isLiked': false,
  },
  {
    'id': 3,
    'userName': 'Robert Doe',
    'initials': 'RD',
    'avatarColor': const Color(0xFF3B82F6),
    'isVerified': true,
    'timeAgo': '1 hr ago',
    'category': 'MEDICAL',
    'categoryColor': const Color(0xFF3B82F6),
    'title': 'Injured person near Tema Station',
    'description': 'Someone collapsed near the bus terminal. Ambulance has been contacted and is currently on the way.',
    'imageAsset': null,
    'severity': 'MEDIUM',
    'location': 'Tema, Ghana',
    'likes': 6,
    'comments': 2,
    'isLiked': false,
  },
]);

class CommunityFeedScreen extends StatefulWidget {
  const CommunityFeedScreen({super.key});

  @override
  State<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<CommunityFeedScreen> {
  String _selectedCategory = 'All';
  final List<String> _categories = ['All', 'Nearby', 'Flood', 'Fire', 'Suspicious', 'Medical'];

  // Upgraded live filtering & search options matching screen 4
  String _searchQuery = '';
  Set<String> _activeTypes = {'Flood', 'Fire', 'Medical', 'Suspicious', 'Earthquake', 'Other'};
  Set<String> _activeSeverities = {'CRITICAL', 'WARNING', 'MEDIUM', 'LOW'};
  double _distanceFromMe = 15.0;
  String _timeRange = 'All Time';
  String _sortBy = 'Most Recent';

  @override
  void initState() {
    super.initState();
    _loadIncidentFeed();
  }

  Future<void> _loadIncidentFeed() async {
    try {
      final incidents = await IncidentApi.instance.getFeed(
        category: _selectedCategory,
        distanceKm: _distanceFromMe,
        timeRange: _timeRange,
        sort: _sortBy,
      );
      if (incidents.isNotEmpty) {
        communityReportsNotifier.value = incidents.map((incident) => incident.toUiMap()).toList();
      }
    } catch (e) {
      print('EAWS Feed API unavailable, keeping local mock feed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
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
                left: 12,
                right: 12,
                bottom: 12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Premium "My Reports" icon shortcut button linking Dashboard
                  IconButton(
                    icon: const Icon(LucideIcons.fileText, color: Colors.white, size: 22),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MyReportsScreen(),
                        ),
                      );
                    },
                  ),
                  const Text(
                    'Community Feed',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  // Search & Sliders Filter icon
                  IconButton(
                    icon: const Icon(LucideIcons.sliders, color: Colors.white, size: 22),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _showFilterBottomSheet();
                    },
                  ),
                ],
              ),
            ),
          ),

          // 2. Scrollable Body Content
          Positioned.fill(
            top: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Horizontal category filter chips list
                const SizedBox(height: 12),
                SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      final isSelected = _selectedCategory.toLowerCase() == cat.toLowerCase();
                      
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedCategory = cat;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? AppTheme.primaryColor : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? Colors.transparent : const Color(0xFFE5E7EB),
                                width: 1.5,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.primaryColor.withOpacity(0.15),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      )
                                    ]
                                  : null,
                            ),
                            child: Row(
                              children: [
                                if (cat == 'Nearby') ...[
                                  Icon(
                                    LucideIcons.mapPin,
                                    size: 13,
                                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  cat,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Reports Sub-header (RECENT REPORTS + Live Dot)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'RECENT REPORTS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.successColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Live',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Live ValueListenableBuilder feed list
                Expanded(
                  child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                    valueListenable: communityReportsNotifier,
                    builder: (context, reports, child) {
                      // Dynamic live filtering
                      final filteredReports = reports.where((report) {
                        // 1. Search query filter
                        if (_searchQuery.isNotEmpty) {
                          final title = report['title'].toString().toLowerCase();
                          final desc = report['description'].toString().toLowerCase();
                          final loc = report['location'].toString().toLowerCase();
                          final query = _searchQuery.toLowerCase();
                          if (!title.contains(query) && !desc.contains(query) && !loc.contains(query)) {
                            return false;
                          }
                        }

                        // 2. Incident Category tab selection
                        final cat = report['category'].toString().toLowerCase();
                        if (_selectedCategory != 'All' && _selectedCategory != 'Nearby') {
                          if (cat != _selectedCategory.toLowerCase()) return false;
                        }

                        // Map category to types checkbox set
                        String type = 'Other';
                        if (cat == 'flood') type = 'Flood';
                        if (cat == 'fire') type = 'Fire';
                        if (cat == 'medical') type = 'Medical';
                        if (cat == 'suspicious') type = 'Suspicious';
                        
                        if (!_activeTypes.contains(type)) return false;

                        // 3. Severity filter
                        final sev = report['severity'].toString().toUpperCase();
                        if (!_activeSeverities.contains(sev)) return false;

                        return true;
                      }).toList();

                      // Sort dynamically matching sort options
                      if (_sortBy == 'Most Reactions') {
                        filteredReports.sort((a, b) => (b['likes'] ?? 0).compareTo(a['likes'] ?? 0));
                      } else {
                        // Default to chronological ID ordering
                        filteredReports.sort((a, b) => (b['id'] ?? 0).compareTo(a['id'] ?? 0));
                      }

                      if (filteredReports.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(LucideIcons.newspaper, size: 54, color: Color(0xFFD1D5DB)),
                              SizedBox(height: 12),
                              Text(
                                'No matching reports found',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Try clearing your alert filters.',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        itemCount: filteredReports.length,
                        itemBuilder: (context, index) {
                          final report = filteredReports[index];
                          
                          // Wrap card in tap navigation to detail view!
                          return GestureDetector(
                            onTap: () {
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
                            child: _buildFeedCard(report),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // 3. Floating Action Button (FAB) matching Screenshot 1
          Positioned(
            bottom: 16,
            right: 20,
            child: FloatingActionButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ReportIncidentScreen(),
                  ),
                );
              },
              backgroundColor: AppTheme.primaryColor,
              elevation: 4,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, color: Colors.white, size: 30),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedCard(Map<String, dynamic> report) {
    final bool isLiked = report['isLiked'] ?? false;
    final int likeCount = report['likes'] ?? 0;
    final int commentCount = report['commentsCount'] ?? 
        (report['comments'] is List ? (report['comments'] as List).length : (report['comments'] ?? 0));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Category Colored Severity Indicator Strip
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: report['categoryColor'],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                ),
              ),
            ),

            // Card Body Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Header Row
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: report['avatarColor'].withOpacity(0.15),
                          child: Text(
                            report['initials'],
                            style: TextStyle(
                              color: report['avatarColor'],
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
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
                                    report['userName'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  if (report['isVerified'] == true) ...[
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.verified,
                                      color: Color(0xFF10B981),
                                      size: 15,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 1),
                              Text(
                                report['timeAgo'],
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Top Right Category Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: report['categoryColor'],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            report['category'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
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
                        fontSize: 15.5,
                        color: AppTheme.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Description text
                    Text(
                      report['description'],
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),

                    // Card Incident Image with translucent severity warning tag on top left
                    if (report['imageAsset'] != null) ...[
                      _buildIncidentImage(
                        report['imageAsset'],
                        report['severity'],
                        isLocalFile: !report['imageAsset'].startsWith('http') && !report['imageAsset'].startsWith('assets/'),
                        isVideo: report['isVideo'] == true,
                      ),
                    ] else if (report['category'] == 'FLOOD') ...[
                      _buildIncidentImage(
                        'https://images.unsplash.com/photo-1547683905-f686c993aae5?auto=format&fit=crop&q=80&w=800',
                        report['severity'],
                      ),
                    ] else if (report['category'] == 'FIRE') ...[
                      _buildIncidentImage(
                        'https://images.unsplash.com/photo-1508873699372-7aeab60b44ab?auto=format&fit=crop&q=80&w=800',
                        report['severity'],
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Card Footer Location pin & likes + comments interaction stats
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.mapPin,
                          size: 13,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            report['location'],
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Likes action button
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _toggleLike(report['id']);
                          },
                          child: Row(
                            children: [
                              Icon(
                                isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                                size: 15,
                                color: isLiked ? AppTheme.primaryColor : AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$likeCount',
                                style: TextStyle(
                                  color: isLiked ? AppTheme.primaryColor : AppTheme.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Comments action button opens ReactionsCommentsScreen!
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ReactionsCommentsScreen(
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
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.messageSquare,
                                size: 15,
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$commentCount',
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentImage(String imageUrl, String label, {bool isLocalFile = false, bool isVideo = false}) {
    ImageProvider imageProvider;
    if (isLocalFile) {
      imageProvider = FileImage(File(imageUrl));
    } else if (imageUrl.startsWith('assets/')) {
      imageProvider = AssetImage(imageUrl);
    } else {
      imageProvider = NetworkImage(imageUrl);
    }

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        image: DecorationImage(
          image: imageProvider,
          fit: BoxFit.cover,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Container(
            color: Colors.black.withOpacity(isVideo ? 0.25 : 0.06),
          ),
          if (isVideo)
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.play,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    label == 'CRITICAL' ? LucideIcons.alertTriangle : LucideIcons.flame,
                    color: label == 'CRITICAL' ? Colors.red : Colors.orange,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
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

  void _toggleLike(int id) {
    final updatedList = List<Map<String, dynamic>>.from(communityReportsNotifier.value);
    final index = updatedList.indexWhere((r) => r['id'] == id);
    if (index != -1) {
      final report = updatedList[index];
      final isLiked = report['isLiked'] ?? false;
      report['isLiked'] = !isLiked;
      report['likes'] = isLiked ? (report['likes'] - 1) : (report['likes'] + 1);
      communityReportsNotifier.value = updatedList;
    }
  }

  // Upgraded dynamic filter alerts bottom sheet styled exactly like Screen 4!
  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: const BoxDecoration(
                color: Color(0xFFF3F4F6),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Stack(
                children: [
                  // 1. Scrollable filter contents
                  Positioned.fill(
                    bottom: 80,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header title and Reset action
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close, color: AppTheme.textPrimary, size: 24),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const Text(
                                'Filter Alerts',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  setSheetState(() {
                                    _searchQuery = '';
                                    _activeTypes = {'Flood', 'Fire', 'Medical', 'Suspicious', 'Earthquake', 'Other'};
                                    _activeSeverities = {'CRITICAL', 'WARNING', 'MEDIUM', 'LOW'};
                                    _distanceFromMe = 15.0;
                                    _timeRange = 'All Time';
                                    _sortBy = 'Most Recent';
                                  });
                                },
                                child: const Text(
                                  'Reset',
                                  style: TextStyle(
                                    color: AppTheme.primaryColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Search Incidents field matching screen 4
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const Icon(LucideIcons.search, color: AppTheme.textSecondary, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: TextEditingController(text: _searchQuery)
                                      ..selection = TextSelection.fromPosition(TextPosition(offset: _searchQuery.length)),
                                    onChanged: (val) {
                                      _searchQuery = val;
                                    },
                                    decoration: const InputDecoration(
                                      hintText: 'Search incidents, locations...',
                                      hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                                      border: InputBorder.none,
                                    ),
                                    style: const TextStyle(fontSize: 14.5),
                                  ),
                                ),
                                if (_searchQuery.isNotEmpty)
                                  GestureDetector(
                                    onTap: () {
                                      setSheetState(() {
                                        _searchQuery = '';
                                      });
                                    },
                                    child: const Icon(Icons.cancel, color: Colors.grey, size: 18),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // INCIDENT TYPE BUTTONS GRID
                          const Text(
                            'INCIDENT TYPE',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textSecondary,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 12),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 3,
                            childAspectRatio: 2.2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            children: ['Flood', 'Fire', 'Medical', 'Suspicious', 'Earthquake', 'Other'].map((type) {
                              final bool isSelected = _activeTypes.contains(type);
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  setSheetState(() {
                                    if (isSelected) {
                                      if (_activeTypes.length > 1) {
                                        _activeTypes.remove(type);
                                      }
                                    } else {
                                      _activeTypes.add(type);
                                    }
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppTheme.primaryColor : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? Colors.transparent : const Color(0xFFE5E7EB),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      type,
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : AppTheme.textSecondary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),

                          // SEVERITY TOGGLES
                          const Text(
                            'SEVERITY',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textSecondary,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                            ),
                            child: Column(
                              children: [
                                _buildSeverityToggleRow(
                                  label: 'Critical',
                                  color: const Color(0xFFEF4444),
                                  isActive: _activeSeverities.contains('CRITICAL'),
                                  onChanged: (val) {
                                    setSheetState(() {
                                      if (val) _activeSeverities.add('CRITICAL');
                                      else if (_activeSeverities.length > 1) _activeSeverities.remove('CRITICAL');
                                    });
                                  },
                                ),
                                const Divider(height: 1),
                                _buildSeverityToggleRow(
                                  label: 'High',
                                  color: const Color(0xFFF59E0B),
                                  isActive: _activeSeverities.contains('WARNING'),
                                  onChanged: (val) {
                                    setSheetState(() {
                                      if (val) _activeSeverities.add('WARNING');
                                      else if (_activeSeverities.length > 1) _activeSeverities.remove('WARNING');
                                    });
                                  },
                                ),
                                const Divider(height: 1),
                                _buildSeverityToggleRow(
                                  label: 'Medium',
                                  color: const Color(0xFF3B82F6),
                                  isActive: _activeSeverities.contains('MEDIUM'),
                                  onChanged: (val) {
                                    setSheetState(() {
                                      if (val) _activeSeverities.add('MEDIUM');
                                      else if (_activeSeverities.length > 1) _activeSeverities.remove('MEDIUM');
                                    });
                                  },
                                ),
                                const Divider(height: 1),
                                _buildSeverityToggleRow(
                                  label: 'Low',
                                  color: const Color(0xFF10B981),
                                  isActive: _activeSeverities.contains('LOW'),
                                  onChanged: (val) {
                                    setSheetState(() {
                                      if (val) _activeSeverities.add('LOW');
                                      else if (_activeSeverities.length > 1) _activeSeverities.remove('LOW');
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // LOCATION RANGE SLIDER
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'LOCATION RANGE',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textSecondary,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              Text(
                                '${_distanceFromMe.toInt()} km',
                                style: const TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Slider.adaptive(
                              value: _distanceFromMe,
                              min: 1.0,
                              max: 50.0,
                              activeColor: AppTheme.primaryColor,
                              inactiveColor: const Color(0xFFE5E7EB),
                              onChanged: (val) {
                                setSheetState(() {
                                  _distanceFromMe = val;
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 24),

                          // TIME RANGE BUTTONS
                          const Text(
                            'TIME RANGE',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textSecondary,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: ['Last Hour', 'Today', 'This Week', 'All Time'].map((time) {
                              final isSelected = _timeRange == time;
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6.0),
                                  child: GestureDetector(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      setSheetState(() {
                                        _timeRange = time;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isSelected ? AppTheme.primaryColor : Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isSelected ? Colors.transparent : const Color(0xFFE5E7EB),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          time,
                                          style: TextStyle(
                                            color: isSelected ? Colors.white : AppTheme.textSecondary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),

                          // SORT BY RADIO LIST
                          const Text(
                            'SORT BY',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textSecondary,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                            ),
                            child: Column(
                              children: [
                                _buildSortRadioRow(
                                  label: 'Most Recent',
                                  isSelected: _sortBy == 'Most Recent',
                                  onTap: () => setSheetState(() => _sortBy = 'Most Recent'),
                                ),
                                const Divider(height: 1),
                                _buildSortRadioRow(
                                  label: 'Nearest to Me',
                                  isSelected: _sortBy == 'Nearest to Me',
                                  onTap: () => setSheetState(() => _sortBy = 'Nearest to Me'),
                                ),
                                const Divider(height: 1),
                                _buildSortRadioRow(
                                  label: 'Most Reactions',
                                  isSelected: _sortBy == 'Most Reactions',
                                  onTap: () => setSheetState(() => _sortBy = 'Most Reactions'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 2. Fixed bottom Apply button matching screen 4
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: Colors.white,
                      padding: EdgeInsets.only(
                        top: 12,
                        bottom: MediaQuery.of(context).padding.bottom + 12,
                        left: 20,
                        right: 20,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            setState(() {}); // Apply state change dynamically to trigger list rebuild!
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                          ),
                          child: const Text(
                            'Apply Filters',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSeverityToggleRow({
    required String label,
    required Color color,
    required bool isActive,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: AppTheme.textPrimary,
            ),
          ),
          const Spacer(),
          Switch.adaptive(
            value: isActive,
            activeColor: color,
            onChanged: (val) {
              HapticFeedback.selectionClick();
              onChanged(val);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSortRadioRow({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          fontSize: 14,
        ),
      ),
      trailing: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : const Color(0xFFD1D5DB),
            width: 2,
          ),
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white, size: 12)
            : null,
      ),
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
    );
  }
}
