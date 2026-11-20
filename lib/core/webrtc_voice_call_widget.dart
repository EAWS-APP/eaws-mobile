import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'api_client.dart';

class WebRtcVoiceCallWidget extends StatefulWidget {
  final String incidentId;

  const WebRtcVoiceCallWidget({super.key, required this.incidentId});

  @override
  State<WebRtcVoiceCallWidget> createState() => _WebRtcVoiceCallWidgetState();
}

class _WebRtcVoiceCallWidgetState extends State<WebRtcVoiceCallWidget> {
  String _callState = 'idle'; // idle | ringing_out | ringing_in | connected | error
  bool _isMuted = false;
  int _durationSec = 0;
  String? _errorMsg;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  String _role = 'caller';
  int _addedIceCount = 0;
  Map<String, dynamic>? _incomingOffer;

  Timer? _pollTimer;
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) => _pollState());
  }

  Future<void> _initRenderer() async {
    await _remoteRenderer.initialize();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _durationTimer?.cancel();
    _cleanupCall();
    _remoteRenderer.dispose();
    super.dispose();
  }

  Future<void> _cleanupCall() async {
    _durationTimer?.cancel();
    _durationTimer = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    try {
      _localStream?.getTracks().forEach((t) => t.stop());
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    _addedIceCount = 0;
    _incomingOffer = null;
    if (mounted) {
      setState(() {
        _durationSec = 0;
        _isMuted = false;
      });
    }
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _durationSec++);
    });
  }

  Future<void> _pollState() async {
    try {
      final body = await EawsApiClient.instance.get('/calls/${widget.incidentId}/state');
      final call = body?['call'];
      if (call == null) return;

      final status = call['status']?.toString() ?? 'idle';
      if (status == 'ended' || status == 'idle') {
        if (_callState != 'idle' && _callState != 'error') {
          await _cleanupCall();
          if (mounted) setState(() => _callState = 'idle');
        }
        return;
      }

      if (status == 'ringing' && call['caller_role'] == 'dispatcher' && _callState == 'idle') {
        _incomingOffer = Map<String, dynamic>.from(call['offer']);
        if (mounted) setState(() => _callState = 'ringing_in');
        return;
      }

      final pc = _pc;
      if (pc == null) return;

      if (_role == 'caller' && call['answer'] != null && _callState == 'ringing_out') {
        final ans = call['answer'];
        await pc.setRemoteDescription(
          RTCSessionDescription(ans['sdp'], ans['type']),
        );
        _startDurationTimer();
        if (mounted) setState(() => _callState = 'connected');
      }

      final List<dynamic> remoteCands = _role == 'caller'
          ? (call['callee_candidates'] ?? [])
          : (call['caller_candidates'] ?? []);
      while (_addedIceCount < remoteCands.length) {
        final c = remoteCands[_addedIceCount];
        _addedIceCount++;
        try {
          await pc.addCandidate(
            RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']),
          );
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<RTCPeerConnection> _initPeerConnection(String role) async {
    final stream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    _localStream = stream;

    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
    });
    _pc = pc;
    _role = role;
    _addedIceCount = 0;

    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }

    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams[0];
      }
    };

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      EawsApiClient.instance
          .post('/calls/${widget.incidentId}/ice', body: {
            'role': role,
            'candidate': {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          })
          .catchError((_) => null);
    };

    return pc;
  }

  Future<void> _startOutgoingCall() async {
    setState(() => _errorMsg = null);
    try {
      final pc = await _initPeerConnection('caller');
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      await EawsApiClient.instance.post('/calls/${widget.incidentId}/offer', body: {
        'offer': {'type': offer.type, 'sdp': offer.sdp},
        'caller_role': 'victim',
        'caller_name': 'Citizen SOS',
      });
      if (mounted) setState(() => _callState = 'ringing_out');
    } catch (e) {
      await _cleanupCall();
      if (mounted) {
        setState(() {
          _callState = 'error';
          _errorMsg = 'Microphone access required for VoIP call';
        });
      }
    }
  }

  Future<void> _answerIncomingCall() async {
    if (_incomingOffer == null) return;
    setState(() => _errorMsg = null);
    try {
      final pc = await _initPeerConnection('callee');
      await pc.setRemoteDescription(
        RTCSessionDescription(_incomingOffer!['sdp'], _incomingOffer!['type']),
      );
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      await EawsApiClient.instance.post('/calls/${widget.incidentId}/answer', body: {
        'answer': {'type': answer.type, 'sdp': answer.sdp},
      });
      _startDurationTimer();
      if (mounted) setState(() => _callState = 'connected');
    } catch (e) {
      await _cleanupCall();
      if (mounted) {
        setState(() {
          _callState = 'error';
          _errorMsg = 'Could not answer VoIP call';
        });
      }
    }
  }

  Future<void> _hangup() async {
    try {
      await EawsApiClient.instance.post('/calls/${widget.incidentId}/end');
    } catch (_) {}
    await _cleanupCall();
    if (mounted) setState(() => _callState = 'idle');
  }

  void _toggleMute() {
    final stream = _localStream;
    if (stream == null) return;
    final next = !_isMuted;
    for (final t in stream.getAudioTracks()) {
      t.enabled = !next;
    }
    setState(() => _isMuted = next);
  }

  @override
  Widget build(BuildContext context) {
    final mm = (_durationSec ~/ 60).toString().padLeft(2, '0');
    final ss = (_durationSec % 60).toString().padLeft(2, '0');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Hidden RTCVideoRenderer for Web/Mobile audio playback
        SizedBox(width: 0, height: 0, child: RTCVideoView(_remoteRenderer)),
        if (_callState == 'ringing_in')
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.shade800,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.greenAccent, width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.phone_in_talk, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '112 Command Calling (VoIP)...',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                ElevatedButton(
                  onPressed: _answerIncomingCall,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.green.shade900,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  child: const Text('Answer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: _hangup,
                  icon: const Icon(Icons.call_end, color: Colors.redAccent),
                  tooltip: 'Decline',
                ),
              ],
            ),
          )
        else if (_callState == 'ringing_out' || _callState == 'connected')
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.shade900.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.lightBlueAccent),
            ),
            child: Row(
              children: [
                const Icon(Icons.graphic_eq, color: Colors.lightBlueAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _callState == 'ringing_out'
                        ? 'Calling 112 Command (VoIP)...'
                        : 'VoIP Connected • $mm:$ss',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                IconButton(
                  onPressed: _toggleMute,
                  icon: Icon(_isMuted ? Icons.mic_off : Icons.mic, color: Colors.white, size: 20),
                ),
                ElevatedButton.icon(
                  onPressed: _hangup,
                  icon: const Icon(Icons.call_end, size: 15),
                  label: const Text('End', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _startOutgoingCall,
                  icon: const Icon(Icons.wifi_calling_3, size: 16),
                  label: const Text('IN-APP VOIP CALL (FREE INTERNET VOICE)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              if (_errorMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_errorMsg!, style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
                ),
            ],
          ),
      ],
    );
  }
}
