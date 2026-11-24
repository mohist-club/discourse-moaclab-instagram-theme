import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import bodyClass from "discourse/helpers/body-class";
import { modifier } from "ember-modifier";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { NotificationLevels } from "discourse/lib/notification-levels";
import DiscourseURL from "discourse/lib/url";
import { clipboardCopy } from "discourse/lib/utilities";
import Category from "discourse/models/category";
import PermissionType from "discourse/models/permission-type";
import { i18n } from "discourse-i18n";

// A studio (a subcategory of the keyboard / keycap categories) as an
// Instagram profile header, above its posts:
//   ring + logo | name, parent, stats, "工作室", description, about link,
//                 "活跃成员包括 …"
//   关注 (blue) · 发帖 (grey) · share (square)
//   tabs: 帖子 (latest) · 热门 (top)
// Follow = Discourse's category notification level (watching first post),
// 发帖 = the native composer in this category, share = copy the link.

const MEMBER_PREVIEW = 3;
const HIGHLIGHTS_MAX = 8;
const studioCache = new Map();

export function studioParentIds() {
  const ids = String(settings.instagram_suggested_categories || "")
    .split("|")
    .map((v) => parseInt(v, 10))
    .filter((id) => id > 0);
  const explore = parseInt(settings.instagram_explore_category, 10);
  if (explore > 0) {
    ids.push(explore);
  }
  return ids;
}

export function isStudio(category) {
  return (
    !!settings.instagram_studio_profile &&
    !!category?.parent_category_id &&
    studioParentIds().includes(category.parent_category_id)
  );
}

export default class IgStudioHeader extends Component {
  @service currentUser;
  @service composer;
  @service router;
  @service interfaceColor;

  @tracked level = this.args.category?.notification_level;
  @tracked members = null;
  @tracked highlights = null;
  @tracked copied = false;
  @tracked busy = false;

  get category() {
    return this.args.category;
  }

  get show() {
    return isStudio(this.category);
  }

  text(key, options) {
    return i18n(themePrefix(`ig.studio.${key}`), options);
  }

  // the category's background image (Discourse paints it on <body>); here
  // it becomes the hero's cover instead (see studio.scss)
  get coverUrl() {
    const light = this.category.uploaded_background?.url;
    const dark = this.category.uploaded_background_dark?.url;
    return (this.interfaceColor?.darkModeActive && dark) || light || null;
  }

  get coverStyle() {
    return this.coverUrl
      ? htmlSafe(`background-image: url("${encodeURI(this.coverUrl)}")`)
      : null;
  }

  get parent() {
    const id = this.category.parent_category_id;
    return this.category.parentCategory || Category.findById?.(id) || null;
  }

  get logoUrl() {
    return (
      this.category.uploaded_logo?.url ||
      this.category.uploaded_logo_dark?.url ||
      null
    );
  }

  get letter() {
    return (this.category.name || "·").trim().charAt(0);
  }

  get letterStyle() {
    return htmlSafe(`background: #${this.category.color || "8e8e8e"}`);
  }

  get topicCount() {
    return this.category.topic_count || 0;
  }

  get replyCount() {
    return Math.max(
      0,
      (this.category.post_count || 0) - (this.category.topic_count || 0)
    );
  }

  get description() {
    const html = this.category.description;
    return html ? htmlSafe(html) : null;
  }

  get aboutUrl() {
    return this.category.topic_url || null;
  }

  get aboutLabel() {
    return this.text("about", { name: this.category.name });
  }

  get following() {
    return (
      this.level === NotificationLevels.WATCHING ||
      this.level === NotificationLevels.WATCHING_FIRST_POST
    );
  }

  get followLabel() {
    return this.text(this.following ? "following" : "follow");
  }

  get canPost() {
    if (!this.currentUser) {
      return true; // leads to log-in
    }
    return this.category.permission === PermissionType.FULL;
  }

  get shareLabel() {
    return this.text(this.copied ? "copied" : "share");
  }

  get latestUrl() {
    return `${this.category.url}/l/latest`;
  }

  get topUrl() {
    return `${this.category.url}/l/top`;
  }

  get onTop() {
    return /top/i.test(this.router.currentRouteName || "");
  }

  get membersPreview() {
    return (this.members || []).slice(0, MEMBER_PREVIEW);
  }

  get membersLine() {
    const list = this.members || [];
    if (!list.length) {
      return null;
    }
    const names = list
      .slice(0, 2)
      .map((u) => u.username)
      .join("、");
    const rest = list.length - 2;
    return rest > 0
      ? this.text("members_more", { names, count: rest })
      : this.text("members", { names });
  }

  // from the studio's latest topics: recent posters (newest first) and
  // highlights — pinned topics first, then the newest with an image
  loadStudio = modifier(() => {
    if (!this.show) {
      return;
    }
    const id = this.category.id;
    let promise = studioCache.get(id);
    if (!promise) {
      promise = ajax(`${this.category.url}/l/latest.json`)
        .then((result) => {
          const topics = result?.topic_list?.topics || [];
          const users = new Map(
            (result?.users || []).map((user) => [user.id, user])
          );
          const seen = new Map();
          for (const topic of topics) {
            for (const poster of topic.posters || []) {
              const user = users.get(poster.user_id);
              if (user && user.id > 0 && !seen.has(user.id)) {
                seen.set(user.id, user);
              }
            }
          }
          const highlights = [
            ...topics.filter((t) => t.pinned && t.image_url),
            ...topics.filter((t) => !t.pinned && t.image_url),
          ]
            .slice(0, HIGHLIGHTS_MAX)
            .map((t) => ({
              title: t.title,
              url: `/t/${t.slug}/${t.id}`,
              image: t.image_url,
              pinned: !!t.pinned,
            }));
          return { members: [...seen.values()], highlights };
        })
        .catch(() => ({ members: [], highlights: [] }));
      studioCache.set(id, promise);
    }
    promise.then(({ members, highlights }) => {
      if (!this.isDestroying && !this.isDestroyed) {
        this.members = members;
        this.highlights = highlights;
      }
    });
  });

  highlightStyle(item) {
    return htmlSafe(`background-image: url("${encodeURI(item.image)}")`);
  }

  avatarUrl(user) {
    return user.avatar_template.replace("{size}", "64");
  }

  @action
  async toggleFollow() {
    if (!this.currentUser) {
      DiscourseURL.routeTo("/login");
      return;
    }
    if (this.busy) {
      return;
    }
    const level = this.following
      ? NotificationLevels.REGULAR
      : NotificationLevels.WATCHING_FIRST_POST;
    this.busy = true;
    try {
      await this.category.setNotification(level);
      this.level = level;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  post() {
    if (!this.currentUser) {
      DiscourseURL.routeTo("/login");
      return;
    }
    this.composer.openNewTopic({ category: this.category });
  }

  @action
  async share() {
    await clipboardCopy(
      new URL(this.category.url, window.location.origin).href
    );
    this.copied = true;
    setTimeout(() => {
      if (!this.isDestroying && !this.isDestroyed) {
        this.copied = false;
      }
    }, 2000);
  }

  <template>
    {{#if this.show}}
      {{bodyClass "ig-studio-page"}}
      {{#if this.coverUrl}}
        {{bodyClass "ig-studio-cover-page"}}
      {{/if}}
      <section
        class="ig-studio {{if this.coverUrl 'ig-studio--cover'}}"
        {{this.loadStudio}}
      >
        {{#if this.coverUrl}}
          <div class="ig-studio__cover" style={{this.coverStyle}}></div>
        {{/if}}
        <div class="ig-studio__top">
          <div class="ig-studio__ring">
            {{#if this.logoUrl}}
              <img
                class="ig-studio__avatar"
                src={{this.logoUrl}}
                alt={{this.category.name}}
              />
            {{else}}
              <span
                class="ig-studio__avatar ig-studio__avatar--letter"
                style={{this.letterStyle}}
              >{{this.letter}}</span>
            {{/if}}
          </div>

          <div class="ig-studio__info">
            <h1 class="ig-studio__name">{{this.category.name}}</h1>
            {{#if this.parent}}
              <a class="ig-studio__parent" href={{this.parent.url}}>
                {{this.parent.name}}
              </a>
            {{/if}}

            <ul class="ig-studio__stats">
              <li><b>{{this.topicCount}}</b>{{this.text "posts"}}</li>
              <li><b>{{this.replyCount}}</b>{{this.text "replies"}}</li>
              {{#if this.members.length}}
                <li><b>{{this.members.length}}</b>{{this.text
                    "active_members"
                  }}</li>
              {{/if}}
            </ul>

            <p class="ig-studio__label">{{this.text "label"}}</p>
            {{#if this.description}}
              <div class="ig-studio__bio">{{this.description}}</div>
            {{/if}}
            {{#if this.aboutUrl}}
              <a class="ig-studio__link" href={{this.aboutUrl}}>
                <span class="ig-studio__link-icon" aria-hidden="true"></span>
                {{this.aboutLabel}}
              </a>
            {{/if}}

            {{#if this.membersLine}}
              <div class="ig-studio__members">
                <span class="ig-studio__member-avatars" aria-hidden="true">
                  {{#each this.membersPreview as |user|}}
                    <img src={{this.avatarUrl user}} alt="" />
                  {{/each}}
                </span>
                <span>{{this.membersLine}}</span>
              </div>
            {{/if}}
          </div>
        </div>

        <div class="ig-studio__actions">
          <button
            type="button"
            class="ig-studio__btn
              {{if
                this.following
                'ig-studio__btn--grey'
                'ig-studio__btn--primary'
              }}"
            aria-pressed={{if this.following "true" "false"}}
            disabled={{this.busy}}
            {{on "click" this.toggleFollow}}
          >{{this.followLabel}}</button>
          {{#if this.canPost}}
            <button
              type="button"
              class="ig-studio__btn ig-studio__btn--grey"
              {{on "click" this.post}}
            >{{this.text "new_post"}}</button>
          {{/if}}
          <button
            type="button"
            class="ig-studio__btn ig-studio__btn--grey ig-studio__btn--icon
              {{if this.copied 'is-copied'}}"
            title={{this.shareLabel}}
            aria-label={{this.shareLabel}}
            {{on "click" this.share}}
          ></button>
        </div>

        {{#if this.highlights.length}}
          <div class="ig-studio__highlights">
            {{#each this.highlights as |item|}}
              <a
                class="ig-studio__highlight"
                href={{item.url}}
                title={{item.title}}
              >
                <span
                  class="ig-studio__highlight-ring
                    {{if item.pinned 'is-pinned'}}"
                >
                  <span
                    class="ig-studio__highlight-image"
                    style={{this.highlightStyle item}}
                  ></span>
                </span>
                <span class="ig-studio__highlight-label">{{item.title}}</span>
              </a>
            {{/each}}
          </div>
        {{/if}}

        <nav class="ig-studio__tabs">
          <a
            class="ig-studio__tab {{unless this.onTop 'is-active'}}"
            href={{this.latestUrl}}
          >
            <span class="ig-studio__tab-icon ig-studio__tab-icon--grid"></span>
            {{this.text "tab_posts"}}
          </a>
          <a
            class="ig-studio__tab {{if this.onTop 'is-active'}}"
            href={{this.topUrl}}
          >
            <span class="ig-studio__tab-icon ig-studio__tab-icon--top"></span>
            {{this.text "tab_top"}}
          </a>
        </nav>
      </section>
    {{/if}}
  </template>
}
