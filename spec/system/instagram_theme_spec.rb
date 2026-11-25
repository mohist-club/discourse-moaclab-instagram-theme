# frozen_string_literal: true

# Measurement specs (performance, web vitals / SEO, Lighthouse) and the
# other system specs together need more than the CI's 10 minutes, so the
# measurements run in their own workflow (.github/workflows/
# theme-measurements.yml: weekly, or started by hand) and pushes run the rest
MEASUREMENT_RUN = %w[schedule workflow_dispatch].include?(ENV["GITHUB_EVENT_NAME"]) unless defined?(
  MEASUREMENT_RUN
)

RSpec.describe "Instagram theme", unless: MEASUREMENT_RUN do
  let!(:theme) { upload_theme }

  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category)
  fab!(:topics) do
    Fabricate.times(3, :topic, category: category).each { |topic| Fabricate(:post, topic: topic) }
  end

  before { sign_in(user) }

  def update_setting(name, value)
    theme.update_setting(name, value)
    theme.save!
  end

  describe "feed" do
    it "renders each topic as an Instagram post card" do
      visit("/latest")

      expect(page).to have_css(".topic-list-item .ig-post", count: topics.size)
      topics.each { |topic| expect(page).to have_css(".ig-post", text: topic.title) }
      expect(page).to have_css(".ig-post .ig-post__like")
    end

    it "keeps Discourse's own topic rows when card_feed is off" do
      update_setting(:card_feed, false)

      visit("/latest")

      expect(page).to have_css(".topic-list-item .main-link", count: topics.size)
      expect(page).to have_no_css(".ig-post")
    end
  end

  describe "desktop shell" do
    it "adds the left rail and the shell class" do
      visit("/latest")

      expect(page).to have_css("#ig-rail")
      expect(page).to have_css("body.ig-desktop-shell")
    end

    it "leaves the native sidebar when instagram_desktop_shell is off" do
      update_setting(:instagram_desktop_shell, false)

      visit("/latest")

      expect(page).to have_css(".sidebar-wrapper")
      expect(page).to have_no_css("#ig-rail")
      expect(page).to have_no_css("body.ig-desktop-shell")
    end
  end

  describe "studios page" do
    fab!(:parent) { Fabricate(:category, name: "Keyboards") }
    fab!(:studios) { Fabricate.times(4, :category, parent_category: parent) }

    let(:studios_path) { "#{parent.url}/subcategories" }

    before { update_setting(:instagram_suggested_categories, parent.id.to_s) }

    it "puts 工作室 in the rail in place of Search" do
      visit("/latest")

      expect(page).to have_css(
        "#ig-rail a.ig-rail-link[data-key='studios'][href='#{studios_path}']",
      )
      expect(page).to have_no_css("#ig-rail a.ig-rail-link[data-key='search']")
    end

    it "shows every studio as a card on the parent's subcategories page" do
      visit(studios_path)

      expect(page).to have_css("body.ig-studios-page")
      expect(page).to have_css(".ig-sp-card", count: studios.size)
      studios.each { |studio| expect(page).to have_css(".ig-sp-card", text: studio.name) }
      expect(page).to have_css("#ig-rail a.ig-rail-link.active[data-key='studios']")
    end

    it "leaves /categories as Discourse's own page" do
      visit("/categories")

      expect(page).to have_css(".category-list, .category-boxes, .categories-list")
      expect(page).to have_no_css(".ig-sp")
      expect(page).to have_no_css("body.ig-studios-page")
    end

    it "keeps Search and the native page when instagram_studios_page is off" do
      update_setting(:instagram_studios_page, false)

      visit(studios_path)

      expect(page).to have_css("#ig-rail a.ig-rail-link[data-key='search']")
      expect(page).to have_no_css("#ig-rail a.ig-rail-link[data-key='studios']")
      expect(page).to have_no_css(".ig-sp")
    end
  end

  describe "home stories tray" do
    fab!(:parent) { Fabricate(:category, name: "Keyboards") }
    fab!(:studios) { Fabricate.times(12, :category, parent_category: parent) }
    fab!(:studio_topics) do
      studios
        .first(3)
        .each_with_index
        .map do |studio, i|
          Fabricate(:topic, category: studio, bumped_at: (i + 1).days.ago).tap do |topic|
            Fabricate(:post, topic: topic)
          end
        end
    end

    before do
      update_setting(:instagram_suggested_categories, parent.id.to_s)
      # topic counts and featured topics are kept by background jobs
      Category.update_stats
      CategoryFeaturedTopic.feature_topics
    end

    it "shows the studios updated most recently, topped up to seven, each opening its page" do
      visit("/")

      expect(page).to have_css(".ig-stories a.ig-story--studio", count: 7)
      first_ring = find(".ig-stories a.ig-story--studio", match: :first)
      expect(first_ring[:href]).to end_with(studios.first.url)
      studios
        .first(3)
        .each { |studio| expect(page).to have_css(".ig-stories a.ig-story[href$='#{studio.url}']") }
    end
  end

  describe "home stories tray without studios" do
    fab!(:parent) { Fabricate(:category, name: "Keyboards") }

    before { update_setting(:instagram_suggested_categories, parent.id.to_s) }

    it "leaves the tray out and asks for the studios once" do
      visit("/")

      expect(page).to have_css(".topic-list-item .ig-post", count: topics.size)
      expect(page).to have_no_css(".ig-stories")
      # a dropped tray used to be built again at once, fetching again forever
      sleep 1
      requests = page.evaluate_script(<<~JS)
          performance
            .getEntriesByType("resource")
            .filter((entry) => entry.name.includes("/categories.json"))
            .length
        JS
      expect(requests).to eq(1)
      expect(page).to have_no_css(".ig-stories")
    end
  end

  describe "right column" do
    it "suggests people, each linking to their profile" do
      visit("/latest")

      expect(page).to have_css(".ig-right__sugg a.ig-right__user[href^='/u/']")
      expect(page).to have_no_css(".ig-right__sugg .ig-right__follow")
    end
  end
end
