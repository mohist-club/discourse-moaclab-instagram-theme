import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DiscourseURL from "discourse/lib/url";
import { i18n } from "discourse-i18n";
import { canGoBackInApp, currentTopic } from "../lib/ig-last-page";

// Instagram's top bar on phones for a post or a profile: a back arrow and
// "帖子" (topic pages) or the username (profile pages). Rendered in the
// header (header-contents__before); shown below 768px on those pages only
// (scss/mobile-topic.scss, scss/mobile-profile.scss), replacing the logo.
export default class IgTopicBar extends Component {
  @service router;
  @service composer;
  @service currentUser;

  get route() {
    return this.router.currentRouteName || "";
  }

  get isMessages() {
    return this.route.startsWith("userPrivateMessages");
  }

  get show() {
    return (
      !!settings.instagram_mobile_layout &&
      (this.route.startsWith("topic.") ||
        this.route.startsWith("user.") ||
        this.isMessages)
    );
  }

  // a private message: the other people in the conversation
  get messagePeople() {
    const topic = currentTopic(this.router);
    if (topic?.archetype !== "private_message") {
      return null;
    }
    const me = this.currentUser?.username;
    const names = (topic.details?.allowed_users || [])
      .map((u) => u.username)
      .filter((name) => name && name !== me);
    return names.length ? names.join("、") : null;
  }

  get title() {
    if (this.messagePeople) {
      return this.messagePeople;
    }
    if (this.isMessages) {
      return i18n(themePrefix("ig.rail.messages"));
    }
    if (this.route.startsWith("user.")) {
      // the profile's username, from the URL (/u/<username>/…)
      const url = this.router.currentURL || window.location.pathname;
      const match = url.match(/^\/u\/([^/?#]+)/);
      return match ? decodeURIComponent(match[1]) : "";
    }
    return i18n(themePrefix("ig.topic.title"));
  }

  get backLabel() {
    return i18n(themePrefix("ig.topic.back"));
  }

  get composeLabel() {
    return i18n(themePrefix("ig.messages.new_message"));
  }

  // the inbox's compose icon presses Discourse's own "new message" button
  @action
  compose() {
    const button = document.querySelector("#new-private-message-btn");
    if (button) {
      button.click();
    } else {
      this.composer.openNewMessage({});
    }
  }

  @action
  back() {
    if (canGoBackInApp()) {
      window.history.back();
    } else {
      DiscourseURL.routeTo("/");
    }
  }

  <template>
    {{#if this.show}}
      <div class="ig-topic-bar">
        <button
          type="button"
          class="ig-topic-bar__back"
          title={{this.backLabel}}
          aria-label={{this.backLabel}}
          {{on "click" this.back}}
        ></button>
        <span class="ig-topic-bar__title">{{this.title}}</span>
        {{#if this.isMessages}}
          <button
            type="button"
            class="ig-topic-bar__compose"
            title={{this.composeLabel}}
            aria-label={{this.composeLabel}}
            {{on "click" this.compose}}
          ></button>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
