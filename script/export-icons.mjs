import { readFile, writeFile } from 'node:fs/promises';
import { chromium } from 'playwright';

// Optional development tool. Application startup and deployment do not use it.
const source = await readFile(new URL('../public/icon.svg', import.meta.url));
const browser = await chromium.launch();

try {
  const page = await browser.newPage();
  const images = await page.evaluate(async (svg) => {
    const image = new Image();
    image.src = `data:image/svg+xml;base64,${svg}`;
    await image.decode();

    return Object.fromEntries([16, 32, 48, 180, 512].map((size) => {
      const canvas = document.createElement('canvas');
      canvas.width = canvas.height = size;
      canvas.getContext('2d').drawImage(image, 0, 0, size, size);
      return [size, canvas.toDataURL('image/png').split(',')[1]];
    }));
  }, source.toString('base64'));

  const png = (size) => Buffer.from(images[size], 'base64');
  for (const [name, size] of [
    ['icon.png', 512],
    ['apple-touch-icon.png', 180],
    ['apple-touch-icon-precomposed.png', 180],
  ]) {
    await writeFile(new URL(`../public/${name}`, import.meta.url), png(size));
  }

  // ICO entries contain PNG images so browsers can choose a native icon size.
  const sizes = [16, 32, 48];
  const header = Buffer.alloc(6 + 16 * sizes.length);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(sizes.length, 4);
  let offset = header.length;
  sizes.forEach((size, index) => {
    const entry = 6 + index * 16;
    header[entry] = header[entry + 1] = size;
    header.writeUInt16LE(1, entry + 4);
    header.writeUInt16LE(32, entry + 6);
    header.writeUInt32LE(png(size).length, entry + 8);
    header.writeUInt32LE(offset, entry + 12);
    offset += png(size).length;
  });
  await writeFile(new URL('../public/favicon.ico', import.meta.url),
    Buffer.concat([header, ...sizes.map(png)]));
  console.log('Exported Reserven PNG and ICO icons from public/icon.svg.');
} finally {
  await browser.close();
}
