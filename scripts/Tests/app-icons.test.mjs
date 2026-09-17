import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const root = new URL('../../', import.meta.url);
const read = path => readFileSync(new URL(path, root));
const pngSignature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

test('shared artwork is a square high-resolution PNG', () => {
  const image = read('Shared/Brand/jieju-icon.png');
  assert.deepEqual(image.subarray(0, 8), pngSignature);
  assert.equal(image.readUInt32BE(16), image.readUInt32BE(20));
  assert.ok(image.readUInt32BE(16) >= 1024);
});

test('both README languages display the shared icon at a compact fixed size', () => {
  for (const path of ['README.md', 'README.en.md']) {
    assert.match(read(path).toString(), /<img src="Shared\/Brand\/jieju-icon.png" alt="[^"]+" width="96" height="96">/);
  }
});

test('Windows ICO contains valid PNG frames for every supported size', () => {
  const ico = read('Apps/Windows/JieJu.Windows/Assets/AppIcon.ico');
  const sizes = [16, 24, 32, 48, 64, 128, 256];
  assert.equal(ico.readUInt16LE(0), 0);
  assert.equal(ico.readUInt16LE(2), 1);
  assert.equal(ico.readUInt16LE(4), sizes.length);
  let expectedOffset = 6 + sizes.length * 16;
  sizes.forEach((size, index) => {
    const entry = 6 + index * 16;
    assert.equal(ico[entry] || 256, size);
    assert.equal(ico[entry + 1] || 256, size);
    const length = ico.readUInt32LE(entry + 8);
    const offset = ico.readUInt32LE(entry + 12);
    assert.equal(offset, expectedOffset);
    assert.ok(offset + length <= ico.length);
    const frame = ico.subarray(offset, offset + length);
    assert.deepEqual(frame.subarray(0, 8), pngSignature);
    assert.equal(frame.readUInt32BE(16), size);
    assert.equal(frame.readUInt32BE(20), size);
    expectedOffset += length;
  });
  assert.equal(expectedOffset, ico.length);
});

test('macOS ICNS is complete and includes a 1024 pixel representation', () => {
  const icon = read('JieJu/Resources/AppIcon.icns');
  assert.equal(icon.toString('ascii', 0, 4), 'icns');
  assert.equal(icon.readUInt32BE(4), icon.length);
  const types = [];
  let offset = 8;
  while (offset < icon.length) {
    types.push(icon.toString('ascii', offset, offset + 4));
    const length = icon.readUInt32BE(offset + 4);
    assert.ok(length >= 8 && offset + length <= icon.length);
    offset += length;
  }
  assert.equal(offset, icon.length);
  assert.ok(types.includes('ic10'));
});

test('both platforms package and reference the approved icon', () => {
  const project = read('JieJu.xcodeproj/project.pbxproj').toString();
  assert.equal(project.match(/INFOPLIST_FILE = JieJu\/Info.plist;/g)?.length, 2);
  assert.match(read('JieJu/Info.plist').toString(), /<key>CFBundleIconFile<\/key>\s*<string>AppIcon<\/string>/);
  assert.ok(project.includes('files = (AE0000000000000000000001 /* AppIcon.icns in Resources */)'));
  const windowsProject = read('Apps/Windows/JieJu.Windows/JieJu.Windows.csproj').toString();
  assert.ok(windowsProject.includes('<ApplicationIcon>Assets/AppIcon.ico</ApplicationIcon>'));
  assert.ok(windowsProject.includes('CopyToPublishDirectory="PreserveNewest"'));
  const window = read('Apps/Windows/JieJu.Windows/MainWindow.xaml.cs').toString();
  assert.ok(window.includes('AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico"))'));
});
