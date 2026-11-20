import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import DiscourseURL from "discourse/lib/url";
import { i18n } from "discourse-i18n";
import { pageBeforeAuth } from "../lib/ig-last-page";

// Top of the Instagram-style log-in / sign-up card: the site logo (full
// logo, else the small one, else the title) and a close button. Close (or
// Esc) goes back to the page you came from, else to the home page.
// Rendered in core's login / create-account outlets; the card itself is
// CSS (scss/auth.scss) around Discourse's own form.
export default class IgAuthHead extends Component {
  @service siteSettings;

  get enabled() {
    return settings.instagram_auth_modal;
  }

  get logoUrl() {
    return (
      this.siteSettings.site_logo_url || this.siteSettings.site_logo_small_url
    );
  }

  // the dark logo, when the site has one, for dark colour schemes
  get darkLogoUrl() {
    return this.siteSettings.site_logo_dark_url;
  }

  get title() {
    return this.siteSettings.title;
  }

  get closeLabel() {
    return i18n(themePrefix("ig.auth.close"));
  }

  // Esc closes, unless a native dialog (e.g. "forgot password") is open —
  // then Esc is that dialog's
  escToClose = modifier(() => {
    const onKey = (event) => {
      if (
        event.key !== "Escape" ||
        event.defaultPrevented ||
        document.querySelector(".d-modal, .fk-d-menu, .select-kit.is-expanded")
      ) {
        return;
      }
      this.leave();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  });

  // back to the page you came from on this site, else home
  leave() {
    DiscourseURL.routeTo(pageBeforeAuth());
  }

  @action
  close(event) {
    event.preventDefault();
    this.leave();
  }

  <template>
    {{#if this.enabled}}
      <div class="ig-auth-head" {{this.escToClose}}>
        <a class="ig-auth-head__logo" href="/">
          {{#if this.logoUrl}}
            <picture>
              {{#if this.darkLogoUrl}}
                <source
                  srcset={{this.darkLogoUrl}}
                  media="(prefers-color-scheme: dark)"
                />
              {{/if}}
              <img src={{this.logoUrl}} alt={{this.title}} />
            </picture>
          {{else}}
            <span>{{this.title}}</span>
          {{/if}}
        </a>
        <a
          class="ig-auth-head__close"
          href="/"
          title={{this.closeLabel}}
          aria-label={{this.closeLabel}}
          {{on "click" this.close}}
        >
          <kbd class="ig-auth-head__esc" aria-hidden="true">Esc</kbd>
        </a>
      </div>
    {{/if}}
  </template>
}
