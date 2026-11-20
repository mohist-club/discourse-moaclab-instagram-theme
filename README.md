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

## 主题设置（后台 → 主题 → 本主题 → 设置）

| 设置 | 默认 | 说明 |
|---|---|---|
| `card_feed` | 开 | 列表渲染为 Instagram 帖子卡片 |
| `show_like_count` | 开 | 卡片上显示点赞按钮与数量 |
| `rounded_avatars` | 开 | 圆形头像 + 作者故事环 |
| `brand_gradient_logo` | 开 | 站点标题用品牌渐变 |
| `brand_gradient_buttons` | 关 | 主按钮用渐变（关=经典蓝） |
| `mobile_bottom_nav` | 开 | 移动端底部导航 |
| `accent_color` | `#0095f6` | 强调色/链接色 |

## 结构

```
about.json                         元数据 + 两套配色 + 资源
settings.yml                       可调设置
common/color_definitions.scss      Instagram 调色板（dark-light-choose）
common/common.scss                 入口，@import scss 分区
common/head_tag.html               theme-color meta
scss/*.scss                        variables/header/feed/topic/buttons/avatars/misc
desktop|mobile/*.scss              端上微调 + 底部导航
javascripts/.../connectors/
  topic-list-item/item.gjs         信息流帖子卡片（点赞/评论/分享逻辑）
javascripts/.../api-initializers/
  ig-theme.js                      设置→body class / 强调色 / 底部导航
locales/en.yml, zh_CN.yml          多语言
assets/*.svg                       分享与底部导航图标
```

## 开发

```bash
pnpm install
pnpm lint
```

最低 Discourse 版本随官方 CI 的 `.discourse-compatibility` 跟踪。
