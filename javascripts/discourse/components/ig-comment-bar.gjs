import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";
import { currentTopic } from "../lib/ig-last-page";

// Instagram's "Add a comment…" bar on phones, fixed above the tab bar on
// topic pages. Tapping it presses Discourse's own reply button (log-in for
// visitors, drafts, permissions all native); shown below 768px only.
export default class IgCommentBar extends Component {
  @service router;
  @service currentUser;

  get show() {
    return (
      !!settings.instagram_mobile_layout &&
      (this.router.currentRouteName || "").startsWith("topic.")
    );
  }

  get avatarUrl() {
    return this.currentUser?.avatar_template?.replace("{size}", "64");
  }

  get isMessage() {
    return currentTopic(this.router)?.archetype === "private_message";
  }

  // a conversation reads "Message…", a post "Add a comment…"
  get placeholder() {
    return i18n(
      themePrefix(this.isMessage ? "ig.topic.message" : "ig.topic.add_comment")
    );
  }

  get postLabel() {
    return i18n(
      themePrefix(this.isMessage ? "ig.topic.send" : "ig.topic.post")
    );
  }

  @action
  reply() {
    const button = document.querySelector(
      "#topic-footer-buttons .create, .topic-footer-main-buttons .create"
    );
    if (button) {
      button.click();
    } else {
      document
        .querySelector("#topic-footer-buttons")
        ?.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  }

  <template>
    {{#if this.show}}
      <button type="button" class="ig-comment-bar" {{on "click" this.reply}}>
        {{#if this.avatarUrl}}
          <img class="ig-comment-bar__avatar" src={{this.avatarUrl}} alt="" />
        {{/if}}
        <span class="ig-comment-bar__field">{{this.placeholder}}</span>
        <span class="ig-comment-bar__post">{{this.postLabel}}</span>
      </button>
    {{/if}}
  </template>
}
