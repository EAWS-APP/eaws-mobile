import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme.dart';

class SOSScreen extends StatefulWidget {
  final bool startImmediately;

  const SOSScreen({
    super.key,
    this.startImmediately = false,
  });

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> with TickerProviderStateMixin {
  bool _isSOSActive = false;
  bool _isCountingDown = false;
  int _countdownSeconds = 10;
  Timer? _countdownTimer;

  // Radar pulsing animation
  late AnimationController _radarController;
  late Animation<double> _radarAnimation;

  // Flashing alert color animation
  late AnimationController _flashController;
  late Animation<Color?> _flashColorAnimation;

  @override
  void initState() {
    super.initState();

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    
    _radarAnimation = Tween<double>(begin: 0.8, end: 2.2).animate(
      CurvedAnimation(parent: _radarController, curve: Curves.easeOut),
    );

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    _flashColorAnimation = ColorTween(
      begin: Colors.black,
      end: const Color(0xFFDC2626), // errorColor
    ).animate(_flashController);

    // If navigated from home screen SOS holding
    if (widget.startImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerCountdown();
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _radarController.dispose();
    _flashController.dispose();
    super.dispose();
  }

  void _triggerCountdown() {
    // Vibrate device briefly to notify user SOS triggered
    HapticFeedback.vibrate();
    
    setState(() {
      _isCountingDown = true;
      _countdownSeconds = 10;
      _isSOSActive = false;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        setState(() {
          _countdownSeconds--;
        });
        HapticFeedback.lightImpact();
      } else {
        timer.cancel();
        _activateSOSBroadcast();
      }
    });
  }

  void _cancelSOS() {
    _countdownTimer?.cancel();
    _flashController.stop();
    setState(() {
      _isCountingDown = false;
      _isSOSActive = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Emergency dispatch cancelled.'),
        backgroundColor: Colors.grey,
      ),
    );
  }

  void _activateSOSBroadcast() {
    HapticFeedback.vibrate();
    setState(() {
      _isCountingDown = false;
      _isSOSActive = true;
    });
    
    // Repeat the red flashing beacon light animation
    _flashController.repeat(reverse: true);
  }

  void _stopSOS() {
    _flashController.stop();
    setState(() {
      _isSOSActive = false;
      _isCountingDown = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Emergency broadcast muted.'),
        backgroundColor: AppTheme.successColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCountingDown) {
      return _buildCountdownLayout();
    } else if (_isSOSActive) {
      return _buildActiveSOSLayout();
    } else {
      return _buildInactiveLayout();
    }
  }

  // Layout 1: Normal Inactive Dashboard
  Widget _buildInactiveLayout() {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Active Tracking'),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Connection Status Bar Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _radarAnimation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _radarAnimation.value,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.successColor.withOpacity(0.15),
                                ),
                              ),
                            );
                          },
                        ),
                        Container(
                          width: 14,
                          height: 14,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.successColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'System Ready & Secured',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Active satellite link established',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Visual Center tracking map icon / information
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        LucideIcons.radar,
                        color: AppTheme.primaryColor,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Ready to Broadcast',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'In an emergency, press the SOS button\non the Home screen or tap below to start.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),

              // Huge Trigger Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _triggerCountdown,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(LucideIcons.shieldAlert, size: 22),
                  label: const Text(
                    'Trigger Emergency SOS Now',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Location Metrics list
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ACTIVE SENSOR TELEMETRY',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textSecondary, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 16),
                    _buildTelemetryRow(LucideIcons.compass, 'Heading', '32.4° NE (Magnetic)'),
                    const Divider(height: 20),
                    _buildTelemetryRow(LucideIcons.mapPin, 'GPS Accuracy', '±3 meters (High Accuracy)'),
                    const Divider(height: 20),
                    _buildTelemetryRow(LucideIcons.activity, 'Alert Channel', 'Satellite Channel B4'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Layout 2: Countdown Overlay
  Widget _buildCountdownLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFF1F2937), // Dark slate bg during countdown
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                const Icon(
                  LucideIcons.shieldAlert,
                  color: AppTheme.primaryColor,
                  size: 64,
                ),
                const SizedBox(height: 16),
                const Text(
                  'SOS EMERGENCY INITIATED',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Broadcasting live telemetry & initiating regional dispatch in:',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
                ),
                const SizedBox(height: 48),

                // Giant Animated Countdown Circle
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 180,
                      height: 180,
                      child: CircularProgressIndicator(
                        value: _countdownSeconds / 10,
                        strokeWidth: 10,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                      ),
                    ),
                    Text(
                      '$_countdownSeconds',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Spacer(),

                // Cancel Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _cancelSOS,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text(
                      'CANCEL DISPATCH',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.1),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Press cancel if this was an accidental trigger',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Layout 3: Active Emergency Beacon Screen
  Widget _buildActiveSOSLayout() {
    return AnimatedBuilder(
      animation: _flashColorAnimation,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: _flashColorAnimation.value,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  // Top Emergency Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'SOS ACTIVE',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 1.5),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: const [
                            Icon(LucideIcons.radio, color: Colors.white, size: 14),
                            SizedBox(width: 6),
                            Text('BROADCASTING', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                          ],
                        ),
                      )
                    ],
                  ),
                  const Spacer(),

                  // Pulsing Radar Circle
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _radarAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _radarAnimation.value,
                            child: Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.12),
                              ),
                            ),
                          );
                        },
                      ),
                      Container(
                        width: 100,
                        height: 100,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: const Icon(
                          LucideIcons.siren,
                          color: AppTheme.primaryColor,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  const Text(
                    'HELP IS ON THE WAY',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Audio recording and live coordinates are being\ntransmitted to the National Control Room.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 32),

                  // Simulated Live Response Dispatch Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: AppTheme.successColor.withOpacity(0.1), shape: BoxShape.circle),
                              child: const Icon(LucideIcons.shieldCheck, color: AppTheme.successColor),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Dispatch Unit Dispatched', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                                  SizedBox(height: 2),
                                  Text('Police response unit is en-route', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text('Estimated Arrival Time', style: TextStyle(color: AppTheme.textSecondary)),
                            Text('~8 mins', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.errorColor, fontSize: 16)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const Spacer(),

                  // Quick Action buttons inside SOS Active State
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // Direct call mock
                            HapticFeedback.vibrate();
                          },
                          icon: const Icon(LucideIcons.phone, color: Colors.white),
                          label: const Text('CALL CONTROL', style: TextStyle(color: Colors.white)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: const BorderSide(color: Colors.white, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _stopSOS,
                          icon: const Icon(LucideIcons.square),
                          label: const Text('STOP SOS'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.errorColor,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTelemetryRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
      ],
    );
  }
}
