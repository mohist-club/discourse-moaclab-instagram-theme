import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";
import DiscourseURL from "discourse/lib/url";
import { countPage, rememberPage } from "../lib/ig-last-page";

// `settings` is injected as a global in Discourse theme JS.
export default apiInitializer((api) => {
  const body = document.body;

  // 1. accent color -> CSS custom property (viewport-independent)
  const accent = (settings.accent_color || "#0095f6").trim();
  document.documentElement.style.setProperty("--ig-accent", accent);

  // 1b. default height of the new-topic editor, as a share of the screen,
  //     through Discourse's own --new-topic-composer-height (a height the
  //     user dragged to is remembered by Discourse and still wins)
  const composerHeight = parseInt(settings.new_topic_composer_height, 10);
  if (composerHeight > 0) {
    document.documentElement.style.setProperty(
      "--new-topic-composer-height",
      `${Math.min(composerHeight, 95)}vh`
    );
  }

  // 1c. the site's icon (logo_small, its dark version for dark schemes)
  //     as CSS custom properties, for /custom-services' profile picture
  //     (scss/custom-services.scss); body.ig-has-site-icon when there is one
  const siteSettings = api.container.lookup("service:site-settings");
  const icon = siteSettings?.site_logo_small_url;
  if (icon) {
    const iconDark = siteSettings.site_logo_small_dark_url || icon;
    const root = document.documentElement.style;
    root.setProperty("--ig-site-icon-light", `url("${icon}")`);
    root.setProperty("--ig-site-icon-dark", `url("${iconDark}")`);
    body.classList.add("ig-has-site-icon");
  }

  // 2. feature classes from boolean settings — never on admin pages, which
  //    stay Discourse-native (re-checked on every page change)
  const flags = {
    "ig-gradient-logo": settings.brand_gradient_logo,
    "ig-gradient-buttons": settings.brand_gradient_buttons,
    "ig-round-avatars": settings.rounded_avatars,
    "ig-card-feed": settings.card_feed,
    "ig-topic-style": settings.instagram_topic_style,
    "ig-auth-modal": settings.instagram_auth_modal,
    "ig-mobile-shell": settings.instagram_mobile_layout,
    "ig-custom-services": settings.instagram_custom_services,
    "ig-cad-viewer": settings.instagram_cad_viewer,
  };
  const applyFlags = () => {
    const admin = isAdminPage();
    for (const [cls, on] of Object.entries(flags)) {
      body.classList.toggle(cls, !!on && !admin);
    }
  };
  applyFlags();
  api.onPageChange(applyFlags);

  // conversations: mark runs of messages from the same person, so the chat
  // shows the name once (first message) and the avatar once (last message)
  api.registerValueTransformer("post-class", ({ value, context }) => {
    const { post, prevPost, nextPost } = context || {};
    if (post?.topic?.archetype !== "private_message") {
      return value;
    }
    const sameSender = (other) =>
      !!other &&
      other.user_id === post.user_id &&
      other.post_type === post.post_type;
    const classes = [...(value || [])];
    if (sameSender(prevPost)) {
      classes.push("ig-chat-continued");
    }
    if (sameSender(nextPost)) {
      classes.push("ig-chat-followed");
    }
    return classes;
  });

  // the page before log-in / sign-up, for their close button and Esc
  api.onPageChange((url) => {
    rememberPage(url);
    countPage();
  });

  // 3. Instagram's bottom tab bar below 768px (phones and narrow desktop
  //    windows; scss/mobile-shell.scss shows it). Hidden on admin pages.
  let nav = null;
  api.onPageChange(() => {
    const admin = isAdminPage();
    if (!nav && !admin && settings.mobile_bottom_nav) {
      nav = buildBottomNav(api);
    }
    if (nav) {
      nav.hidden = admin;
      syncBottomNav(nav);
    }
    body.classList.toggle("ig-has-bottom-nav", !!nav && !admin);
  });
});

function isAdminPage() {
  return (
    window.location.pathname.startsWith("/admin") ||
    document.body.classList.contains("admin-interface")
  );
}

// Instagram's tab bar: Home · Explore · Create · Messages · Profile, the
// same glyphs as the desktop rail (filled when active). Create opens
// Discourse's own new-topic composer; visitors are sent to log in.
function buildBottomNav(api) {
  const user = api.getCurrentUser();
  const site = api.container.lookup("service:site");
  const u = user?.username;

  const nav = document.createElement("nav");
  nav.className = "ig-bottom-nav";
  nav.setAttribute("aria-label", i18n(themePrefix("ig.rail.home")));

  const exploreId = parseInt(settings.instagram_explore_category, 10) || 0;
  const exploreCategory = (site?.categories || []).find(
    (c) => c.id === exploreId
  );
  const exploreHref = !exploreId
    ? "/categories"
    : exploreCategory?.url
      ? `${exploreCategory.url}/l/latest`
      : `/c/${exploreId}/l/latest`;

  const items = [
    { key: "home", href: "/" },
    { key: "explore", href: exploreHref },
    { key: "create", button: true },
    { key: "messages", href: u ? `/u/${u}/messages` : "/login" },
    { key: "profile", href: u ? `/u/${u}/summary` : "/login" },
  ];

  for (const item of items) {
    const el = document.createElement(item.button ? "button" : "a");
    el.className = `ig-bottom-nav__item ig-bottom-nav__item--${item.key}`;
    el.dataset.key = item.key;
    el.setAttribute("aria-label", i18n(themePrefix(`ig.rail.${item.key}`)));
    if (item.button) {
      el.type = "button";
      el.addEventListener("click", () => {
        if (!user) {
          DiscourseURL.routeTo("/login");
          return;
        }
        api.container.lookup("service:composer")?.openNewTopic({});
      });
    } else {
      el.href = item.href;
    }
    if (item.key === "profile" && user) {
      const img = document.createElement("img");
      img.className = "ig-bottom-nav__avatar";
      img.src = user.avatar_template.replace("{size}", "48");
      img.alt = "";
      el.append(img);
    } else {
      const ico = document.createElement("span");
      ico.className = `ig-bottom-nav__ico ig-bottom-nav__ico--${item.key}`;
      ico.setAttribute("aria-hidden", "true");
      el.append(ico);
    }
    nav.append(el);
  }

  document.body.append(nav);
  return nav;
}

function syncBottomNav(nav) {
  const path = window.location.pathname;
  const explore = document.body.classList.contains("ig-explore");
  nav.querySelectorAll(".ig-bottom-nav__item").forEach((el) => {
    const href = el.getAttribute("href");
    let active = false;
    if (el.dataset.key === "home") {
      active = path === "/" || path === "/latest";
    } else if (el.dataset.key === "explore") {
      active = explore || path === href;
    } else if (el.dataset.key === "messages") {
      active = href !== "/login" && path.startsWith(href);
    } else if (el.dataset.key === "profile") {
      active =
        href !== "/login" &&
        path.startsWith(href.replace(/\/summary$/, "")) &&
        !path.includes("/messages");
    }
    el.classList.toggle("active", active);
  });
}
