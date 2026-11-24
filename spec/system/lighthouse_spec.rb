# frozen_string_literal: true

# Google Lighthouse (the engine behind PageSpeed Insights) against the theme,
# signed out as a search engine or a new visitor sees it: performance,
# accessibility, best practices and SEO scores, the lab metrics, and every
# audit that does not pass. Mobile runs use Lighthouse's default mobile
# settings (simulated slow 4G and 4x CPU), desktop runs its desktop preset.
# Prints one IGLH line per run to the CI log; nothing is asserted.
#
# Lighthouse is installed once per run into Discourse's tmp/ (CI only needs
# Node, which the test image has) and drives the Chromium that Playwright
# installed for the system tests.
LIGHTHOUSE_VERSION = "12.2.1"

RSpec.describe "Instagram theme in Lighthouse" do
  # once per file: a stable theme id lets Discourse reuse its compiled CSS
  fab!(:theme) { upload_theme(set_theme_as_default: false) }

  fab!(:posters) do
    Array.new(6) { |i| Fabricate(:user, username: "author#{i}", trust_level: TrustLevel[2]) }
  end
  fab!(:category) { Fabricate(:category, name: "Builds", description: "Keyboard builds") }
  fab!(:upload) { Fabricate(:image_upload, width: 1600, height: 2000) }
  fab!(:topics) do
    Array.new(20) do |i|
      poster = posters[i % posters.size]
      topic =
        Fabricate(
          :topic,
          category: category,
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
      topic.update!(image_upload_id: upload.id)
      topic
    end
  end

  def self.lighthouse_dir
    Rails.root.join("tmp", "lighthouse")
  end

  def self.lighthouse_cli
    lighthouse_dir.join("node_modules", "lighthouse", "cli", "index.js")
  end

  # outside the examples: the CI's per-example limit is 45 seconds
  # installs a tool into tmp/, no records: nothing to leak between tests
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    cli = self.class.lighthouse_cli
    next if File.exist?(cli)
    system(
      "npm",
      "install",
      "--no-audit",
      "--no-fund",
      "--loglevel=error",
      "--prefix",
      self.class.lighthouse_dir.to_s,
      "lighthouse@#{LIGHTHOUSE_VERSION}",
    )
  end

  def chrome_path
    roots = [ENV["PLAYWRIGHT_BROWSERS_PATH"], File.expand_path("~/.cache/ms-playwright")].compact
    roots.flat_map { |root| Dir.glob(File.join(root, "chromium-*", "chrome-linux*", "chrome")) }.max
  end

  def lighthouse(label, path, desktop:)
    cli = self.class.lighthouse_cli
    chrome = chrome_path
    unless File.exist?(cli) && chrome
      puts "IGLH #{label} #{{ error: "lighthouse #{File.exist?(cli)} chrome #{chrome.inspect}" }.to_json}"
      return
    end

    # once in the test browser first: the first request after a theme
    # change compiles its assets (seconds, not what a visitor waits for)
    visit(path)

    url = URI.join(Capybara.current_session.server.base_url, path).to_s
    out = Rails.root.join("tmp", "lighthouse", "#{label}.json").to_s
    args = [
      "node",
      cli.to_s,
      url,
      "--output=json",
      "--output-path=#{out}",
      "--quiet",
      "--only-categories=performance,accessibility,best-practices,seo",
      # Discourse's message bus keeps a long-poll request open, so the
      # network never goes quiet: cap the wait (the CI allows 45s a test)
      "--max-wait-for-load=12000",
      "--skip-audits=full-page-screenshot,screenshot-thumbnails,final-screenshot",
      "--chrome-flags=--headless=new --no-sandbox --disable-dev-shm-usage",
    ]
    args << "--preset=desktop" if desktop

    log = "#{out}.log"
    pid = Process.spawn({ "CHROME_PATH" => chrome }, *args, %i[out err] => [log, "w"])
    begin
      Timeout.timeout(38) { Process.wait(pid) }
    rescue Timeout::Error
      Process.kill("KILL", pid)
      Process.wait(pid)
    end
    unless $?&.success? && File.exist?(out)
      tail = File.exist?(log) ? File.readlines(log).last(8).join[-1500..] : ""
      puts "IGLH #{label} #{{ error: "lighthouse failed (#{$?.inspect})", log: tail }.to_json}"
      return
    end

    report = JSON.parse(File.read(out))
    audits = report["audits"]
    metric = ->(id) { audits.dig(id, "numericValue")&.round(3) }
    failing =
      audits
        .values
        .select do |a|
          a["score"] && a["score"] < 0.9 &&
            %w[binary numeric metricSavings].include?(a["scoreDisplayMode"])
        end
        .sort_by { |a| a["score"] }
        .first(30)
        .map do |a|
          items = a.dig("details", "items") || []
          {
            id: a["id"],
            score: a["score"],
            value: a["displayValue"],
            items:
              items
                .first(3)
                .map do |item|
                  node = item["node"] || {}
                  [node["selector"] || node["snippet"], node["explanation"]].compact
                    .join(" | ")
                    .presence || item["url"] || item.dig("source", "url") || item.to_json[0, 120]
                end
                .map { |s| s.to_s[0, 300] },
          }
        end
    summary = {
      scores: report["categories"].transform_values { |c| (c["score"].to_f * 100).round },
      metrics: {
        fcp: metric["first-contentful-paint"],
        lcp: metric["largest-contentful-paint"],
        tbt: metric["total-blocking-time"],
        cls: metric["cumulative-layout-shift"],
        si: metric["speed-index"],
        tti: metric["interactive"],
      },
      lcpElement:
        audits.dig(
          "largest-contentful-paint-element",
          "details",
          "items",
          0,
          "items",
          0,
          "node",
          "selector",
        ).to_s[
          0,
          140
        ],
      failing: failing,
      warnings: report["runWarnings"],
    }
    puts "IGLH #{label} #{summary.to_json}"
  end

  {
    "home" => ->(_) { "/" },
    "topic" => ->(ctx) { ctx.topics.first.relative_url },
  }.each do |name, path|
    it("runs Lighthouse on #{name} (mobile)") do
      theme.set_default!
      lighthouse("mobile-#{name}", path.call(self), desktop: false)
    end

    # (desktop runs left out for time: the CI gives all system tests 10
    # minutes; lighthouse(..., desktop: true) runs Lighthouse's desktop
    # preset)
    next if name != "home"

    # Discourse's default theme on the same page and data: CI serves the
    # test build (not compressed or minified), so the performance score
    # only means something next to this one
    it("runs Lighthouse on #{name} with the default theme (mobile)") do
      lighthouse("mobile-#{name}-base", path.call(self), desktop: false)
    end
  end
end
