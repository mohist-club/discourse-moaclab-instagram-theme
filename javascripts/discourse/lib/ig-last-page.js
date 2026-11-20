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

// How many pages this tab has shown inside the app, so a back button can
// tell whether history.back() stays on the site.
let pagesShown = 0;

export function countPage() {
  pagesShown++;
}

export function canGoBackInApp() {
  return pagesShown > 1;
}

// The topic of the current page, from the router (the "topic" route or one
// of its parents), or null.
export function currentTopic(router) {
  let route = router?.currentRoute;
  while (route && route.name !== "topic") {
    route = route.parent;
  }
  return route?.attributes || null;
}
