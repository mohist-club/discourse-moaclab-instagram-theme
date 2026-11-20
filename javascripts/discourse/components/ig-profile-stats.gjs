import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { modifier } from "ember-modifier";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

// Instagram's profile counters (posts · followers · following) mapped to
// Discourse's public user summary: topics · replies · likes received.
// Rendered in user-profile-primary; placed beside the avatar on phones
// (scss/mobile-profile.scss), hidden on wider screens.
const cache = new Map();

export default class IgProfileStats extends Component {
  @tracked summary = null;

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
      promise = ajax(`/u/${encodeURIComponent(username)}/summary.json`)
        .then((result) => result?.user_summary || null)
        .catch(() => null);
      cache.set(username, promise);
    }
    promise.then((summary) => {
      if (!this.isDestroying && !this.isDestroyed) {
        this.summary = summary;
      }
    });
  });

  get stats() {
    const s = this.summary;
    if (!s) {
      return null;
    }
    const replies = Math.max(0, (s.post_count || 0) - (s.topic_count || 0));
    return [
      { value: s.topic_count || 0, label: this.text("topics") },
      { value: replies, label: this.text("replies") },
      { value: s.likes_received || 0, label: this.text("likes") },
    ];
  }

  text(key) {
    return i18n(themePrefix(`ig.profile.${key}`));
  }

  <template>
    {{#if this.show}}
      <ul class="ig-profile-stats" {{this.load}}>
        {{#each this.stats as |stat|}}
          <li>
            <b>{{stat.value}}</b>
            <span>{{stat.label}}</span>
          </li>
        {{/each}}
      </ul>
    {{/if}}
  </template>
}
