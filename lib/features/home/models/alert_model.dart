/// Severity levels for emergency alerts, ordered by urgency.
enum AlertSeverity { advisory, watch, warning }

/// A single emergency alert pushed by the EAWS Control Room.
class AlertModel {
  final String id;
  final String title;
  final String description;
  final AlertSeverity severity;
  final String icon;          // Lucide icon name hint (e.g. 'wind', 'cloud-rain')
  final DateTime createdAt;
  final DateTime? expiresAt;  // null = no expiry
  final List<String> checklist; // Actionable safety steps

  const AlertModel({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    this.icon = 'alert-triangle',
    required this.createdAt,
    this.expiresAt,
    this.checklist = const [],
  });

  /// Construct from a Supabase row (Map).
  factory AlertModel.fromMap(Map<String, dynamic> map) {
    return AlertModel(
      id: map['id']?.toString() ?? '',
      title: map['title'] ?? 'Alert',
      description: map['description'] ?? '',
      severity: _parseSeverity(map['severity']),
      icon: map['icon'] ?? 'alert-triangle',
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
      expiresAt: map['expires_at'] != null
          ? DateTime.tryParse(map['expires_at'])
          : null,
      checklist: map['checklist'] != null
          ? List<String>.from(map['checklist'])
          : [],
    );
  }

  /// Whether this alert is still active (not expired).
  bool get isActive {
    if (expiresAt == null) return true;
    return DateTime.now().isBefore(expiresAt!);
  }

  /// Minutes remaining until expiry, or null if no expiry set.
  int? get minutesRemaining {
    if (expiresAt == null) return null;
    final diff = expiresAt!.difference(DateTime.now()).inMinutes;
    return diff > 0 ? diff : 0;
  }

  /// Fractional progress (0.0–1.0) toward expiry, useful for progress bars.
  double get urgencyProgress {
    if (expiresAt == null) return 1.0;
    final total = expiresAt!.difference(createdAt).inSeconds;
    if (total <= 0) return 1.0;
    final elapsed = DateTime.now().difference(createdAt).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  static AlertSeverity _parseSeverity(dynamic value) {
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'warning':
          return AlertSeverity.warning;
        case 'watch':
          return AlertSeverity.watch;
        case 'advisory':
        default:
          return AlertSeverity.advisory;
      }
    }
    return AlertSeverity.advisory;
  }
}
