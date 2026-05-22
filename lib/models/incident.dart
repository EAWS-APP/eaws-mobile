import 'package:flutter/material.dart';

import '../core/theme.dart';

class Incident {
  const Incident({
    required this.id,
    required this.category,
    required this.severity,
    required this.status,
    required this.title,
    required this.description,
    required this.isAnonymous,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.likesCount,
    required this.commentsCount,
    required this.createdAt,
    this.userId,
    this.userName,
    this.isVerified = false,
    this.mediaUrl,
    this.mediaType,
    this.viewsCount = 0,
  });

  final String id;
  final String? userId;
  final String? userName;
  final String category;
  final String severity;
  final String status;
  final String title;
  final String description;
  final bool isAnonymous;
  final bool isVerified;
  final String locationName;
  final double latitude;
  final double longitude;
  final String? mediaUrl;
  final String? mediaType;
  final int likesCount;
  final int commentsCount;
  final int viewsCount;
  final DateTime createdAt;

  factory Incident.fromJson(Map<String, dynamic> json) {
    return Incident(
      id: json['id'].toString(),
      userId: json['user_id']?.toString(),
      userName: json['user_name']?.toString(),
      category: (json['category'] ?? 'OTHER').toString(),
      severity: (json['severity'] ?? 'PENDING TRIAGE').toString(),
      status: (json['status'] ?? 'pending').toString(),
      title: (json['title'] ?? 'Incident reported').toString(),
      description: (json['description'] ?? '').toString(),
      isAnonymous: json['is_anonymous'] == true,
      isVerified: json['is_verified'] == true,
      locationName: (json['location_name'] ?? json['location'] ?? 'Unknown location').toString(),
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      mediaUrl: json['media_url']?.toString(),
      mediaType: json['media_type']?.toString(),
      likesCount: _asInt(json['likes_count']),
      commentsCount: _asInt(json['comments_count']),
      viewsCount: _asInt(json['views_count']),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toUiMap() {
    final color = categoryColor(category);
    final displayName = isAnonymous ? 'Anonymous Citizen' : (userName ?? 'Ghana Citizen');
    return {
      'id': id,
      'userId': userId,
      'userName': displayName,
      'initials': _initials(displayName),
      'avatarColor': isAnonymous ? Colors.grey : AppTheme.primaryColor,
      'isVerified': isVerified,
      'timeAgo': _timeAgo(createdAt),
      'category': category.toUpperCase(),
      'categoryColor': color,
      'title': title,
      'description': description,
      'imageAsset': mediaUrl,
      'isVideo': mediaType == 'video',
      'severity': severity.toUpperCase(),
      'status': status.toUpperCase(),
      'location': locationName,
      'latitude': latitude,
      'longitude': longitude,
      'likes': likesCount,
      'commentsCount': commentsCount,
      'views': viewsCount,
      'comments': <Map<String, dynamic>>[],
      'isLiked': false,
    };
  }

  static Color categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'fire':
        return const Color(0xFFF59E0B);
      case 'medical':
        return const Color(0xFF3B82F6);
      case 'suspicious':
        return const Color(0xFF10B981);
      case 'flood':
        return const Color(0xFFEF4444);
      default:
        return AppTheme.primaryColor;
    }
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return 'GC';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static String _timeAgo(DateTime dateTime) {
    final delta = DateTime.now().difference(dateTime);
    if (delta.inMinutes < 1) return 'Just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';
    if (delta.inHours < 24) return '${delta.inHours} hr ago';
    return '${delta.inDays} days ago';
  }
}

