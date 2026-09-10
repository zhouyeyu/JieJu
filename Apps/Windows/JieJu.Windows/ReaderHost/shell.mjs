import { postToNative } from './bridge.mjs';
postToNative('ready', { readerKind: 'epub' });
