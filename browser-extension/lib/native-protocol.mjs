export const NATIVE_HOST = "com.ryanwang.pinboardshot.browser_capture";
export const PROTOCOL_VERSION = 1;
export const MAX_NATIVE_MESSAGE_BYTES = 1024 * 1024;
export const FALLBACK_CHUNK_CHARS = 524288;

let nextRequest = 0;
export function requestId() {
  nextRequest = (nextRequest + 1) >>> 0;
  return `ps-${Date.now().toString(36)}-${nextRequest.toString(36)}`;
}

export function makeRequest(command, fields = {}) {
  return { requestId: requestId(), command, ...fields };
}

export function decodeNativeReply(reply, expectedRequestId) {
  if (!reply || reply.requestId !== expectedRequestId || typeof reply.ok !== "boolean") {
    throw new Error("native_protocol_error");
  }
  if (!reply.ok) {
    const error = new Error(typeof reply.error === "string" ? `native_${reply.error}` : "native_error");
    error.nativeCode = typeof reply.error === "string" ? reply.error : "native_error";
    error.captureSaved = reply.captureSaved === true;
    throw error;
  }
  return reply;
}

export function splitBase64(value, maxChunkChars = FALLBACK_CHUNK_CHARS) {
  if (typeof value !== "string" || value.length === 0 || !Number.isInteger(maxChunkChars) || maxChunkChars < 4) {
    throw new Error("invalid_tile");
  }
  const chunkChars = maxChunkChars - (maxChunkChars % 4);
  const chunks = [];
  for (let offset = 0; offset < value.length; offset += chunkChars) {
    chunks.push(value.slice(offset, offset + chunkChars));
  }
  return chunks;
}

export function validateChunkRequest(message, maxChunkChars) {
  const encoded = JSON.stringify(message);
  const bytes = new TextEncoder().encode(encoded).byteLength;
  return typeof message.data === "string" && message.data.length <= maxChunkChars && bytes < MAX_NATIVE_MESSAGE_BYTES;
}
