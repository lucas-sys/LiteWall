/*
 * LiteWall — Wallpaper Engine "web" host compatibility shim.
 *
 * Injected with WKUserScript at document start, BEFORE any author script.
 * Implements the 10 documented window.wallpaper* author APIs. See
 * docs/REA-FINDINGS.md for the evidence-backed API inventory.
 *
 * Design rules:
 *   - Property listener callbacks are deferred to a microtask. Delivering them
 *     synchronously inside the setter re-enters author render loops and can
 *     blank React-based wallpapers.
 *   - No fake audio spectrum is generated. A host without a capture source
 *     registers the listener but pushes nothing.
 *   - Every author callback is wrapped: a throwing wallpaper cannot take down
 *     the host process.
 */
(function () {
  'use strict';

  var seed = window.__weSeed || {};
  var properties = seed.properties || {};
  var general = seed.general || { fps: 30 };
  var paused = !!seed.paused;
  var muted = seed.muted !== false;
  var mediaLevel = typeof seed.volume === 'number' ? Math.max(0, Math.min(1, seed.volume)) : 0;
  var assets = Array.isArray(seed.assets) ? seed.assets.slice() : [];
  var assetBase = String(seed.assetBase || '');
  var pools = Object.create(null);

  var listeners = {
    property: null,
    audio: [],
    mediaProperties: [],
    mediaThumbnail: [],
    mediaPlayback: [],
    mediaTimeline: [],
    mediaStatus: []
  };
  var lastFrame = {
    mediaProperties: null,
    mediaThumbnail: null,
    mediaPlayback: null,
    mediaTimeline: null,
    mediaStatus: null
  };
  var initialDelivered = false;

  function clone(value) {
    try { return JSON.parse(JSON.stringify(value)); } catch (e) { return value; }
  }
  function safe(fn, args) {
    try { return fn.apply(undefined, args); }
    catch (e) { if (window.console && console.warn) console.warn('[LiteWall] listener error:', e); }
  }
  function microtask(fn) {
    if (typeof queueMicrotask === 'function') queueMicrotask(fn);
    else Promise.resolve().then(fn);
  }
  function notify(list, args) {
    for (var i = 0; i < list.length; i++) {
      if (typeof list[i] === 'function') safe(list[i], args);
    }
  }
  function mediaElements() {
    if (!document || !document.querySelectorAll) return [];
    return document.querySelectorAll('video, audio');
  }

  // --- 1. wallpaperPropertyListener ---------------------------------------
  function deliverInitial() {
    var l = listeners.property;
    if (!l || initialDelivered) return;
    initialDelivered = true;
    if (typeof l.applyUserProperties === 'function') safe(l.applyUserProperties, [clone(properties)]);
    if (typeof l.applyGeneralProperties === 'function') safe(l.applyGeneralProperties, [clone(general)]);
    if (paused && typeof l.setPaused === 'function') safe(l.setPaused, [true]);
  }

  Object.defineProperty(window, 'wallpaperPropertyListener', {
    configurable: true,
    get: function () { return listeners.property; },
    set: function (value) {
      var next = (value && typeof value === 'object') ? value : null;
      // Re-assigning the same object must not replay the snapshot.
      if (next === listeners.property && initialDelivered) return;
      listeners.property = next;
      initialDelivered = false;
      microtask(deliverInitial);
    }
  });

  // --- 2..7. register* listeners ------------------------------------------
  window.wallpaperRegisterAudioListener = function (cb) {
    if (typeof cb === 'function') listeners.audio.push(cb);
  };

  function registerMedia(kind) {
    return function (cb) {
      if (typeof cb !== 'function') return;
      listeners[kind].push(cb);
      // Late registrants replay the most recent frame.
      if (lastFrame[kind] !== null) {
        var frame = lastFrame[kind];
        microtask(function () { safe(cb, [frame]); });
      }
    };
  }
  window.wallpaperRegisterMediaPropertiesListener = registerMedia('mediaProperties');
  window.wallpaperRegisterMediaThumbnailListener = registerMedia('mediaThumbnail');
  window.wallpaperRegisterMediaPlaybackListener = registerMedia('mediaPlayback');
  window.wallpaperRegisterMediaTimelineListener = registerMedia('mediaTimeline');
  window.wallpaperRegisterMediaStatusListener = registerMedia('mediaStatus');

  // --- 8. wallpaperRequestRandomFileForProperty ----------------------------
  window.wallpaperRequestRandomFileForProperty = function (propertyName, callback) {
    if (typeof callback !== 'function') return;
    var pool = pools[propertyName] || assets;
    // Wallpaper Engine calls back with an empty string when the pool is empty;
    // author code almost always guards with `if (path)`.
    var value = pool.length ? pool[Math.floor(Math.random() * pool.length)] : '';
    microtask(function () { safe(callback, [propertyName, value]); });
  };

  // --- 9. wallpaperMediaIntegration ----------------------------------------
  window.wallpaperMediaIntegration = {
    PLAYBACK_STOPPED: 0,
    PLAYBACK_PLAYING: 1,
    PLAYBACK_PAUSED: 2
  };

  // --- 10. wallpaperPluginListener -----------------------------------------
  window.wallpaperPluginListener = { onPluginLoaded: function () {} };

  // --- file:/// compatibility ----------------------------------------------
  // Author code commonly does `'file:///' + path`. On Windows `path` is an
  // absolute drive path that cannot be mapped on macOS. For relative, flat
  // filenames (as returned by wallpaperRequestRandomFileForProperty) we
  // resolve against the wallpaper directory. Absolute paths are left alone.
  (function installImageSrcHook() {
    if (!assetBase || typeof HTMLImageElement === 'undefined') return;
    try {
      var desc = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, 'src');
      if (!desc || !desc.set || !desc.configurable) return;
      Object.defineProperty(HTMLImageElement.prototype, 'src', {
        configurable: true,
        enumerable: desc.enumerable,
        get: function () { return desc.get.call(this); },
        set: function (value) {
          if (typeof value === 'string' && value.indexOf('file:///') === 0) {
            var rest = value.slice(8);
            if (rest && rest.indexOf('/') === -1 && rest.indexOf('\\') === -1) {
              value = assetBase + encodeURIComponent(rest);
            }
          }
          desc.set.call(this, value);
        }
      });
    } catch (e) { /* Non-fatal: fall back to unmodified author behaviour. */ }
  })();

  // --- Native control bridge -----------------------------------------------
  function applyMediaVolume() {
    var elements = mediaElements();
    for (var i = 0; i < elements.length; i++) {
      try {
        elements[i].muted = muted || mediaLevel <= 0;
        elements[i].volume = mediaLevel;
      } catch (e) { /* ignore */ }
    }
  }

  // Media elements created after the shim runs still inherit the host volume.
  if (document && document.addEventListener) {
    document.addEventListener('loadeddata', function () { applyMediaVolume(); }, true);
  }

  window.__weBridge = {
    version: '1.0.0',
    ready: true,

    setPaused: function (value) {
      paused = !!value;
      var l = listeners.property;
      if (l && typeof l.setPaused === 'function') safe(l.setPaused, [paused]);
      var elements = mediaElements();
      for (var i = 0; i < elements.length; i++) {
        try {
          if (paused) elements[i].pause();
          else {
            var p = elements[i].play();
            if (p && typeof p.catch === 'function') p.catch(function () {});
          }
        } catch (e) { /* ignore */ }
      }
    },

    applyProperties: function (delta) {
      if (!delta || typeof delta !== 'object') return;
      for (var key in delta) {
        if (Object.prototype.hasOwnProperty.call(delta, key)) properties[key] = delta[key];
      }
      var l = listeners.property;
      if (l && typeof l.applyUserProperties === 'function') {
        safe(l.applyUserProperties, [clone(delta)]);
      }
    },

    applyGeneral: function (delta) {
      if (!delta || typeof delta !== 'object') return;
      for (var key in delta) {
        if (Object.prototype.hasOwnProperty.call(delta, key)) general[key] = delta[key];
      }
      var l = listeners.property;
      if (l && typeof l.applyGeneralProperties === 'function') {
        safe(l.applyGeneralProperties, [clone(delta)]);
      }
    },

    pushAudio: function (bands) {
      // Matches Wallpaper Engine: no spectrum is delivered while paused.
      if (paused || !Array.isArray(bands)) return;
      notify(listeners.audio, [bands]);
    },

    pushMedia: function (kind, payload) {
      if (!Object.prototype.hasOwnProperty.call(listeners, kind)) return;
      lastFrame[kind] = payload;
      notify(listeners[kind], [payload]);
    },

    setAssets: function (list) {
      assets = Array.isArray(list) ? list.slice(0, 2000) : [];
    },

    directoryAdded: function (propertyName, files) {
      pools[propertyName] = Array.isArray(files) ? files.slice(0, 2000) : [];
      var l = listeners.property;
      if (l && typeof l.userDirectoryFilesAddedOrChanged === 'function') {
        safe(l.userDirectoryFilesAddedOrChanged, [propertyName, pools[propertyName]]);
      }
    },

    directoryRemoved: function (propertyName, files) {
      pools[propertyName] = [];
      var l = listeners.property;
      if (l && typeof l.userDirectoryFilesRemoved === 'function') {
        safe(l.userDirectoryFilesRemoved, [propertyName, files || []]);
      }
    },

    setVolume: function (level) {
      mediaLevel = Math.max(0, Math.min(1, Number(level) || 0));
      muted = mediaLevel <= 0;
      applyMediaVolume();
    },

    state: function () {
      return { paused: paused, properties: clone(properties), general: clone(general), assets: assets.length };
    }
  };

  // Announce readiness to the native host (WKScriptMessageHandler).
  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.litewall) {
    window.webkit.messageHandlers.litewall.postMessage({ op: 'ready', version: '1.0.0' });
  }
})();
