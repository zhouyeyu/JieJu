import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [directory, destination] = process.argv.slice(2);
if (!directory || !destination) throw new Error('Usage: package-windows-icon.mjs <PNG directory> <output.ico>');
const sizes = [16, 24, 32, 48, 64, 128, 256];
const images = sizes.map(size => readFileSync(join(directory, `${size}.png`)));
const header = Buffer.alloc(6 + sizes.length * 16);
header.writeUInt16LE(1, 2);
header.writeUInt16LE(sizes.length, 4);
let offset = header.length;
images.forEach((data, index) => {
  const size = sizes[index];
  if (data.readUInt32BE(16) !== size || data.readUInt32BE(20) !== size) throw new Error(`Invalid PNG size: ${size}`);
  const entry = 6 + index * 16;
  header[entry] = header[entry + 1] = size === 256 ? 0 : size;
  header.writeUInt16LE(1, entry + 4);
  header.writeUInt16LE(32, entry + 6);
  header.writeUInt32LE(data.length, entry + 8);
  header.writeUInt32LE(offset, entry + 12);
  offset += data.length;
});
writeFileSync(destination, Buffer.concat([header, ...images]));
