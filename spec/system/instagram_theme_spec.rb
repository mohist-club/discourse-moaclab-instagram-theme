# frozen_string_literal: true

RSpec.describe "Instagram theme" do
  let!(:theme) { upload_theme }

  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category)
  fab!(:topics) { Fabricate.times(3, :post, category: category).map(&:topic) }

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
end
