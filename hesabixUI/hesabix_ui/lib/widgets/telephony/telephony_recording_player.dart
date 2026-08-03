import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';

import '../../services/telephony/telephony_api.dart';

/// پخش‌کننده ضبط مکالمه — بارگذاری تنبل تا هر ردیف لیست باز نشود.
class TelephonyRecordingPlayer extends StatefulWidget {
  final int businessId;
  final int callId;

  const TelephonyRecordingPlayer({super.key, required this.businessId, required this.callId});

  @override
  State<TelephonyRecordingPlayer> createState() => _TelephonyRecordingPlayerState();
}

class _TelephonyRecordingPlayerState extends State<TelephonyRecordingPlayer> {
  final _api = TelephonyApi();
  FlutterSoundPlayer? _player;
  String? _url;
  bool _expanded = false;
  bool _loading = false;
  bool _playing = false;
  bool _opened = false;
  String? _error;

  Future<void> _ensureLoaded() async {
    if (_url != null || _loading) return;
    setState(() {
      _expanded = true;
      _loading = true;
      _error = null;
    });
    try {
      _player ??= FlutterSoundPlayer();
      if (!_opened) {
        await _player!.openPlayer();
        _opened = true;
      }
      final info = await _api.recordingInfo(widget.businessId, widget.callId);
      final url = info['recording_url']?.toString();
      if (url == null || url.isEmpty) {
        setState(() {
          _error = 'فایل ضبط در دسترس نیست';
          _loading = false;
        });
        return;
      }
      setState(() {
        _url = url;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _toggle() async {
    await _ensureLoaded();
    if (_url == null || _player == null) return;
    if (_playing) {
      await _player!.stopPlayer();
      setState(() => _playing = false);
      return;
    }
    await _player!.startPlayer(
      fromURI: _url,
      whenFinished: () {
        if (mounted) setState(() => _playing = false);
      },
    );
    setState(() => _playing = true);
  }

  @override
  void dispose() {
    _player?.closePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!_expanded) {
      return TextButton.icon(
        onPressed: _ensureLoaded,
        icon: Icon(Icons.play_circle_outline_rounded, color: scheme.primary, size: 20),
        label: const Text('پخش ضبط'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    if (_error != null) {
      return Text(_error!, style: TextStyle(color: scheme.error, fontSize: 12));
    }
    if (_loading || _url == null) {
      return const SizedBox(
        height: 28,
        width: 28,
        child: Padding(
          padding: EdgeInsets.all(4),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 22,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 4),
              Text(
                _playing ? 'در حال پخش…' : 'پخش ضبط مکالمه',
                style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
