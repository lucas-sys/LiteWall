/*
 * Particle Clock — exercises every Wallpaper Engine web host API.
 * Kept as a compatibility probe: a correct host must let this file run
 * without throwing, even when no media/audio source is available.
 */
(function () {
  'use strict';

  var canvas = document.getElementById('stage');
  var ctx = canvas.getContext('2d');
  var timeNode = document.getElementById('time');
  var captionNode = document.getElementById('caption');

  var state = {
    accent: [242, 140, 89],
    caption: 'STAY FOCUSED',
    count: 220,
    paused: false,
    fps: 30,
    audio: [],
    media: null,
    playback: 0,
    lastFrame: 0
  };
  var particles = [];
  var w = 0, h = 0, tick = 0;

  function resize() {
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    w = window.innerWidth; h = window.innerHeight;
    canvas.width = w * dpr; canvas.height = h * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    seed();
  }

  function seed() {
    particles = [];
    for (var i = 0; i < state.count; i++) {
      particles.push({
        x: Math.random() * w, y: Math.random() * h,
        vx: (Math.random() - 0.5) * 0.28, vy: (Math.random() - 0.5) * 0.28,
        r: Math.random() * 1.6 + 0.4, a: Math.random() * 0.5 + 0.1
      });
    }
  }

  function parseColor(v) {
    var p = String(v).trim().split(/\s+/).map(Number);
    return p.length === 3 && !p.some(isNaN)
      ? p.map(function (c) { return Math.round(Math.max(0, Math.min(1, c)) * 255); })
      : state.accent;
  }

  function render(now) {
    requestAnimationFrame(render);
    if (state.paused) return;
    if (now - state.lastFrame < 1000 / state.fps) return;
    state.lastFrame = now;
    tick += 1;

    var boost = state.audio.length
      ? state.audio.reduce(function (a, b) { return a + b; }, 0) / state.audio.length
      : 0;

    ctx.fillStyle = 'rgba(10, 11, 16, 0.28)';
    ctx.fillRect(0, 0, w, h);
    var c = state.accent;
    for (var i = 0; i < particles.length; i++) {
      var p = particles[i];
      p.x += p.vx * (1 + boost * 2); p.y += p.vy * (1 + boost * 2);
      if (p.x < 0 || p.x > w) p.vx *= -1;
      if (p.y < 0 || p.y > h) p.vy *= -1;
      ctx.fillStyle = 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + p.a + ')';
      ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2); ctx.fill();
    }

    if (tick % 15 === 0) {
      var d = new Date();
      timeNode.textContent = String(d.getHours()).padStart(2, '0') + ':'
        + String(d.getMinutes()).padStart(2, '0');
    }
  }

  // --- Full WE web host API surface ---------------------------------------

  window.wallpaperPropertyListener = {
    applyUserProperties: function (p) {
      if (!p) return;
      if (p.accent) state.accent = parseColor(p.accent.value);
      if (p.caption) { state.caption = String(p.caption.value); captionNode.textContent = state.caption; }
      if (p.count) { state.count = Number(p.count.value); seed(); }
    },
    applyGeneralProperties: function (p) {
      if (p && p.fps) state.fps = Math.max(1, Math.min(120, Number(p.fps) || 30));
    },
    setPaused: function (v) { state.paused = Boolean(v); },
    userDirectoryFilesAddedOrChanged: function (propertyName, files) {
      if (propertyName === 'slideshow' && files && files.length) {
        captionNode.dataset.files = String(files.length);
      }
    },
    userDirectoryFilesRemoved: function (propertyName) {
      if (propertyName === 'slideshow') captionNode.dataset.files = '0';
    }
  };

  if (typeof window.wallpaperRegisterAudioListener === 'function') {
    window.wallpaperRegisterAudioListener(function (bands) { state.audio = bands || []; });
  }
  if (typeof window.wallpaperRegisterMediaPropertiesListener === 'function') {
    window.wallpaperRegisterMediaPropertiesListener(function (info) { state.media = info; });
  }
  if (typeof window.wallpaperRegisterMediaThumbnailListener === 'function') {
    window.wallpaperRegisterMediaThumbnailListener(function () {});
  }
  if (typeof window.wallpaperRegisterMediaPlaybackListener === 'function') {
    window.wallpaperRegisterMediaPlaybackListener(function (v) { state.playback = v; });
  }
  if (typeof window.wallpaperRegisterMediaTimelineListener === 'function') {
    window.wallpaperRegisterMediaTimelineListener(function () {});
  }
  if (typeof window.wallpaperRegisterMediaStatusListener === 'function') {
    window.wallpaperRegisterMediaStatusListener(function () {});
  }
  if (typeof window.wallpaperRequestRandomFileForProperty === 'function') {
    window.wallpaperRequestRandomFileForProperty('slideshow', function (path) {
      if (path) state.slideshowFile = path;
    });
  }

  state.playback = window.wallpaperMediaIntegration
    ? window.wallpaperMediaIntegration.PLAYBACK_PLAYING : 1;
  if (window.wallpaperPluginListener && window.wallpaperPluginListener.onPluginLoaded) {
    window.wallpaperPluginListener.onPluginLoaded();
  }

  window.addEventListener('resize', resize);
  captionNode.textContent = state.caption;
  resize();
  requestAnimationFrame(render);
})();
