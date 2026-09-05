#!/usr/bin/env node

import { execFile, spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const root = dirname(fileURLToPath(import.meta.url));
const host = process.env.MIRROR_REMOTE_HOST || '0.0.0.0';
const port = Number(process.env.MIRROR_REMOTE_PORT || 8765);
const adb = process.env.ADB_PATH || '/opt/homebrew/bin/adb';
const scrcpy = process.env.SCRCPY_PATH || '/opt/homebrew/bin/scrcpy';
const tokenFile = process.env.MIRROR_REMOTE_TOKEN_FILE || join(root, '.remote-control-token');
let knownMirrorHost = process.env.MIRROR_HOST || '';
let lastNetworkConnectAttempt = 0;

if (!existsSync(tokenFile)) {
  writeFileSync(tokenFile, randomBytes(8).toString('hex') + '\n', { mode: 0o600 });
}
const accessToken = readFileSync(tokenFile, 'utf8').trim();

// Keep the Mac reachable while it is on external power. The assertion ends
// automatically if this service stops, and does not block display sleep.
const keepAwake = spawn('/usr/bin/caffeinate', ['-s', '-w', String(process.pid)], {
  stdio: 'ignore',
});
keepAwake.unref();

const publicFiles = new Map([
  ['/', 'index.html'],
  ['/index.html', 'index.html'],
  ['/app.js', 'app.js'],
  ['/styles.css', 'styles.css'],
]);

const mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
};

const allowedKeys = new Map([
  ['back', '4'],
  ['home', '3'],
  ['recents', '187'],
  ['volumeUp', '24'],
  ['volumeDown', '25'],
  ['mute', '164'],
  ['wake', '224'],
  ['sleep', '223'],
  ['enter', '66'],
  ['escape', '111'],
  ['up', '19'],
  ['down', '20'],
  ['left', '21'],
  ['right', '22'],
  ['select', '23'],
]);

const allowedApps = new Map([
  ['dashboard', ['shell', 'am', 'start', '-n', 'dev.mirror.repurpose/.MainActivity']],
  ['settings', ['shell', 'am', 'start', '-a', 'android.settings.SETTINGS']],
]);

function json(response, status, value) {
  const body = Buffer.from(JSON.stringify(value));
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': body.length,
    'Cache-Control': 'no-store',
  });
  response.end(body);
}

async function bodyJson(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 16 * 1024) throw new Error('Request is too large');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
}

async function authorizedDevices() {
  const { stdout } = await execFileAsync(adb, ['devices'], { timeout: 5000 });
  return stdout
    .split(/\r?\n/)
    .slice(1)
    .map((line) => line.trim().split(/\s+/))
    .filter((parts) => parts.length >= 2 && parts[1] === 'device')
    .map((parts) => parts[0]);
}

async function refreshNetworkConnection(devices) {
  if (!knownMirrorHost && devices.includes('be9d0af')) {
    try {
      const { stdout } = await execFileAsync(adb, [
        '-s', 'be9d0af', 'shell', 'ip route 2>/dev/null | head -1',
      ], { timeout: 4000 });
      knownMirrorHost = stdout.match(/\bsrc\s+(\d+\.\d+\.\d+\.\d+)/)?.[1] || '';
    } catch (_) {}
  }
  if (!knownMirrorHost
      || !/^192\.168\.|^10\.|^172\.(1[6-9]|2\d|3[01])\./.test(knownMirrorHost)) return;
  if (Date.now() - lastNetworkConnectAttempt < 10000) return;
  lastNetworkConnectAttempt = Date.now();
  try {
    await execFileAsync(adb, ['connect', `${knownMirrorHost}:5555`], { timeout: 4000 });
  } catch (_) {}
}

async function mirrorSerial() {
  let devices = await authorizedDevices();
  await refreshNetworkConnection(devices);
  devices = await authorizedDevices();
  const requested = process.env.MIRROR_SERIAL;
  if (requested && devices.includes(requested)) return requested;
  return devices.find((serial) => /^192\.168\./.test(serial))
    || devices.find((serial) => serial === 'be9d0af')
    || devices[0]
    || null;
}

async function adbCall(args, options = {}) {
  const serial = await mirrorSerial();
  if (!serial) throw new Error('Mirror is not connected');
  return execFileAsync(adb, ['-s', serial, ...args], {
    timeout: options.timeout || 8000,
    maxBuffer: options.maxBuffer || 20 * 1024 * 1024,
    encoding: options.encoding,
  });
}

function number(value, minimum, maximum) {
  const parsed = Math.round(Number(value));
  if (!Number.isFinite(parsed) || parsed < minimum || parsed > maximum) {
    throw new Error('Coordinate is out of range');
  }
  return String(parsed);
}

async function status() {
  const serial = await mirrorSerial();
  if (!serial) return { connected: false };
  const { stdout } = await execFileAsync(adb, [
    '-s', serial, 'shell',
    'echo "$(getprop sys.boot_completed)|$(getprop wlan.driver.status)|$(ip route 2>/dev/null | head -1)|$(wm size 2>/dev/null | tail -1)"',
  ], { timeout: 5000 });
  const [booted, wifiDriver, route, display] = stdout.trim().split('|');
  return { connected: true, serial, booted: booted === '1', wifiDriver, route, display };
}

function requireToken(request) {
  return request.headers['x-mirror-token'] === accessToken;
}

const server = createServer(async (request, response) => {
  const url = new URL(request.url || '/', `http://${request.headers.host || 'localhost'}`);
  try {
    if (publicFiles.has(url.pathname) && request.method === 'GET') {
      const filename = join(root, publicFiles.get(url.pathname));
      const content = readFileSync(filename);
      response.writeHead(200, {
        'Content-Type': mimeTypes[extname(filename)] || 'application/octet-stream',
        'Content-Length': content.length,
        'Cache-Control': 'no-store',
      });
      response.end(content);
      return;
    }

    if (!url.pathname.startsWith('/api/') || !requireToken(request)) {
      json(response, 401, { error: 'Enter the Mirror remote access key' });
      return;
    }

    if (request.method === 'GET' && url.pathname === '/api/status') {
      json(response, 200, await status());
      return;
    }

    if (request.method === 'GET' && url.pathname === '/api/screen') {
      const { stdout } = await adbCall(['exec-out', 'screencap', '-p'], { encoding: 'buffer' });
      response.writeHead(200, {
        'Content-Type': 'image/png',
        'Content-Length': stdout.length,
        'Cache-Control': 'no-store, max-age=0',
      });
      response.end(stdout);
      return;
    }

    if (request.method === 'POST' && url.pathname === '/api/key') {
      const body = await bodyJson(request);
      const keyCode = allowedKeys.get(body.key);
      if (!keyCode) throw new Error('Unknown control key');
      if (body.key === 'wake') {
        // This display has no touch layer. Wake it and dismiss Android's
        // credential-free keyguard so the phone remote never strands the user.
        await adbCall(['shell', 'input', 'keyevent', keyCode]);
        await new Promise((resolve) => setTimeout(resolve, 180));
        await adbCall(['shell', 'input', 'keyevent', '82']);
      } else {
        await adbCall(['shell', 'input', 'keyevent', keyCode]);
      }
      json(response, 200, { ok: true });
      return;
    }

    if (request.method === 'POST' && url.pathname === '/api/tap') {
      const body = await bodyJson(request);
      await adbCall(['shell', 'input', 'tap', number(body.x, 0, 8192), number(body.y, 0, 8192)]);
      json(response, 200, { ok: true });
      return;
    }

    if (request.method === 'POST' && url.pathname === '/api/swipe') {
      const body = await bodyJson(request);
      await adbCall([
        'shell', 'input', 'swipe',
        number(body.x1, 0, 8192), number(body.y1, 0, 8192),
        number(body.x2, 0, 8192), number(body.y2, 0, 8192),
        number(body.duration || 250, 50, 3000),
      ]);
      json(response, 200, { ok: true });
      return;
    }

    if (request.method === 'POST' && url.pathname === '/api/text') {
      const body = await bodyJson(request);
      const value = String(body.text || '');
      if (!value || value.length > 300) throw new Error('Text must be 1–300 characters');
      await adbCall(['shell', 'input', 'text', value.replace(/ /g, '%s')]);
      json(response, 200, { ok: true });
      return;
    }

    if (request.method === 'POST' && url.pathname === '/api/app') {
      const body = await bodyJson(request);
      const args = allowedApps.get(body.app);
      if (!args) throw new Error('Unknown app');
      await adbCall(args);
      json(response, 200, { ok: true });
      return;
    }

    if (request.method === 'POST' && url.pathname === '/api/scrcpy') {
      const serial = await mirrorSerial();
      if (!serial) throw new Error('Mirror is not connected');
      const child = spawn(scrcpy, [
        '-s', serial, '--stay-awake', '--window-title', 'Mirror Control', '--no-audio',
      ], { detached: true, stdio: 'ignore' });
      child.unref();
      json(response, 200, { ok: true });
      return;
    }

    json(response, 404, { error: 'Control not found' });
  } catch (error) {
    json(response, 500, { error: error.message || 'Control failed' });
  }
});

server.listen(port, host, () => {
  console.log(`Mirror Remote is available at http://127.0.0.1:${port}`);
  console.log(`Access key: ${accessToken}`);
});
