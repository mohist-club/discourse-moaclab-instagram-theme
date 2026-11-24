import Component from "@glimmer/component";
import { cached, tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import bodyClass from "discourse/helpers/body-class";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { NotificationLevels } from "discourse/lib/notification-levels";
import DiscourseURL from "discourse/lib/url";
import { i18n } from "discourse-i18n";
import { studioParentIds } from "./ig-studio-header";

// /categories as a grid of Instagram profile cards — one per top-level
// category, in Discourse's own order:
//   cover (the category's background image, else its colour as a
//   gradient) · logo in a story ring overlapping it · Follow
//   name · description · topics / new this week
//   subcategory chips · newest topic
// Rendered in core's above-discovery-categories outlet; the native list
// below is hidden but kept (its load-more sentinel still works).

const MAX_CHIPS = 6;

function t(key, options) {
  return i18n(themePrefix(`ig.categories.${key}`), options);
}

function isFollowing(level) {
  return (
    level === NotificationLevels.WATCHING ||
    level === NotificationLevels.WATCHING_FIRST_POST
  );
}

function letterOf(category) {
  return (category?.name || "·").trim().charAt(0);
}

function colorStyle(category) {
  return htmlSafe(`--cat-color: #${category?.color || "8e8e8e"}`);
}

// Follow = Discourse's category notification level (watching first post)
class IgCategoryFollow extends Component {
  @service currentUser;

  @tracked level = this.args.category.notification_level;
  @tracked busy = false;

  get following() {
    return isFollowing(this.level);
  }

  get label() {
    return t(this.following ? "following" : "follow");
  }

  @action
  async toggle() {
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
      await this.args.category.setNotification(level);
      this.level = level;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.busy = false;
    }
  }

  <template>
    <button
      type="button"
      class="ig-cat__follow {{if this.following 'is-following'}}"
      aria-pressed={{if this.following "true" "false"}}
      disabled={{this.busy}}
      {{on "click" this.toggle}}
    >{{this.label}}</button>
  </template>
}

// The keyboard / keycap category (a studio parent, see ig-studio-header):
// a full-width card whose studios form a directory — filter by name, sort
// by activity / topics / name, compact tiles with their own Follow, the
// first rows shown and "show all" for the rest.
const STUDIOS_COLLAPSED = 12;
const SORTS = ["active", "topics", "name"];

class IgStudioDirectory extends Component {
  @tracked query = "";
  @tracked sort = "active";
  @tracked expanded = false;

  get card() {
    return this.args.card;
  }

  // cached: read by visible, hiddenCount, canCollapse and the template
  @cached
  get studios() {
    const q = this.query.trim().toLowerCase();
    const list = this.card.studios.filter(
      (s) => !q || s.name.toLowerCase().includes(q)
    );
    const by = {
      active: (a, b) => b.week - a.week || b.topics - a.topics,
      topics: (a, b) => b.topics - a.topics,
      name: (a, b) => a.name.localeCompare(b.name),
    }[this.sort];
    return [...list].sort(by);
  }

  get visible() {
    return this.expanded || this.query
      ? this.studios
      : this.studios.slice(0, STUDIOS_COLLAPSED);
  }

  get hiddenCount() {
    return this.studios.length - this.visible.length;
  }

  get canCollapse() {
    return (
      this.expanded && !this.query && this.studios.length > STUDIOS_COLLAPSED
    );
  }

  get sortTabs() {
    return SORTS.map((key) => ({
      key,
      label: t(`sort_${key}`),
      active: key === this.sort,
    }));
  }

  get studiosTitle() {
    return t("studios", { count: this.card.studios.length });
  }

  get filterPlaceholder() {
    return t("filter_studios");
  }

  get showAllLabel() {
    return t("show_all", { count: this.hiddenCount });
  }

  get collapseLabel() {
    return t("collapse");
  }

  get noMatch() {
    return this.query && this.studios.length === 0;
  }

  label(key, options) {
    return t(key, options);
  }

  @action
  onFilter(event) {
    this.query = event.target.value;
  }

  @action
  setSort(key) {
    this.sort = key;
  }

  @action
  toggleExpanded() {
    this.expanded = !this.expanded;
  }

  <template>
    <article class="ig-cat ig-cat--featured" style={{this.card.style}}>
      <a
        class="ig-cat__cover {{if this.card.coverStyle 'has-image'}}"
        href={{this.card.url}}
        style={{this.card.coverStyle}}
        aria-label={{this.card.name}}
      ></a>

      <div class="ig-cat__top">
        <a class="ig-cat__ring" href={{this.card.url}} tabindex="-1">
          {{#if this.card.logo}}
            <img class="ig-cat__logo" src={{this.card.logo}} alt="" />
          {{else}}
            <span
              class="ig-cat__logo ig-cat__logo--letter"
            >{{this.card.letter}}</span>
          {{/if}}
        </a>
        <IgCategoryFollow @category={{this.card.category}} />
      </div>

      <div class="ig-cat__body">
        <h2 class="ig-cat__name"><a
            href={{this.card.url}}
          >{{this.card.name}}</a></h2>
        {{#if this.card.description}}
          <p class="ig-cat__desc">{{this.card.description}}</p>
        {{/if}}
        <p class="ig-cat__stats">
          <span><b>{{this.card.studios.length}}</b>{{this.label
              "studios_short"
            }}</span>
          <span><b>{{this.card.topics}}</b>{{this.label "topics"}}</span>
          {{#if this.card.week}}
            <span><b>{{this.card.week}}</b>{{this.label "this_week"}}</span>
          {{/if}}
        </p>
      </div>

      <div class="ig-studios">
        <div class="ig-studios__bar">
          <h3>{{this.studiosTitle}}</h3>
          <div class="ig-studios__tools">
            <div class="ig-studios__sort" role="tablist">
              {{#each this.sortTabs as |tab|}}
                <button
                  type="button"
                  role="tab"
                  class="ig-studios__sort-tab {{if tab.active 'is-active'}}"
                  aria-selected={{if tab.active "true" "false"}}
                  {{on "click" (fn this.setSort tab.key)}}
                >{{tab.label}}</button>
              {{/each}}
            </div>
            <label class="ig-studios__filter">
              <span class="ig-studios__filter-icon" aria-hidden="true"></span>
              <input
                type="search"
                value={{this.query}}
                placeholder={{this.filterPlaceholder}}
                aria-label={{this.filterPlaceholder}}
                {{on "input" this.onFilter}}
              />
            </label>
          </div>
        </div>

        <ul class="ig-studios__grid">
          {{#each this.visible as |studio|}}
            <li class="ig-studio-tile" style={{studio.style}}>
              <a class="ig-studio-tile__link" href={{studio.url}}>
                <span class="ig-studio-tile__ring">
                  {{#if studio.logo}}
                    <img
                      class="ig-studio-tile__logo"
                      src={{studio.logo}}
                      alt=""
                      loading="lazy"
                    />
                  {{else}}
                    <span
                      class="ig-studio-tile__logo ig-studio-tile__logo--letter"
                    >{{studio.letter}}</span>
                  {{/if}}
                </span>
                <span class="ig-studio-tile__name">{{studio.name}}</span>
                <span class="ig-studio-tile__meta">
                  {{this.label "topics_count" count=studio.topics}}
                </span>
              </a>
              <IgCategoryFollow @category={{studio.category}} />
            </li>
          {{/each}}
        </ul>

        {{#if this.noMatch}}
          <p class="ig-studios__empty">{{this.label "no_studios"}}</p>
        {{/if}}

        {{#if this.hiddenCount}}
          <button
            type="button"
            class="ig-studios__more"
            {{on "click" this.toggleExpanded}}
          >{{this.showAllLabel}}</button>
        {{else if this.canCollapse}}
          <button
            type="button"
            class="ig-studios__more"
            {{on "click" this.toggleExpanded}}
          >{{this.collapseLabel}}</button>
        {{/if}}
      </div>
    </article>
  </template>
}

export default class IgCategoriesGrid extends Component {
  get show() {
    return !!settings.instagram_categories_page && this.cards.length > 0;
  }

  get categories() {
    const list = this.args.categories;
    return list ? [...list] : [];
  }

  // cached: each read rebuilt every card object, which re-rendered the
  // whole grid (and reset each card's follow button)
  @cached
  get cards() {
    const studioParents = studioParentIds();
    const cards = this.categories
      .filter((c) => !c.parent_category_id)
      .map((c) => {
        const subs = c.subcategories || [];
        const latest = (c.topics || c.featuredTopics || [])[0];
        const background =
          c.uploaded_background?.url || c.uploaded_background_dark?.url;
        return {
          category: c,
          url: c.url,
          name: c.name,
          description: c.description_text || "",
          logo: c.uploaded_logo?.url || c.uploaded_logo_dark?.url || null,
          letter: letterOf(c),
          style: colorStyle(c),
          coverStyle: background
            ? htmlSafe(`background-image: url("${encodeURI(background)}")`)
            : null,
          topics: c.topic_count || 0,
          week: c.topics_week || 0,
          chips: subs.slice(0, MAX_CHIPS).map((sub) => ({
            url: sub.url,
            name: sub.name,
            logo: sub.uploaded_logo?.url || null,
            letter: letterOf(sub),
            style: colorStyle(sub),
          })),
          moreChips: Math.max(0, subs.length - MAX_CHIPS),
          featured: studioParents.includes(c.id) && subs.length > 0,
          studios: subs.map((sub) => ({
            category: sub,
            url: sub.url,
            name: sub.name || "",
            logo: sub.uploaded_logo?.url || sub.uploaded_logo_dark?.url || null,
            letter: letterOf(sub),
            style: colorStyle(sub),
            topics: sub.topic_count || 0,
            week: sub.topics_week || 0,
          })),
          latest: latest
            ? {
                title: latest.title,
                url: `/t/${latest.slug}/${latest.id}`,
              }
            : null,
        };
      });
    // the studio parents first, as wide cards
    return [
      ...cards.filter((card) => card.featured),
      ...cards.filter((card) => !card.featured),
    ];
  }

  get totalTopics() {
    return this.cards.reduce((sum, card) => sum + card.topics, 0);
  }

  get heading() {
    return t("title");
  }

  get summary() {
    return t("summary", {
      categories: this.cards.length,
      topics: this.totalTopics,
    });
  }

  label(key, options) {
    return t(key, options);
  }

  <template>
    {{#if this.show}}
      {{bodyClass "ig-categories-page"}}
      <section class="ig-cats">
        <header class="ig-cats__head">
          <h1>{{this.heading}}</h1>
          <p>{{this.summary}}</p>
        </header>

        <div class="ig-cats__grid">
          {{#each this.cards as |card|}}
            {{#if card.featured}}
              <IgStudioDirectory @card={{card}} />
            {{else}}
              <article class="ig-cat" style={{card.style}}>
                <a
                  class="ig-cat__cover {{if card.coverStyle 'has-image'}}"
                  href={{card.url}}
                  style={{card.coverStyle}}
                  aria-label={{card.name}}
                ></a>

                <div class="ig-cat__top">
                  <a class="ig-cat__ring" href={{card.url}} tabindex="-1">
                    {{#if card.logo}}
                      <img class="ig-cat__logo" src={{card.logo}} alt="" />
                    {{else}}
                      <span
                        class="ig-cat__logo ig-cat__logo--letter"
                      >{{card.letter}}</span>
                    {{/if}}
                  </a>
                  <IgCategoryFollow @category={{card.category}} />
                </div>

                <div class="ig-cat__body">
                  <h2 class="ig-cat__name"><a
                      href={{card.url}}
                    >{{card.name}}</a></h2>
                  {{#if card.description}}
                    <p class="ig-cat__desc">{{card.description}}</p>
                  {{/if}}
                  <p class="ig-cat__stats">
                    <span><b>{{card.topics}}</b>{{this.label "topics"}}</span>
                    {{#if card.week}}
                      <span><b>{{card.week}}</b>{{this.label
                          "this_week"
                        }}</span>
                    {{/if}}
                  </p>

                  {{#if card.chips.length}}
                    <ul class="ig-cat__chips">
                      {{#each card.chips as |chip|}}
                        <li>
                          <a
                            class="ig-cat__chip"
                            href={{chip.url}}
                            style={{chip.style}}
                          >
                            {{#if chip.logo}}
                              <img src={{chip.logo}} alt="" />
                            {{else}}
                              <span
                                class="ig-cat__chip-letter"
                              >{{chip.letter}}</span>
                            {{/if}}
                            {{chip.name}}
                          </a>
                        </li>
                      {{/each}}
                      {{#if card.moreChips}}
                        <li>
                          <a
                            class="ig-cat__chip ig-cat__chip--more"
                            href={{card.url}}
                          >
                            +{{card.moreChips}}
                          </a>
                        </li>
                      {{/if}}
                    </ul>
                  {{/if}}

                  {{#if card.latest}}
                    <a class="ig-cat__latest" href={{card.latest.url}}>
                      <span
                        class="ig-cat__latest-icon"
                        aria-hidden="true"
                      ></span>
                      <span
                        class="ig-cat__latest-title"
                      >{{card.latest.title}}</span>
                    </a>
                  {{/if}}
                </div>
              </article>
            {{/if}}
          {{/each}}
        </div>
      </section>
    {{/if}}
  </template>
}
