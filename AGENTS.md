# discourse-moaclab-instagram-theme

moaclab.com 的 Instagram 风格主题：信息流帖子卡片、桌面端左侧导航竖栏和 Stories 横条、移动端底部导航，内置浅色和深色两套配色。

**状态：开发中，尚未安装到生产站点。** 当前默认主题仍是 `discourse-moaclab-redditish-theme`（线上主题 276）。

站点级的协作约定、发布流程和切换默认主题的步骤在私有维护仓库 `mohist-club/Moaclab`（`ops/workflow.md`、`ops/release.md`）。本文件只写这个仓库内的开发约定。

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

CI（`.github/workflows/discourse-theme.yml`）用 Discourse 官方工作流在最新 Discourse 上跑 lint 和测试。仓库目前没有 `spec/` 和 `test/`，所以 CI 只验证 lint 和主题能否安装。上线前至少补一组系统测试，覆盖信息流卡片渲染和桌面端外壳的开关。

## 提交与发布

- 开发中阶段可以直接推 `main`。提交信息沿用现有的 `feat:` / `fix:` 前缀加中文说明。
- 安装到生产站点之前（包括只设为「用户可选」），先完成维护仓库 `ops/workflow.md` 的准入清单。从那以后改为分支加 PR，CI 全绿后由仓库所有者合并，并同步更新 `about.json` 的 `theme_version` 和 README。
- 上线和切换默认主题按维护仓库 `ops/release.md` 的「切换或新增默认主题」执行。

## 不要做

- 不强制推送。
- 不提交密钥或站点数据。
- 安装、设为用户可选、设为默认都属于生产操作，需要仓库所有者在当前对话里明确批准。
- 不做任务范围以外的重构。
