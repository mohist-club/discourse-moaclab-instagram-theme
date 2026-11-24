# Moaclab Instagram

Moaclab 的 Discourse **Instagram 经典黑白风格**主题：白底黑字、细灰边框、圆形头像与品牌故事环、信息流帖子卡片（大图 + 点赞/评论/分享），移动端带 Instagram 风格底部导航。内置浅色 / 深色两套配色方案。

> 与 `discourse-moaclab-redditish-theme` 同一套工程规范（Discourse Theme CLI、pnpm、ESLint/Prettier/Rubocop、CI），信息流卡片复用同一个 `topic-list-item` connector。

## 安装

在 Discourse 后台打开：

**管理 → 自定义 → 主题 → 安装 → 从 Git 仓库安装**

使用仓库地址：

```text
https://github.com/mohist-club/discourse-moaclab-instagram-theme.git
```

安装后：
1. 在主题页面把 **颜色方案** 关联到 `Instagram Light` / `Instagram Dark`。
2. 勾选 **设为默认主题** 或 **用户可选**。
3. 如需系统深浅自动切换，开启站点设置里的自动深色模式。

## 功能概览

- **信息流**：话题列表渲染为 Instagram 帖子卡片，首帖多图轮播（接近视口才加载），原生点赞 / 收藏，双击图片点赞；加载更多失败会自动重试。
- **桌面端外壳**：左侧导航竖栏（由原生侧边栏改造，含「更多」菜单和「服务」分区）、首页 Stories 横条、≥1160px 的右侧栏、右下角消息浮窗。
- **探索**：指定类别显示为 Instagram 探索网格，悬停显示标题，顶部为 Instagram 搜索（原生搜索与搜索历史）。
- **工作室主页**：键盘 / 键帽下的二级类别显示为 Instagram 主页头（封面背景图、精选、关注 = 类别通知）。
- **/categories**：类别卡片网格 + 可筛选、可排序的工作室目录。
- **登录注册**：弹窗样式（Esc 关闭），手机上为 Instagram 移动端登录页；表单与登录方式仍是原生的。
- **手机端（<768px）**：Instagram 顶栏 / 底部标签栏；帖子详情、个人主页、探索、消息列表、私信气泡（群聊显示用户名）、通知、搜索、设置、工作室和标签页按 Instagram 移动端排版。
- **管理后台**：完全保持 Discourse 原生样式。

## 主题设置（后台 → 主题 → 本主题 → 设置）

每项界面改动都有开关，关闭后回到 Discourse 原生表现。

| 设置 | 默认 | 说明 |
|---|---|---|
| `card_feed` | 开 | 列表渲染为 Instagram 帖子卡片（关闭则为原生话题列表，探索网格随之关闭） |
| `show_like_count` | 开 | 卡片上显示点赞按钮与数量 |
| `rounded_avatars` | 开 | 圆形头像 + 作者故事环 |
| `brand_gradient_logo` | 开 | 站点标题用品牌渐变 |
| `brand_gradient_buttons` | 关 | 主按钮用渐变（关=经典蓝） |
| `accent_color` | `#0095f6` | 强调色/链接色 |
| `instagram_desktop_shell` | 开 | 桌面端左侧导航竖栏 |
| `instagram_stories` | 开 | 首页 Stories 横条 |
| `instagram_clean_feed` | 开 | 桌面端隐藏欢迎横幅、搜索框和列表筛选 |
| `instagram_hide_header` | 开 | 桌面端隐藏 Discourse 顶部头部 |
| `instagram_right_sidebar` | 开 | 桌面端（≥1160px）右侧栏 |
| `instagram_messages_dock` | 开 | 桌面端右下角消息浮窗 |
| `instagram_suggested_categories` | `13` | 右栏「为你推荐」读取的父类别 ID |
| `instagram_apps_categories` | `5\|9` | 左侧「社区与工具」菜单顶部的类别入口（活动、资源） |
| `instagram_tools_section` | `服务` | 右栏「服务」模块读取的侧边栏分区 |
| `instagram_qa_category` | `4` | 页脚「问答与求助」类别 ID |
| `instagram_topic_style` | 开 | 帖子详情页的 Instagram 样式 |
| `instagram_post_gallery` | 开 | 卡片多图轮播 |
| `instagram_explore_category` | `13` | 「探索」打开的类别 ID |
| `instagram_explore_search` | 开 | 探索页 Instagram 搜索 |
| `instagram_studio_profile` | 开 | 工作室主页头 |
| `instagram_categories_page` | 开 | /categories 卡片网格与工作室目录 |
| `instagram_auth_modal` | 开 | 登录 / 注册弹窗样式 |
| `new_topic_composer_height` | `70` | 创建话题编辑器高度（屏幕高度 %，0 = 原生） |
| `mobile_bottom_nav` | 开 | 手机端底部标签栏 |
| `instagram_mobile_layout` | 开 | 手机端 Instagram 顶栏与各页面排版 |
| `instagram_custom_services` | 开 | /custom-services 页使用主题样式 |
| `instagram_cad_viewer` | 开 | /viewer 模型预览页使用主题样式 |

## 结构

```
about.json                         元数据、两套配色、图标资源
settings.yml                       主题设置（en / zh_CN 说明）
common/color_definitions.scss      调色板与设计变量
common/common.scss                 样式入口，引入 scss/ 各分区
scss/*.scss                        按区域分文件：feed、topic、shell、sidebar、stories、
                                   right-sidebar、explore、studio、categories、auth、
                                   mobile-*、messages-*、custom-services 等
desktop/、mobile/                  端上微调
javascripts/discourse/
  api-initializers/
    ig-theme.js                    设置→body class、强调色、底部标签栏、私信气泡分组
    ig-navigation.js               桌面端外壳：左栏、Stories、右栏、探索
    ig-load-more.js                加载更多失败后的自动重试
    ig-messages.js                 消息浮窗、评论栏
  connectors/topic-list-item/      信息流帖子卡片、私信列表行
  connectors/*                     其余 plugin outlet 挂载点
  components/*.gjs                 工作室页头、探索搜索、类别网格、登录页头、
                                   手机顶栏、评论栏、主页统计与网格等
  lib/                             首帖加载队列、来源页记录
locales/en.yml, zh_CN.yml          文案
spec/system/                       系统测试（信息流卡片、桌面端外壳开关、手机端无横向溢出与通栏图片；performance_spec 与默认主题对比性能，结果在 CI 日志的 IGPERF 行；web_vitals_seo_spec 按 Google Lighthouse 的指标和 SEO 审核项对比，结果在 IGVITALS / IGCRAWL 行）
assets/*.svg                       图标
```

## 开发

```bash
pnpm install --frozen-lockfile
pnpm lint
```

系统测试在 CI（`.github/workflows/discourse-theme.yml`）里随最新 Discourse 运行。

当前版本：1.39.0（`about.json` 的 `theme_version`）。

最低 Discourse 版本随官方 CI 的 `.discourse-compatibility` 跟踪。
