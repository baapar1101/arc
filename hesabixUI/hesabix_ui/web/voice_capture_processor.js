/**
 * AudioWorklet: resample میکروفون به PCM16 mono @ targetSampleRate.
 * فریم‌های ~۲۰ms با resampler کسری پایدار (بدون کلیک مرز بافر).
 */
class VoiceCaptureProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const opts = (options && options.processorOptions) || {};
    this.targetRate = opts.targetSampleRate || 8000;
    this._srcRate = sampleRate;
    this._ratio = this._srcRate / this.targetRate;
    this._pos = 0;
    this._pending = [];
    this._out = [];
    this._frame = Math.max(80, Math.round(this.targetRate * 0.02));
  }

  _emit() {
    const n = this._frame;
    const i16 = new Int16Array(n);
    for (let i = 0; i < n; i++) {
      const v = Math.max(-1, Math.min(1, this._out[i]));
      i16[i] = v < 0 ? v * 0x8000 : v * 0x7fff;
    }
    this._out.splice(0, n);
    this.port.postMessage(i16.buffer, [i16.buffer]);
  }

  process(inputs) {
    const ch = inputs[0] && inputs[0][0];
    if (ch && ch.length) {
      for (let i = 0; i < ch.length; i++) {
        this._pending.push(ch[i]);
      }
    }
    while (this._pos + 1 < this._pending.length) {
      const i0 = Math.floor(this._pos);
      const frac = this._pos - i0;
      const s = this._pending[i0] * (1 - frac) + this._pending[i0 + 1] * frac;
      this._out.push(s);
      this._pos += this._ratio;
      if (this._out.length >= this._frame) {
        this._emit();
      }
    }
    const drop = Math.floor(this._pos);
    if (drop > 0) {
      this._pending.splice(0, drop);
      this._pos -= drop;
    }
    return true;
  }
}

registerProcessor('voice-capture-processor', VoiceCaptureProcessor);
