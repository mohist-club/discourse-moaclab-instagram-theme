import { apiInitializer } from "discourse/lib/api";

// Keeps infinite scrolling alive. Discourse's topic list sets `loadingMore`
// before fetching the next page and only clears it on success: a failed
// request (rate limit, server error, network) leaves the spinner forever and
// the load-more observer never re-arms. Through Discourse's own
// "discovery-topic-list-load-more" behavior transformer we clear the flag
// after a pause, so the native observer fetches the page again — after the
// server's Retry-After for a 429, otherwise after a few seconds, at most
// MAX_RETRIES times per page.

const MAX_RETRIES = 3;
const RETRY_DELAY = 3000;
const RATE_LIMIT_DELAY = 10_000;
const attempts = new Map();

function retryDelay(error) {
  const xhr = error?.jqXHR;
  if (xhr?.status === 429) {
    const retryAfter = parseInt(xhr.getResponseHeader?.("Retry-After"), 10);
    return retryAfter > 0 ? retryAfter * 1000 : RATE_LIMIT_DELAY;
  }
  return RETRY_DELAY;
}

export default apiInitializer((api) => {
  api.registerBehaviorTransformer(
    "discovery-topic-list-load-more",
    ({ next, context }) => {
      const model = context?.model;
      const url = model?.more_topics_url;
      const result = next();

      Promise.resolve(result).catch((error) => {
        if (!model || !url) {
          return;
        }
        const tries = (attempts.get(url) || 0) + 1;
        attempts.set(url, tries);
        // eslint-disable-next-line no-console
        console.warn(
          `[moaclab-instagram] loading more topics failed (${
            error?.jqXHR?.status ?? error?.message ?? "error"
          }), attempt ${tries}/${MAX_RETRIES}: ${url}`
        );
        if (tries > MAX_RETRIES) {
          return;
        }
        setTimeout(() => {
          // the observer re-arms once loadingMore is false
          if (model.loadingMore && model.more_topics_url === url) {
            model.set("loadingMore", false);
          }
        }, retryDelay(error));
      });

      return result;
    }
  );
});
