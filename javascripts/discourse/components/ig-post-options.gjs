import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DModal from "discourse/components/d-modal";
import ShareTopicModal from "discourse/components/modal/share-topic";
import DiscourseURL from "discourse/lib/url";
import { clipboardCopy } from "discourse/lib/utilities";
import { i18n } from "discourse-i18n";

// Instagram's "⋯" sheet: a centred list of full-width rows. Every action
// is a native Discourse one (routing, the core share modal, clipboard).
export default class IgPostOptions extends Component {
  @service modal;

  @tracked copied = false;

  get topic() {
    return this.args.model.topic;
  }

  get absoluteUrl() {
    return new URL(this.topic.url, window.location.origin).href;
  }

  text(key) {
    return i18n(themePrefix(`ig.feed.${key}`));
  }

  get goToLabel() {
    return this.text("go_to_post");
  }

  get shareLabel() {
    return this.text("share_to");
  }

  get copyLabel() {
    return this.text(this.copied ? "copied" : "copy_link");
  }

  get cancelLabel() {
    return this.text("cancel");
  }

  @action
  goToPost() {
    this.args.closeModal();
    DiscourseURL.routeTo(this.topic.url);
  }

  @action
  share() {
    // replaces this modal with the core share modal
    this.modal.show(ShareTopicModal, { model: { topic: this.topic } });
  }

  @action
  async copyLink() {
    await clipboardCopy(this.absoluteUrl);
    this.copied = true;
  }

  <template>
    <DModal @closeModal={{@closeModal}} class="ig-post-options">
      <:body>
        <div class="ig-post-options__list" role="menu">
          <button
            type="button"
            class="ig-post-options__item"
            role="menuitem"
            {{on "click" this.goToPost}}
          >{{this.goToLabel}}</button>
          <button
            type="button"
            class="ig-post-options__item"
            role="menuitem"
            {{on "click" this.share}}
          >{{this.shareLabel}}</button>
          <button
            type="button"
            class="ig-post-options__item"
            role="menuitem"
            {{on "click" this.copyLink}}
          >{{this.copyLabel}}</button>
          <button
            type="button"
            class="ig-post-options__item"
            role="menuitem"
            {{on "click" @closeModal}}
          >{{this.cancelLabel}}</button>
        </div>
      </:body>
    </DModal>
  </template>
}
