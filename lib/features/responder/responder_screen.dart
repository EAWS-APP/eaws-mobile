import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/location_service.dart';
import '../../core/theme.dart';
import 'responder_api.dart';

class ResponderScreen extends StatefulWidget {
  final String? initialAgency;

  const ResponderScreen({super.key, this.initialAgency});

  @override
  State<ResponderScreen> createState() => _ResponderScreenState();
}

class _ResponderScreenState extends State<ResponderScreen> with TickerProviderStateMixin {
  late String _selectedAgency;
  String _unitCallsign = 'POL-KMS-04';
  bool _isLoading = false;
  List<Map<String, dynamic>> _assignments = [];
  Map<String, dynamic>? _activeAssignment;

  // Live Telemetry & Streaming State
  final LocationService _loc = LocationService.instance;
  bool _isStreaming = false;
  int _pingCount = 0;
  DateTime? _lastPingAt;
  double? _lastPingLat;
  double? _lastPingLng;
  double _currentSpeedKmh = 0.0;
  double _currentHeading = 0.0;

  Timer? _pollingTimer;
  Timer? _streamTimer;
  late AnimationController _radarController;
  late Animation<double> _radarAnimation;

  @override
  void initState() {
    super.initState();
    _selectedAgency = (widget.initialAgency ?? 'police').toLowerCase();
    _initDefaultCallsign();

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _radarAnimation = Tween<double>(begin: 0.9, end: 1.5).animate(
      CurvedAnimation(parent: _radarController, curve: Curves.easeOut),
    );

    _initLocation();
    _loadAssignments();

    // Poll for new agency assignments every 5 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadAssignments(silent: true));
  }

  void _initDefaultCallsign() {
    switch (_selectedAgency) {
      case 'ambulance':
        _unitCallsign = 'AMB-KMS-02';
        break;
      case 'fire':
        _unitCallsign = 'FIRE-ACC-03';
        break;
      case 'nadmo':
        _unitCallsign = 'NAD-KMS-01';
        break;
      case 'police':
      default:
        _unitCallsign = 'POL-KMS-04';
        break;
    }
  }

  Future<void> _initLocation() async {
    _loc.latestFix.addListener(_onLocationUpdate);
    await _loc.start(foreground: false);
  }

  void _onLocationUpdate() {
    final fix = _loc.latestFix.value;
    if (fix != null && mounted) {
      setState(() {
        _currentSpeedKmh = (fix.speed * 3.6).clamp(0.0, 180.0);
        _currentHeading = fix.heading;
      });
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _streamTimer?.cancel();
    _radarController.dispose();
    _loc.latestFix.removeListener(_onLocationUpdate);
    if (_isStreaming) {
      _loc.start(foreground: false);
    }
    super.dispose();
  }

  Future<void> _loadAssignments({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    try {
      final list = await ResponderApi.instance.fetchAgencyAssignments(_selectedAgency);
      if (mounted) {
        setState(() {
          _assignments = list;
          // Look for an in-progress assignment for this unit/session
          final inProgress = list.firstWhere(
            (a) => ['accepted', 'en_route', 'on_scene'].contains(a['status']),
            orElse: () => {},
          );
          if (inProgress.isNotEmpty) {
            _activeAssignment = inProgress;
            if (inProgress['status'] == 'en_route' && !_isStreaming) {
              _startStreamingPings();
            }
          } else if (_activeAssignment != null &&
              !list.any((a) => a['id'] == _activeAssignment!['id'] && a['status'] != 'resolved')) {
            _activeAssignment = null;
            _stopStreamingPings();
          }
        });
      }
    } finally {
      if (!silent && mounted) setState(() => _isLoading = false);
    }
  }

  void _startStreamingPings() {
    _isStreaming = true;
    _loc.start(foreground: true); // Enable Android foreground service & wakelock
    _streamTimer?.cancel();

    // Stream GPS telemetry every 4 seconds to POST /api/units/me/location
    _streamTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      final fix = _loc.latestFix.value;
      if (fix == null || _activeAssignment == null) return;

      final success = await ResponderApi.instance.sendLocationPing(
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracy: fix.accuracy,
        heading: fix.heading,
        speedKmh: fix.speed * 3.6,
        assignmentId: _activeAssignment!['id']?.toString(),
        unitId: _unitCallsign,
      );

      if (success && mounted) {
        setState(() {
          _pingCount++;
          _lastPingAt = DateTime.now();
          _lastPingLat = fix.latitude;
          _lastPingLng = fix.longitude;
        });
      }
    });
  }

  void _stopStreamingPings() {
    _isStreaming = false;
    _streamTimer?.cancel();
    _streamTimer = null;
    _loc.start(foreground: false);
  }

  // Lifecycle status transitions
  Future<void> _updateStatus(String assignmentId, String newStatus, {String? notes}) async {
    HapticFeedback.heavyImpact();
    setState(() => _isLoading = true);
    try {
      final res = await ResponderApi.instance.updateAssignmentStatus(
        assignmentId,
        status: newStatus,
        notes: notes,
      );

      if (res != null) {
        if (newStatus == 'en_route') {
          _startStreamingPings();
        } else if (newStatus == 'resolved' || newStatus == 'declined') {
          _stopStreamingPings();
          _activeAssignment = null;
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Status updated to ${newStatus.replaceAll('_', ' ').toUpperCase()}'),
              backgroundColor: newStatus == 'declined' ? AppTheme.errorColor : AppTheme.successColor,
            ),
          );
        }
        await _loadAssignments();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showResolveDialog(String assignmentId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Resolve Incident',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter field resolution notes before closing the incident case:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. Victim stabilized and transferred to Korle Bu ER. Scene secured.',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.successColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _updateStatus(assignmentId, 'resolved', notes: controller.text.trim());
            },
            child: const Text('CONFIRM RESOLVED'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchNavigation(double lat, double lng) async {
    HapticFeedback.lightImpact();
    final Uri uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch external navigation application')),
        );
      }
    }
  }

  Future<void> _callPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
    final Uri uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B132B), // Tactical dark navy
        appBar: _buildAppBar(),
        body: RefreshIndicator(
          onRefresh: () => _loadAssignments(),
          color: AppTheme.primaryColor,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAgencySectorSelector(),
                const SizedBox(height: 16),
                _buildTelemetryStatusCard(),
                const SizedBox(height: 16),
                if (_activeAssignment != null) ...[
                  _buildActiveAssignmentSection(),
                  const SizedBox(height: 24),
                ],
                _buildPendingAssignmentsSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0F172A),
      elevation: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.shieldCheck, color: Color(0xFF38BDF8), size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'RESPONDER MODE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 1.1,
                ),
              ),
              Text(
                'Unit: $_unitCallsign',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _isStreaming ? const Color(0xFF059669) : const Color(0xFF334155),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isStreaming ? Colors.greenAccent : Colors.white38,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _isStreaming ? 'STREAMING' : 'STANDBY',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAgencySectorSelector() {
    final agencies = [
      {'key': 'police', 'label': 'POLICE', 'icon': LucideIcons.shield, 'color': const Color(0xFF1D4ED8)},
      {'key': 'ambulance', 'label': 'AMBULANCE', 'icon': LucideIcons.heartPulse, 'color': const Color(0xFFDC2626)},
      {'key': 'fire', 'label': 'FIRE SERVICE', 'icon': LucideIcons.flame, 'color': const Color(0xFFEA580C)},
      {'key': 'nadmo', 'label': 'NADMO', 'icon': LucideIcons.alertTriangle, 'color': const Color(0xFF059669)},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'OPERATIONAL AGENCY SECTOR',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: agencies.map((a) {
              final isSelected = _selectedAgency == a['key'];
              final color = a['color'] as Color;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(a['icon'] as IconData, size: 14, color: isSelected ? Colors.white : Colors.white70),
                      const SizedBox(width: 6),
                      Text(a['label'] as String),
                    ],
                  ),
                  selected: isSelected,
                  selectedColor: color,
                  backgroundColor: const Color(0xFF1E293B),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 12,
                  ),
                  side: BorderSide(
                    color: isSelected ? color : Colors.white12,
                    width: 1.5,
                  ),
                  onSelected: (val) {
                    if (val && _selectedAgency != a['key']) {
                      setState(() {
                        _selectedAgency = a['key'] as String;
                        _initDefaultCallsign();
                      });
                      _loadAssignments();
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTelemetryStatusCard() {
    final fix = _loc.latestFix.value;
    final bool hasFix = fix != null && fix.source == FixSource.gps;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                hasFix ? LucideIcons.locateFixed : LucideIcons.locate,
                size: 16,
                color: hasFix ? AppTheme.successColor : const Color(0xFFF59E0B),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasFix
                      ? 'GPS ACTIVE • ±${fix.accuracy.toStringAsFixed(1)}m precision'
                      : 'ACQUIRING SATELLITE FIX...',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: hasFix ? Colors.greenAccent : const Color(0xFFFCD34D),
                  ),
                ),
              ),
              if (_pingCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_pingCount Pings Sent',
                    style: const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 16, color: Colors.white10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildTelemetryMetric(
                'COORDINATES',
                hasFix ? '${fix.latitude.toStringAsFixed(4)}, ${fix.longitude.toStringAsFixed(4)}' : '--, --',
              ),
              _buildTelemetryMetric(
                'SPEED',
                '${_currentSpeedKmh.toStringAsFixed(0)} km/h',
              ),
              _buildTelemetryMetric(
                'HEADING',
                '${_currentHeading.toStringAsFixed(0)}°',
              ),
              _buildTelemetryMetric(
                'LAST PING',
                _lastPingAt != null
                    ? '${DateTime.now().difference(_lastPingAt!).inSeconds}s ago (${_lastPingLat?.toStringAsFixed(2)}, ${_lastPingLng?.toStringAsFixed(2)})'
                    : 'Standby',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildActiveAssignmentSection() {
    final a = _activeAssignment!;
    final status = a['status']?.toString() ?? 'accepted';
    final lat = a['latitude'] != null ? (a['latitude'] as num).toDouble() : null;
    final lng = a['longitude'] != null ? (a['longitude'] as num).toDouble() : null;
    final locationName = a['location_name'] ?? 'Coordinates Pending';
    final title = a['incident_title'] ?? 'Emergency Case';
    final priority = (a['priority'] ?? 'CRITICAL').toString().toUpperCase();
    final metadata = a['incident_metadata'] as Map? ?? {};
    final phone = metadata['phone_number'] ?? metadata['phone'] ?? '112';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF2563EB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.radio, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'ACTIVE ASSIGNMENT EN ROUTE',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status.replaceAll('_', ' ').toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.errorColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  priority,
                                  style: const TextStyle(color: AppTheme.errorColor, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Sector: ${a['district_id'] ?? a['region_id'] ?? "Accra / Kumasi Metro"}',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (lat != null && lng != null)
                      IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                        icon: const Icon(LucideIcons.navigation, color: Color(0xFF38BDF8), size: 20),
                        tooltip: 'Launch Navigation',
                        onPressed: () => _launchNavigation(lat, lng),
                      ),
                  ],
                ),
                const Divider(height: 24, color: Colors.white10),

                // Location Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.mapPin, color: Color(0xFFEF4444), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            locationName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          if (lat != null && lng != null)
                            Text(
                              'GPS: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Citizen Contact Row
                Row(
                  children: [
                    const Icon(LucideIcons.user, color: Color(0xFF38BDF8), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        metadata['full_name'] ?? metadata['name'] ?? 'Citizen Contact',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    if (phone.isNotEmpty && phone != '112')
                      InkWell(
                        onTap: () => _callPhone(phone),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.phone, size: 12, color: Colors.greenAccent),
                              const SizedBox(width: 4),
                              Text(phone, style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 20),

                // Action Controls
                _buildActiveActionButtons(a['id'].toString(), status, lat, lng),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveActionButtons(String assignmentId, String status, double? lat, double? lng) {
    if (status == 'accepted') {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(LucideIcons.navigation, size: 18),
              label: const Text('START EN ROUTE (BROADCAST GPS)', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _updateStatus(assignmentId, 'en_route'),
            ),
          ),
        ],
      );
    }

    if (status == 'en_route') {
      return Column(
        children: [
          Row(
            children: [
              if (lat != null && lng != null)
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF38BDF8),
                      side: const BorderSide(color: Color(0xFF38BDF8)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(LucideIcons.map, size: 16),
                    label: const Text('MAPS NAV', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _launchNavigation(lat, lng),
                  ),
                ),
              if (lat != null && lng != null) const SizedBox(width: 10),
              Expanded(
                flex: lat != null && lng != null ? 1 : 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.successColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(LucideIcons.checkCircle2, size: 18),
                  label: const Text('ON SCENE', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => _updateStatus(assignmentId, 'on_scene'),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (status == 'on_scene') {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(LucideIcons.checkCheck, size: 18),
              label: const Text('RESOLVE & COMPLETE CASE', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _showResolveDialog(assignmentId),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildPendingAssignmentsSection() {
    final pending = _assignments.where((a) => a['status'] == 'assigned' || a['status'] == 'pending').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'INCOMING DISPATCH QUEUE',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${pending.length} cases',
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (pending.isEmpty)
          _buildEmptyStandbyQueue()
        else
          ...pending.map((a) => _buildAssignmentCard(a)),
      ],
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic> a) {
    final assignmentId = a['id']?.toString() ?? '';
    final title = a['incident_title'] ?? 'Emergency Case';
    final location = a['location_name'] ?? 'Location pending';
    final priority = (a['priority'] ?? 'CRITICAL').toString().toUpperCase();
    final eta = a['eta_minutes'];
    final timeStr = a['created_at'] != null
        ? DateTime.tryParse(a['created_at'].toString())?.toLocal().toString().substring(11, 16) ?? ''
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  priority,
                  style: const TextStyle(color: AppTheme.errorColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              if (timeStr.isNotEmpty)
                Text(
                  timeStr,
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
              const Spacer(),
              if (eta != null)
                Text(
                  'ETA: ~$eta mins',
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(LucideIcons.mapPin, color: Color(0xFF94A3B8), size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  location,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF94A3B8),
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _updateStatus(assignmentId, 'declined'),
                  child: const Text('DECLINE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(LucideIcons.check, size: 16),
                  label: const Text('ACCEPT CASE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _updateStatus(assignmentId, 'accepted'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStandbyQueue() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          ScaleTransition(
            scale: _radarAnimation,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2563EB).withOpacity(0.12),
              ),
              child: const Icon(LucideIcons.radio, color: Color(0xFF38BDF8), size: 32),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sector Standby',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Unit is active on CAD frequency.\nNew emergency assignments in your jurisdiction will trigger immediately.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
