import { ajax } from "discourse/lib/ajax";

// The topic's first post, loaded once per topic and shared by every card
// (gallery images, like / bookmark ids when the topic list lacks them).
// Uses Discourse's own /posts/by_number/:topic_id/1 endpoint.
const cache = new Map();

export function loadFirstPost(topicId) {
  if (!cache.has(topicId)) {
    cache.set(
      topicId,
      ajax(`/posts/by_number/${topicId}/1.json`).catch((error) => {
        cache.delete(topicId);
        throw error;
      })
    );
  }
  return cache.get(topicId);
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
// about a screen of the viewport, so images are ready before it is seen.
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
    { rootMargin: "100% 0px" }
  );
  callbacks.set(element, callback);
  observer.observe(element);
  return () => {
    observer.unobserve(element);
    callbacks.delete(element);
  };
}
