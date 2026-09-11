export const PNG_SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10];
export const MAX_PNG_BYTES = 2 * 1024 * 1024;

export const ASSET_CONTRACTS = Object.freeze({
  base: { label: "base.png", width: 240, height: 24, frameWidth: 24, frameCount: 10, baselinePixels: 3 },
  throwHit: { label: "throw_hit.png", width: 192, height: 24, frameWidth: 24, frameCount: 8, baselinePixels: 3 },
  throwable: { label: "sprite.png", width: 192, height: 16, frameWidth: 16, frameCount: 12, baselinePixels: null },
});

export class AssetValidationError extends Error {
  constructor(message, code) {
    super(message);
    this.name = "AssetValidationError";
    this.code = code;
  }
}

function fourCC(bytes, offset) {
  return String.fromCharCode(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]);
}

export function inspectPng(arrayBuffer, contract) {
  if (arrayBuffer.byteLength > MAX_PNG_BYTES) {
    throw new AssetValidationError(`파일이 2 MiB 제한을 넘음 (file_too_large)`, "file_too_large");
  }
  const bytes = new Uint8Array(arrayBuffer);
  if (bytes.length < 33 || !PNG_SIGNATURE.every((value, index) => bytes[index] === value)) {
    throw new AssetValidationError("PNG signature가 올바르지 않음 (invalid_png_signature)", "invalid_png_signature");
  }
  const view = new DataView(arrayBuffer);
  if (view.getUint32(8) !== 13 || fourCC(bytes, 12) !== "IHDR") {
    throw new AssetValidationError("IHDR가 없거나 손상됨 (invalid_ihdr)", "invalid_ihdr");
  }
  const width = view.getUint32(16);
  const height = view.getUint32(20);
  const bitDepth = bytes[24];
  const colorType = bytes[25];
  const compression = bytes[26];
  const filter = bytes[27];
  const interlace = bytes[28];
  if (width !== contract.width || height !== contract.height) {
    throw new AssetValidationError(
      `${contract.label} 크기는 ${contract.width}×${contract.height}px, ${contract.frameCount} frames여야 함 (invalid_dimensions)`,
      "invalid_dimensions",
    );
  }
  if (bitDepth !== 8 || colorType !== 6 || compression !== 0 || filter !== 0 || interlace !== 0) {
    throw new AssetValidationError("8-bit non-interlaced RGBA PNG가 아님 (invalid_rgba_format)", "invalid_rgba_format");
  }

  let offset = 8;
  let hasSrgb = false;
  let hasIend = false;
  while (offset + 12 <= bytes.length) {
    const length = view.getUint32(offset);
    const end = offset + 12 + length;
    if (end > bytes.length) {
      throw new AssetValidationError("PNG chunk가 잘림 (truncated_png_chunk)", "truncated_png_chunk");
    }
    const type = fourCC(bytes, offset + 4);
    if (type === "sRGB") hasSrgb = true;
    if (type === "IEND") {
      hasIend = true;
      break;
    }
    offset = end;
  }
  if (!hasSrgb) throw new AssetValidationError("sRGB chunk가 없음 (missing_srgb)", "missing_srgb");
  if (!hasIend) throw new AssetValidationError("IEND가 없음 (incomplete_png)", "incomplete_png");
  return { width, height, frameCount: width / contract.frameWidth };
}

export function validateDecodedPixels(imageData, contract) {
  const alpha = imageData.data;
  let sawTransparent = false;
  let sawOpaque = false;
  for (let index = 3; index < alpha.length; index += 4) {
    const value = alpha[index];
    if (value === 0) sawTransparent = true;
    else if (value === 255) sawOpaque = true;
    else throw new AssetValidationError("반투명 픽셀이 있음 (soft_alpha)", "soft_alpha");
  }
  if (!sawTransparent || !sawOpaque) {
    throw new AssetValidationError("투명·불투명 픽셀이 모두 필요함 (invalid_alpha_range)", "invalid_alpha_range");
  }
  if (contract.baselinePixels == null) return;

  const expectedRow = contract.height - contract.baselinePixels - 1;
  for (let frame = 0; frame < contract.frameCount; frame += 1) {
    let lowestOpaqueRow = -1;
    for (let y = 0; y < contract.height; y += 1) {
      for (let x = frame * contract.frameWidth; x < (frame + 1) * contract.frameWidth; x += 1) {
        if (alpha[(y * contract.width + x) * 4 + 3] === 255) lowestOpaqueRow = y;
      }
    }
    if (lowestOpaqueRow !== expectedRow) {
      throw new AssetValidationError(
        `frame ${frame} 발 기준선은 아래쪽 ${contract.baselinePixels}px이어야 함 (invalid_foot_baseline)`,
        "invalid_foot_baseline",
      );
    }
  }
}

export function inferAssetKind(arrayBuffer) {
  const bytes = new Uint8Array(arrayBuffer);
  if (bytes.length < 24 || !PNG_SIGNATURE.every((value, index) => bytes[index] === value)) return null;
  const view = new DataView(arrayBuffer);
  const width = view.getUint32(16);
  const height = view.getUint32(20);
  return Object.entries(ASSET_CONTRACTS).find(([, contract]) => contract.width === width && contract.height === height)?.[0] ?? null;
}

export async function decodePng(blob, kind) {
  const contract = ASSET_CONTRACTS[kind];
  const buffer = await blob.arrayBuffer();
  const metadata = inspectPng(buffer, contract);
  const bitmap = await createImageBitmap(new Blob([buffer], { type: "image/png" }));
  const canvas = document.createElement("canvas");
  canvas.width = contract.width;
  canvas.height = contract.height;
  const context = canvas.getContext("2d", { willReadFrequently: true });
  context.imageSmoothingEnabled = false;
  context.drawImage(bitmap, 0, 0);
  try {
    validateDecodedPixels(context.getImageData(0, 0, canvas.width, canvas.height), contract);
  } catch (error) {
    bitmap.close();
    throw error;
  }
  return { bitmap, metadata, kind };
}

export async function loadBundledPng(url, kind) {
  const response = await fetch(url, { credentials: "same-origin" });
  if (!response.ok) throw new Error(`공식 ${ASSET_CONTRACTS[kind].label} 로드 실패: ${response.status}`);
  return decodePng(await response.blob(), kind);
}
