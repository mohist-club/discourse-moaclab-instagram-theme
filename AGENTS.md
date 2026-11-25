# discourse-moaclab-instagram-theme

moaclab.com 的 Instagram 风格主题：信息流帖子卡片、桌面端左侧导航竖栏和 Stories 横条、移动端底部导航，内置浅色和深色两套配色。

**状态：已上线。** 2026-11-20 起是 moaclab.com 的默认主题（线上主题 283，从 Git 安装，跟踪 `main`）。原默认主题 `discourse-moaclab-redditish-theme`（276）保留以便回退。

站点级的协作约定、发布流程和回退步骤在私有维护仓库 `mohist-club/Moaclab`（`ops/workflow.md`、`ops/release.md`），线上版本和发布记录在 `components/instagram-theme.md`。本文件只写这个仓库内的开发约定。

## 目录

| 路径 | 内容 |
| --- | --- |
| `about.json` | 元数据、两套配色方案、图标资源 |
| `settings.yml` | 主题设置，每项带 `en` 与 `zh_CN` 说明 |
| `common/color_definitions.scss` | 调色板 |
| `common/common.scss` | 样式入口，引入 `scss/` 下各分区 |
| `scss/` | 按区域分文件：feed、topic、header、sidebar、shell、stories 等 |
| `desktop/`、`mobile/` | 端上微调，移动端底部导航 |
| `javascripts/discourse/api-initializers/ig-theme.js` | 设置映射为 body class 和强调色 |
| `javascripts/discourse/api-initializers/ig-navigation.js` | 桌面端外壳：左栏操作组、Stories 横条 |
| `javascripts/discourse/connectors/topic-list-item/item.gjs` | 信息流帖子卡片 |
| `locales/` | `en` 与 `zh_CN` 文案 |

## 约定

- **组件用 `.gjs`**（Glimmer），通过 plugin outlet 和 `api.*` 扩展界面，不覆盖核心模板。
- **优先用 outlet 和组件，少做 DOM 注入**：`ig-navigation.js` 目前直接往页面里插入元素。新增界面优先找合适的 plugin outlet 写成组件；确实要注入时，保证重复执行不会插入多份，并在路由切换后仍然正确。
- **不在初始化阶段读视口**：`site.mobileView` 等要在渲染时读取，避免触发 `discourse.static-viewport-initialization` 弃用警告。
- **保留原生交互**：点赞、收藏、通知、搜索、发帖调用 Discourse 原生功能，主题只改外观和入口位置。
- **样式**：颜色用 CSS 变量和 `common/color_definitions.scss` 里的定义，浅色和深色都要检查。
- **设置**：每个界面改动尽量有对应的开关，默认值保证关闭后回到 Discourse 原生表现。新增设置同时写 `en` 与 `zh_CN` 说明。
- **文案**：界面文字放 `locales/`，两种语言同步更新。
- **兼容已有组件**：moaclab.com 的工具页 `/typing`、`/viewer` 和帖子内的 CAD 模型嵌入由其他组件提供，隐藏顶栏、改侧栏这类全局改动要确认这些页面仍可用、仍能导航回去。
- 不新增依赖和外部 CDN 资源，确有需要先问。

## 检查

使用 Node.js 22 或更新版本，pnpm 版本以 `package.json` 的 `packageManager` 为准：

```sh
pnpm install --frozen-lockfile
pnpm lint
```

CI（`.github/workflows/discourse-theme.yml`）用 Discourse 官方工作流在最新 Discourse 上跑 lint 和 `spec/system/` 下的功能测试（信息流卡片、桌面端外壳、手机端布局）。性能、Web Vitals 和 Lighthouse 测量在 `.github/workflows/theme-measurements.yml`，每周一或手动运行，不阻塞 PR。

## 提交与发布

1. 从 `main` 开分支，一个分支只做一件事。不再直接推 `main`。
2. 影响线上表现的改动同步更新 `about.json` 的 `theme_version` 和 README 里的「当前版本」。提交信息沿用 `feat:` / `fix:` 前缀加中文说明。
3. 推分支，开指向 `main` 的 PR，等 CI 全绿。合并由仓库所有者决定：所有者在对话里说「合并」，Claude 即可合并。合并后的分支不用手动删除，不打 tag。
4. 合并后更新到网站按维护仓库 `ops/release.md` 的「主题和组件」执行（主题 283 页面 **Check for Updates → Update to Latest**），并在 `components/instagram-theme.md` 的发布记录里追加一行。
5. 回退：在本仓库 revert 对应 PR 并合并，再在主题 283 应用更新；整体回退时把默认主题改回 276，见 `ops/release.md`。

## 不要做

- 不直接推 `main`，不强制推送。
- 不提交密钥或站点数据。
- 更新线上主题 283、修改其设置、切换默认主题都属于生产操作，需要仓库所有者在当前对话里明确批准。
- 不做任务范围以外的重构。
