/**
 * ضبط صوت مرورگر — بدون سرویس ابری.
 * ۱) ترجیح: AudioWorklet → PCM16 @ 16kHz (باینری WS)
 * ۲) جایگزین: MediaRecorder با Opus داخل WebM (کاهش پهنای باند)
 */
(function () {
  let mediaStream = null;
  let audioContext = null;
  let micSource = null;
  let workletNode = null;
  let mediaRecorder = null;
  let mode = 'none'; // worklet | webm

  function supportsWebmOpus() {
    try {
      return (
        typeof MediaRecorder !== 'undefined' &&
        MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
      );
    } catch (_) {
      return false;
    }
  }

  async function startWorklet(ctx, targetRate, onPcmFrame) {
    const base = document.baseURI || window.location.href;
    const moduleUrl = new URL('voice_capture_processor.js', base).href;
    await ctx.audioWorklet.addModule(moduleUrl);
    workletNode = new AudioWorkletNode(ctx, 'voice-capture-processor', {
      processorOptions: { targetSampleRate: targetRate },
    });
    workletNode.port.onmessage = (ev) => {
      const data = ev.data;
      if (data instanceof ArrayBuffer) {
        onPcmFrame(data);
      }
    };
    micSource = ctx.createMediaStreamSource(mediaStream);
    micSource.connect(workletNode);
    // خروجی بی‌صدا برای جلوگیری از echo
    const mute = ctx.createGain();
    mute.gain.value = 0;
    workletNode.connect(mute);
    mute.connect(ctx.destination);
    mode = 'worklet';
  }

  function startWebm(onWebmChunk) {
    const mime = 'audio/webm;codecs=opus';
    mediaRecorder = new MediaRecorder(mediaStream, { mimeType: mime });
    mediaRecorder.ondataavailable = (ev) => {
      if (ev.data && ev.data.size > 0) {
        ev.data.arrayBuffer().then((buf) => onWebmChunk(buf));
      }
    };
    mediaRecorder.start(120);
    mode = 'webm';
  }

  globalThis.HesabixVoiceCapture = {
    supportsWebmOpus,
    async start(ctx, targetRate, onPcmFrame, onWebmChunk) {
      await this.stop();
      audioContext = ctx;
      const devices = navigator.mediaDevices;
      if (!devices || !devices.getUserMedia) {
        throw new Error('mediaDevices unavailable');
      }
      mediaStream = await devices.getUserMedia({ audio: true, video: false });
      if (onWebmChunk && supportsWebmOpus()) {
        try {
          startWebm(onWebmChunk);
          return { mode: 'webm_opus' };
        } catch (e) {
          console.warn('WebM/Opus capture failed, falling back to worklet', e);
        }
      }
      await startWorklet(ctx, targetRate, onPcmFrame);
      return { mode: 'pcm_worklet' };
    },
    async stop() {
      try {
        if (mediaRecorder && mediaRecorder.state !== 'inactive') {
          mediaRecorder.stop();
        }
      } catch (_) {}
      mediaRecorder = null;
      try {
        workletNode?.disconnect();
      } catch (_) {}
      try {
        micSource?.disconnect();
      } catch (_) {}
      workletNode = null;
      micSource = null;
      if (mediaStream) {
        mediaStream.getTracks().forEach((t) => {
          try {
            t.stop();
          } catch (_) {}
        });
      }
      mediaStream = null;
      mode = 'none';
    },
    getMode() {
      return mode;
    },
  };
})();
