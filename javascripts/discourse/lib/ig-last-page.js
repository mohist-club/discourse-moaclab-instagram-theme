// The last page the visitor saw before the log-in / sign-up pages, so their
// close button (and Esc) can go back to it. Fed by ig-theme.js.
const AUTH_PAGES = /^\/(login|signup|password-reset|u\/activate-account)/;
let lastPage = null;

export function rememberPage(url) {
  try {
    const { pathname, search } = new URL(url, window.location.origin);
    if (!AUTH_PAGES.test(pathname)) {
      lastPage = pathname + search;
    }
  } catch {
    // ignore malformed URLs
  }
}

export function pageBeforeAuth() {
  return lastPage || "/";
}
