import { apiInitializer } from "discourse/lib/api";

// `settings` is injected as a global in Discourse theme JS.
export default apiInitializer((api) => {
  const body = document.body;

  // 1. accent color -> CSS custom property
  const accent = (settings.accent_color || "#0095f6").trim();
  document.documentElement.style.setProperty("--ig-accent", accent);

  // 2. toggle feature classes from boolean settings
  const flags = {
    "ig-gradient-logo": settings.brand_gradient_logo,
    "ig-gradient-buttons": settings.brand_gradient_buttons,
    "ig-round-avatars": settings.rounded_avatars,
    "ig-card-feed": settings.card_feed,
  };
  for (const [cls, on] of Object.entries(flags)) {
    body.classList.toggle(cls, !!on);
  }

  // 3. mobile bottom navigation
  const site = api.container.lookup("service:site");
  if (settings.mobile_bottom_nav && site?.mobileView) {
    buildBottomNav(api);
    body.classList.add("ig-has-bottom-nav");
  }
});

function svg(paths) {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;
}

const ICONS = {
  home: svg(
    '<path d="M3 11 12 3l9 8"/><path d="M5 10v10a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1V10"/>'
  ),
  search: svg('<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>'),
  create: svg(
    '<rect x="3" y="3" width="18" height="18" rx="5"/><path d="M12 8v8M8 12h8"/>'
  ),
  activity: svg(
    '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/>'
  ),
  profile: svg(
    '<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 4-6 8-6s8 2 8 6"/>'
  ),
};

function buildBottomNav(api) {
  if (document.querySelector(".ig-bottom-nav")) {
    return;
  }

  const user = api.getCurrentUser();
  const nav = document.createElement("nav");
  nav.className = "ig-bottom-nav";
  nav.setAttribute("aria-label", "Instagram navigation");

  const items = [
    { href: "/", html: ICONS.home },
    { href: "/search", html: ICONS.search },
    { href: "/new-topic", html: ICONS.create },
    { href: user ? "/my/activity" : "/login", html: ICONS.activity },
  ];

  if (user) {
    items.push({
      href: `/u/${user.username}/summary`,
      html: `<span class="ig-avatar-mini"><img src="${user.avatar_template.replace(
        "{size}",
        "52"
      )}" alt=""></span>`,
    });
  } else {
    items.push({ href: "/login", html: ICONS.profile });
  }

  for (const it of items) {
    const a = document.createElement("a");
    a.href = it.href;
    a.innerHTML = it.html;
    nav.appendChild(a);
  }

  document.body.appendChild(nav);

  const setActive = () => {
    const path = window.location.pathname;
    nav.querySelectorAll("a").forEach((a) => {
      const href = a.getAttribute("href");
      const active = href === "/" ? path === "/" : path.startsWith(href);
      a.classList.toggle("active", active);
    });
  };
  setActive();
  api.onPageChange(setActive);
}
