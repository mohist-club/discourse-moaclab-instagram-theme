import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { NotificationLevels } from "discourse/lib/notification-levels";
import DiscourseURL from "discourse/lib/url";
import { i18n } from "discourse-i18n";

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

export default class IgCategoriesGrid extends Component {
  get show() {
    return !!settings.instagram_categories_page && this.cards.length > 0;
  }

  get categories() {
    const list = this.args.categories;
    return list ? [...list] : [];
  }

  get cards() {
    return this.categories
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
          latest: latest
            ? {
                title: latest.title,
                url: `/t/${latest.slug}/${latest.id}`,
              }
            : null,
        };
      });
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
      <section class="ig-cats">
        <header class="ig-cats__head">
          <h1>{{this.heading}}</h1>
          <p>{{this.summary}}</p>
        </header>

        <div class="ig-cats__grid">
          {{#each this.cards as |card|}}
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
                    <span><b>{{card.week}}</b>{{this.label "this_week"}}</span>
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
                    <span class="ig-cat__latest-icon" aria-hidden="true"></span>
                    <span
                      class="ig-cat__latest-title"
                    >{{card.latest.title}}</span>
                  </a>
                {{/if}}
              </div>
            </article>
          {{/each}}
        </div>
      </section>
    {{/if}}
  </template>
}
