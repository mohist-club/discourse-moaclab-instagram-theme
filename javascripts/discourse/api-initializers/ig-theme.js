import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";

// `settings` is injected as a global in Discourse theme JS.
export default apiInitializer((api) => {
  const body = document.body;

  // 1. accent color -> CSS custom property (viewport-independent)
  const accent = (settings.accent_color || "#0095f6").trim();
  document.documentElement.style.setProperty("--ig-accent", accent);

  // 2. toggle feature classes from boolean settings (viewport-independent)
  const flags = {
    "ig-gradient-logo": settings.brand_gradient_logo,
    "ig-gradient-buttons": settings.brand_gradient_buttons,
    "ig-round-avatars": settings.rounded_avatars,
    "ig-card-feed": settings.card_feed,
    "ig-topic-style": settings.instagram_topic_style,
    "ig-auth-modal": settings.instagram_auth_modal,
    "ig-admin-style": settings.instagram_admin_style,
  };
  for (const [cls, on] of Object.entries(flags)) {
    body.classList.toggle(cls, !!on);
  }

  // title of the admin settings column (CSS content, see scss/admin.scss)
  document.documentElement.style.setProperty(
    "--ig-admin-title",
    JSON.stringify(i18n(themePrefix("ig.admin.title")))
  );

  // 3. mobile bottom navigation — read mobileView at render time (not during
  //    static initialization) to avoid the viewport-initialization deprecation.
  let built = false;
  api.onPageChange(() => {
    if (built || !settings.mobile_bottom_nav) {
      return;
    }
    const site = api.container.lookup("service:site");
    if (site?.mobileView) {
      buildBottomNav(api);
      body.classList.add("ig-has-bottom-nav");
      built = true;
    }
  });
});

function svg(paths) {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;
}

const ICONS = {
  home: svg(
    '<path d="M9.005 16.545a2.997 2.997 0 0 1 2.997-2.997A2.997 2.997 0 0 1 15 16.545V22h7V11.543L12 2 2 11.543V22h7.005Z"/>'
  ),
  search: svg(
    '<path d="M19 10.5A8.5 8.5 0 1 1 10.5 2a8.5 8.5 0 0 1 8.5 8.5Z"/><path d="M16.511 16.511 22 22"/>'
  ),
  create: svg('<path d="M12 2.5v19M2.5 12h19"/>'),
  activity: svg(
    '<path d="M16.8 3.9a5 5 0 0 1 4.7 5.2c0 3.1-2.65 5-5.2 7.2-2.5 2.25-3.86 3.47-4.3 3.75-.48-.3-2.14-1.82-4.3-3.75C5.14 14.07 2.5 12.17 2.5 9.12A5 5 0 0 1 7.2 3.9a4.2 4.2 0 0 1 3.68 1.94c.84 1.18.98 1.76 1.12 1.76s.28-.59 1.11-1.77a4.17 4.17 0 0 1 3.68-1.93Z"/>'
  ),
  profile: svg(
    '<circle cx="12" cy="7.5" r="4.5"/><path d="M3 21.5c0-4.4 4-7.5 9-7.5s9 3.1 9 7.5"/>'
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
