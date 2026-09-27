import test from "node:test";
import assert from "node:assert/strict";
import { decodeNativeReply, makeRequest, splitBase64, validateChunkRequest } from "../lib/native-protocol.mjs";

test("native replies must match their request and expose explicit failures", () => {
  const request = makeRequest("hello");
  assert.deepEqual(decodeNativeReply({ requestId: request.requestId, ok: true, protocolVersion: 1 }, request.requestId), { requestId: request.requestId, ok: true, protocolVersion: 1 });
  assert.throws(() => decodeNativeReply({ requestId: "other", ok: true }, request.requestId), /native_protocol_error/);
  assert.throws(() => decodeNativeReply({ requestId: request.requestId, ok: false, error: "bad_tile" }, request.requestId), /native_bad_tile/);
  try { decodeNativeReply({ requestId: request.requestId, ok: false, error: "app_open_failed", captureSaved: true }, request.requestId); }
  catch (error) {
    assert.equal(error.nativeCode, "app_open_failed");
    assert.equal(error.captureSaved, true);
  }
});

test("PNG base64 is split on safe four-character boundaries below the negotiated limit", () => {
  const source = "A".repeat(104);
  const chunks = splitBase64(source, 32);
  assert.equal(chunks.join(""), source);
  assert.ok(chunks.every(chunk => chunk.length <= 32 && chunk.length % 4 === 0));
  assert.ok(chunks.every(data => validateChunkRequest({ requestId: "r", command: "tileChunk", captureId: "c", index: 0, sequence: 0, data }, 32)));
  assert.equal(validateChunkRequest({ data: "A".repeat(33) }, 32), false);
});
