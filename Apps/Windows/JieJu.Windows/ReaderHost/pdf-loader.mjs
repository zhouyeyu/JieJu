import { postToNative } from './bridge.mjs';

try {
  await import('./pdf.mjs');
} catch (error) {
  const detail = String(error?.stack ?? error?.message ?? error);
  document.querySelector('#message').textContent = 'PDF 阅读器初始化失败';
  postToNative('error', { message:detail });
}
