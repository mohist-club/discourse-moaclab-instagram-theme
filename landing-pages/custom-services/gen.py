import html
fam=[('RD','红',[('ARD090','#a3322a'),('ARD091','#d4232a')]),
('OR','橙',[('AOR070','#e0601a')]),
('YW','黄',[('AYW110','#d6dc4a')]),
('GR','绿',[('AGR050','#a9dcc0'),('AGR051','#6ccc4c'),('AGR052','#7d7a2e'),('AGR053','#1e4a35'),('CGR774','#3fbfb6')]),
('BL','蓝',[('ABL025','#a9c3e4'),('ABL020','#4d6078'),('ABL023','#2f6fd0'),('ABL022','#2340a8'),('CBL790','#2d3f9e'),('ABL024','#2aae94')]),
('PR','紫',[('APR002','#c9b8dc'),('APR003','#3b2c78'),('APR001','#2f2a5e')]),
('PK','粉',[('APK080','#e2b2ae'),('APK081','#b02a86')]),
('GD','金',[('AGD041','#d9b088'),('AGD040','#b6926e')]),
('BR','棕',[('ABR030','#4a3029')]),
('GY','灰',[('CGY819','#8aa0b4'),('AGY061','#75777d')]),
('SV','银',[('ASV101','#e9e8e4'),('ASV100','#d4d0c4')]),
('BK','黑',[('ABK010','#1d1f20')])]
N=sum(len(c) for *_,c in fam)
QQ='https://qm.qq.com/q/cSoRKgBBsc'; DC='https://discord.gg/Y75yPtUMcm'; T='https://moaclab.com/t/topic/'
ext='target="_blank" rel="noopener noreferrer"'
ICON={
'grid':'<svg viewBox="0 0 24 24" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="1"/><path d="M9 3v18M15 3v18M3 9h18M3 15h18"/></g></svg>',
'dlc':'<svg viewBox="0 0 24 24" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="3" y="7" width="14" height="14" rx="2"/><path d="M7 3h12a2 2 0 0 1 2 2v12"/></g></svg>',
'drop':'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3s7 7.6 7 12a7 7 0 0 1-14 0c0-4.4 7-12 7-12Z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>',
'link':'<svg viewBox="0 0 24 24" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M10 14a4 4 0 0 0 5.7 0l3.6-3.6a4 4 0 0 0-5.7-5.7L12 6.3"/><path d="M14 10a4 4 0 0 0-5.7 0l-3.6 3.6a4 4 0 0 0 5.7 5.7l1.6-1.6"/></g></svg>',
'topic':'<svg viewBox="0 0 24 24" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M4 5h16v11H9l-5 4V5Z"/><path d="M8 9h8M8 12h5" stroke-linecap="round"/></g></svg>',
'file':'<svg viewBox="0 0 24 24" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M6 3h8l4 4v14H6V3Z"/><path d="M14 3v4h4M9 13h6M9 17h6" stroke-linecap="round"/></g></svg>',
'plus':'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 4v16M4 12h16" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
'x':'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 5l14 14M19 5 5 19" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/></svg>',
}
KEYCAP='<span class="mlp3-keycap"></span>'

works=[('bot60','BOT60% CE','社区定制版','7.8° · WK','JokerPony 设计，TOP 结构，红铜魔法马背板配重。','JokerPony 设计，7.8° 倾角、19mm 前高、TOP 结构与 WK 配列，采用红铜魔法马背板配重。','https://moaclab.com/uploads/default/optimized/2X/a/a69040fd6c2aa47499786da9abbba769287e5507_2_690x517.jpeg',[('查看社区话题',T+'2657',1)]),
('360gt','360GT Community Edition','社区共创','','基于 OTD 360 原型修改。','基于 OTD 360 原型修改，并借鉴 daji 的上下盖方式。配列、颜色和登记信息请查看社区话题。','https://moaclab.com/uploads/default/optimized/2X/4/446b34ad9dff689f94172fa76aac28ddd02f48df_2_690x460.jpeg',[('查看社区话题',T+'2656',1)]),
('atlas-tkl','Atlas TKL','社区作品','','项目资料待补充。','Atlas TKL 社区作品。实拍图片与项目介绍待补充。',None,[('加入 QQ 群咨询',QQ,0)])]
dlc=[('bot-plate','BOT60 红铜魔法马背板','背板','BOT60','','图纸公开','BOT60% CE 话题中公布的红铜魔法马背板配重。可参考公开图纸，具体适配与制作需求请联系沟通。','https://moaclab.com/uploads/default/original/2X/2/2088586964979f884f3be63b23f31c5eb6fcb51e.png',[('查看背板图纸',T+'2569',1),('查看 BOT60% CE 话题',T+'2657',0)]),
('jane-v2-steel','Jane v2/ce 背板','背板','Jane v2 / CE','不锈钢刀纹、铜热着色/刀纹','图纸 · 3D 模型','不锈钢刀纹、铜热着色/刀纹。背板图纸与 3D 模型见社区话题，具体适配与制作需求请联系沟通。','https://moaclab.com/uploads/default/original/2X/5/55c98a4d9f2b98c0fa3872ecfdcb0eec046bf2cd.png',[('查看背板图纸',T+'2695',1)]),
('jjw-moment-pvd','JJW Moment 不锈钢 PVD 配重','配重','JJW Moment','','图纸 · 3D 模型','JJW Moment 不锈钢 PVD 配重。配重图纸与 3D 模型见社区话题，具体适配与制作需求请联系沟通。','https://moaclab.com/uploads/default/original/2X/c/cb317f447fd8dd813f43015ad252003d55067fa0.png',[('查看配重图纸',T+'2694',1)])]
cases=[('color-0','碧波青'),('color-1','石墨灰'),('color-2','樱花粉')]
e=html.escape
def btns(links):
    return ''.join(f'<a class="mlp3-btn {"mlp3-btn--primary" if p else "mlp3-btn--grey"}" href="{u}"{" "+ext if u.startswith("https://qm") or u.startswith("https://discord") else ""}>{e(t)}</a>' for t,u,p in links)
def media(img, alt, cls='mlp3-media'):
    if img: return f'<span class="{cls}"><img src="{img}" alt="{e(alt)}" loading="lazy"></span>'
    return f'<span class="{cls} is-pending">{ICON["plus"]}<span>实拍待补充</span></span>'
pops=[]
def pop(pid, kind, title, text, mediahtml, links):
    pops.append(f'<div id="mlp3-d-{pid}" class="mlp3-pop" popover="auto" role="dialog" aria-labelledby="mlp3-t-{pid}"><div class="mlp3-pop-media">{mediahtml}</div><div class="mlp3-pop-copy"><div class="mlp3-pop-head"><span class="mlp3-mini">{KEYCAP}</span><div><b>Moaclab 定制</b><small>{e(kind)}</small></div></div><div class="mlp3-pop-body"><h2 id="mlp3-t-{pid}">{e(title)}</h2><p>{e(text)}</p></div><div class="mlp3-pop-foot">{btns(links)}</div></div><button type="button" class="mlp3-x" popovertarget="mlp3-d-{pid}" popovertargetaction="hide" aria-label="关闭">{ICON["x"]}</button></div>')
def tags(a,b):
    return f'<span class="mlp3-tags"><span class="mlp3-tag">{e(a)}</span>'+(f'<span class="mlp3-tag mlp3-tag--soft">{e(b)}</span>' if b else '')+'</span>'

# works
w=[]
for i,(pid,title,kind,extra,short,long,img,links) in enumerate(works):
    meta=f'<span class="mlp3-meta">{ICON["topic"]}查看话题</span>' if img else ''
    inner=f'{media(img,title)}<span class="mlp3-text">{tags(kind,extra)}<span class="mlp3-name">{e(title)}</span><span class="mlp3-sub">{e(short)}</span>{meta}</span>'
    cls='mlp3-card mlp3-card--big' if i==0 else 'mlp3-card mlp3-card--row'
    w.append(f'<button type="button" class="{cls}" popovertarget="mlp3-d-{pid}">{inner}</button>')
    pop(pid,kind,title,long,(f'<img src="{img}" alt="{e(title)}" loading="lazy">' if img else f'<span class="mlp3-pending">{ICON["plus"]}<span>实拍图片待补充</span></span>'),links)
works_html=f'<div class="mlp3-feat">{w[0]}<div class="mlp3-feat-side">{w[1]}{w[2]}</div></div>'
# dlc
d=[]
for pid,title,kind,extra,sub,meta,long,img,links in dlc:
    d.append(f'<button type="button" class="mlp3-card" popovertarget="mlp3-d-{pid}">{media(img,title)}<span class="mlp3-text">{tags(kind,extra)}<span class="mlp3-name">{e(title)}</span>'+(f'<span class="mlp3-sub">{e(sub)}</span>' if sub else '')+f'<span class="mlp3-meta">{ICON["file"]}{e(meta)}</span></span></button>')
    pop(pid,kind,title,long,f'<img src="{img}" alt="{e(title)}" loading="lazy">',links)
dlc_html=f'<div class="mlp3-grid mlp3-grid--dlc">{"".join(d)}</div>'
# colour card
rows=[]
for code,name,cs in fam:
    chips=''
    for c,h in cs:
        pid='c-'+c.lower()
        chips+=f'<button type="button" class="mlp3-pms" popovertarget="mlp3-d-{pid}"><span class="mlp3-pms-c" style="background-color:{h}"></span><span class="mlp3-pms-l"><b>{c}</b><small>{name} {code}</small></span></button>'
        pop(pid,'阳极色卡 · '+name,c,'色块为实物色板拍摄取色，受屏幕影响会有偏差。实际颜色以实物色板为准，选色和方案请在 QQ 群沟通。',f'<span class="mlp3-swatch" style="background-color:{h}"></span>',[('加入 QQ 群咨询',QQ,1)])
    rows.append(f'<div class="mlp3-fam"><div class="mlp3-fam-hd"><span class="mlp3-dot" style="background-color:{cs[0][1]}"></span><b>{name}</b><small>{code} · {len(cs)}</small></div><div class="mlp3-chips">{chips}</div></div>')
deck=f'<div class="mlp3-deck">{"".join(rows)}</div>'
cs_html=[]
for i,(pid,name) in enumerate(cases):
    cs_html.append(f'<button type="button" class="mlp3-card mlp3-card--case" popovertarget="mlp3-d-{pid}"><span class="mlp3-media"><span class="mlp3-photo mlp3-photo-{i}" role="img" aria-label="{name}"></span><span class="mlp3-badge">实拍</span></span><span class="mlp3-text"><span class="mlp3-name">{name}</span></span></button>')
    pop(pid,'重新阳极实拍',name,'来自当前服务页的重新阳极实拍案例。实拍颜色受光线与屏幕影响，实际方案以服务沟通为准。',f'<span class="mlp3-photo mlp3-photo-{i}" role="img" aria-label="{name}"></span>',[('查看社区话题',T+'2617',1)])
cases_html=f'<div class="mlp3-grid mlp3-grid--case">{"".join(cs_html)}</div>'

css=open('style.css').read()
photos=''.join(f'.mlp3 .mlp3-photo-{i}{{background-image:url({{{{PHOTO{i}}}}})}}' for i in range(3))
body=f'''<style>{css}{photos}</style>
<div class="mlp3" lang="zh-CN">
<header class="mlp3-hd"><div class="mlp3-ring"><span class="mlp3-avatar">{KEYCAP}</span></div><div class="mlp3-hd-info"><h1>定制你的下一件作品</h1><ul class="mlp3-stats"><li><b>3</b> 件社区作品</li><li><b>3</b> 款 DLC</li><li><b>{N}</b> 种阳极色</li></ul></div><div class="mlp3-hd-more"><p class="mlp3-label">Moaclab 定制服务</p><p class="mlp3-bio">从社区灵感到个性定制，探索键盘的更多可能。</p><a class="mlp3-hlink" href="{T}2617">{ICON["link"]}查看服务与登记</a></div></header>
<div class="mlp3-actions"><a class="mlp3-btn mlp3-btn--primary" href="{QQ}" {ext}>加入 QQ 群</a><a class="mlp3-btn mlp3-btn--grey" href="{DC}" {ext}>加入 Discord</a></div>
<nav class="mlp3-tabs" aria-label="服务页面导航"><a class="mlp3-tab" href="#mlp3-works">{ICON["grid"]}<span>社区作品</span></a><a class="mlp3-tab" href="#mlp3-dlc">{ICON["dlc"]}<span>DLC</span></a><a class="mlp3-tab" href="#mlp3-anodize">{ICON["drop"]}<span>重新阳极</span></a></nav>
<section id="mlp3-works" class="mlp3-sec" tabindex="-1" aria-labelledby="mlp3-works-t"><div class="mlp3-sec-hd"><div><h2 id="mlp3-works-t">社区作品</h2><p>来自社区的创作与灵感。</p></div><span class="mlp3-count">3 件</span></div>{works_html}</section>
<section id="mlp3-dlc" class="mlp3-sec" tabindex="-1" aria-labelledby="mlp3-dlc-t"><div class="mlp3-sec-hd"><div><h2 id="mlp3-dlc-t">DLC</h2><p>配重与背板，为你的键盘增添新的表达。</p></div><span class="mlp3-count">3 款</span></div>{dlc_html}</section>
<section id="mlp3-anodize" class="mlp3-sec" tabindex="-1" aria-labelledby="mlp3-anodize-t"><div class="mlp3-sec-hd"><div><h2 id="mlp3-anodize-t">重新阳极</h2><p>为喜爱的键盘，换一种色彩。按色系整理的阳极色卡，点色块看大图。</p></div><span class="mlp3-count">{N} 色</span></div>{deck}<p class="mlp3-fine">色块为实物色板拍摄取色，受屏幕影响会有偏差。实际颜色以实物色板为准，方案以服务沟通为准。</p><h3 class="mlp3-subhd">实拍案例</h3>{cases_html}<p class="mlp3-fine">实拍颜色受光线与屏幕影响，实际方案以服务沟通为准。</p></section>
{"".join(pops)}
</div>'''
open('body.template.html','w').write(body)
print(len(body))
