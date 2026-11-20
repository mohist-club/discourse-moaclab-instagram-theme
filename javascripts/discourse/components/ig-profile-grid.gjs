import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { htmlSafe } from "@ember/template";
import { modifier } from "ember-modifier";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

// Instagram's profile grid on phones: the user's topics as 3:4 tiles,
// 3 across, 2px apart (image, else the title on grey), newest first.
// Rendered at the top of the profile summary (above-user-summary-stats);
// the native summary sections give way to it below 768px.
const cache = new Map();

export default class IgProfileGrid extends Component {
  @tracked result = null;

  get user() {
    return this.args.user;
  }

  get show() {
    return !!settings.instagram_mobile_layout && !!this.user?.username;
  }

  load = modifier(() => {
    const username = this.user?.username;
    if (!username) {
      return;
    }
    let promise = cache.get(username);
    if (!promise) {
      promise = ajax(
        `/topics/created-by/${encodeURIComponent(username)}.json`
      ).catch(() => null);
      cache.set(username, promise);
    }
    promise.then((result) => {
      if (!this.isDestroying && !this.isDestroyed) {
        this.result = result;
      }
    });
  });

  get tiles() {
    return (this.result?.topic_list?.topics || []).map((topic) => {
      const image = topic.thumbnails?.[0]?.url || topic.image_url;
      return {
        url: `/t/${topic.slug}/${topic.id}`,
        title: topic.title,
        style: image
          ? htmlSafe(`background-image: url("${encodeURI(image)}")`)
          : null,
      };
    });
  }

  get loaded() {
    return this.result !== null;
  }

  get hasMore() {
    return !!this.result?.topic_list?.more_topics_url;
  }

  get allUrl() {
    return `/u/${this.user.username}/activity/topics`;
  }

  text(key) {
    return i18n(themePrefix(`ig.profile.${key}`));
  }

  <template>
    {{#if this.show}}
      <section class="ig-profile-grid" {{this.load}}>
        {{#if this.tiles.length}}
          <ul class="ig-profile-grid__tiles">
            {{#each this.tiles as |tile|}}
              <li>
                <a
                  class="ig-profile-grid__tile {{if tile.style 'has-image'}}"
                  href={{tile.url}}
                  style={{tile.style}}
                  title={{tile.title}}
                >
                  {{#unless tile.style}}
                    <span>{{tile.title}}</span>
                  {{/unless}}
                </a>
              </li>
            {{/each}}
          </ul>
          {{#if this.hasMore}}
            <a class="ig-profile-grid__all" href={{this.allUrl}}>{{this.text
                "all_topics"
              }}</a>
          {{/if}}
        {{else if this.loaded}}
          <p class="ig-profile-grid__empty">{{this.text "no_topics"}}</p>
        {{/if}}
      </section>
    {{/if}}
  </template>
}
