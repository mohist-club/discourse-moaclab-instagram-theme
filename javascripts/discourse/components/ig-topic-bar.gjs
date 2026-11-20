import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DiscourseURL from "discourse/lib/url";
import { i18n } from "discourse-i18n";
import { canGoBackInApp } from "../lib/ig-last-page";

// Instagram's post page top bar on phones: a back arrow and "帖子".
// Rendered in the header (header-contents__before); shown below 768px on
// topic pages only (scss/mobile-topic.scss), where it replaces the logo.
export default class IgTopicBar extends Component {
  @service router;

  get show() {
    return (
      !!settings.instagram_mobile_layout &&
      (this.router.currentRouteName || "").startsWith("topic.")
    );
  }

  get title() {
    return i18n(themePrefix("ig.topic.title"));
  }

  get backLabel() {
    return i18n(themePrefix("ig.topic.back"));
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
      </div>
    {{/if}}
  </template>
}
