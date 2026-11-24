# frozen_string_literal: true

# Measurement specs (performance, web vitals / SEO, Lighthouse) and the
# other system specs together need more than the CI's 10 minutes, so the
# measurements run in their own workflow (.github/workflows/
# theme-measurements.yml: weekly, or started by hand) and pushes run the rest
MEASUREMENT_RUN = %w[schedule workflow_dispatch].include?(ENV["GITHUB_EVENT_NAME"]) unless defined?(
  MEASUREMENT_RUN
)

# Phones (390px, touch): no page may pan sideways, and posts and their
# images run edge to edge. Each page also prints a report and a small
# screenshot to the CI log (IGREPORT / IGSHOT lines) for visual review.
RSpec.describe "Instagram theme on phones", mobile: true, unless: MEASUREMENT_RUN do
  # once per file: a stable theme id lets Discourse reuse its compiled CSS
  fab!(:theme) { upload_theme(set_theme_as_default: false) }

  fab!(:user) { Fabricate(:user, username: "phoneuser", trust_level: TrustLevel[1]) }
  fab!(:friend) { Fabricate(:user, username: "keyboard_friend_99", trust_level: TrustLevel[2]) }
  fab!(:parent) { Fabricate(:category, name: "Keyboards") }
  fab!(:studio) { Fabricate(:category, name: "Koi Lab Studio", parent_category: parent) }
  fab!(:upload) { Fabricate(:image_upload, width: 1080, height: 1350) }
  fab!(:topics) do
    Array.new(3) do |i|
      topic =
        Fabricate(
          :topic,
          category: studio,
          user: friend,
          title: "A keyboard build log with a fairly long title number #{i + 1}",
        )
      Fabricate(
        :post,
        topic: topic,
        user: friend,
        raw: "Build log\n\n![photo|690x862](#{upload.short_url})",
        cooked:
          "<p>Build log with a longwordthatdoesnotbreakanywhereatallinthisparagraph</p>" +
            %(<p><div class="lightbox-wrapper"><a class="lightbox" href="#{upload.url}">) +
            %(<img src="#{upload.url}" width="690" height="862" alt="photo"></a></div></p>),
      )
      topic.update!(image_upload_id: upload.id)
      topic
    end
  end
  fab!(:reply) { Fabricate(:post, topic: topics.first, user: user, raw: "Nice build, thanks!") }
  fab!(:pm) { Fabricate(:private_message_post, user: friend, recipient: user).topic }

  before do
    # site settings are reset for every example: make it the default here
    theme.set_default!
    theme.update_setting(:instagram_explore_category, parent.id.to_s)
    theme.update_setting(:instagram_suggested_categories, parent.id.to_s)
    theme.save!
  end

  let(:measure_js) { <<~JS }
    (() => {
      const vw = window.innerWidth;
      const describe = (el) => {
        let s = el.tagName.toLowerCase();
        if (el.id) s += "#" + el.id;
        const cls = (typeof el.className === "string" ? el.className : "").trim();
        if (cls) s += "." + cls.split(/\\s+/).slice(0, 4).join(".");
        return s;
      };
      const path = (el) => {
        const parts = [];
        for (let n = el; n && n !== document.body && parts.length < 5; n = n.parentElement) {
          parts.unshift(describe(n));
        }
        return parts.join(" > ");
      };
      const clipped = (el) => {
        for (let n = el.parentElement; n && n !== document.body; n = n.parentElement) {
          const cs = getComputedStyle(n);
          if (/(hidden|auto|scroll|clip)/.test(cs.overflowX)) return true;
          if (cs.position === "fixed") return false;
        }
        return false;
      };
      const offenders = [];
      for (const el of document.body.querySelectorAll("*")) {
        const cs = getComputedStyle(el);
        if (cs.display === "none" || cs.visibility === "hidden") continue;
        const r = el.getBoundingClientRect();
        if (r.width <= 1 || r.height <= 1) continue;
        if (r.right <= vw + 0.5 && r.left >= -0.5) continue;
        if (clipped(el)) continue;
        const parent = el.parentElement;
        if (parent && offenders.some((o) => o.el === parent)) continue;
        offenders.push({ el, path: path(el), left: Math.round(r.left), right: Math.round(r.right),
          width: Math.round(r.width), cssWidth: cs.width, margin: cs.margin, position: cs.position });
      }
      const rect = (sel) => {
        const el = document.querySelector(sel);
        if (!el) return null;
        const r = el.getBoundingClientRect();
        return { left: Math.round(r.left), width: Math.round(r.width), top: Math.round(r.top), height: Math.round(r.height) };
      };
      return JSON.stringify({
        url: location.pathname,
        bodyClass: document.body.className,
        vw,
        scrollWidth: document.documentElement.scrollWidth,
        bodyScrollWidth: document.body.scrollWidth,
        offenders: offenders.slice(0, 25).map(({ el, ...o }) => o),
        media: rect(".ig-post__media"),
        mediaImg: rect(".ig-post__media img"),
        cookedImg: rect(".topic-post .cooked img:not(.avatar):not(.emoji)"),
        header: rect(".d-header"),
        headerItems: [...document.querySelectorAll(".d-header .contents > *, .d-header-icons > li")]
          .filter((el) => getComputedStyle(el).display !== "none")
          .map((el) => describe(el) + " " + Math.round(el.getBoundingClientRect().left) + "+" + Math.round(el.getBoundingClientRect().width)),
        cookedChain: (() => {
          const out = [];
          let n = document.querySelector(".topic-post .cooked img:not(.avatar):not(.emoji)");
          for (let i = 0; n && i < 7; i++, n = n.parentElement) {
            const r = n.getBoundingClientRect();
            const cs = getComputedStyle(n);
            out.push(describe(n) + " " + Math.round(r.left) + "+" + Math.round(r.width) + " d=" + cs.display + " w=" + cs.width + " mw=" + cs.maxWidth + " m=" + cs.margin + " p=" + cs.padding);
          }
          return out;
        })(),
      });
    })()
  JS

  def report(name)
    sleep 1.5
    json = page.evaluate_script(measure_js)
    shot = nil
    page.driver.with_playwright_page do |pw|
      shot = pw.screenshot(type: "jpeg", quality: 55, scale: "css", fullPage: false)
    end
    puts "IGREPORT #{name} #{json}"
    puts "IGSHOT #{name} #{Base64.strict_encode64(shot)}"
    JSON.parse(json)
  end

  def expect_no_sideways_scroll(data)
    expect(data["scrollWidth"]).to eq(data["vw"]),
    -> { "page is #{data["scrollWidth"]}px wide: #{data["offenders"].to_json}" }
    expect(data["offenders"]).to eq([])
  end

  def expect_full_width(rect, data)
    expect(rect).to be_present
    expect([rect["left"], rect["width"]]).to eq([0, data["vw"]])
  end

  signed_in_pages = {
    "home" => ->(_) { "/" },
    "latest" => ->(_) { "/latest" },
    "topic" => ->(ctx) { ctx.topics.first.relative_url },
    "explore" => ->(ctx) { ctx.parent.url },
    "studio" => ->(ctx) { ctx.studio.url },
    "categories" => ->(_) { "/categories" },
    "profile" => ->(ctx) { "/u/#{ctx.user.username}/summary" },
    "messages" => ->(ctx) { "/u/#{ctx.user.username}/messages" },
    "pm" => ->(ctx) { ctx.pm.relative_url },
    "notifications" => ->(ctx) { "/u/#{ctx.user.username}/notifications" },
    "search" => ->(_) { "/search?q=keyboard" },
    "preferences" => ->(ctx) { "/u/#{ctx.user.username}/preferences/account" },
  }

  signed_in_pages.each do |name, url|
    it "fits the screen: #{name}" do
      sign_in(user)
      visit(url.call(self))
      data = report(name)

      expect_no_sideways_scroll(data)
      expect_full_width(data["media"], data) if %w[home latest].include?(name)
      expect_full_width(data["cookedImg"], data) if name == "topic"
      expect(data["media"]["width"]).to be < data["vw"] / 2 if name == "explore"
    end
  end

  { "anon-home" => "/", "anon-topic" => nil, "login" => "/login" }.each do |name, path|
    it "fits the screen signed out: #{name}" do
      visit(path || topics.first.relative_url)
      data = report(name)

      expect_no_sideways_scroll(data)
    end
  end
end
