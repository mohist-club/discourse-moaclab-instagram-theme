# /custom-services 页面源码（LP 插件）

moaclab.com/custom-services 是 discourse-landing-pages 插件里的页面「Moaclab 定制化服务」，内容存在站点数据库里，这里只是生成用的源码。

- `style.css`：页面样式（`.mlp3`，跟随主题的 `--ig-*` 变量，浅色/深色通用）
- `gen.py`：生成 `body.template.html`（`python3 gen.py`）
- `body.template.html`：页面 HTML，`{{PHOTO0}}`–`{{PHOTO2}}` 是三张重新阳极实拍图（base64），更新时从线上旧页面取出替换

旧版页面备份在 LP 插件里的 `custom-services-backup-20261126`（仅管理员可见）。
