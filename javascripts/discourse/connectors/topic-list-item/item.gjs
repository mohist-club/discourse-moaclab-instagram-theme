import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import ShareTopicModal from "discourse/components/modal/share-topic";
import PluginOutlet from "discourse/components/plugin-outlet";
import TopicExcerpt from "discourse/components/topic-list/topic-excerpt";
import TopicLink from "discourse/components/topic-list/topic-link";
import UnreadIndicator from "discourse/components/topic-list/unread-indicator";
import TopicPostBadges from "discourse/components/topic-post-badges";
import TopicStatus from "discourse/components/topic-status";
import avatar from "discourse/helpers/avatar";
import formatDate from "discourse/helpers/format-date";
import lazyHash from "discourse/helpers/lazy-hash";
import topicFeaturedLink from "discourse/helpers/topic-featured-link";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { deferAnonymousAction } from "discourse/lib/anonymous-action";
import { wantsNewWindow } from "discourse/lib/intercept-click";
import DiscourseURL from "discourse/lib/url";
import { i18n } from "discourse-i18n";
import IgPostOptions from "../../components/ig-post-options";

// Instagram feed post (instagram.com, 2026) mapped onto a Discourse topic:
//   header   avatar · username • time / category (IG's location line) · ⋯
//   media    first thumbnail: 468px + 1px border, 4px radius, 3:4 … 1.91:1
//   actions  like + count · comments + count · share ············ save
//   caption  username + title + #tags … more (expands the excerpt)
//   footer   "View all N comments"
// Topics without an image show title + excerpt where the media would be.
// Like, save and share all call Discourse's own APIs.

const MIN_RATIO = 3 / 4;
const MAX_RATIO = 1.91;

export default class Item extends Component {
  @service currentUser;
  @service modal;
  @service bookmarkApi;

  @tracked liked = false;
  @tracked likeCount;
  @tracked likePost;
  @tracked isTogglingLike = false;
  @tracked saved = !!this.args.outletArgs.topic.bookmarked;
  @tracked savedBookmarkId = null;
  @tracked isTogglingSave = false;
  @tracked expanded = false;

  get topic() {
    return this.args.outletArgs.topic;
  }

  get poster() {
    return this.topic.posters?.[0]?.user;
  }

  get thumbnail() {
    return this.topic.thumbnails?.[0];
  }

  get mediaStyle() {
    const ratio =
      Number(this.thumbnail?.width) / Number(this.thumbnail?.height);
    const safe = Number.isFinite(ratio) && ratio > 0 ? ratio : 1;
    const clamped = Math.min(MAX_RATIO, Math.max(MIN_RATIO, safe));
    return htmlSafe(`--ig-media-ratio: ${clamped}`);
  }

  get category() {
    return this.args.outletArgs.hideCategory ? null : this.topic.category;
  }

  get tagNames() {
    return (this.topic.tags || [])
      .map((tag) => (typeof tag === "string" ? tag : tag?.name))
      .filter(Boolean);
  }

  get topicLikeCount() {
    return this.likeCount ?? this.topic.like_count ?? 0;
  }

  get replyCount() {
    return this.topic.replyCount ?? 0;
  }

  get hasExcerpt() {
    return !!this.topic.excerpt;
  }

  get newDotText() {
    return this.currentUser?.trust_level > 0
      ? ""
      : i18n("filters.new.lower_title");
  }

  text(key, options) {
    return i18n(themePrefix(`ig.feed.${key}`), options);
  }

  get likeLabel() {
    return this.text(this.liked ? "unlike" : "like");
  }

  get saveLabel() {
    return this.text(this.saved ? "unsave" : "save");
  }

  get commentLabel() {
    return this.text("comment");
  }

  get shareLabel() {
    return this.text("share");
  }

  get optionsLabel() {
    return this.text("options");
  }

  get moreLabel() {
    return this.text("more");
  }

  get viewCommentsLabel() {
    return this.text("view_comments", { count: this.replyCount });
  }

  get canToggleLike() {
    if (!this.currentUser) {
      return !this.topic.archived;
    }
    return this.likePost ? this.likePost.canToggleLike : true;
  }

  get likeDisabled() {
    return this.isTogglingLike || !this.canToggleLike;
  }

  @action
  onTitleFocus(event) {
    event.target.closest(".topic-list-item")?.classList.add("selected");
  }

  @action
  onTitleBlur(event) {
    event.target.closest(".topic-list-item")?.classList.remove("selected");
  }

  @action
  openTopic(event) {
    if (event.target.closest("a:not(.raw-link), button, .badge-wrapper")) {
      return;
    }

    const { navigateToTopic } = this.args.outletArgs;
    if (wantsNewWindow(event)) {
      window.open(this.topic.lastUnreadUrl, "_blank");
    } else {
      navigateToTopic(this.topic, this.topic.lastUnreadUrl);
    }
  }

  @action
  share(event) {
    event.stopPropagation();
    this.modal.show(ShareTopicModal, { model: { topic: this.topic } });
  }

  @action
  openOptions(event) {
    event.stopPropagation();
    this.modal.show(IgPostOptions, { model: { topic: this.topic } });
  }

  @action
  toggleExpanded(event) {
    event.stopPropagation();
    this.expanded = !this.expanded;
  }

  @action
  async toggleLike(event) {
    event.stopPropagation();

    if (this.isTogglingLike || !this.canToggleLike) {
      return;
    }

    this.isTogglingLike = true;

    try {
      const post = this.likePost ?? (await this.topic.firstPost());
      this.likePost = post;
      this.liked = post.liked;

      if (!this.currentUser) {
        await deferAnonymousAction(this, "like_post", { post_id: post.id });
        return;
      }

      if (!post.canToggleLike) {
        return;
      }

      const wasLiked = post.liked;
      await post.likeAction.togglePromise(post);
      this.liked = post.liked;

      if (wasLiked !== post.liked) {
        this.likeCount = Math.max(
          0,
          Number(this.topicLikeCount) + (post.liked ? 1 : -1)
        );
      }
    } finally {
      this.isTogglingLike = false;
    }
  }

  // Instagram's save = Discourse bookmark on the topic's first post, through
  // the core bookmark API (same endpoints the post menu uses).
  @action
  async toggleSave(event) {
    event.stopPropagation();

    if (!this.currentUser) {
      DiscourseURL.routeTo("/login");
      return;
    }
    if (this.isTogglingSave) {
      return;
    }

    this.isTogglingSave = true;

    try {
      const post = this.likePost ?? (await this.topic.firstPost());
      this.likePost = post;

      if (this.saved) {
        const id = this.savedBookmarkId ?? post.bookmark_id;
        if (!id) {
          // saved on a later post: manage it inside the topic
          DiscourseURL.routeTo(this.topic.lastUnreadUrl);
          return;
        }
        await this.bookmarkApi.delete(id);
        this.savedBookmarkId = null;
        this.saved = false;
      } else {
        const created = await this.bookmarkApi.create(
          this.bookmarkApi.buildNewBookmark("Post", post.id)
        );
        this.savedBookmarkId = created?.id ?? null;
        this.saved = true;
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isTogglingSave = false;
    }
  }

  <template>
    {{! template-lint-disable no-invalid-interactive }}
    <article
      {{on "click" this.openTopic}}
      class="ig-post {{if this.thumbnail 'ig-post--media' 'ig-post--text'}}"
    >
      <header class="ig-post__header">
        {{#if this.poster}}
          <a
            class="ig-post__avatar"
            data-user-card={{this.poster.username}}
            href="/u/{{this.poster.username}}"
          >
            {{avatar this.poster imageSize="medium"}}
          </a>
        {{/if}}

        <div class="ig-post__who">
          <div class="ig-post__byline">
            {{#if this.poster}}
              <a
                class="ig-post__user"
                data-user-card={{this.poster.username}}
                href="/u/{{this.poster.username}}"
              >{{this.poster.username}}</a>
              <span class="ig-post__dot" aria-hidden="true">•</span>
            {{/if}}
            <span class="ig-post__time">
              {{formatDate this.topic.createdAt format="tiny" noTitle="true"}}
            </span>
          </div>

          {{#if this.category}}
            <PluginOutlet
              @name="topic-list-before-category"
              @outletArgs={{lazyHash topic=this.topic}}
            />
            <a
              class="ig-post__place"
              href={{this.category.url}}
            >{{this.category.name}}</a>
          {{/if}}
        </div>

        <button
          type="button"
          class="ig-post__options"
          title={{this.optionsLabel}}
          aria-label={{this.optionsLabel}}
          {{on "click" this.openOptions}}
        >
          <span class="ig-glyph ig-glyph--dots" aria-hidden="true"></span>
        </button>
      </header>

      {{#if this.thumbnail}}
        <div class="ig-post__media" style={{this.mediaStyle}}>
          <img
            alt={{this.topic.title}}
            loading="lazy"
            decoding="async"
            width={{this.thumbnail.width}}
            height={{this.thumbnail.height}}
            src={{this.thumbnail.url}}
          />
        </div>
      {{else}}
        <div class="ig-post__text">
          <h2 class="ig-post__title link-top-line">
            <TopicStatus @topic={{this.topic}} />
            <TopicLink
              {{on "focus" this.onTitleFocus}}
              {{on "blur" this.onTitleBlur}}
              @topic={{this.topic}}
              class="raw-link raw-topic-link"
            />
            {{#if this.topic.featured_link}}
              {{topicFeaturedLink this.topic}}
            {{/if}}
            <PluginOutlet
              @name="topic-list-after-title"
              @outletArgs={{lazyHash topic=this.topic}}
            />
            <UnreadIndicator @topic={{this.topic}} />
            {{#if @outletArgs.showTopicPostBadges}}
              <TopicPostBadges
                @unreadPosts={{this.topic.unread_posts}}
                @unseen={{this.topic.unseen}}
                @newDotText={{this.newDotText}}
                @url={{this.topic.lastUnreadUrl}}
              />
            {{/if}}
          </h2>
          {{#if this.hasExcerpt}}
            <div class="ig-post__excerpt">
              <TopicExcerpt @topic={{this.topic}} />
            </div>
          {{/if}}
          {{#if this.tagNames.length}}
            <div class="ig-post__tags">
              {{#each this.tagNames as |tag|}}
                <a class="ig-post__tag" href="/tag/{{tag}}">#{{tag}}</a>
              {{/each}}
            </div>
          {{/if}}
        </div>
      {{/if}}

      {{! grid views (Explore, suggested topics): title and counts on hover }}
      <div class="ig-post__overlay" aria-hidden="true">
        <span class="ig-post__overlay-title">{{this.topic.title}}</span>
        <span class="ig-post__overlay-stats">
          <span class="ig-post__overlay-stat">
            <span class="ig-glyph ig-glyph--heart-filled"></span>
            {{this.topicLikeCount}}
          </span>
          <span class="ig-post__overlay-stat">
            <span class="ig-glyph ig-glyph--comment-filled"></span>
            {{this.replyCount}}
          </span>
        </span>
      </div>

      <div class="ig-post__actions">
        {{#if settings.show_like_count}}
          <button
            type="button"
            class="ig-post__action ig-post__like {{if this.liked 'is-liked'}}"
            title={{this.likeLabel}}
            aria-pressed={{if this.liked "true" "false"}}
            disabled={{this.likeDisabled}}
            {{on "click" this.toggleLike}}
          >
            <span
              class="ig-glyph
                {{if this.liked 'ig-glyph--heart-filled' 'ig-glyph--heart'}}"
              aria-hidden="true"
            ></span>
            {{#if this.topicLikeCount}}
              <span class="ig-post__count">{{this.topicLikeCount}}</span>
            {{/if}}
            <span class="sr-only">{{this.likeLabel}}</span>
          </button>
        {{/if}}

        <a
          class="ig-post__action ig-post__comment"
          href={{this.topic.lastUnreadUrl}}
          title={{this.commentLabel}}
        >
          <span class="ig-glyph ig-glyph--comment" aria-hidden="true"></span>
          {{#if this.replyCount}}
            <span class="ig-post__count">{{this.replyCount}}</span>
          {{/if}}
          <span class="sr-only">{{this.commentLabel}}</span>
        </a>

        <button
          type="button"
          class="ig-post__action ig-post__share"
          title={{this.shareLabel}}
          {{on "click" this.share}}
        >
          <span class="ig-glyph ig-glyph--share" aria-hidden="true"></span>
          <span class="sr-only">{{this.shareLabel}}</span>
        </button>

        <button
          type="button"
          class="ig-post__action ig-post__save {{if this.saved 'is-saved'}}"
          title={{this.saveLabel}}
          aria-pressed={{if this.saved "true" "false"}}
          disabled={{this.isTogglingSave}}
          {{on "click" this.toggleSave}}
        >
          <span
            class="ig-glyph
              {{if this.saved 'ig-glyph--save-filled' 'ig-glyph--save'}}"
            aria-hidden="true"
          ></span>
          <span class="sr-only">{{this.saveLabel}}</span>
        </button>
      </div>

      {{#if this.thumbnail}}
        <div class="ig-post__caption link-top-line">
          {{#if this.poster}}
            <a
              class="ig-post__user"
              data-user-card={{this.poster.username}}
              href="/u/{{this.poster.username}}"
            >{{this.poster.username}}</a>
          {{/if}}
          <TopicStatus @topic={{this.topic}} />
          <TopicLink
            {{on "focus" this.onTitleFocus}}
            {{on "blur" this.onTitleBlur}}
            @topic={{this.topic}}
            class="raw-link raw-topic-link"
          />
          {{#if this.topic.featured_link}}
            {{topicFeaturedLink this.topic}}
          {{/if}}
          <PluginOutlet
            @name="topic-list-after-title"
            @outletArgs={{lazyHash topic=this.topic}}
          />
          {{#each this.tagNames as |tag|}}
            <a class="ig-post__tag" href="/tag/{{tag}}">#{{tag}}</a>
          {{/each}}
          <UnreadIndicator @topic={{this.topic}} />
          {{#if @outletArgs.showTopicPostBadges}}
            <TopicPostBadges
              @unreadPosts={{this.topic.unread_posts}}
              @unseen={{this.topic.unseen}}
              @newDotText={{this.newDotText}}
              @url={{this.topic.lastUnreadUrl}}
            />
          {{/if}}
          {{#if this.hasExcerpt}}
            {{#unless this.expanded}}
              <button
                type="button"
                class="ig-post__more"
                {{on "click" this.toggleExpanded}}
              >{{this.moreLabel}}</button>
            {{/unless}}
          {{/if}}
        </div>
        {{#if this.expanded}}
          <div class="ig-post__excerpt">
            <TopicExcerpt @topic={{this.topic}} />
          </div>
        {{/if}}
      {{/if}}

      {{#if this.replyCount}}
        <a
          class="ig-post__comments"
          href={{this.topic.lastUnreadUrl}}
        >{{this.viewCommentsLabel}}</a>
      {{/if}}
    </article>
  </template>
}
