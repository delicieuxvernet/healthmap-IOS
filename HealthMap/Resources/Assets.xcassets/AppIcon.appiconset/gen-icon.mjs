// gen-icon.mjs — Génère un AppIcon 1024x1024 : rond bleu (IOS.blue #007AFF)
// centré sur fond blanc. Pure-Node, aucune dépendance externe.
//
// Usage : node gen-icon.mjs
// Sortie : AppIcon.png (à côté de ce fichier)

import { writeFileSync } from "node:fs";
import { deflateSync } from "node:zlib";
import { createHash } from "node:crypto";

const SIZE = 1024;
const RADIUS = 410;            // ~80% diamètre — laisse une marge confortable
const CX = SIZE / 2;
const CY = SIZE / 2;
const BLUE = [0, 122, 255];    // #007AFF (IOS.blue)
const WHITE = [255, 255, 255];

// Anti-aliasing : pour chaque pixel, on échantillonne 4 sub-pixels (2×2)
// et on fait la moyenne — assez bon pour un rond simple, pas besoin de plus.
function pixelAt(x, y) {
  const samples = [
    [x + 0.25, y + 0.25],
    [x + 0.75, y + 0.25],
    [x + 0.25, y + 0.75],
    [x + 0.75, y + 0.75],
  ];
  let inside = 0;
  for (const [sx, sy] of samples) {
    const dx = sx - CX, dy = sy - CY;
    if (dx * dx + dy * dy <= RADIUS * RADIUS) inside++;
  }
  if (inside === 4) return BLUE;
  if (inside === 0) return WHITE;
  // Mélange linéaire pour les pixels du bord
  const t = inside / 4;
  return [
    Math.round(BLUE[0] * t + WHITE[0] * (1 - t)),
    Math.round(BLUE[1] * t + WHITE[1] * (1 - t)),
    Math.round(BLUE[2] * t + WHITE[2] * (1 - t)),
  ];
}

// Construit le buffer raw : pour chaque ligne, 1 byte filter (0 = None)
// suivi de SIZE × 3 bytes RGB.
const raw = Buffer.alloc(SIZE * (1 + SIZE * 3));
let off = 0;
for (let y = 0; y < SIZE; y++) {
  raw[off++] = 0; // filter = None
  for (let x = 0; x < SIZE; x++) {
    const [r, g, b] = pixelAt(x, y);
    raw[off++] = r;
    raw[off++] = g;
    raw[off++] = b;
  }
}

// Helper CRC32 pour les chunks PNG
function crc32(buf) {
  // Calcul CRC32 standard (polynôme 0xEDB88320), implem simple — pas critique perf ici
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    crc ^= buf[i];
    for (let j = 0; j < 8; j++) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, "ascii");
  const crcInput = Buffer.concat([typeBuf, data]);
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(crcInput), 0);
  return Buffer.concat([len, typeBuf, data, crcBuf]);
}

// PNG signature
const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

// IHDR : 1024x1024, 8-bit, RGB, no interlace
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(SIZE, 0);
ihdr.writeUInt32BE(SIZE, 4);
ihdr[8] = 8;   // bit depth
ihdr[9] = 2;   // color type RGB
ihdr[10] = 0;  // compression
ihdr[11] = 0;  // filter
ihdr[12] = 0;  // interlace

// IDAT : zlib-compressed pixel data
const idat = deflateSync(raw, { level: 9 });

// IEND : empty
const iend = Buffer.alloc(0);

const png = Buffer.concat([
  signature,
  chunk("IHDR", ihdr),
  chunk("IDAT", idat),
  chunk("IEND", iend),
]);

writeFileSync(new URL("./AppIcon.png", import.meta.url), png);

const md5 = createHash("md5").update(png).digest("hex").slice(0, 8);
console.log(`AppIcon.png written: ${png.length} bytes, md5=${md5}`);
console.log(`Dimensions: ${SIZE}x${SIZE}, blue circle radius=${RADIUS}px on white background`);
