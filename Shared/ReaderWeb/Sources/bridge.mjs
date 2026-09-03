export const contractVersion = 1;

export const readerToHostTypes = Object.freeze([
  "selectionChanged",
  "locationChanged",
  "paginationChanged",
  "ready",
  "error"
]);

export const hostToReaderTypes = Object.freeze([
  "configure",
  "turnPage",
  "restoreLocation",
  "clearSelection"
]);

const knownTypes = new Set([...readerToHostTypes, ...hostToReaderTypes]);

export function message(type, payload = {}) {
  if (!knownTypes.has(type)) throw new TypeError(`Unknown JieJu bridge message: ${type}`);
  if (payload === null || typeof payload !== "object" || Array.isArray(payload)) {
    throw new TypeError("JieJu bridge payload must be an object");
  }
  return { contractVersion, type, payload };
}

export function detectNativeHost(scope = globalThis) {
  const macHandler = scope?.webkit?.messageHandlers?.jiejuBridge;
  if (typeof macHandler?.postMessage === "function") {
    return { platform: "macOS", postMessage: value => macHandler.postMessage(value) };
  }
  const windowsWebView = scope?.chrome?.webview;
  if (typeof windowsWebView?.postMessage === "function") {
    return { platform: "windows", postMessage: value => windowsWebView.postMessage(value) };
  }
  return null;
}

export function postToNative(type, payload = {}, host = detectNativeHost()) {
  if (!host) throw new Error("JieJu native reader host is unavailable");
  const value = message(type, payload);
  host.postMessage(value);
  return value;
}

export function installCommandListener(handler, scope = globalThis) {
  if (typeof handler !== "function") throw new TypeError("Command handler must be a function");
  const dispatch = raw => {
    const value = typeof raw === "string" ? JSON.parse(raw) : raw;
    if (!value || value.contractVersion !== contractVersion || !hostToReaderTypes.includes(value.type)) return false;
    handler(value);
    return true;
  };

  if (typeof scope?.chrome?.webview?.addEventListener === "function") {
    const listener = event => dispatch(event.data);
    scope.chrome.webview.addEventListener("message", listener);
    return { dispatch, dispose: () => scope.chrome.webview.removeEventListener?.("message", listener) };
  }
  const listener = event => dispatch(event.detail);
  scope?.addEventListener?.("jieju-command", listener);
  return { dispatch, dispose: () => scope?.removeEventListener?.("jieju-command", listener) };
}
