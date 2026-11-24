import Component from "@glimmer/component";
import { cached } from "@glimmer/tracking";
import { service } from "@ember/service";
import bodyClass from "discourse/helpers/body-class";
import { NotificationLevels } from "discourse/lib/notification-levels";
import { i18n } from "discourse-i18n";
import { studiosParentId } from "../lib/ig-studios";

// The studios page (instagram_studios_page) in the layout of Instagram's
// blog (about.instagram.com/blog), without its filters:
//   large title + one line
//   featured: one large card, two compact rows beside it
//   then every other studio in a 3-column grid
// A card: square image (the newest featured post's, else the logo on
// white) with the logo as a badge · #N posts / #following pills · name ·
// clock + "updated … ago". Hovering a card lays it on a cream panel.
// Rendered in core's above-discovery-categories outlet on the studio
// parent's subcategories page; all studios come with that page (each with
// its featured topics), so nothing else is fetched. Images load lazily.

const FEATURED = 3;
const DAY = 24 * 60 * 60 * 1000;

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
      <span class="ig-sp-card__date">
        <span class="ig-sp-card__clock" aria-hidden="true"></span>
        {{@studio.updated}}
      </span>
    </span>
  </a>
</template>;

export default class IgStudiosPage extends Component {
  @service router;

  get parentId() {
    return studiosParentId();
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
    const following = [
      NotificationLevels.WATCHING,
      NotificationLevels.WATCHING_FIRST_POST,
    ];
    const studios = this.categories.map((c, index) => {
      const topics = c.topics || c.featuredTopics || [];
      const cover = topics.find((topic) => imageOf(topic, 0));
      const time = lastUpdate(topics);
      return {
        index,
        time,
        url: c.url,
        name: c.name || "",
        letter: (c.name || "·").trim().charAt(0),
        logo: c.uploaded_logo?.url || c.uploaded_logo_dark?.url || null,
        image: cover ? imageOf(cover, 600) : null,
        imageBig: cover ? imageOf(cover, 1080) : null,
        postsTag: t("posts", { count: c.topic_count || 0 }),
        followingTag: following.includes(c.notification_level)
          ? t("following")
          : null,
        updated: updatedLabel(time),
      };
    });
    // newest first; studios without posts last, in Discourse's order
    return studios.sort(
      (a, b) => (b.time || 0) - (a.time || 0) || a.index - b.index
    );
  }

  get hasFeatured() {
    return this.studios.length > FEATURED;
  }

  get main() {
    return this.studios[0];
  }

  get side() {
    return this.studios.slice(1, FEATURED);
  }

  get grid() {
    return this.hasFeatured ? this.studios.slice(FEATURED) : this.studios;
  }

  get title() {
    return t("title");
  }

  get summary() {
    return t("summary", { count: this.studios.length });
  }

  <template>
    {{#if this.show}}
      {{bodyClass "ig-studios-page"}}
      <section class="ig-sp">
        <header class="ig-sp__hero">
          <h1>{{this.title}}</h1>
          <p>{{this.summary}}</p>
        </header>

        {{#if this.hasFeatured}}
          <div class="ig-sp__feat">
            <StudioCard @studio={{this.main}} @big={{true}} @eager={{true}} />
            <div class="ig-sp__feat-side">
              {{#each this.side as |studio|}}
                <StudioCard @studio={{studio}} @row={{true}} @eager={{true}} />
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
  </template>
}
