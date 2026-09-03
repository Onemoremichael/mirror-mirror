#!/usr/bin/env node

import { createInterface } from "node:readline/promises";
import { stdin as input, stdout as output } from "node:process";
import { execFileSync } from "node:child_process";

// Replacement for the retired Studio app's local identification and Wi-Fi setup.
// Scan mode is read-only. Connect mode sends credentials entered locally; the
// password is hidden and is never written to disk or printed.
// Requires Node.js 22+ and a Mac connected to the Mirror's mirror-* access point.

const MIRROR_HOST = "192.168.43.1";
const STATUS_URL = `http://${MIRROR_HOST}:8080/`;
const SOCKET_URL = `ws://${MIRROR_HOST}:7000/socket`;
const IDENTIFY_REQUEST_TYPE = "com.mirror.proto.user.IdentifyRequest";
const PAIR_REQUEST_TYPE = "com.mirror.proto.oobe.PairRequest";
const OOBE_STEP_REQUEST_TYPE = "com.mirror.proto.oobe.OOBEStepRequest";
const CONNECTIVITY_REQUEST_TYPE = "com.mirror.proto.network.CheckConnectivityRequest";
const SCAN_REQUEST_TYPE = "com.mirror.proto.network.ScanRequest";
const CONNECT_REQUEST_TYPE = "com.mirror.proto.network.ConnectNetworkRequest";
const MODE = process.argv[2] ?? "scan";
const encoder = new TextEncoder();
const decoder = new TextDecoder();

function encodeVarint(value) {
  const bytes = [];
  let n = BigInt(value);
  while (n >= 0x80n) {
    bytes.push(Number((n & 0x7fn) | 0x80n));
    n >>= 7n;
  }
  bytes.push(Number(n));
  return Uint8Array.from(bytes);
}

function concat(...parts) {
  const length = parts.reduce((sum, part) => sum + part.length, 0);
  const result = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

function bytesField(tag, bytes) {
  return concat(encodeVarint((tag << 3) | 2), encodeVarint(bytes.length), bytes);
}

function varintField(tag, value) {
  return concat(encodeVarint(tag << 3), encodeVarint(value));
}

function stringField(tag, value) {
  return bytesField(tag, encoder.encode(value));
}

function makeEnvelope(type, message = new Uint8Array()) {
  return concat(stringField(1, type), bytesField(2, message));
}

function makeIdentifyRequest() {
  // Stable, local-only identifiers let a successful PIN pairing survive retries.
  return concat(
    stringField(1, "00000000-0000-4000-8000-000000000001"), // user id
    stringField(2, "offline-local-control"),                 // user token
    varintField(3, 2),                                       // PROD
    stringField(4, "local-control@mirror.invalid"),          // email
    stringField(5, "Local Control"),                         // name
    stringField(6, "offline-local-control"),                 // API token
    stringField(7, "00000000-0000-4000-8000-000000000002"), // device id
  );
}

function makeConnectRequest(ssid, password) {
  return concat(
    stringField(2, password), // pre-shared key
    stringField(3, ssid),
    varintField(4, 2),        // WPA/WPA2 PSK
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
    if (shift > 63n) throw new Error("Invalid protobuf varint");
  }
  throw new Error("Truncated protobuf varint");
}

function parseFields(bytes) {
  const fields = [];
  let offset = 0;
  while (offset < bytes.length) {
    const key = readVarint(bytes, offset);
    offset = key.offset;
    const tag = Number(key.value >> 3n);
    const wireType = Number(key.value & 7n);
    if (wireType === 0) {
      const item = readVarint(bytes, offset);
      fields.push({ tag, wireType, value: item.value });
      offset = item.offset;
    } else if (wireType === 2) {
      const size = readVarint(bytes, offset);
      offset = size.offset;
      const end = offset + Number(size.value);
      if (end > bytes.length) throw new Error("Truncated protobuf field");
      fields.push({ tag, wireType, value: bytes.slice(offset, end) });
      offset = end;
    } else if (wireType === 1) {
      offset += 8;
    } else if (wireType === 5) {
      offset += 4;
    } else {
      throw new Error(`Unsupported protobuf wire type ${wireType}`);
    }
  }
  return fields;
}

function firstField(fields, tag) {
  return fields.find((field) => field.tag === tag)?.value;
}

function decodeEnvelope(bytes) {
  const fields = parseFields(bytes);
  const typeBytes = firstField(fields, 1);
  const message = firstField(fields, 2) ?? new Uint8Array();
  return { type: typeBytes ? decoder.decode(typeBytes) : "", message };
}

function zigzagDecode(value) {
  return Number((value >> 1n) ^ -(value & 1n));
}

function decodeScanResult(bytes) {
  const fields = parseFields(bytes);
  const bssid = firstField(fields, 1);
  const ssid = firstField(fields, 2);
  const security = firstField(fields, 3);
  const strength = firstField(fields, 4);
  const rssi = firstField(fields, 5);
  return {
    ssid: ssid ? decoder.decode(ssid) : "",
    security: ["open", "WEP", "WPA/WPA2", "enterprise"][Number(security ?? 0n)] ?? `type-${security}`,
    strength: Number(strength ?? 0n),
    rssi: rssi === undefined ? null : zigzagDecode(rssi),
    bssid: bssid ? decoder.decode(bssid) : "",
  };
}

function decodeScanResults(bytes) {
  return parseFields(bytes)
    .filter((field) => field.tag === 1 && field.wireType === 2)
    .map((field) => decodeScanResult(field.value));
}

async function checkStatus() {
  const response = await fetch(STATUS_URL, { signal: AbortSignal.timeout(4000) });
  if (!response.ok) throw new Error(`Mirror status returned HTTP ${response.status}`);
  const status = await response.json();
  console.log(`Found Mirror ${status.serial ?? "(unknown)"}, OS ${status.os_version ?? "(unknown)"}.`);
}

async function promptForCredentials(terminal) {
  const ssid = (await terminal.question("Wi-Fi network name (SSID): ")).trim();
  if (!ssid) throw new Error("The Wi-Fi network name cannot be empty");

  output.write("Wi-Fi password (hidden): ");
  let password;
  try {
    execFileSync("/bin/stty", ["-echo"], { stdio: ["inherit", "ignore", "inherit"] });
    password = await terminal.question("");
  } finally {
    execFileSync("/bin/stty", ["echo"], { stdio: ["inherit", "ignore", "inherit"] });
    output.write("\n");
  }
  const validPassword = (password.length >= 8 && password.length <= 63) || /^[0-9a-fA-F]{64}$/.test(password);
  if (!validPassword) throw new Error("A WPA/WPA2 password must be 8–63 characters, or 64 hexadecimal characters");
  return { ssid, password };
}

async function run() {
  await checkStatus();
  const networks = new Map();
  const terminal = createInterface({ input, output });
  let credentials = null;
  try {
    credentials = MODE === "connect" ? await promptForCredentials(terminal) : null;
  } catch (error) {
    terminal.close();
    throw error;
  }
  const socket = new WebSocket(SOCKET_URL);
  socket.binaryType = "arraybuffer";

  await new Promise((resolve, reject) => {
    let opened = false;
    let scanSent = false;
    let connectSent = false;
    let setupStarted = false;
    let pairingPromptActive = false;
    let settleTimer;
    let phaseTimer;
    const setPhaseTimeout = (milliseconds, message) => {
      clearTimeout(phaseTimer);
      phaseTimer = setTimeout(() => {
        socket.close();
        terminal.close();
        if (networks.size > 0) resolve();
        else reject(new Error(message));
      }, milliseconds);
    };
    const sendConnect = () => {
      if (connectSent || socket.readyState !== WebSocket.OPEN || !credentials) return;
      connectSent = true;
      console.log(`Sending Wi-Fi settings for ${JSON.stringify(credentials.ssid)} to the Mirror…`);
      socket.send(makeEnvelope(CONNECT_REQUEST_TYPE, makeConnectRequest(credentials.ssid, credentials.password)));
      setPhaseTimeout(40_000, "The Mirror did not report whether it joined the Wi-Fi network");
    };
    const beginSetup = () => {
      if (setupStarted || socket.readyState !== WebSocket.OPEN) return;
      setupStarted = true;
      console.log("Identification accepted; entering the Mirror's network-setup step…");
      socket.send(makeEnvelope(OOBE_STEP_REQUEST_TYPE, varintField(1, 1)));
      if (MODE === "connect") {
        setPhaseTimeout(40_000, "The Mirror accepted pairing but did not begin Wi-Fi setup");
        setTimeout(sendConnect, 500);
        return;
      }
      socket.send(makeEnvelope(CONNECTIVITY_REQUEST_TYPE));
      setPhaseTimeout(30_000, "The Mirror accepted pairing but did not return network-setup data");
      // Old firmware may omit the connectivity reply, so do not wait forever.
      setTimeout(sendScan, 1_500);
    };
    const sendScan = () => {
      if (scanSent || socket.readyState !== WebSocket.OPEN) return;
      scanSent = true;
      console.log("Requesting a read-only Wi-Fi scan…");
      socket.send(makeEnvelope(SCAN_REQUEST_TYPE));
      setPhaseTimeout(30_000, "The Mirror accepted identification but did not return Wi-Fi scan results");
    };

    socket.addEventListener("open", () => {
      opened = true;
      console.log("Connected to the Mirror; sending the retired app's identification handshake…");
      socket.send(makeEnvelope(IDENTIFY_REQUEST_TYPE, makeIdentifyRequest()));
      setPhaseTimeout(20_000, "The Mirror did not answer the identification handshake");
    });

    socket.addEventListener("message", async (event) => {
      try {
        const envelope = decodeEnvelope(new Uint8Array(event.data));
        console.log(`Mirror message: ${envelope.type || "(unknown type)"} (${envelope.message.length} bytes)`);
        if (envelope.type === "com.mirror.proto.user.IdentifyResponse") {
          const pairingRequired = firstField(parseFields(envelope.message), 1) === 1n;
          if (!pairingRequired) {
            console.log("The Mirror recognizes this local controller.");
            beginSetup();
          } else if (!pairingPromptActive) {
            pairingPromptActive = true;
            clearTimeout(phaseTimer);
            console.log("\nPairing is required. Look at the Mirror for a PIN.");
            const pin = (await terminal.question("Enter the PIN shown on the Mirror: ")).trim();
            pairingPromptActive = false;
            if (!/^\d+$/.test(pin)) throw new Error("The PIN must contain only digits");
            console.log("Sending PIN to the Mirror…");
            socket.send(makeEnvelope(PAIR_REQUEST_TYPE, stringField(1, pin)));
            setPhaseTimeout(20_000, "The Mirror did not answer the PIN submission");
          }
        } else if (envelope.type === "com.mirror.proto.oobe.PairResponse") {
          const success = firstField(parseFields(envelope.message), 1) === 1n;
          if (success) {
            console.log("PIN accepted.");
            beginSetup();
          } else {
            throw new Error("The Mirror rejected that PIN; rerun the script to try again");
          }
        } else if (envelope.type === "com.mirror.proto.network.CheckConnectivityResponse") {
          sendScan();
        } else if (envelope.type === "com.mirror.proto.network.ConnectNetworkResponse") {
          const fields = parseFields(envelope.message);
          const success = firstField(fields, 1) === 1n;
          const failureType = Number(firstField(fields, 2) ?? 0n);
          if (!success) throw new Error(`The Mirror rejected the Wi-Fi connection (failure code ${failureType})`);
          console.log("The Mirror accepted the Wi-Fi connection.");
          clearTimeout(phaseTimer);
          setTimeout(() => {
            socket.close();
            resolve();
          }, 1_000);
        }
        if (envelope.type === "com.mirror.proto.network.ScanResponse") {
          const success = firstField(parseFields(envelope.message), 1);
          console.log(`Scan accepted: ${success === 1n ? "yes" : "no"}`);
        } else if (envelope.type === "com.mirror.proto.network.ScanResults") {
          for (const network of decodeScanResults(envelope.message)) {
            if (network.ssid) networks.set(network.ssid, network);
          }
          clearTimeout(settleTimer);
          settleTimer = setTimeout(() => {
            clearTimeout(phaseTimer);
            socket.close();
            resolve();
          }, 3_000);
        }
      } catch (error) {
        if (error.message.startsWith("The PIN") || error.message.startsWith("The Mirror rejected")) {
          clearTimeout(phaseTimer);
          clearTimeout(settleTimer);
          socket.close();
          terminal.close();
          reject(error);
        } else {
          console.error(`Ignored an unreadable Mirror message: ${error.message}`);
        }
      }
    });

    socket.addEventListener("error", () => {
      clearTimeout(phaseTimer);
      clearTimeout(settleTimer);
      terminal.close();
      reject(new Error("Could not open the Mirror WebSocket"));
    });

    socket.addEventListener("close", () => {
      if (connectSent) {
        clearTimeout(phaseTimer);
        console.log("The Mirror closed its setup connection while switching networks.");
        resolve();
      } else if (!opened) {
        clearTimeout(phaseTimer);
        reject(new Error("The Mirror closed the WebSocket before it opened"));
      }
    });
  });

  terminal.close();

  if (MODE === "connect") {
    console.log("Wi-Fi provisioning finished. Reconnect this Mac to its normal Wi-Fi and check the Mirror screen.");
    return;
  }

  const sorted = [...networks.values()].sort((a, b) => b.strength - a.strength);
  if (sorted.length === 0) throw new Error("The scan completed but returned no named networks");
  console.table(sorted);
}

if (Number(process.versions.node.split(".")[0]) < 22) {
  console.error("This script needs Node.js 22 or newer.");
  process.exit(1);
}

if (!new Set(["scan", "connect"]).has(MODE)) {
  console.error("Usage: node mirror-wifi-scan.mjs [scan|connect]");
  process.exit(1);
}

run().catch((error) => {
  console.error(`\nScan failed: ${error.message}`);
  console.error("Confirm that this Mac is connected to the Mirror's mirror-* Wi-Fi network, then try again.");
  process.exitCode = 1;
});
