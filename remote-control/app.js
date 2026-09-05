const connection = document.querySelector('#connection');
const login = document.querySelector('#login');
const remote = document.querySelector('#remote');
const screen = document.querySelector('#screen');
const screenMessage = document.querySelector('#screen-message');
let token = localStorage.getItem('mirrorRemoteToken') || '';
let refreshing = false;
let pointerStart = null;

async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    cache: 'no-store',
    headers: { 'X-Mirror-Token': token, 'Content-Type': 'application/json', ...(options.headers || {}) },
  });
  if (response.status === 401) {
    token = '';
    localStorage.removeItem('mirrorRemoteToken');
    login.hidden = false;
    remote.hidden = true;
    throw new Error('Access key required');
  }
  const type = response.headers.get('content-type') || '';
  const result = type.includes('application/json') ? await response.json() : response;
  if (!response.ok) throw new Error(result.error || 'Remote control failed');
  return result;
}

async function refreshStatus() {
  try {
    const value = await api('/api/status');
    connection.textContent = value.connected ? 'Online' : 'Mirror offline';
    connection.classList.toggle('online', value.connected);
  } catch (error) {
    connection.textContent = error.message;
    connection.classList.remove('online');
  }
}

async function refreshScreen() {
  if (refreshing || remote.hidden) return;
  refreshing = true;
  try {
    const response = await fetch(`/api/screen?t=${Date.now()}`, {
      cache: 'no-store', headers: { 'X-Mirror-Token': token },
    });
    if (!response.ok) throw new Error(response.status === 401 ? 'Access key required' : 'Screen unavailable');
    const blob = await response.blob();
    const previous = screen.src;
    screen.src = URL.createObjectURL(blob);
    screenMessage.hidden = true;
    if (previous.startsWith('blob:')) URL.revokeObjectURL(previous);
    connection.textContent = 'Online';
    connection.classList.add('online');
  } catch (error) {
    screenMessage.hidden = false;
    screenMessage.textContent = error.message;
    connection.textContent = 'Reconnecting…';
    connection.classList.remove('online');
  } finally {
    refreshing = false;
  }
}

function send(path, body) {
  return api(path, { method: 'POST', body: JSON.stringify(body) })
    .then(() => setTimeout(refreshScreen, 180))
    .catch((error) => { connection.textContent = error.message; });
}

document.querySelector('#login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  token = document.querySelector('#token').value.trim();
  try {
    const value = await api('/api/status');
    localStorage.setItem('mirrorRemoteToken', token);
    login.hidden = true;
    remote.hidden = false;
    connection.textContent = value.connected ? 'Online' : 'Mirror offline';
    connection.classList.toggle('online', value.connected);
    refreshScreen();
  } catch (error) {
    connection.textContent = error.message;
    connection.classList.remove('online');
  }
});

document.querySelectorAll('[data-key]').forEach((button) => {
  button.addEventListener('click', () => send('/api/key', { key: button.dataset.key }));
});

document.querySelectorAll('[data-app]').forEach((button) => {
  button.addEventListener('click', () => send('/api/app', { app: button.dataset.app }));
});

document.querySelector('#text-form').addEventListener('submit', (event) => {
  event.preventDefault();
  const field = document.querySelector('#text');
  if (field.value) send('/api/text', { text: field.value });
  field.value = '';
});

document.querySelector('#open-mac').addEventListener('click', () => send('/api/scrcpy', {}));

function point(event) {
  const rect = screen.getBoundingClientRect();
  return {
    x: (event.clientX - rect.left) * screen.naturalWidth / rect.width,
    y: (event.clientY - rect.top) * screen.naturalHeight / rect.height,
  };
}

screen.addEventListener('pointerdown', (event) => {
  pointerStart = { ...point(event), time: Date.now() };
  screen.setPointerCapture(event.pointerId);
});

screen.addEventListener('pointerup', (event) => {
  if (!pointerStart) return;
  const end = point(event);
  const distance = Math.hypot(end.x - pointerStart.x, end.y - pointerStart.y);
  if (distance < 20) {
    send('/api/tap', end);
  } else {
    send('/api/swipe', {
      x1: pointerStart.x, y1: pointerStart.y, x2: end.x, y2: end.y,
      duration: Math.max(80, Math.min(1200, Date.now() - pointerStart.time)),
    });
  }
  pointerStart = null;
});

if (token) {
  login.hidden = true;
  remote.hidden = false;
  refreshStatus();
  refreshScreen();
}
setInterval(refreshScreen, 900);
setInterval(refreshStatus, 10000);
