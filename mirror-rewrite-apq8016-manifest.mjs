#!/usr/bin/env node

import { readFile, writeFile } from 'node:fs/promises';
import { basename } from 'node:path';

const [inputPath, outputPath] = process.argv.slice(2);

if (!inputPath || !outputPath) {
  console.error(`Usage: ${basename(process.argv[1])} INPUT.xml OUTPUT.xml`);
  process.exit(2);
}

const original = await readFile(inputPath, 'utf8');
let seenProjectCount = 0;
let emittedProjectCount = 0;

const fallbackRepos = new Map([
  ['platform/developers/build', 'CodeLinaro-mirror/la_platform_developers_build'],
  ['platform/external/chromium-webview', 'fairphone-mirror/fp2-dev_platform_external_chromium-webview'],
  ['platform/external/google-breakpad', 'msft-mirror-aosp/platform.external.google-breakpad'],
  ['platform/external/svox', 'CodeLinaro-mirror/la_platform_external_svox'],
  ['platform/frameworks/base', 'AOSParadox/android_frameworks_base'],
  ['platform/prebuilts/qemu-kernel', 'msft-mirror-aosp/platform.prebuilts.qemu-kernel'],
  ['platform/prebuilts/tools', 'fairphone-mirror/fp2-dev_platform_prebuilts_tools'],
]);

// This pinned object remains available from CodeLinaro even though the
// archival GitHub copy is incomplete.
const codeLinaroProjects = new Set([
  'platform/prebuilts/sdk',
]);

const unusedProjects = new Set([
  'device/lge/hammerhead-kernel',
  // Legacy Eclipse/ADT packaging; it is not used by an Android platform build,
  // and no public mirror retains the manifest's pinned object.
  'platform/external/eclipse-basebuilder',
  'platform/prebuilts/eclipse',
]);

const rewritten = original
  .replace(
    /<remote\s+fetch="[^"]+"\s+name="caf"(?:\s+review="[^"]+")?\s*\/>/,
    '<remote fetch="https://github.com/RSB4760/" name="github"/>\n' +
      '  <remote fetch="https://github.com/" name="root-github"/>\n' +
      '  <remote fetch="https://git.codelinaro.org/clo/la/" name="codelinaro"/>',
  )
  .replace(/<default\s+remote="caf"/, '<default remote="github"')
  .split('\n')
  .map((line) => {
    if (!line.includes('<project ')) return line;

    const nameMatch = line.match(/\bname="([^"]+)"/);
    if (!nameMatch) throw new Error(`Project without a name: ${line}`);

    const pathMatch = line.match(/\bpath="([^"]+)"/);
    const originalName = nameMatch[1];
    seenProjectCount += 1;
    if (unusedProjects.has(originalName)) return null;

    const checkoutPath = pathMatch?.[1] ?? originalName;
    // The archival organization removed CodeAurora's leading "platform/"
    // namespace, retained other project names, and shortened msm-3.10 to the
    // checkout path used by the Android tree.
    const mirrorPath = originalName === 'kernel/msm-3.10'
      ? checkoutPath
      : originalName.replace(/^platform\//, '');
    const fallbackRepo = fallbackRepos.get(originalName);
    const useCodeLinaro = codeLinaroProjects.has(originalName);
    const githubName = useCodeLinaro
      ? originalName
      : fallbackRepo ?? `apq8016_${mirrorPath.replaceAll('/', '_')}`;

    let result = line.replace(nameMatch[0], `name="${githubName}"`);
    if (!pathMatch) {
      result = result.replace(
        `name="${githubName}"`,
        `name="${githubName}" path="${checkoutPath}"`,
      );
    }
    if (useCodeLinaro) {
      result = result.replace('<project ', '<project remote="codelinaro" ');
    } else if (fallbackRepo) {
      result = result.replace('<project ', '<project remote="root-github" ');
    }
    result = result.replace(/\s+upstream="[^"]+"/g, '');
    emittedProjectCount += 1;
    return result;
  })
  .filter((line) => line !== null)
  .join('\n');

if (seenProjectCount !== 450 || emittedProjectCount !== 447) {
  throw new Error(
    `Expected to see 450 projects and emit 447; saw ${seenProjectCount} and emitted ${emittedProjectCount}`,
  );
}

await writeFile(outputPath, rewritten);
console.log(`Rewrote ${emittedProjectCount} pinned projects for public GitHub mirrors.`);
