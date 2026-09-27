import { decodeNativeReply, makeRequest, NATIVE_HOST, PROTOCOL_VERSION, MAX_NATIVE_MESSAGE_BYTES } from "./native-protocol.mjs";

export class NativeCaptureClient {
  constructor(chromeApi, timeoutMs = 60000) {
    this.chrome = chromeApi;
    this.timeoutMs = timeoutMs;
    this.port = null;
    this.pending = new Map();
    this.disconnectError = null;
  }

  async connect() {
    if (this.port) return;
    this.port = this.chrome.runtime.connectNative(NATIVE_HOST);
    this.port.onMessage.addListener(reply => {
      const pending = this.pending.get(reply?.requestId);
      if (!pending) return;
      clearTimeout(pending.timer);
      this.pending.delete(reply.requestId);
      try { pending.resolve(decodeNativeReply(reply, reply.requestId)); }
      catch (error) { pending.reject(error); }
    });
    this.port.onDisconnect.addListener(() => {
      const reason = this.chrome.runtime.lastError?.message || "native_disconnected";
      this.disconnectError = new Error(reason);
      for (const item of this.pending.values()) {
        clearTimeout(item.timer);
        item.reject(this.disconnectError);
      }
      this.pending.clear();
      this.port = null;
    });
    const hello = await this.request("hello", { protocolVersion: PROTOCOL_VERSION });
    if (hello.protocolVersion !== PROTOCOL_VERSION || !Number.isInteger(hello.maxChunkBytes) || hello.maxChunkBytes < 4) {
      throw new Error("native_protocol_unsupported");
    }
    this.maxChunkChars = hello.maxChunkBytes;
  }

  request(command, fields = {}) {
    if (!this.port) return Promise.reject(this.disconnectError || new Error("native_disconnected"));
    const message = makeRequest(command, fields);
    const encodedBytes = new TextEncoder().encode(JSON.stringify(message)).byteLength;
    if (encodedBytes >= MAX_NATIVE_MESSAGE_BYTES) return Promise.reject(new Error("native_message_too_large"));
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(message.requestId);
        reject(new Error("native_timeout"));
      }, this.timeoutMs);
      this.pending.set(message.requestId, { resolve, reject, timer });
      try { this.port.postMessage(message); }
      catch (error) {
        clearTimeout(timer);
        this.pending.delete(message.requestId);
        reject(error);
      }
    });
  }

  disconnect() {
    const port = this.port;
    this.port = null;
    if (port) port.disconnect();
  }
}
