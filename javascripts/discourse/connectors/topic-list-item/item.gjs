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
import { modifier } from "ember-modifier";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { deferAnonymousAction } from "discourse/lib/anonymous-action";
import { wantsNewWindow } from "discourse/lib/intercept-click";
import DiscourseURL from "discourse/lib/url";
import { i18n } from "discourse-i18n";
import IgPostOptions from "../../components/ig-post-options";
import {
  imagesFromCooked,
  loadFirstPost,
  whenNearViewport,
} from "../../lib/ig-first-post";

// Instagram feed post (instagram.com, 2026) mapped onto a Discourse topic:
//   header   avatar · username • time / category (IG's location line) · ⋯
//   media    first thumbnail: 468px + 1px border, 4px radius, 3:4 … 1.91:1
//   actions  like + count · comments + count · share ············ save
//   caption  username + title + #tags … more (expands the excerpt)
//   footer   "View all N comments"
// Topics without an image show title + excerpt where the media would be.
// Like, save and share all call Discourse's own APIs.
//
// Like = Discourse's like on the first post: state from the topic list
// (serialize_topic_op_likes_data), the same /post_actions calls as the post
// menu, log-in-then-like for visitors; double-clicking the media likes it.
// Several images in the first post = Instagram's carousel (arrows, swipe,
// dots); the post is loaded once the card is near the viewport and the
// next image is preloaded.

const MIN_RATIO = 3 / 4;
const MAX_RATIO = 1.91;
const LIKE = 2; // PostActionType like
const CLICK_DELAY = 250; // ms to tell a click on the media from a double click

// Explore and the suggested-topics grid show tiles, not feed posts
function inGrid(element) {
  return (
    !!element.closest(".more-topics__container") ||
    document.body.classList.contains("ig-explore")
  );
}

export default class Item extends Component {
  @service currentUser;
  @service modal;
  @service bookmarkApi;

  @tracked liked = !!this.args.outletArgs.topic.op_liked;
  @tracked likeCount =
    this.args.outletArgs.topic.op_like_count ??
    this.args.outletArgs.topic.like_count ??
    0;
  // undefined when the topic list does not carry it: then ask the post
  @tracked canLike = this.args.outletArgs.topic.op_can_like;
  @tracked postId = this.args.outletArgs.topic.first_post_id || null;
  @tracked bookmarkId = null;
  @tracked isTogglingLike = false;
  @tracked heartPop = false;
  @tracked gallery = null;
  @tracked slideIndex = 0;
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
    return this.likeCount;
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
    if (this.currentUser && !this.canToggleLike) {
      // Discourse does not let you like your own post (Instagram does)
      return this.text(this.isOwnPost ? "cannot_like_own" : "cannot_like");
    }
    return this.text(this.liked ? "unlike" : "like");
  }

  get isOwnPost() {
    const op = this.topic.posters?.[0]?.user_id ?? this.topic.user_id;
    return !!this.currentUser && op === this.currentUser.id;
  }

  get likeUnavailable() {
    return !!this.currentUser && !this.canToggleLike;
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
    return this.canLike ?? true;
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

    const newWindow = wantsNewWindow(event);
    const go = () => {
      if (newWindow) {
        window.open(this.topic.lastUnreadUrl, "_blank");
      } else {
        this.args.outletArgs.navigateToTopic(
          this.topic,
          this.topic.lastUnreadUrl
        );
      }
    };

    // on the feed's media a second click within CLICK_DELAY is a like, not
    // a visit (grid tiles open at once)
    if (
      event.target.closest(".ig-post__media") &&
      !newWindow &&
      !inGrid(event.target)
    ) {
      clearTimeout(this.clickTimer);
      if (event.detail > 1) {
        return;
      }
      this.clickTimer = setTimeout(go, CLICK_DELAY);
      return;
    }
    go();
  }

  willDestroy() {
    super.willDestroy(...arguments);
    clearTimeout(this.clickTimer);
    clearTimeout(this.heartTimer);
  }

  // ---- first post: id, like / bookmark state, images ----
  async firstPost() {
    const post = await loadFirstPost(this.topic.id);
    this.postId ||= post?.id || null;
    this.bookmarkId ||= post?.bookmark_id || null;
    if (this.currentUser && this.canLike === undefined) {
      this.syncLike(post?.actions_summary);
    }
    return post;
  }

  syncLike(actionsSummary) {
    const like = (actionsSummary || []).find((a) => a.id === LIKE);
    if (!like) {
      return;
    }
    this.liked = !!like.acted;
    if (typeof like.count === "number") {
      this.likeCount = like.count;
    }
    this.canLike = like.acted ? !!like.can_undo : !!like.can_act;
  }

  async resolvePostId() {
    if (!this.postId) {
      await this.firstPost();
    }
    return this.postId;
  }

  // ---- gallery ----
  watchGallery = modifier((element) => {
    // grid tiles (Explore, suggested topics) show only the first image, so
    // they never load the post: a screenful of tiles stays one request
    if (
      !settings.instagram_post_gallery ||
      !this.thumbnail ||
      inGrid(element)
    ) {
      return;
    }
    return whenNearViewport(element, () => {
      // the page may have become a grid after this card rendered
      if (inGrid(element)) {
        return;
      }
      this.firstPost()
        .then((post) => {
          if (!this.isDestroying && !this.isDestroyed) {
            const images = imagesFromCooked(post?.cooked);
            this.gallery = images.length > 1 ? images : null;
          }
        })
        .catch(() => {});
    });
  });

  get hasGallery() {
    return !!this.gallery;
  }

  // the first slide keeps the list thumbnail (already loaded); the one
  // after the current slide loads eagerly, the rest lazily
  get slides() {
    const thumb = this.thumbnail;
    if (!this.gallery) {
      return [
        {
          src: thumb.url,
          srcset: null,
          width: thumb.width,
          height: thumb.height,
          loading: "lazy",
        },
      ];
    }
    return this.gallery.map((image, index) => ({
      src: index === 0 ? thumb.url : image.src,
      srcset: index === 0 ? null : image.srcset,
      width: image.width,
      height: image.height,
      loading: index <= this.slideIndex + 1 ? "eager" : "lazy",
    }));
  }

  // Instagram shows at most five dots: a window that follows the current
  // image, the end dots smaller while more images lie beyond them
  get dots() {
    const count = this.gallery?.length || 0;
    const max = 5;
    const start =
      count <= max
        ? 0
        : Math.min(Math.max(this.slideIndex - 2, 0), count - max);
    const end = Math.min(count, start + max) - 1;
    const dots = [];
    for (let index = start; index <= end; index++) {
      dots.push({
        active: index === this.slideIndex,
        small:
          (index === start && start > 0) || (index === end && end < count - 1),
      });
    }
    return dots;
  }

  get atFirstSlide() {
    return this.slideIndex === 0;
  }

  get atLastSlide() {
    return this.slideIndex >= (this.gallery?.length || 1) - 1;
  }

  get previousLabel() {
    return this.text("previous_image");
  }

  get nextLabel() {
    return this.text("next_image");
  }

  @action
  onSlidesScroll(event) {
    const track = event.currentTarget;
    const index = Math.round(track.scrollLeft / (track.clientWidth || 1));
    if (index !== this.slideIndex) {
      this.slideIndex = index;
    }
  }

  @action
  previousSlide(event) {
    this.moveSlide(event, -1);
  }

  @action
  nextSlide(event) {
    this.moveSlide(event, 1);
  }

  moveSlide(event, step) {
    event.stopPropagation();
    const track = event.currentTarget
      .closest(".ig-post__media")
      ?.querySelector(".ig-post__slides");
    track?.scrollBy({ left: step * track.clientWidth, behavior: "smooth" });
  }

  // Instagram: double-click the media to like (never unlikes)
  @action
  likeFromMedia(event) {
    clearTimeout(this.clickTimer);
    if (
      event.target.closest("button") ||
      inGrid(event.target) ||
      this.likeUnavailable
    ) {
      return;
    }
    this.heartPop = true;
    clearTimeout(this.heartTimer);
    this.heartTimer = setTimeout(() => (this.heartPop = false), 900);
    if (!this.liked) {
      this.toggleLike(event);
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
    event?.stopPropagation();

    if (this.isTogglingLike) {
      return;
    }

    // visitors: Discourse's own "log in, then the like is applied"
    if (!this.currentUser) {
      const postId = await this.resolvePostId().catch(() => null);
      if (postId) {
        await deferAnonymousAction(this, "like_post", { post_id: postId });
      } else {
        DiscourseURL.routeTo("/login");
      }
      return;
    }

    if (!this.canToggleLike) {
      return;
    }

    this.isTogglingLike = true;
    const before = {
      liked: this.liked,
      likeCount: this.likeCount,
      canLike: this.canLike,
    };

    try {
      const postId = await this.resolvePostId();
      if (!postId || !this.canToggleLike) {
        return;
      }

      // optimistic, like the post menu; the server's answer settles it
      const liking = !this.liked;
      this.liked = liking;
      this.likeCount = Math.max(0, Number(this.likeCount) + (liking ? 1 : -1));

      const result = liking
        ? await ajax("/post_actions", {
            type: "POST",
            data: { id: postId, post_action_type_id: LIKE, flag_topic: false },
          })
        : await ajax(`/post_actions/${postId}`, {
            type: "DELETE",
            data: { post_action_type_id: LIKE },
          });

      this.syncLike(result?.actions_summary);
      if (!liking && !result?.actions_summary?.some((a) => a.id === LIKE)) {
        this.canLike = true;
      }
    } catch (error) {
      Object.assign(this, before);
      popupAjaxError(error);
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
      const postId = await this.resolvePostId();

      if (this.saved) {
        const id =
          this.savedBookmarkId ??
          this.bookmarkId ??
          (await this.firstPost())?.bookmark_id;
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
          this.bookmarkApi.buildNewBookmark("Post", postId)
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
        <div
          class="ig-post__media
            {{if this.hasGallery 'ig-post__media--gallery'}}"
          style={{this.mediaStyle}}
          {{this.watchGallery}}
          {{on "dblclick" this.likeFromMedia}}
        >
          <div class="ig-post__slides" {{on "scroll" this.onSlidesScroll}}>
            {{#each this.slides as |slide|}}
              <div class="ig-post__slide">
                <img
                  alt={{this.topic.title}}
                  loading={{slide.loading}}
                  decoding="async"
                  width={{slide.width}}
                  height={{slide.height}}
                  src={{slide.src}}
                  srcset={{slide.srcset}}
                />
              </div>
            {{/each}}
          </div>
          {{#if this.hasGallery}}
            {{#unless this.atFirstSlide}}
              <button
                type="button"
                class="ig-post__nav ig-post__nav--prev"
                title={{this.previousLabel}}
                aria-label={{this.previousLabel}}
                {{on "click" this.previousSlide}}
              ></button>
            {{/unless}}
            {{#unless this.atLastSlide}}
              <button
                type="button"
                class="ig-post__nav ig-post__nav--next"
                title={{this.nextLabel}}
                aria-label={{this.nextLabel}}
                {{on "click" this.nextSlide}}
              ></button>
            {{/unless}}
            <span class="ig-post__gallery-badge" aria-hidden="true"></span>
          {{/if}}
          {{#if this.heartPop}}
            <span class="ig-post__heart-pop" aria-hidden="true"></span>
          {{/if}}
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

      {{#if this.hasGallery}}
        <div class="ig-post__dots" aria-hidden="true">
          {{#each this.dots as |dot|}}
            <span
              class="ig-post__dot-indicator
                {{if dot.active 'is-active'}}
                {{if dot.small 'is-small'}}"
            ></span>
          {{/each}}
        </div>
      {{/if}}

      <div class="ig-post__actions">
        {{#if settings.show_like_count}}
          <button
            type="button"
            class="ig-post__action ig-post__like
              {{if this.liked 'is-liked'}}
              {{if this.likeUnavailable 'is-unavailable'}}"
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
