import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'softphone_pcm_media_stub.dart';

/// Softphone PCM I/O for Windows via WinMM (`winmm.dll`).
///
/// Upstream `flutter_sound` ships only a stub Windows plugin (channel `taudio`),
/// so `openPlayer` throws [MissingPluginException]. This backend replaces it
/// for Softphone Relay (PCM16LE mono).
class WindowsSoftphonePcmMedia implements SoftphonePcmMedia {
  WindowsSoftphonePcmMedia({this.sampleRate = 8000, this.numChannels = 1});

  final int sampleRate;
  final int numChannels;

  static const int _bitsPerSample = 16;
  static const int _waveMapper = 0xFFFFFFFF;
  static const int _whdrDone = 0x00000001;
  static const int _mmsyserrNoerror = 0;

  /// ~20 ms frames at 8 kHz mono PCM16.
  int get _frameBytes => (sampleRate * numChannels * (_bitsPerSample ~/ 8) * 20) ~/ 1000;

  late final _Winmm _mm = _Winmm.instance;

  int? _hwo;
  int? _hwi;
  bool _ready = false;
  bool _mic = false;

  final List<_WaveBuffer> _outBusy = <_WaveBuffer>[];
  final List<_WaveBuffer> _outFree = <_WaveBuffer>[];
  final List<_WaveBuffer> _inBufs = <_WaveBuffer>[];

  Timer? _pump;
  void Function(Uint8List pcm)? _onMic;

  @override
  bool get isReady => _ready;

  @override
  bool get isMicActive => _mic;

  @override
  Future<void> start() async {
    if (_ready) return;
    final fmt = _allocFormat();
    final phwo = calloc<IntPtr>();
    try {
      final rc = _mm.waveOutOpen(
        phwo,
        _waveMapper,
        fmt,
        nullptr,
        nullptr,
        0,
      );
      if (rc != _mmsyserrNoerror) {
        throw StateError('waveOutOpen failed: $rc');
      }
      _hwo = phwo.value;
      _ready = true;
      _pump ??= Timer.periodic(const Duration(milliseconds: 10), (_) => _tick());
    } finally {
      calloc.free(fmt);
      calloc.free(phwo);
    }
  }

  @override
  Future<void> startMic(void Function(Uint8List pcm) onFrame) async {
    if (!_ready || _mic) return;
    _onMic = onFrame;
    final fmt = _allocFormat();
    final phwi = calloc<IntPtr>();
    try {
      final rc = _mm.waveInOpen(
        phwi,
        _waveMapper,
        fmt,
        nullptr,
        nullptr,
        0,
      );
      if (rc != _mmsyserrNoerror) {
        throw StateError('waveInOpen failed: $rc');
      }
      _hwi = phwi.value;
      for (var i = 0; i < 4; i++) {
        final buf = _WaveBuffer.allocate(_frameBytes);
        _inBufs.add(buf);
        _prepareIn(buf);
        _queueIn(buf);
      }
      final startRc = _mm.waveInStart(_hwi!);
      if (startRc != _mmsyserrNoerror) {
        throw StateError('waveInStart failed: $startRc');
      }
      _mic = true;
      _pump ??= Timer.periodic(const Duration(milliseconds: 10), (_) => _tick());
    } finally {
      calloc.free(fmt);
      calloc.free(phwi);
    }
  }

  @override
  Future<void> stopMic() async {
    if (!_mic) return;
    _mic = false;
    _onMic = null;
    final hwi = _hwi;
    if (hwi != null) {
      _mm.waveInStop(hwi);
      _mm.waveInReset(hwi);
      for (final buf in _inBufs) {
        _mm.waveInUnprepareHeader(hwi, buf.hdr, sizeOf<_WAVEHDR>());
        buf.free();
      }
      _inBufs.clear();
      _mm.waveInClose(hwi);
      _hwi = null;
    }
  }

  @override
  void playPcm(List<int> pcm) {
    if (!_ready || pcm.isEmpty) return;
    final hwo = _hwo;
    if (hwo == null) return;
    _reclaimOut();
    // Cap queued audio (~200 ms) to avoid runaway latency.
    if (_outBusy.length >= 10) return;
    final bytes = Uint8List.fromList(pcm);
    final buf = _outFree.isNotEmpty
        ? _outFree.removeLast().ensureCapacity(bytes.length)
        : _WaveBuffer.allocate(bytes.length);
    buf.data.asTypedList(bytes.length).setAll(0, bytes);
    buf.hdr.ref
      ..lpData = buf.data.cast()
      ..dwBufferLength = bytes.length
      ..dwBytesRecorded = 0
      ..dwFlags = 0
      ..dwLoops = 0
      ..dwUser = 0
      ..lpNext = nullptr
      ..reserved = 0;
    var rc = _mm.waveOutPrepareHeader(hwo, buf.hdr, sizeOf<_WAVEHDR>());
    if (rc != _mmsyserrNoerror) {
      buf.free();
      return;
    }
    rc = _mm.waveOutWrite(hwo, buf.hdr, sizeOf<_WAVEHDR>());
    if (rc != _mmsyserrNoerror) {
      _mm.waveOutUnprepareHeader(hwo, buf.hdr, sizeOf<_WAVEHDR>());
      buf.free();
      return;
    }
    _outBusy.add(buf);
  }

  @override
  Future<void> stop() async {
    await stopMic();
    _pump?.cancel();
    _pump = null;
    final hwo = _hwo;
    if (hwo != null) {
      _mm.waveOutReset(hwo);
      _reclaimOut(force: true);
      for (final buf in _outFree) {
        buf.free();
      }
      _outFree.clear();
      _mm.waveOutClose(hwo);
      _hwo = null;
    }
    _ready = false;
  }

  void _tick() {
    _reclaimOut();
    if (!_mic) return;
    final hwi = _hwi;
    final onMic = _onMic;
    if (hwi == null || onMic == null) return;
    for (final buf in _inBufs) {
      final flags = buf.hdr.ref.dwFlags;
      if ((flags & _whdrDone) == 0) continue;
      final recorded = buf.hdr.ref.dwBytesRecorded;
      if (recorded > 0) {
        final copy = Uint8List.fromList(buf.data.asTypedList(recorded));
        try {
          onMic(copy);
        } catch (_) {}
      }
      buf.hdr.ref
        ..dwFlags = 0
        ..dwBytesRecorded = 0;
      _queueIn(buf);
    }
  }

  void _reclaimOut({bool force = false}) {
    final hwo = _hwo;
    if (hwo == null) return;
    final keep = <_WaveBuffer>[];
    for (final buf in _outBusy) {
      final done = (buf.hdr.ref.dwFlags & _whdrDone) != 0;
      if (!done && !force) {
        keep.add(buf);
        continue;
      }
      _mm.waveOutUnprepareHeader(hwo, buf.hdr, sizeOf<_WAVEHDR>());
      if (_outFree.length < 12) {
        _outFree.add(buf);
      } else {
        buf.free();
      }
    }
    _outBusy
      ..clear()
      ..addAll(keep);
  }

  void _prepareIn(_WaveBuffer buf) {
    final hwi = _hwi!;
    buf.hdr.ref
      ..lpData = buf.data.cast()
      ..dwBufferLength = buf.capacity
      ..dwBytesRecorded = 0
      ..dwFlags = 0
      ..dwLoops = 0
      ..dwUser = 0
      ..lpNext = nullptr
      ..reserved = 0;
    final rc = _mm.waveInPrepareHeader(hwi, buf.hdr, sizeOf<_WAVEHDR>());
    if (rc != _mmsyserrNoerror) {
      throw StateError('waveInPrepareHeader failed: $rc');
    }
  }

  void _queueIn(_WaveBuffer buf) {
    final hwi = _hwi!;
    final rc = _mm.waveInAddBuffer(hwi, buf.hdr, sizeOf<_WAVEHDR>());
    if (rc != _mmsyserrNoerror) {
      // Best-effort; next tick may recover.
    }
  }

  Pointer<_WAVEFORMATEX> _allocFormat() {
    final blockAlign = numChannels * (_bitsPerSample ~/ 8);
    final fmt = calloc<_WAVEFORMATEX>();
    fmt.ref
      ..wFormatTag = 1 // WAVE_FORMAT_PCM
      ..nChannels = numChannels
      ..nSamplesPerSec = sampleRate
      ..wBitsPerSample = _bitsPerSample
      ..nBlockAlign = blockAlign
      ..nAvgBytesPerSec = sampleRate * blockAlign
      ..cbSize = 0;
    return fmt;
  }
}

class _WaveBuffer {
  _WaveBuffer._(this.data, this.capacity, this.hdr);

  factory _WaveBuffer.allocate(int bytes) {
    final data = calloc<Uint8>(bytes);
    final hdr = calloc<_WAVEHDR>();
    return _WaveBuffer._(data, bytes, hdr);
  }

  Pointer<Uint8> data;
  int capacity;
  final Pointer<_WAVEHDR> hdr;

  _WaveBuffer ensureCapacity(int bytes) {
    if (bytes <= capacity) return this;
    calloc.free(data);
    data = calloc<Uint8>(bytes);
    capacity = bytes;
    return this;
  }

  void free() {
    calloc.free(data);
    calloc.free(hdr);
  }
}

final class _WAVEFORMATEX extends Struct {
  @Uint16()
  external int wFormatTag;
  @Uint16()
  external int nChannels;
  @Uint32()
  external int nSamplesPerSec;
  @Uint32()
  external int nAvgBytesPerSec;
  @Uint16()
  external int nBlockAlign;
  @Uint16()
  external int wBitsPerSample;
  @Uint16()
  external int cbSize;
}

@Packed(1)
final class _WAVEHDR extends Struct {
  external Pointer<Void> lpData;
  @Uint32()
  external int dwBufferLength;
  @Uint32()
  external int dwBytesRecorded;
  @IntPtr()
  external int dwUser;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int dwLoops;
  external Pointer<_WAVEHDR> lpNext;
  @IntPtr()
  external int reserved;
}

class _Winmm {
  _Winmm._(DynamicLibrary lib)
      : waveOutOpen = lib.lookupFunction<
            Uint32 Function(
              Pointer<IntPtr>,
              Uint32,
              Pointer<_WAVEFORMATEX>,
              Pointer<Void>,
              Pointer<Void>,
              Uint32,
            ),
            int Function(
              Pointer<IntPtr>,
              int,
              Pointer<_WAVEFORMATEX>,
              Pointer<Void>,
              Pointer<Void>,
              int,
            )>('waveOutOpen'),
        waveOutPrepareHeader = lib.lookupFunction<
            Uint32 Function(IntPtr, Pointer<_WAVEHDR>, Uint32),
            int Function(int, Pointer<_WAVEHDR>, int)>('waveOutPrepareHeader'),
        waveOutWrite = lib.lookupFunction<
            Uint32 Function(IntPtr, Pointer<_WAVEHDR>, Uint32),
            int Function(int, Pointer<_WAVEHDR>, int)>('waveOutWrite'),
        waveOutUnprepareHeader = lib.lookupFunction<
            Uint32 Function(IntPtr, Pointer<_WAVEHDR>, Uint32),
            int Function(int, Pointer<_WAVEHDR>, int)>('waveOutUnprepareHeader'),
        waveOutReset = lib.lookupFunction<Uint32 Function(IntPtr), int Function(int)>(
          'waveOutReset',
        ),
        waveOutClose = lib.lookupFunction<Uint32 Function(IntPtr), int Function(int)>(
          'waveOutClose',
        ),
        waveInOpen = lib.lookupFunction<
            Uint32 Function(
              Pointer<IntPtr>,
              Uint32,
              Pointer<_WAVEFORMATEX>,
              Pointer<Void>,
              Pointer<Void>,
              Uint32,
            ),
            int Function(
              Pointer<IntPtr>,
              int,
              Pointer<_WAVEFORMATEX>,
              Pointer<Void>,
              Pointer<Void>,
              int,
            )>('waveInOpen'),
        waveInPrepareHeader = lib.lookupFunction<
            Uint32 Function(IntPtr, Pointer<_WAVEHDR>, Uint32),
            int Function(int, Pointer<_WAVEHDR>, int)>('waveInPrepareHeader'),
        waveInAddBuffer = lib.lookupFunction<
            Uint32 Function(IntPtr, Pointer<_WAVEHDR>, Uint32),
            int Function(int, Pointer<_WAVEHDR>, int)>('waveInAddBuffer'),
        waveInStart = lib.lookupFunction<Uint32 Function(IntPtr), int Function(int)>(
          'waveInStart',
        ),
        waveInStop = lib.lookupFunction<Uint32 Function(IntPtr), int Function(int)>(
          'waveInStop',
        ),
        waveInReset = lib.lookupFunction<Uint32 Function(IntPtr), int Function(int)>(
          'waveInReset',
        ),
        waveInUnprepareHeader = lib.lookupFunction<
            Uint32 Function(IntPtr, Pointer<_WAVEHDR>, Uint32),
            int Function(int, Pointer<_WAVEHDR>, int)>('waveInUnprepareHeader'),
        waveInClose = lib.lookupFunction<Uint32 Function(IntPtr), int Function(int)>(
          'waveInClose',
        );

  static final _Winmm instance = _Winmm._(DynamicLibrary.open('winmm.dll'));

  final int Function(
    Pointer<IntPtr>,
    int,
    Pointer<_WAVEFORMATEX>,
    Pointer<Void>,
    Pointer<Void>,
    int,
  ) waveOutOpen;
  final int Function(int, Pointer<_WAVEHDR>, int) waveOutPrepareHeader;
  final int Function(int, Pointer<_WAVEHDR>, int) waveOutWrite;
  final int Function(int, Pointer<_WAVEHDR>, int) waveOutUnprepareHeader;
  final int Function(int) waveOutReset;
  final int Function(int) waveOutClose;

  final int Function(
    Pointer<IntPtr>,
    int,
    Pointer<_WAVEFORMATEX>,
    Pointer<Void>,
    Pointer<Void>,
    int,
  ) waveInOpen;
  final int Function(int, Pointer<_WAVEHDR>, int) waveInPrepareHeader;
  final int Function(int, Pointer<_WAVEHDR>, int) waveInAddBuffer;
  final int Function(int) waveInStart;
  final int Function(int) waveInStop;
  final int Function(int) waveInReset;
  final int Function(int, Pointer<_WAVEHDR>, int) waveInUnprepareHeader;
  final int Function(int) waveInClose;
}
