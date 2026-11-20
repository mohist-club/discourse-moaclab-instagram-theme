import { apiInitializer } from "discourse/lib/api";

// Builds the Instagram desktop shell: brand wordmark at the top of the
// left rail, and a "stories" tray at the top of the discovery feed.
export default apiInitializer((api) => {
  const site = api.container.lookup("service:site");
  const siteSettings = api.container.lookup("service:site-settings");
  const desktop = !site?.mobileView;

  if (settings.instagram_desktop_shell && desktop) {
    document.body.classList.add("ig-desktop-shell");
  }

  const ensure = () => {
    try {
      if (settings.instagram_desktop_shell && desktop) {
        ensureWordmark(siteSettings);
      }
      if (settings.instagram_stories) {
        ensureStories(api, site);
      }
    } catch {
      // never let decoration break navigation
    }
  };

  ensure();
  api.onPageChange(ensure);
});

function ensureWordmark(siteSettings) {
  const sections = document.querySelector(".sidebar-wrapper .sidebar-sections");
  if (!sections || sections.querySelector(".ig-wordmark")) {
    return;
  }
  const link = document.createElement("a");
  link.className = "ig-wordmark";
  link.href = "/";
  link.textContent = siteSettings?.title || "Moaclab";
  sections.prepend(link);
}

function isDiscovery() {
  const b = document.body.classList;
  const onList = document.querySelector("#main-outlet .topic-list");
  const inTopic = [...b].some((c) => c.startsWith("archetype-"));
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

  // already in the right place
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
      label: user ? user.username : i18nLabel("your_story"),
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

function i18nLabel(key) {
  const map = { your_story: "你的故事" };
  return map[key] || key;
}
