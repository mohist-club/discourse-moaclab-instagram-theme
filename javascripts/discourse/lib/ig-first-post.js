import { ajax } from "discourse/lib/ajax";

// The topic's first post, loaded once per topic and shared by every card
// (gallery images, like / bookmark ids when the topic list lacks them).
// Uses Discourse's own /posts/by_number/:topic_id/1 endpoint.
//
// Requests go through a small queue — one at a time, at least GAP ms
// apart — so a screenful of cards never trips Discourse's per-IP request
// limit (by default 50 per 10 seconds), which would also block the list's
// own "load more". A 429 pauses the queue for the time the server asks.
//
// Only what cards use is kept: the post id, bookmark id, the like entry of
// actions_summary and the image list (parsed once), for the latest
// CACHE_MAX topics. A gallery prefetch whose card has gone (scrolled
// past, another page) leaves the queue before it is sent.
const CACHE_MAX = 200;
const GAP = 300;
const DEFAULT_PAUSE = 10_000;
const LIKE = 2;
const cache = new Map(); // topicId -> Promise<summary>
const queue = []; // jobs not yet sent
let running = false;
let pausedUntil = 0;

class Cancelled extends Error {}

function summarize(post) {
  return {
    id: post?.id || null,
    bookmark_id: post?.bookmark_id || null,
    actions_summary: (post?.actions_summary || []).filter((a) => a.id === LIKE),
    images: imagesFromCooked(post?.cooked),
  };
}

function remember(topicId, promise) {
  cache.delete(topicId);
  cache.set(topicId, promise);
  while (cache.size > CACHE_MAX) {
    cache.delete(cache.keys().next().value);
  }
}

function request(topicId) {
  const job = { topicId, wanted: 0, keep: false };
  job.promise = new Promise((resolve, reject) => {
    job.resolve = resolve;
    job.reject = reject;
  }).catch((error) => {
    if (cache.get(topicId) === job.promise) {
      cache.delete(topicId);
    }
    throw error;
  });
  queue.push(job);
  remember(topicId, job.promise);
  runQueue();
  return job;
}

// for an action the reader took (like, save): never dropped
export function loadFirstPost(topicId) {
  const queued = queue.find((job) => job.topicId === topicId);
  if (queued) {
    queued.keep = true;
    return queued.promise;
  }
  if (!cache.has(topicId)) {
    request(topicId).keep = true;
  } else {
    remember(topicId, cache.get(topicId)); // most recently used
  }
  return cache.get(topicId);
}

// for a card's gallery: cancel() drops it if it has not been sent yet and
// no other card or action still wants it
export function prefetchFirstPost(topicId) {
  let job = queue.find((queued) => queued.topicId === topicId);
  if (!job && cache.has(topicId)) {
    return { promise: cache.get(topicId), cancel() {} };
  }
  job ||= request(topicId);
  job.wanted++;
  let cancelled = false;
  return {
    promise: job.promise,
    cancel() {
      if (cancelled) {
        return;
      }
      cancelled = true;
      job.wanted--;
      const index = queue.indexOf(job);
      if (job.wanted <= 0 && !job.keep && index !== -1) {
        queue.splice(index, 1);
        if (cache.get(job.topicId) === job.promise) {
          cache.delete(job.topicId);
        }
        job.reject(new Cancelled());
      }
    },
  };
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function runQueue() {
  if (running) {
    return;
  }
  running = true;
  try {
    while (queue.length) {
      const pause = pausedUntil - Date.now();
      if (pause > 0) {
        await wait(pause);
        continue; // the queue may have changed while paused
      }
      const job = queue.shift();
      try {
        job.resolve(
          summarize(await ajax(`/posts/by_number/${job.topicId}/1.json`))
        );
      } catch (error) {
        const xhr = error?.jqXHR;
        if (xhr?.status === 429) {
          const retry = parseInt(xhr.getResponseHeader?.("Retry-After"), 10);
          pausedUntil = Date.now() + (retry > 0 ? retry * 1000 : DEFAULT_PAUSE);
          queue.unshift(job); // try this one again after the pause
          continue;
        }
        job.reject(error);
      }
      await wait(GAP);
    }
  } finally {
    running = false;
  }
}

// Images a reader sees in the post body, in order. Leaves out link
// previews, quotes, emoji, avatars and anything tiny. The cooked HTML is
// parsed into an inert document, so nothing loads or runs here.
const MAX_IMAGES = 10;
const SKIP_INSIDE = ".onebox, aside.quote, blockquote, .d-editor-preview";
const SKIP_IMAGE = ".emoji, .avatar, .site-icon, .onebox-avatar, .thumbnail";

export function imagesFromCooked(cooked) {
  if (!cooked) {
    return [];
  }
  const doc = new DOMParser().parseFromString(cooked, "text/html");
  const seen = new Set();
  const images = [];

  for (const img of doc.querySelectorAll("img")) {
    if (img.matches(SKIP_IMAGE) || img.closest(SKIP_INSIDE)) {
      continue;
    }
    const src = img.getAttribute("src");
    if (!src || src.startsWith("data:")) {
      continue;
    }
    const width = parseInt(img.getAttribute("width"), 10) || null;
    const height = parseInt(img.getAttribute("height"), 10) || null;
    if ((width && width < 100) || (height && height < 100)) {
      continue;
    }
    const key = img.dataset.base62Sha1 || src;
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    images.push({
      src,
      srcset: img.getAttribute("srcset") || null,
      width,
      height,
    });
    if (images.length >= MAX_IMAGES) {
      break;
    }
  }
  return images;
}

// One observer for every card: calls back once when a card comes within
// half a screen of the viewport, so images are ready before it is seen.
const callbacks = new WeakMap();
let observer = null;

export function whenNearViewport(element, callback) {
  if (typeof IntersectionObserver === "undefined") {
    callback();
    return () => {};
  }
  observer ||= new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          observer.unobserve(entry.target);
          callbacks.get(entry.target)?.();
          callbacks.delete(entry.target);
        }
      }
    },
    { rootMargin: "50% 0px" }
  );
  callbacks.set(element, callback);
  observer.observe(element);
  return () => {
    observer.unobserve(element);
    callbacks.delete(element);
  };
}
