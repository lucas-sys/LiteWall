/*
 * Aurora Flow — Wallpaper Engine "web" wallpaper.
 *
 * Runtime contract used here (all supplied by the WE-compatible host):
 *   window.wallpaperPropertyListener.applyUserProperties(properties)
 *   window.wallpaperPropertyListener.applyGeneralProperties(properties)
 *   window.wallpaperPropertyListener.setPaused(isPaused)
 *   window.wallpaperRegisterAudioListener(callback)
 *
 * This file is intentionally dependency-free: pure Canvas 2D, no network.
 */

(function () {
  'use strict';

  var canvas = document.getElementById('stage');
  var ctx = canvas.getContext('2d', { alpha: false });
  var clockNode = document.getElementById('clock');

  var state = {
    color: [69, 199, 212],
    speed: 0.6,
    density: 170,
    showClock: true,
    style: 'ribbon',
    fps: 30,
    paused: false,
    audioLevel: 0
  };

  var stars = [];
  var ribbons = [];
  var width = 0;
  var height = 0;
  var dpr = 1;
  var lastFrame = 0;
  var frameInterval = 1000 / state.fps;
  var elapsed = 0;

  function hexFromNormalized(triplet) {
    var parts = String(triplet).trim().split(/\s+/).map(Number);
    if (parts.length !== 3 || parts.some(isNaN)) return [69, 199, 212];
    return parts.map(function (c) { return Math.round(Math.max(0, Math.min(1, c)) * 255); });
  }

  function resize() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    width = window.innerWidth;
    height = window.innerHeight;
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    seedStars();
    seedRibbons();
  }

  function seedStars() {
    stars = [];
    var count = Math.round(state.density * (width * height) / (1440 * 900));
    for (var i = 0; i < count; i++) {
      stars.push({
        x: Math.random() * width,
        y: Math.random() * height * 0.82,
        r: Math.random() * 1.2 + 0.2,
        a: Math.random() * 0.6 + 0.15,
        phase: Math.random() * Math.PI * 2
      });
    }
  }

  function seedRibbons() {
    ribbons = [];
    for (var i = 0; i < 4; i++) {
      ribbons.push({ offset: i * 1.7, alpha: 0.16 - i * 0.028, thickness: 190 + i * 62 });
    }
  }

  function rgba(c, a) {
    return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')';
  }

  function drawBackground() {
    var g = ctx.createLinearGradient(0, 0, 0, height);
    g.addColorStop(0, '#050914');
    g.addColorStop(0.55, '#081426');
    g.addColorStop(1, '#0b1c2c');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, width, height);
  }

  function drawStars(t) {
    ctx.save();
    for (var i = 0; i < stars.length; i++) {
      var s = stars[i];
      var twinkle = 0.65 + 0.35 * Math.sin(t * 0.0012 + s.phase);
      ctx.globalAlpha = s.a * twinkle;
      ctx.fillStyle = '#dff4ff';
      ctx.beginPath();
      ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  function drawRibbon(ribbon, t) {
    var c = state.color;
    var amp = height * (state.style === 'wave' ? 0.10 : 0.16);
    var baseY = height * 0.42 + ribbon.offset * 22;
    var energy = 1 + state.audioLevel * 0.45;

    ctx.beginPath();
    ctx.moveTo(0, height);
    for (var x = 0; x <= width; x += 12) {
      var n = x / width;
      var y = baseY
        + Math.sin(n * 3.2 + t * 0.00026 * state.speed + ribbon.offset) * amp
        + Math.sin(n * 7.4 - t * 0.00041 * state.speed + ribbon.offset * 2) * amp * 0.34;
      ctx.lineTo(x, y);
    }
    ctx.lineTo(width, height);
    ctx.closePath();

    var g = ctx.createLinearGradient(0, baseY - amp, 0, height);
    g.addColorStop(0, rgba(c, ribbon.alpha * energy));
    g.addColorStop(0.35, rgba(c, ribbon.alpha * 0.35));
    g.addColorStop(1, rgba(c, 0));
    ctx.fillStyle = g;
    ctx.fill();

    ctx.beginPath();
    for (var x2 = 0; x2 <= width; x2 += 12) {
      var n2 = x2 / width;
      var y2 = baseY
        + Math.sin(n2 * 3.2 + t * 0.00026 * state.speed + ribbon.offset) * amp
        + Math.sin(n2 * 7.4 - t * 0.00041 * state.speed + ribbon.offset * 2) * amp * 0.34;
      if (x2 === 0) ctx.moveTo(x2, y2); else ctx.lineTo(x2, y2);
    }
    ctx.strokeStyle = rgba(c, ribbon.alpha * 1.8);
    ctx.lineWidth = 1.4;
    ctx.stroke();
  }

  function drawClock() {
    if (!state.showClock) {
      clockNode.style.display = 'none';
      return;
    }
    clockNode.style.display = 'block';
    var d = new Date();
    var hh = String(d.getHours()).padStart(2, '0');
    var mm = String(d.getMinutes()).padStart(2, '0');
    clockNode.textContent = hh + ':' + mm;
  }

  function frame(now) {
    requestAnimationFrame(frame);
    if (state.paused) { lastFrame = now; return; }
    if (now - lastFrame < frameInterval) return;
    var dt = Math.min(now - lastFrame, 100);
    lastFrame = now;
    elapsed += dt * state.speed;

    drawBackground();
    drawStars(elapsed);
    for (var i = 0; i < ribbons.length; i++) drawRibbon(ribbons[i], elapsed);
    drawClock();
  }

  // --- Wallpaper Engine host contract -------------------------------------

  // Must be assigned as a global, outside any event handler: the host may
  // deliver the initial property snapshot before DOMContentLoaded.
  window.wallpaperPropertyListener = {
    applyUserProperties: function (properties) {
      if (!properties) return;
      if (properties.schemecolor) state.color = hexFromNormalized(properties.schemecolor.value);
      if (properties.speed) state.speed = Number(properties.speed.value) || 0.6;
      if (properties.density) { state.density = Number(properties.density.value); seedStars(); }
      if (properties.showclock) state.showClock = Boolean(properties.showclock.value);
      if (properties.style) state.style = String(properties.style.value);
    },
    applyGeneralProperties: function (properties) {
      if (properties && properties.fps) {
        state.fps = Math.max(1, Math.min(120, Number(properties.fps) || 30));
        frameInterval = 1000 / state.fps;
      }
    },
    setPaused: function (isPaused) {
      state.paused = Boolean(isPaused);
      if (!state.paused) lastFrame = performance.now();
    }
  };

  if (typeof window.wallpaperRegisterAudioListener === 'function') {
    window.wallpaperRegisterAudioListener(function (bands) {
      if (!bands || !bands.length) { state.audioLevel = 0; return; }
      var sum = 0;
      for (var i = 0; i < bands.length; i++) sum += bands[i];
      state.audioLevel = Math.min(1, sum / bands.length);
    });
  }

  if (window.wallpaperMediaIntegration) {
    // Referenced so hosts that omit the object do not break playback-state logic.
    state.playbackPlaying = window.wallpaperMediaIntegration.PLAYBACK_PLAYING;
  }

  window.addEventListener('resize', resize);
  resize();
  requestAnimationFrame(frame);
})();
