(function () {
'use strict';
var state = {mode:'orbit',palette:'amber',dim:false};
var remote = location.pathname === '/remote';
var offline = location.protocol === 'file:';
var legacyCSS = '';
// Android 6 ships Chromium 44, before CSS custom properties and clamp().
function applyLegacyStyle() {
  if (!legacyCSS) return;
  var colors = {amber:['#c3a374','rgba(195,163,116,.1)'],lilac:['#ac9bc6','rgba(172,155,198,.1)'],ice:['#9abfbd','rgba(154,191,189,.1)']};
  var color = colors[state.palette] || colors.amber;
  var values = {ink:'#e9e6df',accent:color[0],muted:'#85847c',glow:color[1]};
  el('legacy-style').textContent = legacyCSS.replace(/var\(--([a-z]+)\)/g, function(_, key) { return values[key]; }).replace('clamp(76px,12vw,180px)', '12vw');
}
function el(id) { return document.getElementById(id); }
function render(next) {
  state = next;
  document.body.setAttribute('data-mode', state.mode);
  document.body.setAttribute('data-palette', state.palette);
  document.body.classList.toggle('dim', state.dim);
  Array.prototype.forEach.call(document.querySelectorAll('button[data-mode],button[data-palette]'), function(button) {
    var key = button.hasAttribute('data-mode') ? 'mode' : 'palette';
    var active = button.getAttribute('data-' + key) === state[key];
    button.classList.toggle('active', active); button.setAttribute('aria-pressed', active);
  });
  el('dim').setAttribute('aria-pressed', state.dim);
  applyLegacyStyle();
}
function change(value) {
  if (offline) { Object.keys(value).forEach(function(key) { state[key] = value[key]; }); render(state); return; }
  fetch('/state', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(value)})
    .then(function(response) { if (!response.ok) throw Error(); return response.json(); })
    .then(render).catch(function() { el('remote-status').textContent = 'Could not send change. Try again.'; });
}
Array.prototype.forEach.call(document.querySelectorAll('button[data-mode],button[data-palette]'), function(button) {
  button.onclick = function() { var key = button.hasAttribute('data-mode') ? 'mode' : 'palette'; var value = {}; value[key] = button.getAttribute('data-' + key); change(value); };
});
el('dim').onclick = function() { change({dim:!state.dim}); };
function tick() {
  var now = new Date();
  // Match the home timezone even though the recovered Android image uses GMT.
  var local = now.toLocaleTimeString('en-US', {timeZone:'America/New_York',hour:'numeric',minute:'2-digit',hour12:true});
  var parts = local.match(/(\d+):(\d+)\s*(AM|PM)/i);
  var hours = parts ? parts[1] : String(now.getHours() % 12 || 12);
  var minutes = parts ? parts[2] : ('0' + now.getMinutes()).slice(-2);
  el('hours').textContent = hours; el('minutes').textContent = minutes;
  el('clock').setAttribute('datetime', now.toISOString());
  el('clock').setAttribute('aria-label', hours + ':' + minutes + ' ' + (parts ? parts[3] : (now.getHours() >= 12 ? 'PM' : 'AM')));
  el('seconds-mark').style.transform = 'translateX(' + (now.getSeconds() * 57 / 59) + 'px)';
}
for (var i = 0; i < 60; i++) {
  var angle = i * Math.PI / 30;
  var radius = i % 5 === 0 ? 455 : 452;
  var line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
  line.setAttribute('x1', 500 + Math.sin(angle) * 448); line.setAttribute('y1', 500 - Math.cos(angle) * 448);
  line.setAttribute('x2', 500 + Math.sin(angle) * radius); line.setAttribute('y2', 500 - Math.cos(angle) * radius);
  el('ticks').appendChild(line);
}
document.body.classList.toggle('remote-only', remote);
if (!remote) {
  document.querySelector('.display').ondblclick = function() {
    var promise;
    if (document.fullscreenElement) promise = document.exitFullscreen();
    else if (document.documentElement.requestFullscreen) promise = document.documentElement.requestFullscreen();
    if (promise && promise.catch) promise.catch(function() {});
  };
}
document.addEventListener('keydown', function(event) {
  if (event.key === '1') change({mode:'orbit'});
  if (event.key === '2') change({mode:'drift'});
  if (event.key === '3') change({mode:'reflection'});
});
if (!window.CSS || !CSS.supports || !CSS.supports('--test', '0')) {
  var style = document.createElement('style'); style.id = 'legacy-style'; document.head.appendChild(style);
  var request = new XMLHttpRequest(); request.open('GET', './style.css');
  request.onload = function() { legacyCSS = request.responseText; applyLegacyStyle(); }; request.send();
}
if (!offline) {
  var events = new EventSource('/events');
  events.onmessage = function(event) { render(JSON.parse(event.data)); el('remote-status').textContent = 'Connected to the clock'; };
  events.onerror = function() { el('remote-status').textContent = 'Reconnecting…'; };
}
render(state); tick(); setInterval(tick, 1000);
}());
