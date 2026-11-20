import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { NotificationLevels } from "discourse/lib/notification-levels";
import DiscourseURL from "discourse/lib/url";
import Category from "discourse/models/category";
import { i18n } from "discourse-i18n";

// Instagram desktop shell:
//  - a fixed Instagram left rail (#ig-rail): logo glyph, Home / Explore /
//    Messages / Search / Notifications / Create / Profile, and a bottom
//    "More" button that opens a floating menu (like instagram.com)
//  - a "stories" tray at the top of the discovery feed
//  - a right column (current user, suggestions, footer)
export default apiInitializer((api) => {
  const siteSettings = api.container.lookup("service:site-settings");

  // Read mobileView at render time (inside onPageChange), never during static
  // initialization, to avoid discourse.static-viewport-initialization.
  const ensure = () => {
    try {
      closeMorePanel();

      const site = api.container.lookup("service:site");
      const desktop = !site?.mobileView;

      // admin keeps Discourse's own sidebar, header and navigation
      const admin = isAdminPage();
      if (admin) {
        document.getElementById(RAIL_ID)?.remove();
      }

      if (settings.instagram_desktop_shell && desktop) {
        document.body.classList.add("ig-desktop-shell");
        document.body.classList.toggle(
          "ig-hide-header",
          !!settings.instagram_hide_header
        );
        if (!admin) {
          ensureRail(api, siteSettings);
        }
      }
      // Explore: the configured category (and its subcategories) as a grid
      const explore = isExplorePage(site);
      document.body.classList.toggle("ig-explore", explore);

      if (settings.instagram_clean_feed && desktop) {
        document.body.classList.add("ig-clean-feed");
      }
      // Stories only on the home page, as on instagram.com
      const home = window.location.pathname === "/";
      if (settings.instagram_stories && home) {
        ensureStories(api);
      } else {
        document.querySelector(".ig-stories")?.remove();
      }
      // Explore and the card-grid /categories page use the full width
      const categoriesGrid =
        settings.instagram_categories_page &&
        window.location.pathname.replace(/\/$/, "") === "/categories";
      if (explore || categoriesGrid) {
        document.querySelector(".ig-right")?.remove();
      } else if (settings.instagram_right_sidebar && desktop) {
        document.body.classList.add("ig-rightcol");
        ensureRightSidebar(api, siteSettings);
      }
      syncActive();
    } catch {
      // never let decoration break navigation
    }
  };

  api.onPageChange(ensure);
});

const RAIL_ID = "ig-rail";

function isAdminPage() {
  return (
    window.location.pathname.startsWith("/admin") ||
    document.body.classList.contains("admin-interface")
  );
}

function ensureRail(api, siteSettings) {
  const sections = document.querySelector(".sidebar-wrapper .sidebar-sections");
  if (!sections) {
    return;
  }
  if (sections.querySelector(`#${RAIL_ID}`)) {
    return;
  }

  const user = api.getCurrentUser();
  const u = user?.username;
  const rail = document.createElement("div");
  rail.id = RAIL_ID;

  // Logo row: collapsed it shows the small logo at nav-icon size; expanded
  // it crossfades to the full logo (its text part) — or, when the site has
  // no separate full logo, shows the site title as the row's label.
  const logo = document.createElement("a");
  logo.href = "/";
  const title = siteSettings?.title || "Moaclab";
  const smallUrl = siteSettings?.site_logo_small_url;
  const fullUrl = siteSettings?.site_logo_url;
  const useFull = !!fullUrl && fullUrl !== smallUrl;
  logo.className = `ig-logo ${useFull ? "ig-logo--full" : "ig-logo--text"}`;
  logo.setAttribute("aria-label", title);

  const glyph = document.createElement("span");
  glyph.className = "ig-logo-glyph";
  if (smallUrl || fullUrl) {
    const img = document.createElement("img");
    img.src = smallUrl || fullUrl;
    img.alt = "";
    glyph.append(img);
  } else {
    glyph.classList.add("ig-logo-glyph--letter");
    glyph.textContent = title.trim().charAt(0).toUpperCase();
  }
  logo.append(glyph);

  const word = document.createElement("span");
  word.className = "ig-logo-word";
  if (useFull) {
    const img = document.createElement("img");
    img.src = fullUrl;
    img.alt = "";
    word.append(img);
  } else {
    word.textContent = title;
  }
  logo.append(word);
  rail.append(logo);

  // primary nav, Instagram order: Home, Explore (Reels slot), Messages,
  // Search, Notifications, Create, Profile
  const nav = document.createElement("nav");
  nav.className = "ig-rail-nav";
  nav.setAttribute("aria-label", "navigation");

  const items = [
    { key: "home", href: "/", icon: "home", label: railLabel("home") },
    {
      key: "explore",
      href: exploreHref(api.container.lookup("service:site")),
      icon: "explore",
      label: railLabel("explore"),
    },
    {
      key: "messages",
      href: u ? `/u/${u}/messages` : "/login",
      icon: "messages",
      label: railLabel("messages"),
    },
    {
      key: "search",
      href: "/search",
      icon: "search",
      label: railLabel("search"),
    },
    {
      key: "activity",
      href: u ? `/u/${u}/notifications` : "/login",
      icon: "activity",
      label: railLabel("activity"),
    },
    {
      key: "create",
      href: "/new-topic",
      icon: "create",
      label: railLabel("create"),
    },
    {
      key: "profile",
      href: u ? `/u/${u}/summary` : "/login",
      avatar: user?.avatar_template?.replace("{size}", "48"),
      icon: "profile",
      label: railLabel("profile"),
    },
  ];

  for (const it of items) {
    nav.append(railLink(it));
  }
  rail.append(nav);

  // bottom group, like Instagram's "More" + "Also from Meta":
  //   更多       -> account menu (settings, activity, bookmarks, sign out)
  //   社区与工具 -> every link from the native Discourse sidebar
  const foot = document.createElement("div");
  foot.className = "ig-rail-foot";
  foot.append(
    menuButton("more", "menu", () => accountGroups(user, api)),
    menuButton("apps", "apps", () => toolGroups())
  );
  rail.append(foot);

  sections.prepend(rail);
}

function railLink(it) {
  const a = document.createElement("a");
  a.className = "ig-rail-link";
  a.href = it.href;
  a.dataset.key = it.key;

  const ico = document.createElement("span");
  if (it.avatar) {
    ico.className = "ig-rail-ico ig-rail-ico--avatar";
    const img = document.createElement("img");
    img.src = it.avatar;
    img.alt = "";
    ico.append(img);
  } else {
    ico.className = `ig-rail-ico ig-rail-ico--${it.icon}`;
  }

  const label = document.createElement("span");
  label.className = "ig-rail-label";
  label.textContent = it.label;

  a.append(ico, label);
  return a;
}

// ---- floating menus (Instagram-style "More" panel) ----
let morePanelCleanup = null;

function menuButton(key, icon, groups) {
  const btn = document.createElement("button");
  btn.type = "button";
  btn.className = "ig-rail-link ig-rail-menu-btn";
  btn.dataset.key = key;
  btn.setAttribute("aria-haspopup", "menu");
  btn.setAttribute("aria-expanded", "false");
  btn.innerHTML = `<span class="ig-rail-ico ig-rail-ico--${icon}"></span><span class="ig-rail-label">${railLabel(
    key
  )}</span>`;
  btn.addEventListener("click", (event) => {
    event.stopPropagation();
    const wasOpen = btn.getAttribute("aria-expanded") === "true";
    closeMorePanel();
    if (!wasOpen) {
      openMorePanel(groups(), btn);
    }
  });
  return btn;
}

// More: settings, invite, your activity, saved, all categories, dark mode,
// admin (staff), log out — each the native Discourse page or action
function accountGroups(user, api) {
  const interfaceColor = api.container.lookup("service:interface-color");
  const darkMode = interfaceColor?.selectorAvailable
    ? {
        icon: "moon",
        label: t("menu.dark_mode"),
        toggle: true,
        checked: () => !!interfaceColor.darkModeActive,
        // Discourse's own colour-mode switch (cookie + stylesheet flip)
        onToggle: () =>
          interfaceColor.darkModeActive
            ? interfaceColor.forceLightMode()
            : interfaceColor.forceDarkMode(),
      }
    : null;
  const allCategories = {
    href: "/categories",
    icon: "grid",
    label: t("menu.categories"),
  };

  if (!user) {
    return [
      [
        { href: "/login", icon: "profile", label: t("menu.log_in") },
        { href: "/signup", icon: "create", label: t("menu.sign_up") },
      ],
      [allCategories, darkMode].filter(Boolean),
    ];
  }
  return [
    [
      { href: "/my/preferences", icon: "settings", label: t("menu.settings") },
      user.can_invite_to_forum
        ? { href: "/new-invite", icon: "share", label: t("menu.invite") }
        : null,
      { href: "/my/activity", icon: "history", label: t("menu.your_activity") },
      {
        href: "/my/activity/bookmarks",
        icon: "bookmark",
        label: t("menu.saved"),
      },
      allCategories,
      darkMode,
      user.staff
        ? { href: "/admin", icon: "shield", label: t("menu.admin") }
        : null,
    ].filter(Boolean),
    [
      {
        label: t("menu.log_out"),
        // Discourse's own sign-out (same call as the user menu)
        onClick: () => user.destroySession(),
      },
    ],
  ];
}

// The sidebar section named in instagram_tools_section (服务: Typing,
// 图纸预览, 团购 …), read live so labels, links and icons stay whatever the
// sidebar says. Shared by the 社区与工具 menu and the right-column module.
function toolLinks() {
  const name = String(settings.instagram_tools_section || "").trim();
  const sections = [
    ...document.querySelectorAll(
      ".sidebar-wrapper .sidebar-section-wrapper, .sidebar-wrapper .sidebar-section"
    ),
  ];
  const section = sections.find(
    (sec) =>
      sec
        .querySelector(".sidebar-section-header-text, .sidebar-section-header")
        ?.textContent.trim() === name
  );
  const anchors = section
    ? [...section.querySelectorAll("a.sidebar-section-link")]
    : [];
  const links = linkItems(anchors, new Set());
  // the admin sidebar does not render the section: keep the last one seen
  if (links.length) {
    lastToolLinks = links;
  }
  return { name, links: links.length ? links : lastToolLinks };
}

let lastToolLinks = [];

function linkItems(anchors, seen) {
  const items = [];
  for (const link of anchors) {
    const href = link.getAttribute("href");
    if (!href || seen.has(href)) {
      continue;
    }
    seen.add(href);
    items.push({
      href,
      nativeIcon: link.querySelector(".sidebar-section-link-prefix"),
      label: (
        link.querySelector(".sidebar-section-link-content-text")?.textContent ||
        link.textContent ||
        ""
      ).trim(),
    });
  }
  return items;
}

// 社区与工具: the tools section; if the site has no such section, every
// native sidebar link instead, so nothing becomes unreachable
function toolGroups() {
  const { links } = toolLinks();
  if (links.length) {
    return [links];
  }
  const all = linkItems(
    document.querySelectorAll(
      ".sidebar-wrapper .sidebar-sections a.sidebar-section-link"
    ),
    new Set(["/"])
  );
  return all.length ? [all] : [];
}

function openMorePanel(groups, anchor) {
  const panel = document.createElement("div");
  panel.className = "ig-more-panel";
  panel.setAttribute("role", "menu");

  for (const group of groups) {
    if (!group.length) {
      continue;
    }
    const g = document.createElement("div");
    g.className = "ig-more-group";
    for (const it of group) {
      const el = document.createElement(it.href ? "a" : "button");
      el.className = "ig-more-item";
      el.setAttribute("role", "menuitem");
      if (it.href) {
        el.href = it.href;
      } else if (it.toggle) {
        // a switch: flips in place, the menu stays open
        el.type = "button";
        el.setAttribute("role", "menuitemcheckbox");
        el.classList.add("ig-more-item--toggle");
        const sync = () =>
          el.setAttribute("aria-checked", String(!!it.checked()));
        sync();
        el.addEventListener("click", () => {
          it.onToggle();
          sync();
        });
      } else {
        el.type = "button";
        el.addEventListener("click", () => {
          closeMorePanel();
          it.onClick?.();
        });
      }
      if (it.nativeIcon) {
        const ico = document.createElement("span");
        ico.className = "ig-more-native-ico";
        ico.append(it.nativeIcon.cloneNode(true));
        el.append(ico);
      } else if (it.icon) {
        const ico = document.createElement("span");
        ico.className = `ig-rail-ico ig-rail-ico--${it.icon}`;
        el.append(ico);
      }
      const text = document.createElement("span");
      text.textContent = it.label;
      el.append(text);
      if (it.toggle) {
        const sw = document.createElement("span");
        sw.className = "ig-more-switch";
        sw.setAttribute("aria-hidden", "true");
        el.append(sw);
      }
      g.append(el);
    }
    panel.append(g);
  }
  if (!panel.childElementCount) {
    return;
  }

  document.body.append(panel);

  // open above the button, left-aligned with the rail
  const r = anchor.getBoundingClientRect();
  panel.style.left = `${Math.max(8, r.left)}px`;
  panel.style.bottom = `${Math.max(8, window.innerHeight - r.top + 8)}px`;

  anchor.classList.add("active");
  anchor.setAttribute("aria-expanded", "true");

  const onPointer = (event) => {
    if (!panel.contains(event.target) && !anchor.contains(event.target)) {
      closeMorePanel();
    }
  };
  const onKey = (event) => {
    if (event.key === "Escape") {
      closeMorePanel();
      anchor.focus();
    }
  };
  const onClick = (event) => {
    if (event.target.closest("a")) {
      closeMorePanel();
    }
  };
  document.addEventListener("pointerdown", onPointer);
  document.addEventListener("keydown", onKey);
  panel.addEventListener("click", onClick);

  morePanelCleanup = () => {
    document.removeEventListener("pointerdown", onPointer);
    document.removeEventListener("keydown", onKey);
    panel.remove();
    anchor.classList.remove("active");
    anchor.setAttribute("aria-expanded", "false");
  };
}

function closeMorePanel() {
  morePanelCleanup?.();
  morePanelCleanup = null;
}

function syncActive() {
  const path = window.location.pathname;
  const explore = document.body.classList.contains("ig-explore");
  document.querySelectorAll("#ig-rail a.ig-rail-link").forEach((a) => {
    const href = a.getAttribute("href");
    if (!href || href === "/login") {
      a.classList.remove("active");
      return;
    }
    if (a.querySelector(".ig-rail-ico--explore") && exploreCategoryId()) {
      a.classList.toggle("active", explore);
      return;
    }
    const active = href === "/" ? path === "/" : path.startsWith(href);
    a.classList.toggle("active", active);
  });
}

// ---- Explore: one category (instagram_explore_category) as Instagram's
// Explore grid. The rail opens its topic list (/l/latest, so a category
// set to show subcategories first still lists topics).
function exploreCategoryId() {
  return parseInt(settings.instagram_explore_category, 10) || 0;
}

function findCategory(site, id) {
  return (
    (site?.categories || []).find((c) => c.id === id) ||
    Category.findById?.(id) ||
    null
  );
}

function exploreHref(site) {
  const id = exploreCategoryId();
  if (!id) {
    return "/categories";
  }
  const category = findCategory(site, id);
  return category?.url ? `${category.url}/l/latest` : `/c/${id}/l/latest`;
}

// a topic list of the explore category or one of its subcategories
function isExplorePage(site) {
  const id = exploreCategoryId();
  const match = window.location.pathname.match(/^\/c\/(.+)$/);
  if (!id || !match) {
    return false;
  }
  // /c/<parent>/<slug>/<id>[/l/<filter>|/none|/all]: the last number
  const path = match[1].split("/l/")[0];
  const current = parseInt(
    path
      .split("/")
      .filter((part) => /^\d+$/.test(part))
      .pop(),
    10
  );
  if (!current) {
    return false;
  }
  return (
    current === id || findCategory(site, current)?.parent_category_id === id
  );
}

function isDiscovery() {
  const onList = document.querySelector("#main-outlet .topic-list");
  const inTopic = [...document.body.classList].some((c) =>
    c.startsWith("archetype-")
  );
  return !!onList && !inTopic;
}

// ---- shared: the latest-topics list (stories + studio recency) ----
const FEED_TTL = 2 * 60 * 1000;
let latestPromise = null;
let latestAt = 0;

function loadLatest() {
  if (!latestPromise || Date.now() - latestAt > FEED_TTL) {
    latestAt = Date.now();
    latestPromise = ajax("/latest.json").catch(() => null);
  }
  return latestPromise;
}

// ---- Stories: the people active most recently (Instagram's tray) ----
// Newest activity first, one ring per person (not you, not system accounts):
//  1. authors of Discourse's latest public posts;
//  2. everyone taking part in the latest topics;
//  3. topped up from the user directory (most days visited this week, then
//     this month, this year, all time) until the tray holds STORY_MAX.
// A ring opens that person's newest post or topic (directory people: their
// profile); opened rings turn grey like Instagram's "seen" (remembered only
// in this browser) and light up again when that person has something newer.
const STORY_MAX = 20;
const SEEN_KEY = "ig-stories-seen";
const DIRECTORY_PERIODS = ["weekly", "monthly", "yearly", "all"];
let storyCache = null;

function ensureStories(api) {
  const existing = document.querySelector(".ig-stories");
  const list = isDiscovery()
    ? document.querySelector("#main-outlet .topic-list")
    : null;

  if (!list) {
    existing?.remove();
    return;
  }
  if (existing && existing.nextElementSibling === list) {
    return;
  }
  existing?.remove();

  const tray = document.createElement("section");
  tray.className = "ig-stories";
  tray.setAttribute("aria-label", t("stories.label"));

  const track = document.createElement("div");
  track.className = "ig-stories__track";
  tray.append(track);

  const prev = storyNav("prev", -1, track);
  const next = storyNav("next", 1, track);
  tray.append(prev, next);

  const syncNav = () => {
    const max = track.scrollWidth - track.clientWidth;
    prev.hidden = track.scrollLeft <= 1;
    next.hidden = track.scrollLeft >= max - 1;
  };
  track.addEventListener("scroll", syncNav, { passive: true });
  prev.hidden = next.hidden = true;

  list.parentElement.insertBefore(tray, list);

  loadStoryItems(api).then((items) => {
    if (!tray.isConnected) {
      return;
    }
    if (!items.length) {
      tray.remove();
      return;
    }
    const seen = readSeen();
    // unseen first (newest first), then seen — as Instagram orders it
    const ordered = [
      ...items.filter((i) => !seen.has(i.postId)),
      ...items.filter((i) => seen.has(i.postId)),
    ];
    for (const item of ordered) {
      track.append(storyNode({ ...item, seen: seen.has(item.postId) }));
    }
    syncNav();
  });
}

async function loadStoryItems(api) {
  if (storyCache && Date.now() - storyCache.at < FEED_TTL) {
    return storyCache.items;
  }

  const me = api.getCurrentUser()?.username;
  const people = new Map();
  // `when` is the activity time; directory people have none (0) and keep
  // the directory's order after everyone with a known time
  const consider = (username, userId, when, href, avatarTemplate, postId) => {
    if (!username || username === me || !(userId > 0) || !avatarTemplate) {
      return;
    }
    const prev = people.get(username);
    if (prev && prev.when >= when) {
      return;
    }
    people.set(username, {
      label: username,
      when,
      href,
      postId,
      imageUrl: avatarTemplate.replace("{size}", "160"),
    });
  };

  const [posts, latest] = await Promise.all([
    ajax("/posts.json").catch(() => null),
    loadLatest(),
  ]);

  for (const post of posts?.latest_posts || []) {
    if (post.post_type && post.post_type !== 1) {
      continue;
    }
    consider(
      post.username,
      post.user_id,
      Date.parse(post.created_at) || 1,
      `/t/${post.topic_slug}/${post.topic_id}/${post.post_number}`,
      post.avatar_template,
      `p${post.id}`
    );
  }

  const users = new Map((latest?.users || []).map((u) => [u.id, u]));
  for (const topic of latest?.topic_list?.topics || []) {
    const bumped = Date.parse(topic.bumped_at || topic.last_posted_at) || 1;
    const created = Date.parse(topic.created_at) || 1;
    (topic.posters || []).forEach((poster, index) => {
      const user = users.get(poster.user_id);
      if (!user) {
        return;
      }
      const isLast =
        /latest/.test(poster.extras || "") ||
        user.username === topic.last_poster_username;
      if (isLast) {
        consider(
          user.username,
          user.id,
          bumped,
          `/t/${topic.slug}/${topic.id}/last`,
          user.avatar_template,
          `t${topic.id}-${topic.highest_post_number}`
        );
      } else {
        // the original poster (first) or a frequent / recent replier: the
        // exact time is unknown, but they were active since it was created
        consider(
          user.username,
          user.id,
          created,
          `/t/${topic.slug}/${topic.id}`,
          user.avatar_template,
          index === 0 ? `t${topic.id}-op` : `t${topic.id}-u${user.id}`
        );
      }
    });
  }

  for (const period of DIRECTORY_PERIODS) {
    if (people.size >= STORY_MAX) {
      break;
    }
    let result = null;
    try {
      result = await ajax("/directory_items.json", {
        data: { period, order: "days_visited" },
      });
    } catch {
      break; // directory disabled or hidden from this visitor
    }
    for (const item of result?.directory_items || []) {
      const user = item.user;
      if (user && !people.has(user.username)) {
        consider(
          user.username,
          user.id,
          0,
          `/u/${user.username}/activity`,
          user.avatar_template,
          `u-${user.username}`
        );
      }
    }
  }

  // stable sort: people with the same time keep their directory order
  const items = [...people.values()]
    .sort((x, y) => y.when - x.when)
    .slice(0, STORY_MAX);
  storyCache = { at: Date.now(), items };
  return items;
}

function readSeen() {
  try {
    return new Set(JSON.parse(localStorage.getItem(SEEN_KEY) || "[]"));
  } catch {
    return new Set();
  }
}

function markSeen(postId) {
  try {
    const seen = [...readSeen()].filter((id) => id !== postId);
    seen.push(postId);
    localStorage.setItem(SEEN_KEY, JSON.stringify(seen.slice(-300)));
  } catch {
    // storage unavailable: the ring just stays coloured
  }
}

function storyNav(direction, sign, track) {
  const btn = document.createElement("button");
  btn.type = "button";
  btn.className = `ig-stories__nav ig-stories__nav--${direction}`;
  btn.setAttribute("aria-label", t(`stories.${direction}`));
  btn.addEventListener("click", () => {
    track.scrollBy({ left: sign * track.clientWidth * 0.8 });
  });
  return btn;
}

function storyNode({ href, label, imageUrl, postId, seen }) {
  const a = document.createElement("a");
  a.className = `ig-story${seen ? " is-seen" : ""}`;
  a.href = href;
  a.addEventListener("click", () => {
    markSeen(postId);
    a.classList.add("is-seen");
  });

  const ring = document.createElement("span");
  ring.className = "ig-story__ring";

  const av = document.createElement("span");
  av.className = "ig-story__avatar";
  if (imageUrl) {
    const img = document.createElement("img");
    img.src = imageUrl;
    img.alt = "";
    av.append(img);
  } else {
    av.textContent = (label || "·").trim().charAt(0);
  }

  const text = document.createElement("span");
  text.className = "ig-story__label";
  text.textContent = label;

  ring.append(av);
  a.append(ring, text);
  return a;
}

// UI text lives in locales/ (AGENTS.md)
function t(key, options) {
  return i18n(themePrefix(`ig.${key}`), options);
}

function railLabel(key) {
  return t(`rail.${key}`);
}

// ---- Instagram right column: current user + suggestions + footer ----

function ensureRightSidebar(api, siteSettings) {
  // Inject as a sibling of #main-outlet inside #main-outlet-wrapper so it
  // becomes a real grid column (see right-sidebar.scss), not an overlay.
  const wrap = document.querySelector("#main-outlet-wrapper");
  if (!wrap || !isDiscovery()) {
    document.querySelector(".ig-right")?.remove();
    return;
  }
  if (wrap.querySelector(".ig-right")) {
    return;
  }

  const user = api.getCurrentUser();
  const site = api.container.lookup("service:site");
  const title = siteSettings?.title || "Moaclab";
  const aside = document.createElement("aside");
  aside.className = "ig-right";

  // 1. you — or, logged out, the sign-up / log-in module
  // logged out there is no "you" row: log in / sign up live in the rail's
  // More menu (and every rail item that needs an account leads to /login)
  if (user) {
    aside.append(meBlock(user));
  }

  // 2. suggested studios
  const sugg = document.createElement("section");
  sugg.className = "ig-right__sugg";
  sugg.innerHTML = `
    <div class="ig-right__head">
      <h2>${escapeHtml(t("right.suggested"))}</h2>
      <button type="button" class="ig-right__refresh" hidden title="${escapeHtml(
        t("right.refresh")
      )}" aria-label="${escapeHtml(t("right.refresh"))}"></button>
    </div>
    <div class="ig-right__list"></div>`;
  aside.append(sugg);

  // 3. tools from the sidebar's 服务 section (Typing, 图纸, 团购 …)
  const tools = toolsBlock();
  if (tools) {
    aside.append(tools);
  }

  // 4. footer: site pages, then all categories, tags and the Q&A category
  const links = [
    ["/about", t("right.about")],
    ["/faq", t("right.faq")],
    ["/badges", t("right.badges")],
    ["/u", t("right.users")],
    ["/tos", t("right.tos")],
    ["/privacy", t("right.privacy")],
    ["/categories", t("right.categories")],
    ["/tags", t("right.tags")],
    qaLink(site),
  ]
    .filter(Boolean)
    .map(([href, label]) => `<a href="${href}">${escapeHtml(label)}</a>`)
    .join('<span aria-hidden="true"> · </span>');

  const footer = document.createElement("footer");
  footer.className = "ig-right__footer";
  footer.innerHTML = `
    <nav class="ig-right__links">${links}</nav>
    <p class="ig-right__copy">© ${new Date().getFullYear()} ${escapeHtml(
      title
    )}</p>`;
  aside.append(footer);

  wrap.append(aside);

  const listEl = sugg.querySelector(".ig-right__list");
  suggestedParents(site).then((parents) => {
    if (!listEl.isConnected) {
      return;
    }
    if (!parents.length) {
      fillSuggestions(listEl);
      return;
    }
    fillStudios(
      listEl,
      parents,
      site,
      user,
      sugg.querySelector(".ig-right__refresh")
    );
  });
}

// the 问答与求助 category (instagram_qa_category, default 4 = /c/faq/4):
// its own name and URL when loaded, else the plain /c/<id> link
function qaLink(site) {
  const id = parseInt(settings.instagram_qa_category, 10) || 0;
  if (!id) {
    return null;
  }
  const category = findCategory(site, id);
  return [category?.url || `/c/${id}`, category?.name?.trim() || t("right.qa")];
}

function meBlock(user) {
  const me = document.createElement("div");
  me.className = "ig-right__me";
  me.innerHTML = `
    <a class="ig-right__avatar" href="/u/${user.username}/summary">
      <img src="${user.avatar_template.replace("{size}", "96")}" alt="">
    </a>
    <div class="ig-right__text">
      <a class="ig-right__user" href="/u/${user.username}/summary">${escapeHtml(
        user.username
      )}</a>
      <span class="ig-right__sub">${escapeHtml(user.name || "")}</span>
    </div>
    <a class="ig-right__action" href="/u/${user.username}/summary">${escapeHtml(
      t("right.profile")
    )}</a>`;
  return me;
}

// The sidebar's 服务 custom section (name in instagram_tools_section), read
// live so labels, links and icons stay whatever the sidebar says.
function toolsBlock() {
  const { name, links } = toolLinks();
  if (!links.length) {
    return null;
  }

  const block = document.createElement("section");
  block.className = "ig-right__tools";
  const head = document.createElement("div");
  head.className = "ig-right__head";
  const h2 = document.createElement("h2");
  h2.textContent = name || t("right.tools");
  head.append(h2);
  block.append(head);

  for (const item of links) {
    const row = document.createElement("a");
    row.className = "ig-right__row ig-right__tool";
    row.href = item.href;

    const icon = document.createElement("span");
    icon.className = "ig-right__tool-icon";
    if (item.nativeIcon) {
      icon.append(item.nativeIcon.cloneNode(true));
    }

    const label = document.createElement("span");
    label.className = "ig-right__user";
    label.textContent = item.label;

    const open = document.createElement("span");
    open.className = "ig-right__action";
    open.textContent = t("right.open");

    const text = document.createElement("span");
    text.className = "ig-right__text";
    text.append(label);

    row.append(icon, text, open);
    block.append(row);
  }
  return block;
}

// "Suggested for you" = the studios: subcategories of the keyboard / keycap
// categories. Parents are the category IDs in instagram_suggested_categories
// (default 13 = /c/keyboards/13). With the setting empty, top-level
// categories are matched by slug or name instead; with none, active users.
// A configured ID is resolved even when the browser has not loaded that
// category yet (sites with lazily loaded categories).
const DEFAULT_PARENT_KEYS = ["keyboards", "keycaps", "键盘", "键帽库", "键帽"];
const STUDIO_MAX = 5;
let parentsPromise = null;

function suggestedParents(site) {
  parentsPromise ||= resolveParents(site).catch(() => []);
  return parentsPromise;
}

async function resolveParents(site) {
  const categories = site?.categories || [];
  const ids = String(settings.instagram_suggested_categories || "")
    .split("|")
    .map((v) => parseInt(v, 10))
    .filter((id) => id > 0);

  if (!ids.length) {
    return categories.filter(
      (c) =>
        !c.parent_category_id &&
        (DEFAULT_PARENT_KEYS.includes(c.slug?.toLowerCase()) ||
          DEFAULT_PARENT_KEYS.includes(c.name?.trim()))
    );
  }

  const parents = await Promise.all(
    ids.map(async (id) => {
      const known =
        categories.find((c) => c.id === id) || Category.findById?.(id);
      if (known) {
        return known;
      }
      try {
        const result = await ajax(`/c/${id}/show.json`);
        return result?.category || null;
      } catch {
        return null;
      }
    })
  );
  return parents.filter(Boolean);
}

function categoryUrl(category, parent) {
  if (!category.slug) {
    return `/c/${category.id}`;
  }
  return parent?.slug
    ? `/c/${parent.slug}/${category.slug}/${category.id}`
    : `/c/${category.slug}/${category.id}`;
}

function shuffled(list) {
  const out = [...list];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

async function fillStudios(listEl, parents, site, user, refreshBtn) {
  const studios = [];
  for (const parent of parents) {
    // ask Discourse for the full list of subcategories (the browser may hold
    // only some of them); fall back to what is loaded if that fails
    let subs = [];
    try {
      const result = await ajax("/categories.json", {
        data: { parent_category_id: parent.id },
      });
      subs = (result?.category_list?.categories || []).filter(
        (c) => c.id !== parent.id
      );
    } catch {
      subs = [];
    }
    if (!subs.length) {
      subs = (site?.categories || []).filter(
        (c) => c.parent_category_id === parent.id
      );
    }
    for (const c of subs) {
      studios.push({ category: c, parent });
    }
  }

  // newest activity first: when a studio last appeared in the latest topics
  const latest = await loadLatest();
  const lastActive = new Map();
  for (const topic of latest?.topic_list?.topics || []) {
    const when = Date.parse(topic.bumped_at || topic.last_posted_at) || 0;
    if (when > (lastActive.get(topic.category_id) || 0)) {
      lastActive.set(topic.category_id, when);
    }
  }

  if (!listEl.isConnected) {
    return;
  }
  if (!studios.length) {
    listEl.closest(".ig-right__sugg")?.remove();
    return;
  }

  const active = studios
    .filter((s) => lastActive.has(s.category.id))
    .sort(
      (x, y) => lastActive.get(y.category.id) - lastActive.get(x.category.id)
    );
  const quiet = shuffled(studios.filter((s) => !lastActive.has(s.category.id)));
  let shown = [...active, ...quiet].slice(0, STUDIO_MAX);

  const render = () => {
    listEl.innerHTML = shown
      .map((s) => studioRow(s.category, s.parent))
      .join("");
  };
  render();

  listEl.addEventListener("click", (event) => {
    const btn = event.target.closest(".ig-right__follow");
    if (btn) {
      toggleFollow(btn, user);
    }
  });

  // "换一批": a random handful, preferring studios not on screen
  if (refreshBtn && studios.length > STUDIO_MAX) {
    refreshBtn.hidden = false;
    refreshBtn.addEventListener("click", () => {
      const current = new Set(shown.map((s) => s.category.id));
      const fresh = shuffled(
        studios.filter((s) => !current.has(s.category.id))
      );
      const rest = shuffled(studios.filter((s) => current.has(s.category.id)));
      shown = [...fresh, ...rest].slice(0, STUDIO_MAX);
      render();
    });
  }
}

function studioRow(c, parent) {
  const url = categoryUrl(c, parent);
  const logo = c.uploaded_logo?.url;
  const avatar = logo
    ? `<img src="${escapeHtml(logo)}" alt="">`
    : `<span class="ig-right__letter" style="background:#${escapeHtml(
        c.color || "8e8e8e"
      )}">${escapeHtml((c.name || "·").trim().charAt(0))}</span>`;
  const subtitle =
    (c.description_text || "").trim() ||
    t("right.topics", { count: c.topic_count || 0 });
  return `
      <div class="ig-right__row">
        <a class="ig-right__avatar" href="${url}">${avatar}</a>
        <div class="ig-right__text">
          <a class="ig-right__user" href="${url}">${escapeHtml(c.name)}</a>
          <span class="ig-right__sub">${escapeHtml(subtitle)}</span>
        </div>
        ${followButton(c.id, isFollowing(c.notification_level))}
      </div>`;
}

// Instagram's "Follow" = Discourse's native category notification level:
// following a studio sets "watching first post" (a notification for each new
// topic, not every reply); unfollowing returns it to normal.
function isFollowing(level) {
  return (
    level === NotificationLevels.WATCHING ||
    level === NotificationLevels.WATCHING_FIRST_POST
  );
}

function followButton(categoryId, following) {
  return `<button type="button" class="ig-right__action ig-right__follow${
    following ? " is-following" : ""
  }" data-category-id="${categoryId}" aria-pressed="${following}">${escapeHtml(
    t(following ? "right.following" : "right.follow")
  )}</button>`;
}

async function toggleFollow(btn, user) {
  if (!user) {
    DiscourseURL.routeTo("/login");
    return;
  }
  if (btn.disabled) {
    return;
  }

  const id = parseInt(btn.dataset.categoryId, 10);
  const following = btn.classList.contains("is-following");
  const level = following
    ? NotificationLevels.REGULAR
    : NotificationLevels.WATCHING_FIRST_POST;

  btn.disabled = true;
  try {
    const category = Category.findById(id);
    if (category) {
      await category.setNotification(level);
    } else {
      await ajax(`/category/${id}/notifications`, {
        type: "POST",
        data: { notification_level: level },
      });
    }
    btn.classList.toggle("is-following", !following);
    btn.setAttribute("aria-pressed", String(!following));
    btn.textContent = t(following ? "right.follow" : "right.following");
  } catch (error) {
    popupAjaxError(error);
  } finally {
    btn.disabled = false;
  }
}

let suggestionCache = null;

function fillSuggestions(listEl) {
  if (!listEl) {
    return;
  }

  const render = (users) => {
    if (!users?.length) {
      listEl.closest(".ig-right__sugg")?.remove();
      return;
    }
    listEl.innerHTML = users
      .slice(0, 5)
      .map(
        (u) => `
      <div class="ig-right__row">
        <a class="ig-right__avatar" href="/u/${u.username}">
          <img src="${u.avatar_template.replace("{size}", "96")}" alt="">
        </a>
        <div class="ig-right__text">
          <a class="ig-right__user" href="/u/${u.username}">${escapeHtml(
            u.username
          )}</a>
          <span class="ig-right__sub">${escapeHtml(
            u.name || t("right.fallback_subtitle")
          )}</span>
        </div>
        <a class="ig-right__action" href="/u/${u.username}">${escapeHtml(
          t("right.view")
        )}</a>
      </div>`
      )
      .join("");
  };

  if (suggestionCache) {
    render(suggestionCache);
    return;
  }

  ajax("/directory_items.json", {
    data: { period: "weekly", order: "likes_received", page: 0 },
  })
    .then((r) => {
      suggestionCache = (r?.directory_items || [])
        .map((d) => d.user)
        .filter(Boolean);
      render(suggestionCache);
    })
    .catch(() => render([]));
}

function escapeHtml(str) {
  return String(str).replace(
    /[&<>"']/g,
    (c) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      })[c]
  );
}
