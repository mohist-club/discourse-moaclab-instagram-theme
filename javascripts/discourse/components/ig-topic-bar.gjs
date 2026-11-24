import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import bodyClass from "discourse/helpers/body-class";
import DiscourseURL from "discourse/lib/url";
import { i18n } from "discourse-i18n";
import { canGoBackInApp, currentTopic } from "../lib/ig-last-page";

// Instagram's top bar on phones for a post or a profile: a back arrow and
// "帖子" (topic pages), the username (profile pages), the studio's name
// (a subcategory: a studio is a profile) or the #tag. Rendered in the
// header (header-contents__before); shown below 768px on those pages only
// (scss/mobile-topic.scss, scss/mobile-profile.scss), replacing the logo.
export default class IgTopicBar extends Component {
  @service router;
  @service composer;
  @service currentUser;
  @service discovery;

  get route() {
    return this.router.currentRouteName || "";
  }

  get isMessages() {
    return this.route.startsWith("userPrivateMessages");
  }

  get isNotifications() {
    return this.route.startsWith("userNotifications");
  }

  get isPreferences() {
    return this.route.startsWith("preferences");
  }

  // a subcategory's list (a studio, a board): reached from its parent, so
  // it gets a way back; top-level categories are tab-bar destinations
  get subcategory() {
    if (!this.discovery?.onDiscoveryRoute) {
      return null;
    }
    const category = this.discovery.category;
    return category?.parent_category_id ? category : null;
  }

  get tagName() {
    if (!this.discovery?.onDiscoveryRoute) {
      return null;
    }
    const tag = this.discovery.tag;
    return tag?.name || tag?.id || null;
  }

  get show() {
    return (
      !!settings.instagram_mobile_layout &&
      (this.route.startsWith("topic.") ||
        this.route.startsWith("user.") ||
        this.isMessages ||
        this.isNotifications ||
        this.isPreferences ||
        !!this.subcategory ||
        !!this.tagName)
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

  // a group conversation: more than two people, or a group invited
  get isGroupChat() {
    const topic = currentTopic(this.router);
    if (topic?.archetype !== "private_message") {
      return false;
    }
    const details = topic.details || {};
    return (
      (details.allowed_users?.length || 0) > 2 ||
      (details.allowed_groups?.length || 0) > 0
    );
  }

  get title() {
    if (this.messagePeople) {
      return this.messagePeople;
    }
    if (this.isMessages) {
      return i18n(themePrefix("ig.rail.messages"));
    }
    if (this.isNotifications) {
      return i18n(themePrefix("ig.rail.activity"));
    }
    if (this.isPreferences) {
      return i18n(themePrefix("ig.menu.settings"));
    }
    if (this.subcategory) {
      return this.subcategory.name;
    }
    if (this.tagName) {
      return `#${this.tagName}`;
    }
    if (this.route.startsWith("user.")) {
      // the profile's username, from the URL (/u/<username>/…)
      const url = this.router.currentURL || window.location.pathname;
      const match = url.match(/^\/u\/([^/?#]+)/);
      return match ? decodeURIComponent(match[1]) : "";
    }
    return i18n(themePrefix("ig.topic.title"));
  }

  // your own profile: Instagram's ≡ on the right (the native sidebar
  // drawer, with chat, categories and tools)
  get isOwnProfile() {
    if (!this.route.startsWith("user.") || !this.currentUser) {
      return false;
    }
    const url = this.router.currentURL || window.location.pathname;
    const match = url.match(/^\/u\/([^/?#]+)/);
    return (
      !!match &&
      decodeURIComponent(match[1]).toLowerCase() ===
        this.currentUser.username.toLowerCase()
    );
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
    {{#if this.isGroupChat}}
      {{bodyClass "ig-group-chat"}}
    {{/if}}
    {{#if this.show}}
      {{! page classes for the stylesheet (cheaper than :has() on body) }}
      {{bodyClass "ig-has-topic-bar"}}
      {{#if this.isOwnProfile}}
        {{bodyClass "ig-own-profile-bar"}}
      {{/if}}
      <div class="ig-topic-bar {{if this.isOwnProfile 'ig-topic-bar--menu'}}">
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
