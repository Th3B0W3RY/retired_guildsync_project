#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const nodeCrypto = require("crypto");
const ImageAnalysisClient = require("@azure-rest/ai-vision-image-analysis").default;
const { AzureKeyCredential } = require("@azure/core-auth");

// Azure SDK expects Web Crypto on globalThis in some runtimes.
// Node 18 may not expose globalThis.crypto consistently, so bridge it.
if (typeof globalThis.crypto === "undefined" && nodeCrypto.webcrypto) {
  globalThis.crypto = nodeCrypto.webcrypto;
}

function log(message) {
  process.stdout.write(`AZURE_OCR: ${message}\n`);
}

function logError(message) {
  process.stderr.write(`AZURE_OCR_ERROR: ${message}\n`);
}

function detectImageFormat(buffer) {
  if (buffer.length < 12) return null;
  if (buffer.slice(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47]))) return "image/png";
  if (buffer.slice(0, 3).equals(Buffer.from([0xff, 0xd8, 0xff]))) return "image/jpeg";
  if (buffer.slice(0, 6).toString("ascii") === "GIF87a" || buffer.slice(0, 6).toString("ascii") === "GIF89a") return "image/gif";
  if (buffer.slice(0, 2).toString("ascii") === "BM") return "image/bmp";
  if (buffer.slice(0, 4).toString("ascii") === "RIFF" && buffer.slice(8, 12).toString("ascii") === "WEBP") return "image/webp";
  if (buffer.slice(0, 4).equals(Buffer.from([0x00, 0x00, 0x01, 0x00]))) return "image/x-icon";
  if (buffer.slice(0, 4).equals(Buffer.from([0x49, 0x49, 0x2a, 0x00])) || buffer.slice(0, 4).equals(Buffer.from([0x4d, 0x4d, 0x00, 0x2a]))) return "image/tiff";
  return null;
}

function getLinePosition(line, fallbackIndex) {
  const polygon = Array.isArray(line?.boundingPolygon) ? line.boundingPolygon : null;
  if (!polygon || polygon.length === 0) {
    return { x: 0, xMax: 0, y: fallbackIndex * 10, h: 0, noBbox: true };
  }

  const points = polygon.filter((p) => p && typeof p.x === "number" && typeof p.y === "number");
  if (points.length === 0) {
    return { x: 0, xMax: 0, y: fallbackIndex * 10, h: 0, noBbox: true };
  }

  const xs = points.map((p) => p.x);
  const ys = points.map((p) => p.y);
  const minX = Math.min(...xs);
  const maxX = Math.max(...xs);
  const minY = Math.min(...ys);
  const maxY = Math.max(...ys);

  return {
    x: minX,
    xMax: maxX,
    y: minY,
    h: Math.max(1, maxY - minY),
    noBbox: false
  };
}

function sortVisualLines(lines) {
  if (lines.length === 0) return [];

  const heights = lines.map((l) => l.h).filter((h) => Number.isFinite(h) && h > 0).sort((a, b) => a - b);
  const medianHeight = heights.length > 0 ? heights[Math.floor(heights.length / 2)] : 16;
  const rowTolerance = Math.max(10, Math.round(medianHeight * 0.8));

  return lines
    .map((line, idx) => ({
      ...line,
      idx,
      row: Math.round(line.y / rowTolerance)
    }))
    .sort((a, b) => {
      if (a.row !== b.row) return a.row - b.row;
      if (a.x !== b.x) return a.x - b.x;
      if (a.y !== b.y) return a.y - b.y;
      return a.idx - b.idx;
    });
}

function extractTextLines(body) {
  const lines = [];

  const pushText = (lineLike, fallbackIndex) => {
    const value = lineLike?.text ?? lineLike?.content ?? lineLike;
    if (typeof value !== "string") return;
    const trimmed = value.trim();
    if (trimmed.length === 0) return;

    const pos = getLinePosition(lineLike, fallbackIndex);
    lines.push({
      text: trimmed,
      x: pos.x,
      xMax: pos.xMax,
      y: pos.y,
      h: pos.h,
      noBbox: pos.noBbox === true
    });
  };

  const readResult = body?.readResult ?? body?.read ?? null;
  let lineCounter = 0;

  if (Array.isArray(readResult?.blocks)) {
    for (const block of readResult.blocks) {
      if (Array.isArray(block?.lines)) {
        for (const line of block.lines) {
          pushText(line, lineCounter);
          lineCounter += 1;
        }
      } else {
        pushText(block, lineCounter);
        lineCounter += 1;
      }
    }
  }

  if (Array.isArray(readResult?.pages)) {
    for (const page of readResult.pages) {
      if (!Array.isArray(page?.lines)) continue;
      for (const line of page.lines) {
        pushText(line, lineCounter);
        lineCounter += 1;
      }
    }
  }

  // Fallback if no individual line objects were returned.
  if (lines.length === 0 && typeof readResult?.content === "string" && readResult.content.trim().length > 0) {
    return readResult.content
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line.length > 0);
  }

  // Stat extraction is game-agnostic and content-based: we keep text from anywhere on the
  // screen (left, center, or right panels) and let the Ruby StatScanner parser decide what is
  // a real stat. We only drop bracketed chat ("[Channel] Name: ...") here as a cheap, position-
  // independent noise cut; everything else is handled downstream by content rules.
  const sorted = sortVisualLines(lines);
  const asText = sorted.map((line) => line.text);
  const filterBracketLines = (process.env.OCR_FILTER_BRACKET_LINES || "true").toLowerCase() === "true";
  if (!filterBracketLines) return asText;

  return asText.filter((line) => !/^\s*\[[^\]]*\]/.test(line));
}

async function run() {
  if (process.argv.length < 4) {
    throw new Error("Usage: azure_ocr.js <image_path> <output_file_path>");
  }

  const imagePath = path.resolve(process.argv[2]);
  const outputPath = path.resolve(process.argv[3]);
  const endpoint = process.env.GUILDSYNC_AZURE_VISION_ENDPOINT || process.env.AZURE_VISION_ENDPOINT;
  const key = process.env.GUILDSYNC_AZURE_VISION_KEY || process.env.AZURE_VISION_KEY;

  log(`Starting OCR script`);
  log(`Image path: ${imagePath}`);
  log(`Output path: ${outputPath}`);

  if (!endpoint || !key) {
    throw new Error("Missing Azure credentials. Set GUILDSYNC_AZURE_VISION_ENDPOINT and GUILDSYNC_AZURE_VISION_KEY.");
  }

  if (!fs.existsSync(imagePath)) {
    throw new Error(`Image file not found: ${imagePath}`);
  }

  const imageBuffer = fs.readFileSync(imagePath);
  if (!imageBuffer || imageBuffer.length === 0) {
    throw new Error(`Image file is empty: ${imagePath}`);
  }

  const imageMime = detectImageFormat(imageBuffer);
  if (!imageMime) {
    throw new Error("Input file does not appear to be a supported image format.");
  }

  log(`Detected image format: ${imageMime}`);
  log(`Image size: ${imageBuffer.length} bytes`);
  log(`Creating Azure ImageAnalysis client`);

  const credential = new AzureKeyCredential(key);
  const client = ImageAnalysisClient(endpoint, credential);

  log(`Calling Azure Image Analysis API with Read feature`);
  const response = await client.path("/imageanalysis:analyze").post({
    body: imageBuffer,
    queryParameters: {
      features: ["Read"]
    },
    contentType: "application/octet-stream"
  });

  const statusCode = Number(response.status);
  const body = response.body ?? {};
  const bodyKeys = Object.keys(body);
  const requestId = response.headers?.["x-ms-request-id"] || null;

  log(`Azure API response status: ${response.status}`);
  log(`Azure API response keys: ${bodyKeys.join(", ") || "(none)"}`);
  if (requestId) {
    log(`Azure request id: ${requestId}`);
  }

  if (!Number.isFinite(statusCode) || statusCode < 200 || statusCode >= 300) {
    const bodyPreview = JSON.stringify(body).slice(0, 1000);
    throw new Error(`Azure OCR API call failed with status ${response.status}. Body preview: ${bodyPreview}`);
  }

  const textLines = extractTextLines(body);
  const result = {
    text: textLines.join("\n"),
    text_lines: textLines,
    line_count: textLines.length,
    has_text: textLines.length > 0,
    debug: {
      status: response.status,
      request_id: requestId,
      body_keys: bodyKeys,
      read_result_keys: body.readResult ? Object.keys(body.readResult) : []
    }
  };

  if (process.env.OCR_DEBUG_FULL_RESPONSE?.toLowerCase() === "true") {
    result.debug.raw_response = body;
  }

  fs.writeFileSync(outputPath, JSON.stringify(result));
  log(`Completed successfully. Extracted ${textLines.length} text lines.`);
}

module.exports = {
  getLinePosition,
  extractTextLines
};

if (require.main === module) {
  run().catch((error) => {
    const message = error?.message || String(error);
    logError(message);

    const outputPath = process.argv[3] ? path.resolve(process.argv[3]) : null;
    if (outputPath) {
      try {
        fs.writeFileSync(outputPath, JSON.stringify({ error: message }));
      } catch (writeErr) {
        logError(`Failed to write error output file: ${writeErr.message}`);
      }
    }
    process.exit(1);
  });
}
