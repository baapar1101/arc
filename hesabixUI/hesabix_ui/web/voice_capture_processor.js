/**
 * AudioWorklet: resample میکروفون به PCM16 mono @ targetSampleRate و ارسال به main thread.
 */
class VoiceCaptureProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const opts = (options && options.processorOptions) || {};
    this.targetRate = opts.targetSampleRate || 16000;
    this._srcRate = sampleRate;
    this._ratio = this._srcRate / this.targetRate;
    this._pending = new Float32Array(0);
    this._outBuffer = [];
    this._outThreshold = Math.max(320, Math.floor(this.targetRate * 0.02)); // ~20ms @ 16k
  }

  _appendInput(samples) {
    if (this._pending.length === 0) {
      this._pending = samples;
      return;
    }
    const merged = new Float32Array(this._pending.length + samples.length);
    merged.set(this._pending, 0);
    merged.set(samples, this._pending.length);
    this._pending = merged;
  }

  _resampleOne() {
    if (this._pending.length < 2) return null;
    const out = [];
    let pos = 0;
    while (pos + 1 < this._pending.length) {
      const srcIndex = out.length * this._ratio;
      if (srcIndex + 1 >= this._pending.length) break;
      const i0 = Math.floor(srcIndex);
      const frac = srcIndex - i0;
      const i1 = Math.min(i0 + 1, this._pending.length - 1);
      const sample = this._pending[i0] * (1 - frac) + this._pending[i1] * frac;
      out.push(sample);
      pos = i0 + 1;
    }
    if (pos > 0) {
      this._pending = this._pending.subarray(pos);
    }
    return out.length ? Float32Array.from(out) : null;
  }

  _floatToInt16(floats) {
    const out = new Int16Array(floats.length);
    for (let i = 0; i < floats.length; i++) {
      const v = Math.max(-1, Math.min(1, floats[i]));
      out[i] = v < 0 ? v * 0x8000 : v * 0x7fff;
    }
    return out;
  }

  _flushOut() {
    if (this._outBuffer.length < this._outThreshold) return;
    const chunk = Int16Array.from(this._outBuffer);
    this._outBuffer = [];
    this.port.postMessage(chunk.buffer, [chunk.buffer]);
  }

  process(inputs) {
    const input = inputs[0];
    if (!input || !input[0] || input[0].length === 0) {
      return true;
    }
    this._appendInput(input[0]);
    for (;;) {
      const resampled = this._resampleOne();
      if (!resampled) break;
      const i16 = this._floatToInt16(resampled);
      for (let i = 0; i < i16.length; i++) {
        this._outBuffer.push(i16[i]);
      }
      this._flushOut();
    }
    return true;
  }
}

registerProcessor('voice-capture-processor', VoiceCaptureProcessor);
