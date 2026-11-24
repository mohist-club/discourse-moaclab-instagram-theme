# frozen_string_literal: true

# Measurement specs (performance, web vitals / SEO, Lighthouse) and the
# other system specs together need more than the CI's 10 minutes, so the
# measurements run in their own workflow (.github/workflows/
# theme-measurements.yml: weekly, or started by hand) and pushes run the rest
MEASUREMENT_RUN = %w[schedule workflow_dispatch].include?(ENV["GITHUB_EVENT_NAME"]) unless defined?(
  MEASUREMENT_RUN
)

# Google's lab checks, measured against Discourse's default theme on the same
# pages and data, signed out (as a search engine or a new visitor sees them):
#   - Core Web Vitals and Lighthouse's other lab metrics: LCP (and its
#     element), CLS (and what shifted), FCP, TBT, TTFB. Phones run with
#     Lighthouse's mobile CPU slowdown (4x); the network is not throttled.
#   - Lighthouse diagnostics the theme can affect: image sizing, lazy /
#     eager images, missing width and height, non-composited animations,
#     DOM size.
#   - Lighthouse's SEO audits: title, meta description, viewport, lang,
#     canonical, robots, h1, crawlable links, link text, image alt, legible
#     font sizes, tap targets — plus the crawler view Googlebot is served.
# Prints one IGVITALS / IGCRAWL line per run to the CI log.
RSpec.describe "Instagram theme web vitals and SEO", if: !ENV["CI"] || MEASUREMENT_RUN do
  # once per file: a stable theme id lets Discourse reuse its compiled CSS
  # (CI gives all system tests 10 minutes)
  fab!(:theme) { upload_theme(set_theme_as_default: false) }

  fab!(:posters) do
    Array.new(8) { |i| Fabricate(:user, username: "writer#{i}", trust_level: TrustLevel[2]) }
  end
  fab!(:parent) { Fabricate(:category, name: "Keyboards", description: "Keyboard builds") }
  fab!(:studios) do
    Array.new(3) { |i| Fabricate(:category, name: "Studio #{i}", parent_category: parent) }
  end
  fab!(:upload) { Fabricate(:image_upload, width: 1600, height: 2000) }
  fab!(:topics) do
    Array.new(32) do |i|
      poster = posters[i % posters.size]
      topic =
        Fabricate(
          :topic,
          category: studios[i % studios.size],
          user: poster,
          title: "Keyboard build log number #{i + 1} with photos",
        )
      img = %(<img src="#{upload.url}" width="690" height="862" alt="build photo">)
      Fabricate(
        :post,
        topic: topic,
        user: poster,
        raw: "Build log #{i}\n\n![build photo|690x862](#{upload.short_url})",
        cooked: %(<p>Build log #{i} with a few words about the switches.</p><p>#{img}</p>),
      )
      Fabricate(:post, topic: topic, user: posters[(i + 1) % posters.size], raw: "Nice one #{i}")
      topic.update!(image_upload_id: upload.id)
      topic
    end
  end

  before do
    theme.update_setting(:instagram_explore_category, parent.id.to_s)
    theme.update_setting(:instagram_suggested_categories, parent.id.to_s)
    theme.save!
  end

  let(:init_js) { <<~JS }
    (() => {
      if (window.__igVitals) return;
      const v = (window.__igVitals = { lcp: null, lcpEl: null, lcpUrl: null, cls: 0, shifts: [], fcp: null, longTasks: [] });
      const describe = (el) => {
        if (!el || !el.tagName) return String(el && el.nodeName);
        let s = el.tagName.toLowerCase();
        if (el.id) s += "#" + el.id;
        const cls = typeof el.className === "string" ? el.className.trim() : "";
        if (cls) s += "." + cls.split(/\\s+/).slice(0, 3).join(".");
        const p = el.parentElement;
        return p ? describe1(p) + " > " + s : s;
      };
      const describe1 = (el) => {
        let s = el.tagName.toLowerCase();
        const cls = typeof el.className === "string" ? el.className.trim() : "";
        if (cls) s += "." + cls.split(/\\s+/).slice(0, 2).join(".");
        return s;
      };
      v.describe = describe;
      const obs = (type, fn) => {
        try { new PerformanceObserver((l) => l.getEntries().forEach(fn)).observe({ type, buffered: true }); } catch (e) {}
      };
      obs("largest-contentful-paint", (e) => {
        v.lcp = e.startTime; v.lcpEl = describe(e.element); v.lcpUrl = (e.url || "").split("/").pop().slice(0, 60);
        v.lcpLazy = e.element?.loading === "lazy";
      });
      obs("layout-shift", (e) => {
        if (e.hadRecentInput) return;
        v.cls += e.value;
        if (e.value > 0.001) v.shifts.push({ t: Math.round(e.startTime), value: Math.round(e.value * 1000) / 1000, nodes: (e.sources || []).map((s) => describe(s.node)).slice(0, 3) });
      });
      obs("paint", (e) => { if (e.name === "first-contentful-paint") v.fcp = e.startTime; });
      obs("longtask", (e) => v.longTasks.push({ start: e.startTime, d: e.duration }));
    })();
  JS

  let(:audit_js) { <<~JS }
    (() => {
      const v = window.__igVitals || {};
      const vw = innerWidth, vh = innerHeight, dpr = devicePixelRatio || 1;
      const nav = performance.getEntriesByType("navigation")[0] || {};
      const fcp = v.fcp || 0;
      const tbt = (v.longTasks || []).filter((t) => t.start + t.d > fcp)
        .reduce((a, t) => a + Math.max(0, t.d - 50), 0);
      const describe = v.describe || ((e) => e.tagName);
      const visible = (el) => {
        const r = el.getBoundingClientRect();
        if (!r.width || !r.height) return null;
        const cs = getComputedStyle(el);
        if (cs.visibility === "hidden" || cs.display === "none" || +cs.opacity === 0) return null;
        return r;
      };
      const res = new Map(performance.getEntriesByType("resource").map((r) => [r.name, r]));

      // ---- images ----
      const imgs = { total: 0, oversized: [], noAlt: [], noSize: [], eagerOffscreen: 0, lazyInView: [], bytes: 0 };
      for (const img of document.images) {
        const r = visible(img);
        if (!r) continue;
        imgs.total++;
        const entry = res.get(img.currentSrc);
        const kb = entry ? Math.round((entry.decodedBodySize || entry.encodedBodySize || 0) / 1024) : 0;
        imgs.bytes += kb;
        const need = r.width * dpr;
        if (img.naturalWidth > need * 1.5 && img.naturalWidth - need > 200) {
          imgs.oversized.push(describe(img) + " " + img.naturalWidth + "px for " + Math.round(need) + "px (" + kb + "KB)");
        }
        if (!img.hasAttribute("alt")) imgs.noAlt.push(describe(img));
        if (!img.getAttribute("width") || !img.getAttribute("height")) imgs.noSize.push(describe(img));
        const inView = r.top < vh && r.bottom > 0;
        if (inView && img.loading === "lazy") imgs.lazyInView.push(describe(img));
        if (!inView && r.top > vh * 2 && img.loading !== "lazy") imgs.eagerOffscreen++;
      }
      imgs.oversized = imgs.oversized.slice(0, 6); imgs.noAlt = imgs.noAlt.slice(0, 6);
      imgs.noSize = [imgs.noSize.length, ...imgs.noSize.slice(0, 4)]; imgs.lazyInView = imgs.lazyInView.slice(0, 4);

      // ---- animations that the compositor can't run ----
      const anims = [];
      for (const a of document.getAnimations()) {
        if (a.playState !== "running") continue;
        const props = new Set();
        for (const k of a.effect?.getKeyframes?.() || []) Object.keys(k).forEach((p) => props.add(p));
        ["offset", "easing", "composite", "computedOffset"].forEach((p) => props.delete(p));
        const bad = [...props].filter((p) => !["transform", "opacity", "translate", "rotate", "scale"].includes(p));
        if (bad.length) anims.push((a.animationName || a.id || "anim") + ": " + bad.join(",") + " on " + describe(a.effect?.target));
      }

      // ---- SEO ----
      // (textContent: innerText is empty for cards whose rendering
      // content-visibility skips while they are off screen)
      const meta = (n) => document.querySelector(`meta[name="${n}"]`)?.getAttribute("content") || null;
      const links = [...document.querySelectorAll("a")].filter((a) => visible(a));
      const generic = /^(more|read more|click here|here|link|learn more|更多|查看更多|点击这里|这里|详情)$/i;
      const linkText = (a) => (a.textContent || a.getAttribute("aria-label") || a.getAttribute("title") || [...a.querySelectorAll("img")].map((i) => i.alt).join(" ")).trim();
      const uncrawlable = links.filter((a) => {
        const h = a.getAttribute("href");
        return !h || h === "#" || /^javascript:/i.test(h);
      }).filter((a) => a.getAttribute("role") !== "button");
      const emptyText = links.filter((a) => !linkText(a));
      const genericText = links.filter((a) => generic.test(linkText(a)));

      // text legibility: share of visible text characters under 12px
      let chars = 0, small = 0; const smallSamples = new Map();
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        const t = n.nodeValue.trim();
        if (!t || !n.parentElement) continue;
        const el = n.parentElement;
        if (!visible(el)) continue;
        const size = parseFloat(getComputedStyle(el).fontSize);
        chars += t.length;
        if (size < 12) { small += t.length; const k = describe(el) + " " + size + "px"; smallSamples.set(k, (smallSamples.get(k) || 0) + t.length); }
      }

      // tap targets (phones): visible controls smaller than 24px / 48px
      const controls = [...document.querySelectorAll("a, button, input, select, textarea, [role=button], [tabindex]:not([tabindex='-1'])")]
        .map((el) => [el, visible(el)]).filter(([, r]) => r && r.top < vh * 3);
      const tiny = controls.filter(([el, r]) => (r.width < 24 || r.height < 24) && !(el.tagName === "A" && el.closest("p, li.cooked, .cooked")));
      const under48 = controls.filter(([, r]) => r.width < 48 || r.height < 48);

      let depth = 0;
      const walk = (el, d) => { depth = Math.max(depth, d); for (const c of el.children) walk(c, d + 1); };
      walk(document.body, 1);

      return JSON.stringify({
        url: location.pathname,
        vitals: {
          lcp: v.lcp && Math.round(v.lcp), lcpEl: v.lcpEl, lcpUrl: v.lcpUrl, lcpLazy: !!v.lcpLazy,
          cls: Math.round((v.cls || 0) * 1000) / 1000, shifts: (v.shifts || []).slice(0, 6),
          fcp: v.fcp && Math.round(v.fcp), tbt: Math.round(tbt), ttfb: Math.round(nav.responseStart || 0),
          load: Math.round(nav.loadEventEnd || 0),
        },
        images: imgs,
        animations: anims.slice(0, 8),
        dom: { nodes: document.getElementsByTagName("*").length, depth },
        seo: {
          title: document.title, description: meta("description"), viewport: meta("viewport"), robots: meta("robots"),
          lang: document.documentElement.lang, canonical: document.querySelector("link[rel=canonical]")?.href || null,
          h1: [...document.querySelectorAll("h1")].filter((h) => visible(h)).map((h) => h.innerText.trim().slice(0, 60)),
          links: links.length, uncrawlable: uncrawlable.slice(0, 6).map(describe), uncrawlableCount: uncrawlable.length,
          emptyLinkText: emptyText.slice(0, 6).map(describe), emptyLinkTextCount: emptyText.length,
          genericLinkText: genericText.slice(0, 6).map((a) => describe(a) + " '" + linkText(a) + "'"),
          smallTextPct: chars ? Math.round((small / chars) * 1000) / 10 : 0,
          smallText: [...smallSamples.entries()].sort((a, b) => b[1] - a[1]).slice(0, 6).map(([k, n]) => k + " x" + n),
          tinyTargets: tiny.length, tinySamples: tiny.slice(0, 8).map(([el, r]) => describe(el) + " " + Math.round(r.width) + "x" + Math.round(r.height)),
          under48: under48.length, controls: controls.length,
        },
      });
    })()
  JS

  # The first request after a theme change compiles its CSS (longer with
  # parallel test processes). Done over plain HTTP with its own time limits
  # before the browser loads the page: a browser visit cut off by the CI's
  # 45s example timeout leaves the test process hanging, and compiling is
  # not what a visitor waits for
  def warm_up(path, mobile:)
    base = Capybara.current_session.server.base_url
    uri = URI.join(base, path)
    agent = mobile ? "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) Mobile" : "Mozilla/5.0"
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 15) do |http|
      html = http.get(uri.request_uri, "User-Agent" => agent).body
      Nokogiri
        .HTML5(html)
        .css('link[rel="stylesheet"]')
        .each do |link|
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > 14
          http.get(URI.join(base, link["href"]).request_uri, "User-Agent" => agent)
        end
    end
  rescue StandardError => e
    puts "IGVITALS warm-up #{path}: #{e.class} #{e.message}"
  end

  def audit(label, path, mobile:)
    data = nil
    warm_up(path, mobile:)
    page.driver.with_playwright_page do |pw|
      pw.add_init_script(script: init_js)
      cdp = pw.context.new_cdp_session(pw)
      cdp.send_message("Emulation.setCPUThrottlingRate", params: { rate: mobile ? 4 : 1 })
      begin
        visit(path)
        sleep(mobile ? 4 : 2.5)
        data = JSON.parse(page.evaluate_script(audit_js))
      ensure
        cdp.send_message("Emulation.setCPUThrottlingRate", params: { rate: 1 })
      end
    end
    puts "IGVITALS #{label} #{data.to_json}"
    data
  end

  pages = {
    "home" => ->(_) { "/" },
    "topic" => ->(ctx) { ctx.topics.first.relative_url },
    "explore" => ->(ctx) { ctx.parent.url },
    "studio" => ->(ctx) { ctx.studios.first.url },
    # (categories and profile pages: left out for time — the CI gives all
    # system tests 10 minutes; mobile_layout_spec still covers them)
  }

  [false, true].each do |mobile|
    context(mobile ? "on a phone" : "on desktop", mobile: mobile) do
      [false, true].each do |on|
        label = "#{mobile ? "mobile" : "desktop"}-#{on ? "theme" : "base"}"
        pages.each do |name, path|
          it "audits #{name} (#{label})" do
            theme.set_default! if on
            audit("#{label}-#{name}", path.call(self), mobile: mobile)
          end
        end
      end
    end
  end

  # what Googlebot is served: Discourse's server-rendered crawler view
  [false, true].each do |on|
    it "audits the crawler view (#{on ? "theme" : "base"})" do
      theme.set_default! if on
      base = Capybara.current_session.server.base_url
      pages.each do |name, path|
        uri = URI.join(base, path.call(self))
        response =
          Net::HTTP.start(uri.host, uri.port) do |http|
            http.get(
              uri.request_uri,
              "User-Agent" =>
                "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
            )
          end
        doc = Nokogiri.HTML5(response.body)
        info = {
          status: response.code.to_i,
          kb: response.body.bytesize / 1024,
          title: doc.at("title")&.text,
          description: doc.at('meta[name="description"]')&.[]("content"),
          canonical: doc.at('link[rel="canonical"]')&.[]("href"),
          robots: doc.at('meta[name="robots"]')&.[]("content"),
          xRobots: response["X-Robots-Tag"],
          lang: doc.at("html")&.[]("lang"),
          viewport: doc.at('meta[name="viewport"]')&.[]("content"),
          h1: doc.css("h1").map { |h| h.text.strip[0, 60] },
          links: doc.css("a[href]").size,
          imgsNoAlt: doc.css("img:not([alt])").size,
          jsonLd: doc.css('script[type="application/ld+json"]').size,
          itemprops: doc.css("[itemprop]").size,
          stylesheets:
            doc
              .css('link[rel="stylesheet"]')
              .map { |l| l["href"].to_s.split("/")[-1].to_s.split("?")[0] },
          themeColor: doc.css('meta[name="theme-color"]').size,
        }
        puts "IGCRAWL #{on ? "theme" : "base"}-#{name} #{info.to_json}"
      end
    end
  end
end
