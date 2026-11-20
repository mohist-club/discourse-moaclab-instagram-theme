import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import { modifier } from "ember-modifier";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import {
  isValidSearchTerm,
  searchForTerm,
  updateRecentSearches,
} from "discourse/lib/search";
import DiscourseURL from "discourse/lib/url";
import { i18n } from "discourse-i18n";

// Instagram's Explore search, on the Explore category's own page: a round
// grey field; focused, it lists your recent searches (Discourse's own
// search history); typing shows live results as Instagram account rows —
// studios / categories, people, tags, then posts — from Discourse's quick
// search (/search/query, the same call as the header search). Enter opens
// the selected row, or Discourse's full search page.

const DEBOUNCE = 250;
const MAX_ROWS = { categories: 5, users: 5, tags: 3, topics: 8 };

export default class IgExploreSearch extends Component {
  @service currentUser;
  @service siteSettings;

  @tracked term = "";
  @tracked open = false;
  @tracked loading = false;
  @tracked results = null;
  @tracked recent = null;
  @tracked activeIndex = -1;

  get show() {
    const id = parseInt(settings.instagram_explore_category, 10) || 0;
    return (
      !!settings.instagram_explore_search &&
      !!id &&
      this.args.category?.id === id
    );
  }

  text(key, options) {
    return i18n(themePrefix(`ig.search.${key}`), options);
  }

  get placeholder() {
    return this.text("placeholder");
  }

  get trimmed() {
    return this.term.trim();
  }

  get hasTerm() {
    return this.trimmed.length > 0;
  }

  get canLogRecent() {
    return !!this.currentUser && !!this.siteSettings.log_search_queries;
  }

  get fullSearchUrl() {
    return `/search?q=${encodeURIComponent(this.trimmed)}`;
  }

  get fullSearchLabel() {
    return this.text("see_all", { term: this.trimmed });
  }

  // one flat list of rows, so arrow keys can walk it
  get rows() {
    const r = this.results;
    if (!r) {
      return [];
    }
    const rows = [];
    for (const c of r.categories.slice(0, MAX_ROWS.categories)) {
      rows.push({
        kind: "category",
        url: c.url,
        title: c.name,
        subtitle: c.parentCategory?.name
          ? c.parentCategory.name
          : this.text("topics", { count: c.topic_count || 0 }),
        image: c.uploaded_logo?.url || null,
        letter: (c.name || "·").trim().charAt(0),
        color: c.color,
      });
    }
    for (const u of r.users.slice(0, MAX_ROWS.users)) {
      rows.push({
        kind: "user",
        url: `/u/${u.username}`,
        title: u.username,
        subtitle: u.name || "",
        image: u.avatar_template?.replace("{size}", "88"),
      });
    }
    for (const tag of r.tags.slice(0, MAX_ROWS.tags)) {
      const name = tag.name ?? tag.id ?? tag;
      rows.push({
        kind: "tag",
        url: `/tag/${name}`,
        title: `#${name}`,
        subtitle: this.text("tag"),
      });
    }
    const seen = new Set();
    const topics = [
      ...r.posts.map((p) => p.topic).filter(Boolean),
      ...r.topics,
    ];
    for (const t of topics) {
      if (seen.has(t.id) || seen.size >= MAX_ROWS.topics) {
        continue;
      }
      seen.add(t.id);
      rows.push({
        kind: "topic",
        url: `/t/${t.slug}/${t.id}`,
        title: t.title,
        subtitle: t.category?.name || "",
        image: t.image_url || null,
      });
    }
    return rows.map((row, index) => ({
      ...row,
      index,
      active: index === this.activeIndex,
      square: row.kind === "topic",
      isCategory: row.kind === "category",
      style: row.color ? htmlSafe(`background: #${row.color}`) : null,
    }));
  }

  get noResults() {
    return this.results && !this.loading && this.rows.length === 0;
  }

  get recentTerms() {
    return (this.recent || []).slice(0, 8);
  }

  // close when clicking outside
  outside = modifier((element) => {
    const onDown = (event) => {
      if (!element.contains(event.target)) {
        this.open = false;
      }
    };
    document.addEventListener("pointerdown", onDown);
    return () => document.removeEventListener("pointerdown", onDown);
  });

  @action
  async onFocus() {
    this.open = true;
    if (this.canLogRecent && this.recent === null) {
      this.recent = this.currentUser.recent_searches || [];
      try {
        const result = await ajax("/u/recent-searches");
        this.recent = result?.recent_searches || [];
      } catch {
        // keep whatever the user model had
      }
    }
  }

  @action
  onInput(event) {
    this.term = event.target.value;
    this.activeIndex = -1;
    clearTimeout(this.timer);
    if (!isValidSearchTerm(this.trimmed, this.siteSettings)) {
      this.results = null;
      this.loading = false;
      return;
    }
    this.loading = true;
    this.timer = setTimeout(() => this.runSearch(this.trimmed), DEBOUNCE);
  }

  async runSearch(term) {
    this.pending?.abort?.();
    const promise = searchForTerm(term, { skipSearchLog: false });
    this.pending = promise;
    try {
      const results = await promise;
      if (term === this.trimmed && !this.isDestroying && !this.isDestroyed) {
        this.results = results;
      }
    } catch {
      // aborted or failed: leave the previous results
    } finally {
      if (this.pending === promise) {
        this.loading = false;
      }
    }
  }

  @action
  onKeydown(event) {
    const count = this.rows.length;
    if (event.key === "ArrowDown" && count) {
      event.preventDefault();
      this.open = true;
      this.activeIndex = (this.activeIndex + 1) % count;
    } else if (event.key === "ArrowUp" && count) {
      event.preventDefault();
      this.activeIndex = (this.activeIndex - 1 + count) % count;
    } else if (event.key === "Enter") {
      event.preventDefault();
      const row = this.rows[this.activeIndex];
      if (row) {
        this.go(row.url);
      } else if (this.hasTerm) {
        this.fullSearch();
      }
    } else if (event.key === "Escape") {
      this.open = false;
      event.target.blur();
    }
  }

  go(url) {
    this.open = false;
    DiscourseURL.routeTo(url);
  }

  @action
  fullSearch() {
    if (this.canLogRecent) {
      updateRecentSearches(this.currentUser, this.trimmed);
    }
    this.go(this.fullSearchUrl);
  }

  @action
  useRecent(term) {
    this.term = term;
    this.open = true;
    this.loading = true;
    this.runSearch(term);
  }

  @action
  clear() {
    this.term = "";
    this.results = null;
    this.activeIndex = -1;
    this.loading = false;
  }

  // phones: Instagram's "Cancel" next to the field closes the search
  @action
  cancel(event) {
    this.clear();
    this.open = false;
    event.currentTarget
      .closest(".ig-search")
      ?.querySelector(".ig-search__input")
      ?.blur();
  }

  @action
  async clearRecent() {
    try {
      await ajax("/u/recent-searches", { type: "DELETE" });
      this.recent = [];
      this.currentUser.set?.("recent_searches", []);
    } catch (error) {
      popupAjaxError(error);
    }
  }

  <template>
    {{#if this.show}}
      <div class="ig-search {{if this.open 'is-open'}}" {{this.outside}}>
        <div class="ig-search__field">
          <span class="ig-search__icon" aria-hidden="true"></span>
          <input
            class="ig-search__input"
            type="search"
            value={{this.term}}
            placeholder={{this.placeholder}}
            aria-label={{this.placeholder}}
            autocomplete="off"
            {{on "focus" this.onFocus}}
            {{on "input" this.onInput}}
            {{on "keydown" this.onKeydown}}
          />
          {{#if this.loading}}
            <span class="ig-search__spinner" aria-hidden="true"></span>
          {{else if this.hasTerm}}
            <button
              type="button"
              class="ig-search__clear"
              aria-label={{this.text "clear"}}
              {{on "click" this.clear}}
            ></button>
          {{/if}}
        </div>
        {{#if this.open}}
          <button
            type="button"
            class="ig-search__cancel"
            {{on "click" this.cancel}}
          >{{this.text "cancel"}}</button>
        {{/if}}

        {{#if this.open}}
          <div class="ig-search__panel" role="listbox">
            {{#if this.hasTerm}}
              {{#each this.rows as |row|}}
                <a
                  class="ig-search__row {{if row.active 'is-active'}}"
                  href={{row.url}}
                  role="option"
                  aria-selected={{if row.active "true" "false"}}
                >
                  {{#if row.image}}
                    <img
                      class="ig-search__avatar {{if row.square 'is-square'}}"
                      src={{row.image}}
                      alt=""
                    />
                  {{else if row.isCategory}}
                    <span
                      class="ig-search__avatar ig-search__avatar--letter"
                      style={{row.style}}
                    >{{row.letter}}</span>
                  {{else}}
                    <span
                      class="ig-search__avatar ig-search__avatar--{{row.kind}}"
                    ></span>
                  {{/if}}
                  <span class="ig-search__text">
                    <span class="ig-search__title">{{row.title}}</span>
                    {{#if row.subtitle}}
                      <span class="ig-search__sub">{{row.subtitle}}</span>
                    {{/if}}
                  </span>
                </a>
              {{/each}}
              {{#if this.noResults}}
                <p class="ig-search__empty">{{this.text "no_results"}}</p>
              {{/if}}
              <a
                class="ig-search__all"
                href={{this.fullSearchUrl}}
                {{on "click" this.fullSearch}}
              >
                <span
                  class="ig-search__avatar ig-search__avatar--search"
                ></span>
                <span class="ig-search__title">{{this.fullSearchLabel}}</span>
              </a>
            {{else}}
              <div class="ig-search__head">
                <h3>{{this.text "recent"}}</h3>
                {{#if this.recentTerms.length}}
                  <button
                    type="button"
                    class="ig-search__link"
                    {{on "click" this.clearRecent}}
                  >{{this.text "clear_all"}}</button>
                {{/if}}
              </div>
              {{#each this.recentTerms as |term|}}
                <button
                  type="button"
                  class="ig-search__row"
                  {{on "click" (fn this.useRecent term)}}
                >
                  <span
                    class="ig-search__avatar ig-search__avatar--search"
                  ></span>
                  <span class="ig-search__text">
                    <span class="ig-search__title">{{term}}</span>
                  </span>
                </button>
              {{else}}
                <p class="ig-search__empty">{{this.text "no_recent"}}</p>
              {{/each}}
            {{/if}}
          </div>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
