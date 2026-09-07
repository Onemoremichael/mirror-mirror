import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { networkInterfaces } from 'node:os';

const root = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.PORT || 8766);
const state = { mode: 'orbit', palette: 'amber', dim: false, started: Date.now() };
const clients = new Set();
const files = { '/': ['index.html', 'text/html'], '/remote': ['index.html', 'text/html'], '/app.js': ['app.js', 'text/javascript'], '/style.css': ['style.css', 'text/css'] };
function publish() { clients.forEach(res => res.write('data: ' + JSON.stringify(state) + '\n\n')); }
const server = createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/events') {
    res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive' });
    clients.add(res); res.write('data: ' + JSON.stringify(state) + '\n\n');
    req.on('close', () => clients.delete(res)); return;
  }
  if (url.pathname === '/state' && req.method === 'POST') {
    // This server controls only the visual prototype; it has no device access.
    if (req.headers.origin && req.headers.origin !== 'http://' + req.headers.host) { res.writeHead(403); res.end(); return; }
    try {
      let body = '';
      for await (const chunk of req) { body += chunk; if (body.length > 1024) throw Error('Too large'); }
      const change = JSON.parse(body);
      if (['orbit', 'reset', 'drift', 'reflection'].includes(change.mode)) { state.mode = change.mode; state.started = Date.now(); }
      if (['amber', 'lilac', 'ice'].includes(change.palette)) state.palette = change.palette;
      if (typeof change.dim === 'boolean') state.dim = change.dim;
      publish(); res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(state));
    } catch { res.writeHead(400); res.end('Invalid change'); }
    return;
  }
  const file = files[url.pathname];
  if (!file) { res.writeHead(404); res.end('Not found'); return; }
  try { res.writeHead(200, { 'Content-Type': file[1], 'Cache-Control': 'no-store' }); res.end(await readFile(join(root, file[0]))); }
  catch { res.writeHead(500); res.end('Could not load prototype'); }
});
const heartbeat = setInterval(() => clients.forEach(res => res.write(': heartbeat\n\n')), 15000);
server.on('close', () => clearInterval(heartbeat));
server.listen(port, '0.0.0.0', () => {
  console.log('Afterglow display: http://localhost:' + port);
  Object.values(networkInterfaces()).flat().filter(i => i.family === 'IPv4' && !i.internal).forEach(i => console.log('Phone remote: http://' + i.address + ':' + port + '/remote'));
});
