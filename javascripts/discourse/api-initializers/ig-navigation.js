import { apiInitializer } from "discourse/lib/api";

// Instagram desktop shell:
//  - brand wordmark + a fixed Instagram action group (search / create /
//    activity / profile) injected at the top of the left rail
//  - a "stories" tray at the top of the discovery feed
//  - a `ig-clean-feed` body flag so the feed shows only stories + posts
export default apiInitializer((api) => {
  const siteSettings = api.container.lookup("service:site-settings");

  // Read mobileView at render time (inside onPageChange), never during static
  // initialization, to avoid discourse.static-viewport-initialization.
  const ensure = () => {
    try {
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
  const rail = document.createElement("div");
  rail.id = RAIL_ID;

  const wordmark = document.createElement("a");
  wordmark.className = "ig-wordmark";
  wordmark.href = "/";
  wordmark.textContent = siteSettings?.title || "Moaclab";
  rail.append(wordmark);

  const nav = document.createElement("nav");
  nav.className = "ig-rail-nav";
  nav.setAttribute("aria-label", "Instagram");

  const items = [
    {
      key: "home",
      href: "/",
      icon: "home",
      label: railLabel("home"),
    },
    {
      key: "search",
      href: "/search",
      icon: "search",
      label: railLabel("search"),
    },
    {
      key: "create",
      href: "/new-topic",
      icon: "create",
      label: railLabel("create"),
    },
  ];
  if (user) {
    items.push({
      key: "activity",
      href: `/u/${user.username}/notifications`,
      icon: "activity",
      label: railLabel("activity"),
    });
    items.push({
      key: "profile",
      href: `/u/${user.username}/summary`,
      avatar: user.avatar_template?.replace("{size}", "48"),
      label: railLabel("profile"),
    });
  }

  for (const it of items) {
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
    nav.append(a);
  }

  rail.append(nav);
  sections.prepend(rail);
}

function syncActive() {
  const path = window.location.pathname;
  document.querySelectorAll("#ig-rail .ig-rail-link").forEach((a) => {
    const href = a.getAttribute("href");
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
    search: "搜索",
    create: "创建",
    activity: "动态",
    profile: "我的",
    your_story: "你的故事",
  };
  return map[key] || key;
}
