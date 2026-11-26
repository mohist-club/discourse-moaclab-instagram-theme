import Component from "@glimmer/component";
import { cached, tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import bodyClass from "discourse/helpers/body-class";
import { NotificationLevels } from "discourse/lib/notification-levels";
import DiscourseURL from "discourse/lib/url";
import Category from "discourse/models/category";
import { i18n } from "discourse-i18n";
import { studiosParentId } from "../lib/ig-studios";

// The studios page (instagram_studios_page) in the layout of the studio
// pages and /custom-services:
//   profile header: the parent's logo in a story ring | title, counts
//   (studios · posts · following), label, one line, link to the parent;
//   New post / Suggest a studio
//   tabs: Recent · All A–Z · Following (signed in)
//   Recent: studios with posts, newest first — one large card and two
//   rows beside it, then a 3-column grid of square cards; then the studios
//   without posts as a compact logo grid
//   All: every studio as a logo tile, by name
//   Following: the followed studios as cards
// A card: square image (the newest featured post's, else the logo on
// white) with the logo as a badge · #N posts / #following tags · name ·
// clock + "updated … ago". Hovering a card lays it on a cream panel.
// Rendered in core's above-discovery-categories outlet on the studio
// parent's subcategories page; all studios come with that page (each with
// its featured topics), so nothing else is fetched. Images load lazily.

const FEATURED = 3;
const DAY = 24 * 60 * 60 * 1000;
const FOLLOWING = [
  NotificationLevels.WATCHING,
  NotificationLevels.WATCHING_FIRST_POST,
];

function t(key, options) {
  return i18n(themePrefix(`ig.studios.${key}`), options);
}

// the smallest generated thumbnail at least `size` wide, else the original
function imageOf(topic, size) {
  const fit = (topic.thumbnails || [])
    .filter((th) => th.url && (th.max_width || th.width || 0) >= size)
    .sort((a, b) => (a.max_width || a.width) - (b.max_width || b.width))[0];
  return fit?.url || topic.image_url || null;
}

function lastUpdate(topics) {
  const times = topics
    .map((topic) =>
      Date.parse(topic.bumped_at || topic.last_posted_at || topic.created_at)
    )
    .filter((time) => !isNaN(time));
  return times.length ? Math.max(...times) : null;
}

function updatedLabel(time) {
  if (!time) {
    return t("no_posts");
  }
  const days = Math.floor((Date.now() - time) / DAY);
  if (days < 1) {
    return t("updated_today");
  }
  if (days < 30) {
    return t("updated_days", { count: days });
  }
  if (days < 365) {
    return t("updated_months", { count: Math.floor(days / 30) });
  }
  return t("updated_years", { count: Math.floor(days / 365) });
}

// the description's first sentence, for the large card
function firstSentence(text) {
  const line = (text || "").split(/[。\n]|\. /)[0].trim();
  return line ? `${line}${/[　-鿿]/.test(line) ? "。" : "."}` : null;
}

const StudioCard = <template>
  <a
    class="ig-sp-card
      {{if @row 'ig-sp-card--row'}}
      {{if @big 'ig-sp-card--big'}}"
    href={{@studio.url}}
  >
    <span
      class="ig-sp-card__media
        {{unless @studio.image (if @studio.logo 'is-logo' 'is-letter')}}"
    >
      {{#if @studio.image}}
        <img
          class="ig-sp-card__img"
          src={{if @big @studio.imageBig @studio.image}}
          alt=""
          loading={{if @eager "eager" "lazy"}}
          fetchpriority={{if @eager "high"}}
        />
        {{#if @studio.logo}}
          <img
            class="ig-sp-card__badge"
            src={{@studio.logo}}
            alt=""
            loading="lazy"
          />
        {{/if}}
      {{else if @studio.logo}}
        <img
          class="ig-sp-card__logo"
          src={{@studio.logo}}
          alt=""
          loading="lazy"
        />
      {{else}}
        <span class="ig-sp-card__letter">{{@studio.letter}}</span>
      {{/if}}
    </span>
    <span class="ig-sp-card__text">
      <span class="ig-sp-card__tags">
        <span class="ig-sp-tag">{{@studio.postsTag}}</span>
        {{#if @studio.followingTag}}
          <span class="ig-sp-tag">{{@studio.followingTag}}</span>
        {{/if}}
      </span>
      <span class="ig-sp-card__name">{{@studio.name}}</span>
      {{#if @big}}
        {{#if @studio.summary}}
          <span class="ig-sp-card__sub">{{@studio.summary}}</span>
        {{/if}}
      {{/if}}
      <span class="ig-sp-card__date">
        <span class="ig-sp-card__clock" aria-hidden="true"></span>
        {{@studio.updated}}
      </span>
    </span>
  </a>
</template>;

// a compact logo tile: studios without posts, and the A–Z list
const StudioTile = <template>
  <a class="ig-sp-mini" href={{@studio.url}}>
    <span class="ig-sp-mini__logo {{unless @studio.logo 'is-letter'}}">
      {{#if @studio.logo}}
        <img src={{@studio.logo}} alt="" loading="lazy" />
      {{else}}
        {{@studio.letter}}
      {{/if}}
    </span>
    <span class="ig-sp-mini__name">{{@studio.name}}</span>
    <span class="ig-sp-mini__sub">{{@studio.tileLine}}</span>
  </a>
</template>;

const SectionHead = <template>
  <div class="ig-sp__sec-hd">
    <div>
      <h2>{{@title}}</h2>
      <p>{{@sub}}</p>
    </div>
    <span class="ig-sp__count">{{@count}}</span>
  </div>
</template>;

export default class IgStudiosPage extends Component {
  @service router;
  @service currentUser;
  @service composer;

  @tracked tab = "recent";

  get parentId() {
    return studiosParentId();
  }

  get parent() {
    return Category.findById(this.parentId) || null;
  }

  get categories() {
    const list = this.args.categories;
    return list ? [...list] : [];
  }

  // only on the studio parent's subcategories page; /categories (and any
  // other category's subcategories) stay Discourse's own
  get show() {
    return (
      !!this.parentId &&
      this.router.currentRouteName === "discovery.subcategories" &&
      this.categories.length > 0 &&
      this.categories.every((c) => c.parent_category_id === this.parentId)
    );
  }

  // cached: rebuilt only when the categories change
  @cached
  get studios() {
    return this.categories.map((c, index) => {
      const topics = c.topics || c.featuredTopics || [];
      const cover = topics.find((topic) => imageOf(topic, 0));
      const time = lastUpdate(topics);
      const posts = c.topic_count || 0;
      return {
        index,
        time,
        posts,
        url: c.url,
        name: c.name || "",
        letter: (c.name || "·").trim().charAt(0),
        logo: c.uploaded_logo?.url || c.uploaded_logo_dark?.url || null,
        image: cover ? imageOf(cover, 600) : null,
        imageBig: cover ? imageOf(cover, 1080) : null,
        summary: firstSentence(c.description_text),
        postsTag: t("posts", { count: posts }),
        following: FOLLOWING.includes(c.notification_level),
        followingTag: FOLLOWING.includes(c.notification_level)
          ? t("following")
          : null,
        updated: updatedLabel(time),
        tileLine: time ? t("tile_posts", { count: posts }) : t("waiting"),
      };
    });
  }

  // studios with posts, newest first
  get posted() {
    return this.studios
      .filter((s) => s.time)
      .sort((a, b) => b.time - a.time || a.index - b.index);
  }

  // studios without posts, in Discourse's order
  get waiting() {
    return this.studios.filter((s) => !s.time);
  }

  get byName() {
    return [...this.studios].sort((a, b) => a.name.localeCompare(b.name));
  }

  get followed() {
    return this.posted.concat(this.waiting).filter((s) => s.following);
  }

  get hasFeatured() {
    return this.posted.length > FEATURED;
  }

  get main() {
    return this.posted[0];
  }

  get side() {
    return this.posted.slice(1, FEATURED);
  }

  get grid() {
    return this.hasFeatured ? this.posted.slice(FEATURED) : this.posted;
  }

  get totalPosts() {
    return this.studios.reduce((sum, s) => sum + s.posts, 0);
  }

  get parentName() {
    return this.parent?.name || "";
  }

  get parentLogo() {
    return (
      this.parent?.uploaded_logo?.url ||
      this.parent?.uploaded_logo_dark?.url ||
      null
    );
  }

  get parentUrl() {
    return this.parent?.url || null;
  }

  get onRecent() {
    return this.tab === "recent";
  }

  get onAll() {
    return this.tab === "all";
  }

  get onFollowing() {
    return this.tab === "following";
  }

  get label() {
    return t("label", { parent: this.parentName });
  }

  get allPostsLabel() {
    return t("all_posts", { parent: this.parentName });
  }

  count(n) {
    return t("count", { count: n });
  }

  get recentCount() {
    return this.count(this.posted.length);
  }

  get waitingCount() {
    return this.count(this.waiting.length);
  }

  get allCount() {
    return this.count(this.studios.length);
  }

  get followedCount() {
    return this.count(this.followed.length);
  }

  @action
  setTab(tab) {
    this.tab = tab;
  }

  @action
  newPost() {
    if (!this.currentUser) {
      DiscourseURL.routeTo("/login");
      return;
    }
    this.composer.openNewTopic({});
  }

  @action
  suggest() {
    if (!this.currentUser) {
      DiscourseURL.routeTo("/login");
      return;
    }
    this.composer.openNewTopic({
      category: this.parent,
      title: t("suggest_title"),
    });
  }

  <template>
    {{#if this.show}}
      {{bodyClass "ig-studios-page"}}
      <section class="ig-sp">
        <header class="ig-sp__hd">
          <div class="ig-sp__ring">
            <div class="ig-sp__avatar">
              {{#if this.parentLogo}}
                <img src={{this.parentLogo}} alt="" />
              {{/if}}
            </div>
          </div>
          <div class="ig-sp__info">
            <h1>{{t "title"}}</h1>
            <ul class="ig-sp__stats">
              <li><b>{{this.studios.length}}</b> {{t "stat_studios"}}</li>
              <li><b>{{this.totalPosts}}</b> {{t "stat_posts"}}</li>
              {{#if this.currentUser}}
                <li><b>{{this.followed.length}}</b> {{t "stat_following"}}</li>
              {{/if}}
            </ul>
          </div>
          <div class="ig-sp__more">
            {{#if this.parentName}}
              <p class="ig-sp__label">{{this.label}}</p>
            {{/if}}
            <p class="ig-sp__bio">{{t "bio"}}</p>
            {{#if this.parentUrl}}
              <a class="ig-sp__link" href={{this.parentUrl}}>
                <span class="ig-sp__link-icon" aria-hidden="true"></span>
                {{this.allPostsLabel}}
              </a>
            {{/if}}
          </div>
        </header>

        <div class="ig-sp__actions">
          <button
            type="button"
            class="ig-sp__btn ig-sp__btn--primary"
            {{on "click" this.newPost}}
          >{{t "new_post"}}</button>
          {{#if this.parent}}
            <button
              type="button"
              class="ig-sp__btn ig-sp__btn--grey"
              {{on "click" this.suggest}}
            >{{t "suggest"}}</button>
          {{/if}}
        </div>

        <nav class="ig-sp__tabs">
          <button
            type="button"
            class="ig-sp__tab {{if this.onRecent 'is-active'}}"
            data-tab="recent"
            aria-pressed={{if this.onRecent "true" "false"}}
            {{on "click" (fn this.setTab "recent")}}
          >
            <span
              class="ig-sp__tab-icon ig-sp__tab-icon--recent"
              aria-hidden="true"
            ></span>
            <span class="ig-sp__tab-label">{{t "tab_recent"}}</span>
          </button>
          <button
            type="button"
            class="ig-sp__tab {{if this.onAll 'is-active'}}"
            data-tab="all"
            aria-pressed={{if this.onAll "true" "false"}}
            {{on "click" (fn this.setTab "all")}}
          >
            <span
              class="ig-sp__tab-icon ig-sp__tab-icon--all"
              aria-hidden="true"
            ></span>
            <span class="ig-sp__tab-label">{{t "tab_all"}}</span>
          </button>
          {{#if this.currentUser}}
            <button
              type="button"
              class="ig-sp__tab {{if this.onFollowing 'is-active'}}"
              data-tab="following"
              aria-pressed={{if this.onFollowing "true" "false"}}
              {{on "click" (fn this.setTab "following")}}
            >
              <span
                class="ig-sp__tab-icon ig-sp__tab-icon--following"
                aria-hidden="true"
              ></span>
              <span class="ig-sp__tab-label">{{t "tab_following"}}</span>
            </button>
          {{/if}}
        </nav>

        {{#if this.onRecent}}
          {{#if this.posted.length}}
            <section class="ig-sp__sec ig-sp__sec--recent">
              <SectionHead
                @title={{t "recent_title"}}
                @sub={{t "recent_sub"}}
                @count={{this.recentCount}}
              />
              {{#if this.hasFeatured}}
                <div class="ig-sp__feat">
                  <StudioCard
                    @studio={{this.main}}
                    @big={{true}}
                    @eager={{true}}
                  />
                  <div class="ig-sp__feat-side">
                    {{#each this.side as |studio|}}
                      <StudioCard
                        @studio={{studio}}
                        @row={{true}}
                        @eager={{true}}
                      />
                    {{/each}}
                  </div>
                </div>
              {{/if}}
              <div class="ig-sp__grid">
                {{#each this.grid as |studio|}}
                  <StudioCard @studio={{studio}} />
                {{/each}}
              </div>
            </section>
          {{/if}}
          {{#if this.waiting.length}}
            <section class="ig-sp__sec ig-sp__sec--waiting">
              <SectionHead
                @title={{t "waiting_title"}}
                @sub={{t "waiting_sub"}}
                @count={{this.waitingCount}}
              />
              <div class="ig-sp__minis">
                {{#each this.waiting as |studio|}}
                  <StudioTile @studio={{studio}} />
                {{/each}}
              </div>
            </section>
          {{/if}}
        {{else if this.onAll}}
          <section class="ig-sp__sec ig-sp__sec--all">
            <SectionHead
              @title={{t "all_title"}}
              @sub={{t "all_sub"}}
              @count={{this.allCount}}
            />
            <div class="ig-sp__minis">
              {{#each this.byName as |studio|}}
                <StudioTile @studio={{studio}} />
              {{/each}}
            </div>
          </section>
        {{else}}
          <section class="ig-sp__sec ig-sp__sec--following">
            <SectionHead
              @title={{t "following_title"}}
              @sub={{t "following_sub"}}
              @count={{this.followedCount}}
            />
            {{#if this.followed.length}}
              <div class="ig-sp__grid">
                {{#each this.followed as |studio|}}
                  <StudioCard @studio={{studio}} />
                {{/each}}
              </div>
            {{else}}
              <p class="ig-sp__empty">{{t "following_empty"}}</p>
            {{/if}}
          </section>
        {{/if}}
      </section>
    {{/if}}
  </template>
}
