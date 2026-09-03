import test from "node:test";
import assert from "node:assert/strict";
import {
  contractVersion,
  detectNativeHost,
  installCommandListener,
  message,
  postToNative
} from "../Sources/bridge.mjs";

test("creates a versioned bridge message", () => {
  assert.deepEqual(message("turnPage", { delta: 1 }), {
    contractVersion: 1,
    type: "turnPage",
    payload: { delta: 1 }
  });
  assert.throws(() => message("futureMessage"), /Unknown JieJu bridge message/);
});

test("detects WKWebView and WebView2 without platform-specific reader code", () => {
  const sentByMac = [];
  const mac = detectNativeHost({
    webkit: { messageHandlers: { jiejuBridge: { postMessage: value => sentByMac.push(value) } } }
  });
  postToNative("ready", { readerKind: "epub" }, mac);
  assert.equal(mac.platform, "macOS");
  assert.equal(sentByMac[0].contractVersion, contractVersion);

  const sentByWindows = [];
  const windows = detectNativeHost({ chrome: { webview: { postMessage: value => sentByWindows.push(value) } } });
  postToNative("clearSelection", {}, windows);
  assert.equal(windows.platform, "windows");
  assert.equal(sentByWindows[0].type, "clearSelection");
});

test("accepts only current host-to-reader commands", () => {
  const received = [];
  const listener = installCommandListener(value => received.push(value), {});
  assert.equal(listener.dispatch({ contractVersion: 1, type: "configure", payload: {} }), true);
  assert.equal(listener.dispatch({ contractVersion: 2, type: "configure", payload: {} }), false);
  assert.equal(listener.dispatch({ contractVersion: 1, type: "selectionChanged", payload: {} }), false);
  assert.equal(received.length, 1);
});
