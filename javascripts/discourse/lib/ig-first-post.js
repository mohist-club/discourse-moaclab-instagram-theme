import { ajax } from "discourse/lib/ajax";

// The topic's first post, loaded once per topic and shared by every card
// (gallery images, like / bookmark ids when the topic list lacks them).
// Uses Discourse's own /posts/by_number/:topic_id/1 endpoint.
//
// Requests go through a small queue — one at a time, at least GAP ms
// apart — so a screenful of cards never trips Discourse's per-IP request
// limit (by default 50 per 10 seconds), which would also block the list's
// own "load more". A 429 pauses the queue for the time the server asks.
const cache = new Map();
const queue = [];
const GAP = 300;
const DEFAULT_PAUSE = 10_000;
let running = false;
let pausedUntil = 0;

export function loadFirstPost(topicId) {
  if (!cache.has(topicId)) {
    const promise = new Promise((resolve, reject) => {
      queue.push({ topicId, resolve, reject });
    }).catch((error) => {
      cache.delete(topicId);
      throw error;
    });
    cache.set(topicId, promise);
    runQueue();
  }
  return cache.get(topicId);
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
      }
      const job = queue.shift();
      try {
        job.resolve(await ajax(`/posts/by_number/${job.topicId}/1.json`));
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
