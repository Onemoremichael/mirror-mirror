#!/usr/bin/env node

import { createInterface } from "node:readline/promises";
import { stdin as input, stdout as output } from "node:process";

const host = process.env.MIRROR_HOST ?? "192.168.0.51";
const command = process.argv[2] ?? "status";
const encoder = new TextEncoder();
const decoder = new TextDecoder();

const TYPES = {
  identifyRequest: "com.mirror.proto.user.IdentifyRequest",
  identifyResponse: "com.mirror.proto.user.IdentifyResponse",
  pairRequest: "com.mirror.proto.oobe.PairRequest",
  pairResponse: "com.mirror.proto.oobe.PairResponse",
  screenRequest: "com.mirror.proto.navigation.MirrorScreenRequest",
  screenResponse: "com.mirror.proto.navigation.MirrorScreenResponse",
  packagesRequest: "com.mirror.proto.updater.GetInstalledPackageRequest",
  packagesResponse: "com.mirror.proto.updater.GetInstalledPackageResponse",
  featuresRequest: "com.mirror.proto.mirror.SupportedFeaturesRequest",
  featuresResponse: "com.mirror.proto.mirror.SupportedFeaturesResponse",
};

function varint(value) {
  let n = BigInt(value);
  const bytes = [];
  while (n >= 0x80n) {
    bytes.push(Number((n & 0x7fn) | 0x80n));
    n >>= 7n;
  }
  bytes.push(Number(n));
  return Uint8Array.from(bytes);
}

function concat(...parts) {
  const result = new Uint8Array(parts.reduce((size, part) => size + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

function varintField(tag, value) {
  return concat(varint(tag << 3), varint(value));
}

function bytesField(tag, bytes) {
  return concat(varint((tag << 3) | 2), varint(bytes.length), bytes);
}

function stringField(tag, value) {
  return bytesField(tag, encoder.encode(value));
}

function envelope(type, message = new Uint8Array()) {
  return concat(stringField(1, type), bytesField(2, message));
}

function identifyRequest() {
  return concat(
    stringField(1, "00000000-0000-4000-8000-000000000001"),
    stringField(2, "offline-local-control"),
    varintField(3, 2),
    stringField(4, "local-control@mirror.invalid"),
    stringField(5, "Local Control"),
    stringField(6, "offline-local-control"),
    stringField(7, "00000000-0000-4000-8000-000000000002"),
  );
}

function readVarint(bytes, start) {
  let value = 0n;
  let shift = 0n;
  let offset = start;
  while (offset < bytes.length) {
    const byte = bytes[offset++];
    value |= BigInt(byte & 0x7f) << shift;
    if ((byte & 0x80) === 0) return { value, offset };
    shift += 7n;
  }
  throw new Error("Truncated protobuf varint");
}

function fields(bytes) {
  const result = [];
  for (let offset = 0; offset < bytes.length;) {
    const key = readVarint(bytes, offset);
    offset = key.offset;
    const tag = Number(key.value >> 3n);
    const wireType = Number(key.value & 7n);
    if (wireType === 0) {
      const item = readVarint(bytes, offset);
      result.push({ tag, wireType, value: item.value });
      offset = item.offset;
    } else if (wireType === 2) {
      const size = readVarint(bytes, offset);
      offset = size.offset;
      const end = offset + Number(size.value);
      if (end > bytes.length) throw new Error("Truncated protobuf field");
      result.push({ tag, wireType, value: bytes.slice(offset, end) });
      offset = end;
    } else if (wireType === 1) {
      offset += 8;
    } else if (wireType === 5) {
      offset += 4;
    } else {
      throw new Error(`Unsupported protobuf wire type ${wireType}`);
    }
  }
  return result;
}

function first(items, tag) {
  return items.find((item) => item.tag === tag)?.value;
}

function decodeEnvelope(bytes) {
  const items = fields(bytes);
  const type = first(items, 1);
  return {
    type: type ? decoder.decode(type) : "",
    message: first(items, 2) ?? new Uint8Array(),
  };
}

function decodePackage(bytes) {
  const items = fields(bytes);
  const name = first(items, 1);
  const version = first(items, 2);
  return {
    name: name ? decoder.decode(name) : "",
    version: version ? decoder.decode(version) : "",
    versionCode: Number(first(items, 3) ?? 0n),
    installDate: Number(first(items, 4) ?? 0n),
  };
}

function decodeFeatures(bytes) {
  const items = fields(bytes);
  const names = {
    2: "plcWorkoutOnly",
    3: "cameraOnLocalRecording",
    4: "cameraOnStreamRecording",
    5: "cameraOnStreaming",
    6: "faceOff",
    7: "sleepModeControls",
    8: "backendEmojis",
    9: "musicControl",
    10: "findFriends",
    11: "packageReport",
    12: "connectedWeights",
    13: "uhsTicks",
  };
  const result = {
    musicTypes: items
      .filter((item) => item.tag === 1 && item.wireType === 0)
      .map((item) => Number(item.value)),
  };
  for (const [tag, name] of Object.entries(names)) {
    const value = first(items, Number(tag));
    if (value !== undefined) result[name] = value === 1n;
  }
  return result;
}

async function showStatus() {
  const response = await fetch(`http://${host}:8080/`, { signal: AbortSignal.timeout(4000) });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  console.log(JSON.stringify(await response.json(), null, 2));
}

async function runSocketCommand() {
  const terminal = createInterface({ input, output });
  const socket = new WebSocket(`ws://${host}:7000/socket`);
  socket.binaryType = "arraybuffer";

  await new Promise((resolve, reject) => {
    let commandSent = false;
    let timer;
    const finish = (error) => {
      clearTimeout(timer);
      terminal.close();
      socket.close();
      error ? reject(error) : resolve();
    };
    const armTimeout = (milliseconds, message) => {
      clearTimeout(timer);
      timer = setTimeout(() => finish(new Error(message)), milliseconds);
    };
    const sendCommand = () => {
      if (commandSent) return;
      commandSent = true;
      if (command === "features") {
        console.log("Requesting the Mirror's advertised feature flags…");
        socket.send(envelope(TYPES.featuresRequest));
        armTimeout(10_000, "No supported-features response received");
      } else if (command === "packages") {
        console.log("Requesting the installed-package inventory…");
        socket.send(envelope(TYPES.packagesRequest));
        armTimeout(15_000, "No installed-package response received");
      } else if (command === "dashboard") {
        console.log("Requesting the Mirror dashboard screen…");
        socket.send(envelope(TYPES.screenRequest, varintField(1, 1)));
        armTimeout(8_000, "No dashboard acknowledgement received");
      }
    };

    socket.addEventListener("open", () => {
      console.log(`Connected to Mirror ${host}; identifying local controller…`);
      socket.send(envelope(TYPES.identifyRequest, identifyRequest()));
      armTimeout(15_000, "No identification response received");
    });

    socket.addEventListener("message", async (event) => {
      try {
        const item = decodeEnvelope(new Uint8Array(event.data));
        console.log(`Mirror message: ${item.type || "(unknown)"} (${item.message.length} bytes)`);
        if (item.type === TYPES.identifyResponse) {
          const pairingRequired = first(fields(item.message), 1) === 1n;
          if (!pairingRequired) {
            sendCommand();
          } else {
            clearTimeout(timer);
            const pin = (await terminal.question("Enter the PIN shown on the Mirror: ")).trim();
            if (!/^\d+$/.test(pin)) return finish(new Error("PIN must contain only digits"));
            socket.send(envelope(TYPES.pairRequest, stringField(1, pin)));
            armTimeout(20_000, "No pairing response received");
          }
        } else if (item.type === TYPES.pairResponse) {
          const success = first(fields(item.message), 1) === 1n;
          if (!success) return finish(new Error("The Mirror rejected the PIN"));
          sendCommand();
        } else if (item.type === TYPES.packagesResponse) {
          const packages = fields(item.message)
            .filter((field) => field.tag === 1 && field.wireType === 2)
            .map((field) => decodePackage(field.value));
          console.table(packages);
          finish();
        } else if (item.type === TYPES.featuresResponse) {
          console.log(JSON.stringify(decodeFeatures(item.message), null, 2));
          finish();
        } else if (command === "dashboard" && (
          item.type === TYPES.screenResponse || item.type === "com.mirror.proto.DashboardMirrorUIState"
        )) {
          console.log("Dashboard request acknowledged.");
          finish();
        }
      } catch (error) {
        finish(error);
      }
    });

    socket.addEventListener("error", () => finish(new Error("WebSocket connection failed")));
    socket.addEventListener("close", () => {
      if (!commandSent) finish(new Error("Mirror closed the connection before accepting a command"));
    });
  });
}

if (!new Set(["status", "features", "packages", "dashboard"]).has(command)) {
  console.error("Usage: node mirror-control.mjs [status|features|packages|dashboard]");
  process.exit(1);
}

(command === "status" ? showStatus() : runSocketCommand()).catch((error) => {
  console.error(`Mirror command failed: ${error.message}`);
  process.exitCode = 1;
});
