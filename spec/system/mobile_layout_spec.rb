# frozen_string_literal: true

# Phones: no page may scroll sideways, and the theme's mobile pages are
# measured. Each page prints a report (and a small screenshot) to the log.
RSpec.describe "Instagram theme on phones", mobile: true do
  let!(:theme) { upload_theme }

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
        if (!r.width || !r.height) continue;
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
        headerHtml: (document.querySelector(".d-header")?.outerHTML || "").slice(0, 6000),
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

  it "measures the signed-in pages" do
    sign_in(user)
    {
      "latest" => "/latest",
      "topic" => topics.first.relative_url,
      "explore" => parent.url,
      "studio" => studio.url,
      "categories" => "/categories",
      "profile" => "/u/#{user.username}/summary",
      "messages" => "/u/#{user.username}/messages",
      "pm" => pm.relative_url,
      "notifications" => "/u/#{user.username}/notifications",
      "search" => "/search?q=keyboard",
      "preferences" => "/u/#{user.username}/preferences/account",
    }.each do |name, url|
      visit(url)
      report(name)
    end
  end

  it "measures the signed-out pages" do
    {
      "anon-latest" => "/latest",
      "anon-topic" => topics.first.relative_url,
      "login" => "/login",
    }.each do |name, url|
      visit(url)
      report(name)
    end
  end
end
