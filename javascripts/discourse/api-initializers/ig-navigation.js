import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";

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
        ensureStories(api, site);
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

  // logo slot: Instagram shows only a glyph here. Use the site's small logo
  // (what Discourse's own header uses), falling back to the site title.
  const logo = document.createElement("a");
  logo.className = "ig-logo";
  logo.href = "/";
  const logoUrl = siteSettings?.site_logo_small_url;
  const title = siteSettings?.title || "Moaclab";
  logo.setAttribute("aria-label", title);
  if (logoUrl) {
    const img = document.createElement("img");
    img.src = logoUrl;
    img.alt = title;
    logo.append(img);
  } else {
    const text = document.createElement("span");
    text.className = "ig-logo-text";
    text.textContent = title;
    logo.append(text);
  }
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
        { href: "/login", icon: "profile", label: "登录" },
        { href: "/signup", icon: "create", label: "注册" },
      ],
    ];
  }
  return [
    [
      { href: "/my/preferences", icon: "settings", label: "设置" },
      { href: "/my/activity", icon: "activity", label: "你的动态" },
      { href: "/my/activity/bookmarks", icon: "bookmark", label: "已收藏" },
    ],
    [
      {
        label: "退出",
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

function ensureStories(api, site) {
  const existing = document.querySelector(".ig-stories");

  if (!isDiscovery()) {
    existing?.remove();
    return;
  }

  const list = document.querySelector("#main-outlet .topic-list");
  if (!list) {
    existing?.remove();
    return;
  }
  if (existing && existing.nextElementSibling === list) {
    return;
  }
  existing?.remove();

  const tray = document.createElement("div");
  tray.className = "ig-stories";
  tray.setAttribute("aria-label", "Stories");

  const user = api.getCurrentUser();
  tray.append(
    storyNode({
      href: "/new-topic",
      label: user ? user.username : railLabel("your_story"),
      mine: true,
      avatarUrl: user?.avatar_template?.replace("{size}", "120"),
      fallback: user?.username,
    })
  );

  const categories = (site?.categories || [])
    .filter((c) => !c.parent_category_id)
    .slice(0, 16);

  for (const c of categories) {
    tray.append(
      storyNode({
        href: `/c/${c.slug}/${c.id}`,
        label: c.name,
        color: c.color,
        fallback: c.name,
      })
    );
  }

  list.parentElement.insertBefore(tray, list);
}

function storyNode({ href, label, mine, color, avatarUrl, fallback }) {
  const a = document.createElement("a");
  a.className = "ig-story" + (mine ? " ig-story--mine" : "");
  a.href = href;

  const ring = document.createElement("span");
  ring.className = "ig-story__ring";

  const av = document.createElement("span");
  av.className = "ig-story__avatar";
  if (color) {
    av.style.background = `#${color}`;
  }
  if (avatarUrl) {
    const img = document.createElement("img");
    img.src = avatarUrl;
    img.alt = "";
    av.append(img);
  } else {
    av.textContent = (fallback || "·").trim().charAt(0);
  }

  const text = document.createElement("span");
  text.className = "ig-story__label";
  text.textContent = label;

  ring.append(av);
  a.append(ring, text);
  return a;
}

function railLabel(key) {
  const map = {
    home: "首页",
    explore: "探索",
    messages: "消息",
    search: "搜索",
    activity: "通知",
    create: "创建",
    profile: "主页",
    more: "更多",
    apps: "社区与工具",
    your_story: "你的故事",
  };
  return map[key] || key;
}

// ---- Instagram right column: current user + suggestions + footer ----
let suggestionCache = null;

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
      <a class="ig-right__me-av" href="/u/${user.username}/summary">
        <img src="${user.avatar_template.replace("{size}", "132")}" alt="">
      </a>
      <div class="ig-right__me-text">
        <a class="ig-right__me-user" href="/u/${user.username}/summary">${user.username}</a>
        <span class="ig-right__me-name">${escapeHtml(user.name || "")}</span>
      </div>
      <a class="ig-right__switch" href="/u/${user.username}/preferences/account">切换</a>`;
    aside.append(me);
  }

  const sugg = document.createElement("div");
  sugg.className = "ig-right__sugg";
  sugg.innerHTML = `
    <div class="ig-right__sugg-head">
      <span>为你推荐</span>
      <a href="/u">查看全部</a>
    </div>
    <div class="ig-right__sugg-list"></div>`;
  aside.append(sugg);

  const footer = document.createElement("nav");
  footer.className = "ig-right__footer";
  footer.innerHTML = `
    <span><a href="/about">关于</a> · <a href="/faq">帮助</a> · <a href="/badges">徽章</a> ·
    <a href="/u">用户</a> · <a href="/tos">条款</a> · <a href="/privacy">隐私</a> ·
    <a href="/categories">分类</a></span>
    <span class="ig-right__copy">© ${new Date().getFullYear()} ${escapeHtml(
      siteSettings?.title || "Moaclab"
    )}</span>`;
  aside.append(footer);

  wrap.append(aside);

  fillSuggestions(sugg.querySelector(".ig-right__sugg-list"));
}

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
        <a class="ig-right__row-av" href="/u/${u.username}">
          <img src="${u.avatar_template.replace("{size}", "68")}" alt="">
        </a>
        <div class="ig-right__row-text">
          <a class="ig-right__row-user" href="/u/${u.username}">${u.username}</a>
          <span>${escapeHtml(u.name || "推荐关注")}</span>
        </div>
        <a class="ig-right__row-act" href="/u/${u.username}">查看</a>
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
