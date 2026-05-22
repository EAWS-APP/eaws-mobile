import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../core/theme.dart';
import 'community_feed_screen.dart';
import 'incident_api.dart';

class ReportIncidentScreen extends StatefulWidget {
  const ReportIncidentScreen({super.key});

  @override
  State<ReportIncidentScreen> createState() => _ReportIncidentScreenState();
}

class _ReportIncidentScreenState extends State<ReportIncidentScreen> {
  // Form State variables
  String _selectedIncidentType = 'Flood';
  final TextEditingController _customTypeController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  int _charCount = 0;
  bool _isAnonymous = false;

  // Media capture variables
  File? _selectedMediaFile;
  bool _isImage = true;
  bool _isSimulator = false;
  final ImagePicker _picker = ImagePicker();

  // Location details
  double _latitude = 5.6037;
  double _longitude = -0.1870;
  String _locationName = 'Accra, Ghana';
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    _checkIfSimulator();
    _descriptionController.addListener(() {
      setState(() {
        _charCount = _descriptionController.text.length;
      });
    });
    // Auto fetch user's location
    _fetchCurrentLocation();
  }

  Future<void> _checkIfSimulator() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        setState(() {
          _isSimulator = !iosInfo.isPhysicalDevice;
        });
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        setState(() {
          _isSimulator = !androidInfo.isPhysicalDevice;
        });
      }
    } catch (e) {
      print('EAWS Simulator Detection Error: $e');
    }
  }

  Future<void> _pickMedia(bool isImage) async {
    HapticFeedback.lightImpact();
    if (_isSimulator) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Running on simulator. Loading high-quality emergency mock ${isImage ? "photo" : "video"} for testing...',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.primaryColor,
          duration: const Duration(seconds: 4),
        ),
      );
      
      setState(() {
        _selectedMediaFile = File(isImage ? 'mock_photo.jpg' : 'mock_video.mp4');
        _isImage = isImage;
      });
      // Auto-pinpoint location at the exact moment mock evidence is loaded
      _fetchCurrentLocation();
      return;
    }

    try {
      if (isImage) {
        final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        if (photo != null) {
          setState(() {
            _selectedMediaFile = File(photo.path);
            _isImage = true;
          });
          // Auto-pinpoint location at the exact moment photo was captured
          _fetchCurrentLocation();
        }
      } else {
        final XFile? video = await _picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(seconds: 60),
        );
        if (video != null) {
          setState(() {
            _selectedMediaFile = File(video.path);
            _isImage = false;
          });
          // Auto-pinpoint location at the exact moment video was captured
          _fetchCurrentLocation();
        }
      }
    } catch (e) {
      print('EAWS Camera Capture Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open camera: $e. Make sure camera access is allowed.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Widget _buildMediaPreviewWidget() {
    final bool isMock = _selectedMediaFile!.path.startsWith('mock_');
    Widget mediaWidget;

    if (isMock) {
      final mockUrl = _selectedIncidentType == 'Fire'
          ? 'https://images.unsplash.com/photo-1508873699372-7aeab60b44ab?auto=format&fit=crop&q=80&w=800'
          : (_selectedIncidentType == 'Medical'
              ? 'https://images.unsplash.com/photo-1584515979956-d9f6e5d09982?auto=format&fit=crop&q=80&w=800'
              : 'https://images.unsplash.com/photo-1547683905-f686c993aae5?auto=format&fit=crop&q=80&w=800');
      
      mediaWidget = Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          image: DecorationImage(
            image: NetworkImage(mockUrl),
            fit: BoxFit.cover,
          ),
        ),
        child: !_isImage
            ? Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.play, color: Colors.white, size: 32),
                ),
              )
            : null,
      );
    } else {
      mediaWidget = Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: _isImage
            ? Image.file(
                _selectedMediaFile!,
                fit: BoxFit.cover,
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: const Color(0xFFE5E7EB),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(LucideIcons.video, color: AppTheme.primaryColor, size: 48),
                        SizedBox(height: 8),
                        Text(
                          'Video Evidence Captured Successfully',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.play, color: Colors.white, size: 32),
                    ),
                  ),
                ],
              ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 8),
            child: mediaWidget,
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                setState(() {
                  _selectedMediaFile = null;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isImage ? LucideIcons.image : LucideIcons.video,
                    color: Colors.white,
                    size: 11,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isImage ? 'PHOTO EVIDENCE' : 'VIDEO EVIDENCE',
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

  @override
  void dispose() {
    _descriptionController.dispose();
    _customTypeController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location permissions are permanently denied. Please enable them in your device settings.'),
            action: SnackBarAction(
              label: 'Settings',
              textColor: Colors.white,
              onPressed: () => Geolocator.openAppSettings(),
            ),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return;
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        final Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 4),
        );
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });

        // Query OSM dynamic Nominatim geocoding to resolve address name
        final client = HttpClient();
        final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&zoom=18&addressdetails=1');
        final request = await client.getUrl(url);
        request.headers.set('User-Agent', 'EAWSMobileApp/1.0 (masters@eaws.org)');
        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();
        final data = json.decode(responseBody);
        if (data != null && data['address'] != null) {
          final addr = data['address'];
          final poi = addr['amenity'] ?? addr['building'] ?? addr['shop'] ?? addr['office'] ?? '';
          final road = addr['road'] ?? addr['street'] ?? addr['highway'] ?? '';
          final suburb = addr['suburb'] ?? addr['neighbourhood'] ?? addr['city_district'] ?? '';
          final city = addr['city'] ?? addr['town'] ?? addr['village'] ?? '';
          final country = addr['country'] ?? '';

          List<String> parts = [];
          if (poi.isNotEmpty) parts.add(poi);
          if (road.isNotEmpty) parts.add(road);
          if (suburb.isNotEmpty) parts.add(suburb);
          if (city.isNotEmpty && parts.length < 3) parts.add(city);
          
          if (parts.isEmpty && country.isNotEmpty) {
            parts.add(country);
          }

          setState(() {
            _locationName = parts.take(3).join(', ');
          });
        }
      }
    } catch (e) {
      print('EAWS Report Location Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> _handleSubmitReport() async {
    final String desc = _descriptionController.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe what you are seeing before submitting.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    // Determine category values
    Color catColor = const Color(0xFFEF4444);
    String catLabel = _selectedIncidentType.toUpperCase();
    if (_selectedIncidentType == 'Fire') catColor = const Color(0xFFF59E0B);
    if (_selectedIncidentType == 'Medical') catColor = const Color(0xFF3B82F6);
    if (_selectedIncidentType == 'Suspicious') catColor = const Color(0xFF10B981);
    
    if (_selectedIncidentType == 'Other') {
      final custom = _customTypeController.text.trim();
      if (custom.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please specify the custom incident type.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return;
      }
      catLabel = custom.toUpperCase();
      catColor = const Color(0xFF10B981); // Neutral/custom color
    }

    final String? mediaPath = _selectedMediaFile?.path;
    String? finalImageAsset;
    bool isVideoReport = false;
    
    if (mediaPath != null) {
      if (mediaPath.startsWith('mock_')) {
        finalImageAsset = _selectedIncidentType == 'Fire'
            ? 'https://images.unsplash.com/photo-1508873699372-7aeab60b44ab?auto=format&fit=crop&q=80&w=800'
            : (_selectedIncidentType == 'Medical'
                ? 'https://images.unsplash.com/photo-1584515979956-d9f6e5d09982?auto=format&fit=crop&q=80&w=800'
                : 'https://images.unsplash.com/photo-1547683905-f686c993aae5?auto=format&fit=crop&q=80&w=800');
        isVideoReport = !_isImage;
      } else {
        finalImageAsset = mediaPath;
        isVideoReport = !_isImage;
      }
    }

    final title = '$_selectedIncidentType incident reported near $_locationName';
    Map<String, dynamic> newReport;

    try {
      final remoteIncident = await IncidentApi.instance.createIncident(
        category: catLabel,
        title: title,
        description: desc,
        isAnonymous: _isAnonymous,
        locationName: _locationName,
        latitude: _latitude,
        longitude: _longitude,
        mediaUrl: finalImageAsset != null && finalImageAsset.startsWith('http') ? finalImageAsset : null,
        mediaType: finalImageAsset == null ? null : (isVideoReport ? 'video' : 'image'),
      );
      newReport = remoteIncident.toUiMap();
    } catch (e) {
      print('EAWS Incident API submit failed, using local fallback: $e');
      // Build the dynamic new card model while the backend route is still coming online.
      newReport = {
        'id': DateTime.now().millisecondsSinceEpoch,
        'userId': 'user_12345',
        'userName': _isAnonymous ? 'Anonymous Citizen' : 'Ghana Citizen',
        'initials': _isAnonymous ? 'AC' : 'GC',
        'avatarColor': _isAnonymous ? Colors.grey : AppTheme.primaryColor,
        'isVerified': !_isAnonymous,
        'timeAgo': 'Just now',
        'category': catLabel,
        'categoryColor': catColor,
        'title': title,
        'description': desc,
        'imageAsset': finalImageAsset,
        'isVideo': isVideoReport,
        'severity': 'PENDING TRIAGE',
        'status': 'ACTIVE',
        'location': _locationName,
        'latitude': _latitude,
        'longitude': _longitude,
        'likes': 0,
        'commentsCount': 0,
        'comments': <Map<String, dynamic>>[],
        'isLiked': false,
      };
    }

    // Prepend to dynamic list
    final List<Map<String, dynamic>> currentReports = List.from(communityReportsNotifier.value);
    currentReports.insert(0, newReport);
    communityReportsNotifier.value = currentReports;

    HapticFeedback.mediumImpact();
    Navigator.pop(context); // Close incident report screen

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Incident Report Submitted Successfully!',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.successColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Report Incident',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _handleSubmitReport,
            child: const Text(
              'Post',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. INCIDENT TYPE
            const Text(
              'INCIDENT TYPE',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1.1),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: ['Flood', 'Fire', 'Medical', 'Suspicious', 'Other'].map((type) {
                  final isSelected = _selectedIncidentType == type;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _selectedIncidentType = type;
                        });
                      },
                      icon: Icon(
                        type == 'Flood'
                            ? LucideIcons.droplets
                            : (type == 'Fire'
                                ? LucideIcons.flame
                                : (type == 'Medical' 
                                    ? LucideIcons.heartPulse 
                                    : (type == 'Suspicious' ? LucideIcons.eyeOff : LucideIcons.moreHorizontal))),
                        size: 16,
                      ),
                      label: Text(type),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected ? AppTheme.primaryColor : Colors.white,
                        foregroundColor: isSelected ? Colors.white : AppTheme.textSecondary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected ? Colors.transparent : const Color(0xFFE5E7EB),
                            width: 1.5,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            if (_selectedIncidentType == 'Other') ...[
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _customTypeController,
                  style: const TextStyle(fontSize: 14.5, color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'E.g., Road block, Wild animal...',
                    hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),

            // 2. DESCRIPTION
            const Text(
              'DESCRIPTION',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1.1),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextField(
                    controller: _descriptionController,
                    maxLines: 4,
                    maxLength: 500,
                    style: const TextStyle(fontSize: 14.5, color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Describe what you are seeing... Be specific about location, danger level, and who is affected.',
                      hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_charCount / 500',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 4. ADD MEDIA
            const Text(
              'ADD MEDIA',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1.1),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildMediaButton('Take Photo', LucideIcons.camera),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMediaButton('Record Video', LucideIcons.video),
                ),
              ],
            ),
            if (_selectedMediaFile != null) ...[
              _buildMediaPreviewWidget(),
            ],
            const SizedBox(height: 24),

            // 5. LOCATION
            const Text(
              'LOCATION',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1.1),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(LucideIcons.mapPin, color: AppTheme.primaryColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Location',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        _isLoadingLocation
                            ? const SizedBox(
                                height: 12,
                                width: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                              )
                            : Text(
                                '${_latitude.toStringAsFixed(4)}°N, ${_longitude.toStringAsFixed(4)}°W - $_locationName',
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                              ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: AppTheme.textSecondary, size: 20),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _fetchCurrentLocation();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 6. ANONYMOUS POST
            const Text(
              'ANONYMOUS POST',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1.1),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: Color(0xFFFEE2E2), shape: BoxShape.circle),
                    child: const Icon(LucideIcons.eyeOff, color: AppTheme.primaryColor, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Post Anonymously', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary, fontSize: 14)),
                        SizedBox(height: 2),
                        Text('Hidden from public feed, but visible to EAWS', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: _isAnonymous,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _isAnonymous = val;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),

            // Big Red Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _handleSubmitReport,
                icon: const Icon(LucideIcons.send, size: 18),
                label: const Text('Submit Incident Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'Your report will be reviewed and visible to the community.',
                style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }


  Widget _buildMediaButton(String label, IconData icon) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD1D5DB), width: 1.5, style: BorderStyle.none), // Custom dashed design
      ),
      child: Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFD1D5DB), width: 1.5, strokeAlign: BorderSide.strokeAlignInside),
        ),
        child: InkWell(
          onTap: () => _pickMedia(label.toLowerCase().contains('photo')),
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppTheme.primaryColor, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
