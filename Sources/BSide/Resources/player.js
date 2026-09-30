// B-Side player page: YouTube Music's player without YouTube Music's UI.
//
// The web view holds an empty local document that was given the
// music.youtube.com origin (see PlayerController.loadHome). Nothing on it
// creates a player, so this script does:
//   1. fetches the real home page as text and reads the player configuration
//      (`ytcfg`) out of it,
//   2. loads the player script that configuration names,
//   3. creates a player with `yt.player.Application.create`.
// Google's player still does all the stream work; this only replaces the UI
// code that would have called it. The track queue and the playlist list come
// from the internal data API the YouTube Music UI uses.
//
// None of this is a documented API. Every name that may change is in the
// ADJUST HERE block.
(function () {
  'use strict';
  if (window.__bside || window.top !== window) return;

  // ---- ADJUST HERE ---------------------------------------------------------
  const HOST = 'music.youtube.com';
  const CONTEXT_ID = 'WEB_PLAYER_CONTEXT_CONFIG_ID_MUSIC_WATCH'; // key in ytcfg WEB_PLAYER_CONTEXT_CONFIGS
  const CONFIG_URL = '/';               // page whose HTML carries `ytcfg.set({...})`
  const CONFIG_CALL = 'ytcfg.set(';
  // The queue comes from the same internal endpoint the YouTube Music UI uses.
  const QUEUE_ENDPOINT = '/youtubei/v1/next?prettyPrint=false';
  const QUEUE_ITEM = 'playlistPanelVideoRenderer'; // response objects that carry a videoId
  // A track that exists both as a song and as a music video arrives wrapped:
  // { primaryRenderer: {item}, counterpart: [{ counterpartRenderer: {item} }] }
  const QUEUE_WRAPPER = 'playlistPanelVideoWrapperRenderer';
  const TYPE_KEY = 'musicVideoType';    // somewhere inside each item
  const AUDIO_TYPE = 'MUSIC_VIDEO_TYPE_ATV';
  const LOWEST_QUALITY = 'tiny';        // 144p, for videos that have no song version
  const RADIO_PREFIX = 'RDAMVM';        // playlist ID of the automatic radio for a track
  const SHUFFLE_PARAMS = 'wAEB8gECKAE%3D'; // `params` value that makes the server shuffle a playlist
  const ARTWORK_MIN_WIDTH = 320;        // smallest thumbnail that still looks sharp at 160 pt
  const CONTINUATION = /"next(?:Radio)?ContinuationData":\{"continuation":"([^"]+)"/; // token for the next page
  const REFILL_THRESHOLD = 3;           // fetch the next page this many tracks before the end
  const BROWSE_ENDPOINT = '/youtubei/v1/browse?prettyPrint=false';
  const LIBRARY_PLAYLISTS = 'FEmusic_liked_playlists'; // browse ID of the user's playlists
  const LIBRARY_ITEM = 'musicTwoRowItemRenderer';      // one tile in that list
  const PLAYLIST_BROWSE_PREFIX = 'VL';  // a playlist's browse ID is 'VL' + its playlist ID
  const ACCOUNT_ENDPOINT = '/youtubei/v1/account/account_menu?prettyPrint=false';
  const ACCOUNT_HEADER = 'activeAccountHeaderRenderer'; // carries accountName and channelHandle (no email)
  const AUTH_COOKIES = ['SAPISID', '__Secure-3PAPISID'];
  const RESTART_THRESHOLD_S = 3;        // Previous restarts the track after this many seconds
  const PLAYER_ELEMENT = '#movie_player';
  const PLAYER_SIZE = 'width:320px;height:180px';
  const AD_CLASS = 'ad-showing';
  const REPORT_INTERVAL_MS = 5000;
  const BOOT_TIMEOUT_MS = 20000;
  const MEDIA_EVENTS = ['play', 'playing', 'pause', 'seeked', 'ended', 'durationchange', 'loadedmetadata', 'emptied'];
  const ENDED = 0, PLAYING = 1, BUFFERING = 3; // getPlayerState() values
  // --------------------------------------------------------------------------

  if (location.hostname !== HOST) return;
  const config = window.__bsideConfig || {};
  let player = null;
  let queue = [];        // [{ id, versions: [ids], audio, title, artist, artwork }]
  let queueIndex = -1;
  let announcedFor = ''; // track whose version and quality were already logged
  let lastQueueBytes = 0;
  let queueContinuation = null;
  let refilling = false;
  let volume = 100;      // 0 to 100, set by the app

  function post(message) {
    try { window.webkit.messageHandlers.bside.postMessage(message); } catch (e) {}
  }

  function event(kind, detail) {
    post({ type: 'event', kind: kind, detail: String(detail || '') });
  }

  // Once per track: say what is really being decoded.
  function announce(videoId) {
    const track = queue[queueIndex];
    if (!videoId || videoId === announcedFor || !track || track.id !== videoId) return;
    if (player.getPlayerState() !== PLAYING) return;
    announcedFor = videoId;
    event('version', videoId + (track.audio ? ' song' : ' video at quality ' + player.getPlaybackQuality()) + ', volume ' + player.getVolume());
  }

  function report() {
    if (!player) return;
    const data = player.getVideoData() || {};
    announce(data.video_id);
    const state = player.getPlayerState();
    const duration = player.getDuration();
    // The queue knows the track's real title, artist and square artwork; the
    // player only knows the video's.
    const entry = queue[queueIndex];
    const known = entry && entry.id === data.video_id ? entry : {};
    post({
      type: 'state',
      title: known.title || data.title || '',
      artist: known.artist || data.author || '',
      artwork: known.artwork || (data.video_id ? 'https://i.ytimg.com/vi/' + data.video_id + '/hqdefault.jpg' : ''),
      videoId: data.video_id || '',
      queueIndex: queueIndex,
      queueCount: queue.length,
      queueHasMore: !!queueContinuation,
      position: player.getCurrentTime() || 0,
      duration: isFinite(duration) ? duration : 0,
      playing: state === PLAYING || state === BUFFERING,
      ad: player.classList.contains(AD_CLASS),
    });
  }

  function createPlayer(context) {
    const create = window.yt && yt.player && yt.player.Application && yt.player.Application.create;
    if (!create) return event('error', 'boot: yt.player.Application.create not found');

    const host = document.createElement('div');
    host.id = 'bside-player';
    host.style.cssText = PLAYER_SIZE;
    document.body.appendChild(host);
    create(host, { args: {} }, context);

    const started = Date.now();
    const timer = setInterval(function () {
      const candidate = document.querySelector(PLAYER_ELEMENT);
      if (candidate && typeof candidate.loadVideoById === 'function') {
        clearInterval(timer);
        player = candidate;
        if (config.muted) player.mute();
        player.setVolume(volume);
        player.addEventListener('onError', function (code) { event('error', 'player error ' + code); });
        player.addEventListener('onStateChange', function (state) { if (state === ENDED) playAt(queueIndex + 1); });
        event('ready', 'player');
      } else if (Date.now() - started > BOOT_TIMEOUT_MS) {
        clearInterval(timer);
        event('error', 'boot: player element did not appear');
      }
    }, 100);
  }

  function contextFromPage() {
    const contexts = window.ytcfg && ytcfg.get && ytcfg.get('WEB_PLAYER_CONTEXT_CONFIGS');
    return contexts && contexts[CONTEXT_ID];
  }

  // Index of the brace that closes the JSON object starting at `start`, or -1.
  function endOfObject(text, start) {
    let depth = 0, inString = false;
    for (let i = start; i < text.length; i++) {
      const c = text[i];
      if (inString) {
        if (c === '\\') i++;
        else if (c === '"') inString = false;
      } else if (c === '"') inString = true;
      else if (c === '{') depth++;
      else if (c === '}' && --depth === 0) return i;
    }
    return -1;
  }

  // Rebuilds `ytcfg` from the configuration in the home page's HTML.
  async function loadConfig() {
    const response = await fetch(CONFIG_URL, { credentials: 'include' });
    const html = await response.text();
    const data = {};
    let index = 0;
    while ((index = html.indexOf(CONFIG_CALL, index)) !== -1) {
      index += CONFIG_CALL.length;
      const end = html[index] === '{' ? endOfObject(html, index) : -1;
      if (end < 0) continue;
      try { Object.assign(data, JSON.parse(html.slice(index, end + 1))); } catch (e) {}
    }
    if (!data.WEB_PLAYER_CONTEXT_CONFIGS) throw new Error('no player config in ' + CONFIG_URL + ' (HTTP ' + response.status + ')');
    window.ytcfg = {
      data_: data,
      get: function (key, fallback) { return key in data ? data[key] : fallback; },
      set: function (key, value) { if (typeof key === 'object') Object.assign(data, key); else data[key] = value; },
    };
    window.yt = window.yt || {};
    window.yt.config_ = data;
    event('config', 'signed in: ' + !!data.LOGGED_IN + ', client ' + data.INNERTUBE_CLIENT_NAME + ' ' + data.INNERTUBE_CLIENT_VERSION);
    post({ type: 'account', signedIn: !!data.LOGGED_IN, name: '', handle: '' });
    if (data.LOGGED_IN) accountName().catch(function () {}); // the name is a nicety
  }

  async function accountName() {
    const text = await api(ACCOUNT_ENDPOINT, {});
    cut(text, [ACCOUNT_HEADER], function (key, node) {
      const name = find(node.accountName, 'text') || '';
      const handle = find(node.channelHandle, 'text') || '';
      if (name || handle) post({ type: 'account', signedIn: true, name: name, handle: handle });
    });
  }

  async function boot() {
    await loadConfig();
    const context = contextFromPage();
    if (!context || !context.jsUrl) return event('error', 'boot: no player config in ytcfg');

    const script = document.createElement('script');
    script.onload = function () {
      try { createPlayer(context); } catch (e) { event('error', 'boot: ' + e); }
    };
    script.onerror = function () { event('error', 'boot: could not load ' + context.jsUrl); };
    script.src = context.jsUrl;
    document.head.appendChild(script);
  }

  // The header the YouTube Music UI sends so the server treats the request as
  // signed in. Without it only public playlists load.
  async function authHeaders() {
    const headers = { 'Content-Type': 'application/json' };
    const cookies = Object.fromEntries(document.cookie.split('; ').map(function (pair) {
      const split = pair.indexOf('=');
      return [pair.slice(0, split), pair.slice(split + 1)];
    }));
    const secret = AUTH_COOKIES.map(function (name) { return cookies[name]; }).find(Boolean);
    if (!secret) return headers;
    const timestamp = Math.floor(Date.now() / 1000);
    const input = new TextEncoder().encode(timestamp + ' ' + secret + ' ' + location.origin);
    const digest = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-1', input)));
    const hex = digest.map(function (byte) { return byte.toString(16).padStart(2, '0'); }).join('');
    headers['Authorization'] = 'SAPISIDHASH ' + timestamp + '_' + hex;
    headers['X-Origin'] = location.origin;
    headers['X-Goog-AuthUser'] = String(ytcfg.get('SESSION_INDEX', '0'));
    return headers;
  }

  async function api(endpoint, body) {
    const response = await fetch(endpoint, {
      method: 'POST', credentials: 'include', headers: await authHeaders(),
      body: JSON.stringify(Object.assign({ context: ytcfg.get('INNERTUBE_CONTEXT') }, body)),
    });
    if (!response.ok) throw new Error(endpoint.split('?')[0] + ' failed: HTTP ' + response.status);
    return response.text();
  }

  // Responses are several hundred KB of JSON, nearly all of it UI data.
  // Parsing one whole costs about 20 MB of heap, so only the objects stored
  // under `keys` are cut out of the text and parsed.
  function cut(text, keys, visit) {
    const markers = keys.map(function (key) { return '"' + key + '":'; });
    let index = 0;
    for (;;) {
      let at = -1, which = -1;
      markers.forEach(function (marker, i) {
        const found = text.indexOf(marker, index);
        if (found !== -1 && (at === -1 || found < at)) { at = found; which = i; }
      });
      if (at === -1) return;
      const start = at + markers[which].length;
      const end = text[start] === '{' ? endOfObject(text, start) : -1;
      if (end < 0) { index = start; continue; }
      visit(keys[which], JSON.parse(text.slice(start, end + 1)));
      index = end + 1;
    }
  }

  // One page of a playlist's or a radio's tracks, in play order.
  async function fetchQueue(body) {
    const text = await api(QUEUE_ENDPOINT, body);
    const tracks = [];
    cut(text, [QUEUE_WRAPPER, QUEUE_ITEM], function (key, node) {
      tracks.push(key === QUEUE_WRAPPER ? track(versionsOf(node)) : track([node]));
    });
    const more = text.match(CONTINUATION);
    lastQueueBytes = text.length;
    return { tracks: tracks.filter(Boolean), continuation: more ? more[1] : null };
  }

  function versionsOf(wrapper) {
    const renderers = [wrapper.primaryRenderer].concat(
      (wrapper.counterpart || []).map(function (entry) { return entry.counterpartRenderer; }));
    return renderers.map(function (renderer) { return renderer && renderer[QUEUE_ITEM]; });
  }

  function find(node, key) {
    if (!node || typeof node !== 'object') return undefined;
    if (key in node) return node[key];
    for (const child of Object.values(node)) {
      const found = find(child, key);
      if (found !== undefined) return found;
    }
    return undefined;
  }

  // Picks which version of a track to play: the song when audio-only is on
  // and a song version exists, otherwise the one the server listed first.
  function track(items) {
    const versions = items.filter(function (item) { return item && item.videoId; });
    if (!versions.length) return null;
    const song = versions.find(function (item) { return find(item, TYPE_KEY) === AUDIO_TYPE; });
    const chosen = (config.audioOnly && song) || versions[0];
    return {
      id: chosen.videoId,
      versions: versions.map(function (item) { return item.videoId; }),
      audio: chosen === song,
      title: find(chosen.title, 'text') || '',
      artist: find(chosen.shortBylineText, 'text') || find(chosen.longBylineText, 'text') || '',
      artwork: thumbnail(chosen.thumbnail),
    };
  }

  // The smallest thumbnail that is wide enough, or the largest there is.
  function thumbnail(node) {
    const list = (find(node, 'thumbnails') || []).slice().sort(function (a, b) { return a.width - b.width; });
    const fit = list.find(function (item) { return item.width >= ARTWORK_MIN_WIDTH; }) || list[list.length - 1];
    return fit ? fit.url : '';
  }

  function describe(tracks, source) {
    const songs = tracks.filter(function (entry) { return entry.audio; }).length;
    return tracks.length + ' tracks from ' + source + ': ' + songs + ' songs, ' + (tracks.length - songs)
      + ' videos, ' + (queueContinuation ? 'more available' : 'complete')
      + ' (response ' + Math.round(lastQueueBytes / 1024) + ' KB)';
  }

  function setQueue(page, source) {
    queue = page.tracks;
    queueContinuation = page.continuation;
    event('queue', describe(queue, source));
  }

  // Playlists arrive about 50 tracks at a time. The next page is fetched when
  // playback gets close to the end of what is loaded.
  async function refill() {
    const token = queueContinuation;
    if (!token || refilling) return;
    refilling = true;
    try {
      const page = await fetchQueue({ continuation: token });
      if (queueContinuation !== token) return; // a different queue was loaded meanwhile
      queue = queue.concat(page.tracks);
      queueContinuation = page.tracks.length ? page.continuation : null;
      event('queue', describe(queue, 'next page'));
    } catch (e) {
      event('error', 'queue refill: ' + e);
    } finally {
      refilling = false;
    }
  }

  function playAt(index, startSeconds) {
    if (!player || index < 0 || index >= queue.length) return false;
    queueIndex = index;
    player.loadVideoById({ videoId: queue[index].id, startSeconds: startSeconds || 0 });
    player.setVolume(volume); // the player keeps its own idea of the volume across loads; make sure
    // Nothing shows the picture, so a video without a song version is decoded
    // as small as the player allows.
    if (config.audioOnly && !queue[index].audio) player.setPlaybackQualityRange(LOWEST_QUALITY, LOWEST_QUALITY);
    if (index >= queue.length - REFILL_THRESHOLD) refill();
    return true;
  }

  async function load(kind, id, startSeconds, options) {
    if (!player) return event('error', 'load: player not ready');
    if (kind === 'playlist') {
      const body = { playlistId: id };
      const shuffle = !!(options && options.shuffle);
      if (shuffle) body.params = SHUFFLE_PARAMS;
      const page = await fetchQueue(body);
      if (!page.tracks.length) return event('error', 'load: playlist ' + id + ' is empty or not accessible');
      setQueue(page, shuffle ? 'shuffled playlist' : 'playlist');
      playAt(Math.min(config.startIndex || 0, queue.length - 1), 0);
      return;
    }
    // Like YouTube Music with autoplay on: the track, then its radio. The
    // radio is fetched first because it also says whether the track has a
    // song version.
    let page = { tracks: [], continuation: null };
    try { page = await fetchQueue({ videoId: id, playlistId: RADIO_PREFIX + id }); } catch (e) { event('error', 'radio: ' + e); }
    if (!page.tracks.length || page.tracks[0].versions.indexOf(id) === -1) {
      page.tracks.unshift({ id: id, versions: [id], audio: false });
    }
    setQueue(page, 'radio');
    playAt(0, startSeconds);
  }

  // The signed-in user's playlists, for the picker in the app window.
  async function playlists() {
    const text = await api(BROWSE_ENDPOINT, { browseId: LIBRARY_PLAYLISTS });
    const items = [];
    cut(text, [LIBRARY_ITEM], function (key, node) {
      const browseId = find(node.navigationEndpoint, 'browseId') || '';
      const title = find(node.title, 'text') || '';
      if (browseId.indexOf(PLAYLIST_BROWSE_PREFIX) !== 0 || !title) return; // e.g. the "New playlist" tile
      const subtitle = ((node.subtitle && node.subtitle.runs) || []).map(function (run) { return run.text; }).join('');
      items.push({
        id: browseId.slice(PLAYLIST_BROWSE_PREFIX.length),
        title: title,
        subtitle: subtitle,
        artwork: thumbnail(node.thumbnailRenderer),
      });
    });
    post({ type: 'playlists', items: items });
    event('library', items.length + ' playlists (response ' + Math.round(text.length / 1024) + ' KB)');
  }

  window.__bside = {
    load(kind, id, startSeconds, options) {
      load(kind, id, startSeconds, options).catch(function (e) { event('error', 'load: ' + e); });
    },
    play() { if (player) player.playVideo(); },
    pause() { if (player) player.pauseVideo(); },
    toggle() {
      if (!player) return;
      player.getPlayerState() === PLAYING ? player.pauseVideo() : player.playVideo();
    },
    next() { if (!playAt(queueIndex + 1)) event('error', 'next: end of queue'); },
    previous() {
      if (!player) return;
      if (player.getCurrentTime() > RESTART_THRESHOLD_S || !playAt(queueIndex - 1)) player.seekTo(0, true);
    },
    seek(seconds) { if (player) player.seekTo(seconds, true); },
    volume(level) {
      volume = Math.max(0, Math.min(100, Number(level) || 0));
      if (player) player.setVolume(volume);
    },
    playlists() {
      playlists().catch(function (e) { event('error', 'playlists: ' + e); });
    },
    report: report,
  };

  MEDIA_EVENTS.forEach(function (name) {
    document.addEventListener(name, report, true);
  });
  setInterval(report, REPORT_INTERVAL_MS);

  boot().catch(function (e) { event('error', 'boot: ' + e); });
})();
