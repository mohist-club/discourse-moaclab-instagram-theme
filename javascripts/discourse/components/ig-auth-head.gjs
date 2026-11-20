import Component from "@glimmer/component";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";

// Top of the Instagram-style log-in / sign-up card: the site logo (full
// logo, else the small one, else the title) and a close button back to the
// home page. Rendered in core's login / create-account outlets; the card
// itself is pure CSS (scss/auth.scss) around Discourse's own form.
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

  <template>
    {{#if this.enabled}}
      <div class="ig-auth-head">
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
        ></a>
      </div>
    {{/if}}
  </template>
}
