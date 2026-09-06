export const RECORDING_LIMIT_MS = 30_000;

export const RECORDING_MIME_CANDIDATES = [
  "video/webm;codecs=vp9",
  "video/webm;codecs=vp8",
  "video/webm",
  "video/mp4;codecs=avc1.42E01E",
  "video/mp4",
];

export function selectRecordingMimeType(isTypeSupported, candidates = RECORDING_MIME_CANDIDATES) {
  return candidates.find((candidate) => isTypeSupported(candidate)) ?? null;
}

export function extensionForMimeType(mimeType) {
  return mimeType.toLowerCase().includes("mp4") ? "mp4" : "webm";
}

export class CanvasRecorder {
  constructor(canvas, onStatus) {
    this.canvas = canvas;
    this.onStatus = onStatus;
    this.recorder = null;
    this.stream = null;
    this.stopTimer = null;
  }

  get supported() {
    return typeof this.canvas.captureStream === "function"
      && typeof window.MediaRecorder === "function"
      && typeof window.MediaRecorder.isTypeSupported === "function";
  }

  get active() {
    return this.recorder?.state === "recording";
  }

  start() {
    if (!this.supported || this.active) return false;
    const mimeType = selectRecordingMimeType((candidate) => window.MediaRecorder.isTypeSupported(candidate));
    if (!mimeType) return false;

    const chunks = [];
    try {
      this.stream = this.canvas.captureStream(30);
      this.recorder = new window.MediaRecorder(this.stream, { mimeType });
    } catch (_error) {
      this.stream?.getTracks().forEach((track) => track.stop());
      this.stream = null;
      this.recorder = null;
      return false;
    }
    this.recorder.addEventListener("dataavailable", (event) => {
      if (event.data.size > 0) chunks.push(event.data);
    });
    this.recorder.addEventListener("stop", () => {
      const actualMime = this.recorder.mimeType || mimeType;
      const blob = new Blob(chunks, { type: actualMime });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `sidey-asset-preview.${extensionForMimeType(actualMime)}`;
      link.click();
      window.setTimeout(() => URL.revokeObjectURL(url), 1000);
      this.stream?.getTracks().forEach((track) => track.stop());
      this.stream = null;
      this.recorder = null;
      this.onStatus("recorded", actualMime);
    }, { once: true });
    this.recorder.start(250);
    this.stopTimer = window.setTimeout(() => this.stop(), RECORDING_LIMIT_MS);
    this.onStatus("recording", mimeType);
    return true;
  }

  stop() {
    window.clearTimeout(this.stopTimer);
    this.stopTimer = null;
    if (this.active) this.recorder.stop();
  }
}
