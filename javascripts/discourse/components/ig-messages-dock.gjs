import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import formatDate from "discourse/helpers/format-date";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

// Instagram's floating "Messages" dock (instagram.com, 2026), backed by
// Discourse personal messages. Collapsed: a 248×54 pill (Direct glyph,
// "Messages", three recent contacts, unread badge). Expanded: the
// conversation list; rows open the PM topic, the pencil opens Discourse's
// own new-message composer. Data comes from the core PM list endpoint.

const CACHE_MS = 60 * 1000;
const ROUTES = [
  "discovery.",
  "topic.",
  "tag.",
  "tags.",
  "full-page-search",
  "user",
];
let cache = null;

export default class IgMessagesDock extends Component {
  @service currentUser;
  @service site;
  @service router;
  @service composer;

  @tracked open = false;
  @tracked loading = false;
  @tracked items = cache?.items ?? null;

  constructor() {
    super(...arguments);
    if (this.enabled) {
      this.load();
    }
  }

  get enabled() {
    return (
      !!settings.instagram_messages_dock &&
      !!this.currentUser &&
      this.currentUser.can_send_private_messages !== false &&
      !this.site.mobileView
    );
  }

  // Instagram shows the dock on feed, post, profile and search pages; never
  // on the messages pages themselves, admin, or tool pages like /typing.
  get visible() {
    if (!this.enabled) {
      return false;
    }
    const name = this.router.currentRouteName || "";
    if (name.startsWith("userPrivateMessages")) {
      return false;
    }
    return ROUTES.some((prefix) => name.startsWith(prefix));
  }

  text(key, options) {
    return i18n(themePrefix(`ig.messages.${key}`), options);
  }

  get title() {
    return this.text("title");
  }

  get newLabel() {
    return this.text("new_message");
  }

  get collapseLabel() {
    return this.text("collapse");
  }

  get seeAllLabel() {
    return this.text("see_all");
  }

  get emptyLabel() {
    return this.text("empty");
  }

  get loadingLabel() {
    return this.text("loading");
  }

  get unreadDotLabel() {
    return this.text("unread_dot");
  }

  get unreadCount() {
    return (this.items || []).filter((item) => item.unread).length;
  }

  get unreadLabel() {
    return this.text("unread", { count: this.unreadCount });
  }

  get badge() {
    return this.unreadCount > 9 ? "9+" : String(this.unreadCount);
  }

  get previewAvatars() {
    const seen = new Set();
    const out = [];
    for (const item of this.items || []) {
      if (item.avatar && !seen.has(item.avatar)) {
        seen.add(item.avatar);
        out.push(item.avatar);
      }
      if (out.length === 3) {
        break;
      }
    }
    return out;
  }

  get allUrl() {
    return `/u/${this.currentUser.username}/messages`;
  }

  async load(force = false) {
    if (!force && cache && Date.now() - cache.at < CACHE_MS) {
      this.items = cache.items;
      return;
    }

    this.loading = true;
    try {
      const result = await ajax(
        `/topics/private-messages/${this.currentUser.username}.json`
      );
      const users = new Map((result.users || []).map((u) => [u.id, u]));
      const me = this.currentUser.id;

      const items = (result.topic_list?.topics || []).slice(0, 20).map((t) => {
        const ids = [...(t.participants || []), ...(t.posters || [])]
          .map((p) => p.user_id)
          .filter((id) => id && id !== me);
        const other = users.get(ids[0]) || users.get(t.posters?.[0]?.user_id);
        const unread =
          !!t.unseen ||
          (t.unread_posts ?? 0) > 0 ||
          (t.last_read_post_number != null &&
            t.last_read_post_number < t.highest_post_number);

        return {
          id: t.id,
          url: `/t/${t.slug}/${t.id}`,
          title: t.title,
          name: other?.name || other?.username || t.title,
          avatar: other?.avatar_template?.replace("{size}", "96"),
          when: new Date(t.last_posted_at || t.bumped_at),
          unread,
        };
      });

      cache = { at: Date.now(), items };
      this.items = items;
    } catch {
      this.items ??= [];
    } finally {
      this.loading = false;
    }
  }

  @action
  expand() {
    this.open = true;
    this.load(true);
  }

  @action
  collapse() {
    this.open = false;
  }

  @action
  compose() {
    this.open = false;
    this.composer.openNewMessage({});
  }

  @action
  closeOnNavigate(event) {
    if (event.target.closest("a")) {
      this.open = false;
    }
  }

  @action
  onKeydown(event) {
    if (event.key === "Escape") {
      this.open = false;
    }
  }

  <template>
    {{! template-lint-disable no-invalid-interactive }}
    {{#if this.visible}}
      <div class="ig-dock {{if this.open 'is-open'}}">
        {{#if this.open}}
          <section
            class="ig-dock__panel"
            aria-label={{this.title}}
            {{on "keydown" this.onKeydown}}
          >
            <header class="ig-dock__head">
              <h2 class="ig-dock__title">
                {{this.title}}
                {{#if this.unreadCount}}
                  <span class="ig-dock__head-count">{{this.unreadLabel}}</span>
                {{/if}}
              </h2>
              <button
                type="button"
                class="ig-dock__icon-btn"
                title={{this.newLabel}}
                aria-label={{this.newLabel}}
                {{on "click" this.compose}}
              >
                <span
                  class="ig-glyph ig-glyph--compose"
                  aria-hidden="true"
                ></span>
              </button>
              <button
                type="button"
                class="ig-dock__icon-btn"
                title={{this.collapseLabel}}
                aria-label={{this.collapseLabel}}
                aria-expanded="true"
                {{on "click" this.collapse}}
              >
                <span
                  class="ig-glyph ig-glyph--chevron-down"
                  aria-hidden="true"
                ></span>
              </button>
            </header>

            <div class="ig-dock__list" {{on "click" this.closeOnNavigate}}>
              {{#if this.items.length}}
                {{#each this.items as |item|}}
                  <a
                    class="ig-dock__row {{if item.unread 'is-unread'}}"
                    href={{item.url}}
                  >
                    <span class="ig-dock__avatar">
                      {{#if item.avatar}}
                        <img src={{item.avatar}} alt="" />
                      {{/if}}
                    </span>
                    <span class="ig-dock__text">
                      <span class="ig-dock__name">{{item.name}}</span>
                      <span class="ig-dock__preview">
                        <span class="ig-dock__subject">{{item.title}}</span>
                        <span aria-hidden="true">·</span>
                        <span class="ig-dock__time">
                          {{formatDate item.when format="tiny" noTitle="true"}}
                        </span>
                      </span>
                    </span>
                    {{#if item.unread}}
                      <span
                        class="ig-dock__dot"
                        title={{this.unreadDotLabel}}
                      ></span>
                    {{/if}}
                  </a>
                {{/each}}
              {{else if this.loading}}
                <p class="ig-dock__empty">{{this.loadingLabel}}</p>
              {{else}}
                <p class="ig-dock__empty">{{this.emptyLabel}}</p>
              {{/if}}
            </div>

            <a
              class="ig-dock__all"
              href={{this.allUrl}}
              {{on "click" this.collapse}}
            >{{this.seeAllLabel}}</a>
          </section>
        {{else}}
          <button
            type="button"
            class="ig-dock__pill"
            aria-expanded="false"
            {{on "click" this.expand}}
          >
            <span class="ig-dock__pill-icon">
              <span class="ig-glyph ig-glyph--share" aria-hidden="true"></span>
              {{#if this.unreadCount}}
                <span class="ig-dock__badge">{{this.badge}}</span>
              {{/if}}
            </span>
            <span class="ig-dock__pill-label">{{this.title}}</span>
            <span class="ig-dock__stack" aria-hidden="true">
              {{#each this.previewAvatars as |src|}}
                <img src={{src}} alt="" />
              {{/each}}
            </span>
          </button>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
