#!/usr/bin/env node
// Bounded, read-only camera-output test. Requires the installed diagnostic APK.
// Captures private reports locally, never uploads images or changes firmware.
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const serial = process.env.MIRROR_SERIAL || 'be9d0af';
const count = Number(process.argv[2] || 3);
if (!Number.isInteger(count) || count < 1 || count > 10) throw Error('Use 1..10 attempts');
const destination = resolve('.work', `camera-startup-${Date.now()}`);
mkdirSync(destination, { recursive: true });
const adb = (...args) => execFileSync('adb', ['-s', serial, ...args],
  { encoding: 'utf8', timeout: 15000, maxBuffer: 1024 * 1024 });
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const report = () => adb('exec-out', 'run-as', 'dev.mirror.cameraprobe', 'cat', 'files/report.txt');
const idle = () => /Active Camera Clients:\s*\[\]/.test(adb('shell', 'dumpsys', 'media.camera'));
const results = [];
if (!idle()) throw Error('Camera already in use; close it before this test');
console.log(`Private reports: ${destination}`);
try {
  for (let attempt = 1; attempt <= count; attempt++) {
    adb('shell', 'am', 'force-stop', 'dev.mirror.cameraprobe');
    // Prevent a failed launch from reusing the previous attempt's frame counts.
    adb('shell', 'run-as', 'dev.mirror.cameraprobe', 'rm', '-f', 'files/report.txt');
    adb('shell', 'input', 'keyevent', '224');
    adb('shell', 'wm', 'dismiss-keyguard');
    adb('shell', 'am', 'start', '-n', 'dev.mirror.cameraprobe/.ProbeActivity',
      '--ez', 'autoRotation', 'true');
    let current = '', frames = 0;
    const began = Date.now();
    while (Date.now() - began < 25000) {
      await pause(2000);
      try { current = report(); }
      catch (error) {
        if (String(error.stderr).includes('No such file')) continue;
        throw error;
      }
      if (current.includes('CAMERA_RELEASED')) throw Error('Preview was interrupted before measurement');
      frames = Math.max(0, ...Array.from(current.matchAll(/^FRAME (\d+)/gm), m => Number(m[1])));
      if (frames >= 300 || /OPEN_ERROR|CAMERA_ERROR/.test(current)) break;
    }
    const power = adb('shell', 'dumpsys', 'power');
    writeFileSync(resolve(destination, `${attempt}-preview.txt`), current);
    writeFileSync(resolve(destination, `${attempt}-power.txt`), power);
    const first = current.match(/^FRAME 1 .*$/m)?.[0] || 'No first-frame report';
    console.log(`Attempt ${attempt}: reported frames=${frames}; ${first}`);
    adb('shell', 'input', 'keyevent', '3');
    const closing = Date.now();
    let released = false;
    while (Date.now() - closing < 20000) {
      await pause(1000);
      current = report();
      if (idle() && (current.includes('CAMERA_RELEASED') || !current.includes('DEFAULT '))) {
        released = true; break;
      }
    }
    writeFileSync(resolve(destination, `${attempt}-complete.txt`), current);
    results.push({ attempt, frames, first, released });
    writeFileSync(resolve(destination, 'summary.json'), JSON.stringify(results, null, 2));
    if (!released) throw Error('Camera did not release cleanly; stopping without another open');
  }
} finally {
  adb('shell', 'input', 'keyevent', '3');
}
console.log(JSON.stringify(results, null, 2));
// Frame arrival is not proof of image quality; inspect reports/images separately.
if (results.some(result => result.frames < 300 || !result.released)) process.exitCode = 1;
