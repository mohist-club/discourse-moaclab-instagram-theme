import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";
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

      if (settings.instagram_desktop_shell && desktop) {
        document.body.classList.add("ig-desktop-shell");
        document.body.classList.toggle(
          "ig-hide-header",
          !!settings.instagram_hide_header
        );
        ensureRail(api, siteSettings);
      }
      if (settings.instagram_clean_feed && desktop) {
        document.body.classList.add("ig-clean-feed");
      }
      if (settings.instagram_stories) {
        ensureStories(api);
      }
      if (settings.instagram_right_sidebar && desktop) {
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
      href: "/categories",
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
    menuButton("more", "menu", () => accountGroups(user)),
    menuButton("apps", "apps", () => nativeLinkGroups())
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

// account menu: what Instagram's "More" holds, mapped to Discourse
function accountGroups(user) {
  if (!user) {
    return [
      [
        { href: "/login", icon: "profile", label: t("menu.log_in") },
        { href: "/signup", icon: "create", label: t("menu.sign_up") },
      ],
    ];
  }
  return [
    [
      { href: "/my/preferences", icon: "settings", label: t("menu.settings") },
      { href: "/my/activity", icon: "history", label: t("menu.your_activity") },
      {
        href: "/my/activity/bookmarks",
        icon: "bookmark",
        label: t("menu.saved"),
      },
    ],
    [
      {
        label: t("menu.log_out"),
        // Discourse's own sign-out (same call as the user menu)
        onClick: () => user.destroySession(),
      },
    ],
  ];
}

// every link the native sidebar renders: categories, custom links such as
// /typing and /viewer, admin, review ... read live so nothing is lost
function nativeLinkGroups() {
  const seen = new Set(["/"]);
  const items = [];
  document
    .querySelectorAll(
      ".sidebar-wrapper .sidebar-sections a.sidebar-section-link"
    )
    .forEach((link) => {
      const href = link.getAttribute("href");
      if (!href || seen.has(href)) {
        return;
      }
      seen.add(href);
      items.push({
        href,
        nativeIcon: link.querySelector(".sidebar-section-link-prefix"),
        label: (
          link.querySelector(".sidebar-section-link-content-text")
            ?.textContent ||
          link.textContent ||
          ""
        ).trim(),
      });
    });
  return items.length ? [items] : [];
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
  document.querySelectorAll("#ig-rail a.ig-rail-link").forEach((a) => {
    const href = a.getAttribute("href");
    if (!href || href === "/login") {
      a.classList.remove("active");
      return;
    }
    const active = href === "/" ? path === "/" : path.startsWith(href);
    a.classList.toggle("active", active);
  });
}

function isDiscovery() {
  const onList = document.querySelector("#main-outlet .topic-list");
  const inTopic = [...document.body.classList].some((c) =>
    c.startsWith("archetype-")
  );
  return !!onList && !inTopic;
}

// ---- Stories: people who posted most recently (Instagram's tray) ----
// Source: Discourse's latest-posts endpoint (public posts only). A ring opens
// that person's latest post; opened rings turn grey like Instagram's "seen",
// remembered only in this browser.
const STORY_TTL = 2 * 60 * 1000;
const STORY_MAX = 20;
const SEEN_KEY = "ig-stories-seen";
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
  if (storyCache && Date.now() - storyCache.at < STORY_TTL) {
    return storyCache.items;
  }

  const me = api.getCurrentUser()?.username;
  try {
    const result = await ajax("/posts.json");
    const people = new Set();
    const items = [];
    for (const post of result?.latest_posts || []) {
      if (
        !post.username ||
        post.user_id <= 0 ||
        post.username === me ||
        (post.post_type && post.post_type !== 1) ||
        people.has(post.username)
      ) {
        continue;
      }
      people.add(post.username);
      items.push({
        postId: post.id,
        label: post.username,
        href: `/t/${post.topic_slug}/${post.topic_id}/${post.post_number}`,
        imageUrl: post.avatar_template?.replace("{size}", "160"),
      });
      if (items.length >= STORY_MAX) {
        break;
      }
    }
    storyCache = { at: Date.now(), items };
    return items;
  } catch {
    return [];
  }
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
  const aside = document.createElement("aside");
  aside.className = "ig-right";

  if (user) {
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
      <a class="ig-right__action" href="/u/${user.username}/preferences/account">${escapeHtml(
        t("right.switch")
      )}</a>`;
    aside.append(me);
  }

  const site = api.container.lookup("service:site");
  const parent = suggestedParent(site);
  const sugg = document.createElement("section");
  sugg.className = "ig-right__sugg";
  sugg.innerHTML = `
    <div class="ig-right__head">
      <h2>${escapeHtml(t("right.suggested"))}</h2>
      <a href="${parent ? categoryUrl(parent) : "/u"}">${escapeHtml(
        t("right.see_all")
      )}</a>
    </div>
    <div class="ig-right__list"></div>`;
  aside.append(sugg);

  const links = [
    ["/about", "about"],
    ["/faq", "faq"],
    ["/badges", "badges"],
    ["/u", "users"],
    ["/tos", "tos"],
    ["/privacy", "privacy"],
    ["/categories", "categories"],
  ]
    .map(
      ([href, key]) => `<a href="${href}">${escapeHtml(t(`right.${key}`))}</a>`
    )
    .join('<span aria-hidden="true"> · </span>');

  const footer = document.createElement("footer");
  footer.className = "ig-right__footer";
  footer.innerHTML = `
    <nav class="ig-right__links">${links}</nav>
    <p class="ig-right__copy">© ${new Date().getFullYear()} ${escapeHtml(
      siteSettings?.title || "Moaclab"
    )}</p>`;
  aside.append(footer);

  wrap.append(aside);

  const listEl = sugg.querySelector(".ig-right__list");
  if (parent) {
    fillStudios(listEl, parent, site);
  } else {
    fillSuggestions(listEl);
  }
}

// "Suggested for you" = the studios: subcategories of the keyboard category.
// The parent comes from the instagram_suggested_category setting, or the
// top-level category named 键盘; with neither, fall back to active users.
function suggestedParent(site) {
  const categories = site?.categories || [];
  const id = parseInt(settings.instagram_suggested_category, 10);
  return (
    (id && categories.find((c) => c.id === id)) ||
    categories.find(
      (c) => !c.parent_category_id && c.name?.trim() === "键盘"
    ) ||
    null
  );
}

function categoryUrl(category, parent) {
  return parent
    ? `/c/${parent.slug}/${category.slug}/${category.id}`
    : `/c/${category.slug}/${category.id}`;
}

async function fillStudios(listEl, parent, site) {
  let studios = (site?.categories || []).filter(
    (c) => c.parent_category_id === parent.id
  );
  if (!studios.length) {
    // lazily loaded categories: ask Discourse for the subcategories
    try {
      const result = await ajax("/categories.json", {
        data: { parent_category_id: parent.id },
      });
      studios = result?.category_list?.categories || [];
    } catch {
      studios = [];
    }
  }
  if (!listEl.isConnected) {
    return;
  }
  if (!studios.length) {
    listEl.closest(".ig-right__sugg")?.remove();
    return;
  }

  // a fresh handful each visit, so every studio gets seen
  const picks = [...studios];
  for (let i = picks.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [picks[i], picks[j]] = [picks[j], picks[i]];
  }

  listEl.innerHTML = picks
    .slice(0, 5)
    .map((c) => {
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
        <a class="ig-right__action" href="${url}">${escapeHtml(
          t("right.view")
        )}</a>
      </div>`;
    })
    .join("");
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
