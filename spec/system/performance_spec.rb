# frozen_string_literal: true

# Measures what the theme costs a browser, against Discourse's default theme
# on the same pages and data: requests, script / style / layout time, long
# tasks and MutationObserver callbacks (attributed to the file that created
# the observer). Prints one IGPERF line per run to the CI log.
RSpec.describe "Instagram theme performance" do
  let!(:theme) { upload_theme(set_theme_as_default: false) }

  fab!(:user) { Fabricate(:user, username: "perfuser", trust_level: TrustLevel[1]) }
  fab!(:posters) do
    Array.new(12) { |i| Fabricate(:user, username: "poster#{i}", trust_level: TrustLevel[2]) }
  end
  fab!(:parent) { Fabricate(:category, name: "Keyboards") }
  fab!(:studios) do
    Array.new(4) { |i| Fabricate(:category, name: "Studio #{i}", parent_category: parent) }
  end
  fab!(:upload) { Fabricate(:image_upload, width: 1080, height: 1350) }
  fab!(:topics) do
    Array.new(45) do |i|
      poster = posters[i % posters.size]
      topic =
        Fabricate(
          :topic,
          category: studios[i % studios.size],
          user: poster,
          title: "Keyboard build log number #{i + 1} with photos",
        )
      img = %(<img src="#{upload.url}" width="690" height="862" alt="photo">)
      Fabricate(
        :post,
        topic: topic,
        user: poster,
        raw: "Build log #{i}\n\n![photo|690x862](#{upload.short_url})",
        cooked: %(<p>Build log #{i}</p><p>#{img}</p><p>#{img}</p>),
      )
      Fabricate(:post, topic: topic, user: posters[(i + 1) % posters.size], raw: "Nice one #{i}")
      topic.update!(image_upload_id: upload.id)
      topic
    end
  end

  let(:init_js) { <<~JS }
    (() => {
      if (window.__igPerf) return;
      const perf = (window.__igPerf = { mo: {}, longTasks: [], start: performance.now() });
      const where = () => {
        const lines = (new Error().stack || "").split("\\n").slice(2);
        const line = lines.find((l) => !/__igPerf|at new|MutationObserver/.test(l)) || lines[0] || "";
        const m = line.match(/\\/([^/]+\\.js)(?:\\?[^:]*)?:(\\d+)/);
        return m ? m[1].replace(/-[0-9a-f]{8,}/, "") + ":" + m[2] : line.trim().slice(0, 80);
      };
      const Native = window.MutationObserver;
      window.MutationObserver = class extends Native {
        constructor(cb) {
          const key = where();
          const s = (perf.mo[key] ||= { observers: 0, calls: 0, ms: 0, records: 0 });
          s.observers++;
          super((records, obs) => {
            const t = performance.now();
            try { return cb(records, obs); }
            finally { s.calls++; s.records += records.length; s.ms += performance.now() - t; }
          });
        }
      };
      try {
        new PerformanceObserver((list) => {
          for (const e of list.getEntries()) perf.longTasks.push(Math.round(e.duration));
        }).observe({ type: "longtask", buffered: true });
      } catch (e) {}
    })();
  JS

  let(:collect_js) { <<~JS }
    (() => {
      const perf = window.__igPerf || { mo: {}, longTasks: [] };
      const res = performance.getEntriesByType("resource");
      const api = {};
      for (const r of res) {
        if (!["fetch", "xmlhttprequest"].includes(r.initiatorType)) continue;
        const u = new URL(r.name, location.href);
        const key = u.pathname.replace(/\\/\\d+(?=\\/|\\.json|$)/g, "/:id") + (u.search ? "?" + [...u.searchParams.keys()].join("&") : "");
        api[key] = (api[key] || 0) + 1;
      }
      const css = res.filter((r) => /stylesheets\\//.test(r.name)).map((r) => ({
        name: r.name.split("/").pop().split("?")[0].replace(/_[0-9a-f]{16,}/, ""),
        kb: Math.round((r.decodedBodySize || 0) / 1024),
      }));
      const imgs = res.filter((r) => r.initiatorType === "img").length;
      const nav = performance.getEntriesByType("navigation")[0];
      const mo = Object.entries(perf.mo)
        .map(([k, v]) => ({ k, ...v, ms: Math.round(v.ms * 10) / 10 }))
        .sort((a, b) => b.ms - a.ms)
        .slice(0, 8);
      return JSON.stringify({
        api, apiCount: Object.values(api).reduce((a, b) => a + b, 0), imgs, css, mo,
        longTasks: perf.longTasks, longTaskMs: perf.longTasks.reduce((a, b) => a + b, 0),
        domNodes: document.getElementsByTagName("*").length,
        dcl: nav ? Math.round(nav.domContentLoadedEventEnd) : null,
        cards: document.querySelectorAll(".topic-list-item").length,
      });
    })()
  JS

  def cdp_metrics(cdp)
    cdp.send_message("Performance.getMetrics")["metrics"]
      .to_h { |m| [m["name"], m["value"]] }
      .slice(
        "ScriptDuration",
        "RecalcStyleCount",
        "RecalcStyleDuration",
        "LayoutCount",
        "LayoutDuration",
        "TaskDuration",
        "JSHeapUsedSize",
        "Nodes",
      )
  end

  def measure(label, path, scroll: false)
    result = nil
    page.driver.with_playwright_page do |pw|
      pw.add_init_script(script: init_js)
      cdp = pw.context.new_cdp_session(pw)
      cdp.send_message("Performance.enable")
      visit(path)
      sleep 4
      loaded = cdp_metrics(cdp)
      data = JSON.parse(page.evaluate_script(collect_js))
      data["load"] = loaded
      if scroll
        before = cdp_metrics(cdp)
        long_before = data["longTasks"].size
        15.times do
          page.execute_script("window.scrollBy(0, 700)")
          sleep 0.35
        end
        sleep 3
        after = cdp_metrics(cdp)
        scrolled = JSON.parse(page.evaluate_script(collect_js))
        data["scroll"] = after.to_h { |k, v| [k, (v - before[k]).round(4)] }
        data["scrollLongTasks"] = scrolled["longTasks"].drop(long_before)
        data["scrollApi"] = scrolled["api"]
        data["scrollMo"] = scrolled["mo"]
        data["cardsAfterScroll"] = scrolled["cards"]
      end
      result = data
    end
    puts "IGPERF #{label} #{result.to_json}"
    result
  end

  # base: Discourse's default theme; theme: this one as the site default
  def use_theme(on)
    theme.set_default! if on
  end

  before do
    theme.update_setting(:instagram_explore_category, parent.id.to_s)
    theme.update_setting(:instagram_suggested_categories, parent.id.to_s)
    theme.save!
  end

  pages = {
    "home" => ->(_) { "/" },
    "topic" => ->(ctx) { ctx.topics.first.relative_url },
    "explore" => ->(ctx) { ctx.parent.url },
    "categories" => ->(_) { "/categories" },
    "profile" => ->(ctx) { "/u/#{ctx.posters.first.username}/summary" },
  }

  [false, true].each do |mobile|
    context(mobile ? "on a phone" : "on desktop", mobile: mobile) do
      [false, true].each do |on|
        label = "#{mobile ? "mobile" : "desktop"}-#{on ? "theme" : "base"}"

        pages.each do |name, path|
          it "measures #{name} (#{label})" do
            use_theme(on)
            sign_in(user)
            measure("#{label}-#{name}", path.call(self))
          end
        end

        it "measures scrolling the home feed (#{label})" do
          use_theme(on)
          sign_in(user)
          measure("#{label}-scroll", "/", scroll: true)
        end
      end
    end
  end
end
