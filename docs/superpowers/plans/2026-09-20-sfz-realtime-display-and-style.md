# sfz 实时显示功能与样式优化 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 sfz 图片水印工具增加实时显示（参数值 chip、图片信息栏、始终实时预览）并用「现代卡片风」重做页面样式。

**Architecture:** 保持零依赖 CoffeeScript + Cake 架构。`src/script.coffee` 重构为清晰模块（状态、渲染管线、值标签、信息栏、加载、下载），输入事件即时更新 chip/字数、120ms 防抖重绘 canvas、500ms 防抖实测文件大小；`public/index.html` 重写为卡片布局 + 内联 CSS。

**Tech Stack:** CoffeeScript 2.7（Cake 编译）、原生 HTML/CSS/JS、Canvas 2D。无任何新依赖。

**规格依据:** `docs/superpowers/specs/2026-09-20-sfz-realtime-display-and-style-design.md`

## Global Constraints

- 零依赖：不引入任何运行时或构建期依赖（现有 coffeescript 除外）
- 无网络请求：CSS 内联于 index.html，无外部字体/CDN
- 构建命令：`cake build`（或 `npm run build`），编译 `src/*.coffee` → `public/script.js`；`public/*.js` 已被 .gitignore，**不提交编译产物**
- 元素 ID 必须保持：`image`、`text`、`color`、`alpha`、`angle`、`space`、`size`、`graph`
- 新增元素 ID：值 chip 为 `value-color`/`value-alpha`/`value-angle`/`value-space`/`value-size`；信息栏为 `info-size`/`info-weight`/`info-count`
- 界面文案全部中文；空文字 = 无水印（预览与下载均为底图）
- 验证方式：`cake build` 编译通过 + 手动清单（本项目无测试框架，规格已确认此方式）
- 提交范围：只提交 `src/script.coffee`、`public/index.html`、`docs/**`；**不要提交** `pnpm-lock.yaml`（工作区已有无关改动）和 `.idea/`
- 在 master 分支直接提交（遵循仓库既有习惯）

---

### Task 1: 重构 src/script.coffee — 模块化 + 始终实时预览

**Files:**
- Modify: `src/script.coffee`（整体重写）

**Interfaces:**
- Consumes: 无（首个任务）
- Produces: 全局函数 `drawText`、`updateValueLabels`、`updateInfoBar`、`updateFileSize`、`readFile`、`download`；模块变量 `input`（各输入元素引用）、`state`（`file`/`img`/`canvas`/`textCtx`）。Task 2 的 HTML 依赖这些函数更新 chip（`value-*`）与信息栏（`info-*`）——函数内对缺失元素做空值保护，因此对旧 HTML 也安全。

- [ ] **Step 1: 用以下完整代码重写 `src/script.coffee`**

```coffee
$ = (sel) -> document.querySelector sel

PREFIX = 'data:image/png;base64,'

inputItems = ['text', 'color', 'alpha', 'angle', 'space', 'size']
input = {}

image = $ '#image'
graph = $ '#graph'

state =
    file: null
    img: null
    canvas: null
    textCtx: null


dataURItoBlob = (dataURI) ->
    binStr = atob (dataURI.split ',')[1]
    len = binStr.length
    arr = new Uint8Array len

    for i in [0..len - 1]
        arr[i] = binStr.charCodeAt i
    new Blob [arr], type: 'image/png'


generateFileName = ->
    pad = (n) -> if n < 10 then '0' + n else n

    d = new Date
    '' + d.getFullYear() + '-' + (pad d.getMonth() + 1) + '-' + (pad d.getDate()) + ' ' + \
        (pad d.getHours()) + (pad d.getMinutes()) + (pad d.getSeconds()) + '.png'


formatBytes = (bytes) ->
    if bytes < 1024
        '' + bytes + ' B'
    else if bytes < 1024 * 1024
        (bytes / 1024).toFixed 1 + ' KB'
    else
        (bytes / 1024 / 1024).toFixed 1 + ' MB'


debounce = (fn, wait) ->
    timer = null
    return ->
        clearTimeout timer
        timer = setTimeout fn, wait


makeStyle = ->
    match = input.color.value.match /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i
    if not match?
        return 'rgba(0,0,255,' + input.alpha.value + ')'
    'rgba(' + (parseInt match[1], 16) + ',' + (parseInt match[2], 16) + ',' \
         + (parseInt match[3], 16) + ',' + input.alpha.value + ')'


redraw = ->
    return if not state.canvas?
    ctx = state.canvas.getContext '2d'
    ctx.clearRect 0, 0, state.canvas.width, state.canvas.height
    ctx.drawImage state.img, 0, 0


drawText = ->
    return if not state.canvas?
    text = input.text.value

    if state.textCtx?
        redraw()
    else
        state.textCtx = state.canvas.getContext '2d'

    return if text.length is 0

    textSize = input.size.value * Math.max 15, (Math.min state.canvas.width, state.canvas.height) / 25

    state.textCtx.save()
    state.textCtx.translate(state.canvas.width / 2, state.canvas.height / 2)
    state.textCtx.rotate (input.angle.value) * Math.PI / 180

    state.textCtx.fillStyle = makeStyle()
    state.textCtx.font = 'bold ' + textSize + 'px -apple-system,"Helvetica Neue",Helvetica,Arial,"PingFang SC","Hiragino Sans GB","WenQuanYi Micro Hei",sans-serif'

    width = (state.textCtx.measureText text).width
    step = Math.sqrt (Math.pow state.canvas.width, 2) + (Math.pow state.canvas.height, 2)
    margin = (state.textCtx.measureText '啊').width

    x = Math.ceil step / (width + margin)
    y = Math.ceil (step / (input.space.value * textSize)) / 2

    for i in [-x..x]
        for j in [-y..y]
            state.textCtx.fillText text, (width + margin) * i, input.space.value * textSize * j

    state.textCtx.restore()
    return


download = ->
    return if not state.canvas?
    link = document.createElement 'a'
    link.download = generateFileName()
    imageData = state.canvas.toDataURL 'image/png'
    blob = dataURItoBlob imageData
    link.href = URL.createObjectURL blob
    graph.appendChild link

    setTimeout ->
        link.click()
        graph.removeChild link
    , 100


updateValueLabels = ->
    setText = (id, text) ->
        el = $ '#' + id
        el.textContent = text if el?

    setText 'value-color', input.color.value
    setText 'value-alpha', input.alpha.value
    setText 'value-angle', input.angle.value + '°'
    setText 'value-space', input.space.value
    setText 'value-size', input.size.value


updateInfoBar = ->
    setText = (id, text) ->
        el = $ '#' + id
        el.textContent = text if el?

    if state.canvas?
        setText 'info-size', state.canvas.width + ' × ' + state.canvas.height + ' px'
    else
        setText 'info-size', '—'
    setText 'info-count', input.text.value.length + ' 字'


updateFileSize = ->
    el = $ '#info-weight'
    return if not el?
    if not state.canvas?
        el.textContent = '—'
        return
    dataURI = state.canvas.toDataURL 'image/png'
    bytes = Math.floor (dataURI.length - PREFIX.length) * 3 / 4
    el.textContent = formatBytes bytes


renderDebounced = debounce drawText, 120
updateFileSizeDebounced = debounce updateFileSize, 500


readFile = ->
    return if not state.file?

    fileReader = new FileReader

    fileReader.onload = ->
        img = new Image
        img.onload = ->
            state.img = img
            state.canvas = document.createElement 'canvas'
            state.canvas.width = img.width
            state.canvas.height = img.height
            state.canvas.title = '点击下载'
            state.textCtx = null

            ctx = state.canvas.getContext '2d'
            ctx.drawImage img, 0, 0

            drawText()
            updateInfoBar()
            updateFileSize()

            graph.innerHTML = ''
            graph.appendChild state.canvas

            state.canvas.addEventListener 'click', ->
                download()

        img.src = fileReader.result

    fileReader.readAsDataURL state.file


image.addEventListener 'change', ->
    state.file = @files[0]
    return if not state.file?
    return alert '仅支持 png, jpg, gif 图片格式' if state.file.type not in ['image/png', 'image/jpeg', 'image/gif']
    readFile()


inputItems.forEach (item) ->
    el = $ '#' + item
    input[item] = el

    el.addEventListener 'input', ->
        updateValueLabels()
        updateInfoBar()
        renderDebounced()
        updateFileSizeDebounced()
```

- [ ] **Step 2: 编译**

Run: `cd E:\Code\OpenSource\sfz && npm run build`
Expected: 无错误输出，`public/script.js` 重新生成（gitignored，不提交）。

- [ ] **Step 3: 对照旧 HTML 手动验证（浏览器打开 `public/index.html`）**

预期（此阶段页面仍是旧样式，chip/信息栏尚不存在，属正常）：
1. 选择图片 → 预览正常显示底图 + 水印
2. **取消勾选「实时刷新」复选框后**拖动滑块/输入文字 → 预览依然实时更新（旧开关已失效，Task 2 会移除该控件，预期行为）
3. 清空文字框 → 水印消失，仅剩底图；再输入 → 水印恢复
4. 点击 canvas → 下载 PNG，文件名形如 `2026-09-20 143025.png`
5. 文件选择框点「取消」→ 控制台无报错（旧代码会崩溃，新代码静默返回）
6. 选择 .txt 文件 → 弹出「仅支持 png, jpg, gif 图片格式」
7. 浏览器控制台无任何报错（chip/信息栏元素缺失被空值保护跳过）

- [ ] **Step 4: 提交**

```bash
cd E:\Code\OpenSource\sfz && git add src/script.coffee && git commit -m "refactor: modularize script with debounced always-live preview"
```

---

### Task 2: 重写 public/index.html — 现代卡片风 + chip + 信息栏

**Files:**
- Modify: `public/index.html`（整体重写）

**Interfaces:**
- Consumes: Task 1 的 `updateValueLabels`/`updateInfoBar`/`updateFileSize`（在 `input` 事件中被调用）及元素 ID 约定
- Produces: chip 元素 `value-color`/`value-alpha`/`value-angle`/`value-space`/`value-size`；信息栏 `info-size`/`info-weight`/`info-count`；移除 `auto-refresh`/`refresh` 控件

- [ ] **Step 1: 用以下完整代码重写 `public/index.html`**

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"/>
    <title>图片水印打码工具</title>
    <style>
        body {
            margin: 0;
            background: #f5f7fa;
            font-family: -apple-system, "Helvetica Neue", Helvetica, Arial, "PingFang SC", "Hiragino Sans GB", "WenQuanYi Micro Hei", sans-serif;
            color: #111827;
        }

        #container {
            max-width: 560px;
            margin: 0 auto;
            padding: 32px 16px;
        }

        header {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 10px;
        }

        .logo {
            width: 18px;
            height: 18px;
            border-radius: 5px;
            background: #2563eb;
            flex: none;
        }

        h1 {
            margin: 0;
            font-size: 20px;
            font-weight: 700;
        }

        .desc {
            margin: 0 0 20px;
            font-size: 13px;
            color: #6b7280;
            line-height: 1.6;
        }

        .desc a { color: #2563eb; }

        .card {
            background: #fff;
            border-radius: 10px;
            box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
            padding: 16px;
            margin-bottom: 16px;
        }

        .card h2 {
            margin: 0 0 14px;
            font-size: 15px;
            font-weight: 600;
        }

        .badge {
            display: inline-block;
            width: 20px;
            height: 20px;
            margin-right: 6px;
            border-radius: 50%;
            background: #2563eb;
            color: #fff;
            font-size: 12px;
            line-height: 20px;
            text-align: center;
        }

        #text {
            width: 100%;
            box-sizing: border-box;
            padding: 8px 10px;
            border: 1px solid #e5e7eb;
            border-radius: 6px;
            font-size: 14px;
        }

        #text:focus {
            outline: none;
            border-color: #2563eb;
        }

        .row {
            display: flex;
            align-items: center;
            gap: 10px;
            margin-top: 12px;
        }

        .row label {
            width: 42px;
            flex: none;
            font-size: 14px;
            color: #374151;
        }

        input[type=range] {
            flex: 1;
            accent-color: #2563eb;
        }

        input[type=color] {
            flex: none;
            width: 36px;
            height: 26px;
            padding: 0;
            border: 1px solid #e5e7eb;
            border-radius: 5px;
            background: none;
        }

        .chip {
            flex: none;
            min-width: 40px;
            padding: 2px 6px;
            border-radius: 4px;
            background: #eff6ff;
            color: #2563eb;
            font-size: 12px;
            font-variant-numeric: tabular-nums;
            text-align: center;
        }

        .info {
            display: flex;
            justify-content: space-around;
            padding: 12px 16px;
        }

        .info-item {
            display: flex;
            align-items: center;
            gap: 5px;
            font-size: 13px;
            color: #374151;
            font-variant-numeric: tabular-nums;
        }

        canvas {
            box-sizing: border-box;
            width: 100%;
            border: 1px dashed #cbd5e1;
            border-radius: 6px;
            cursor: pointer;
        }

        canvas:hover { border-color: #2563eb; }

        @media (max-width: 560px) {
            #container { padding: 16px 12px; }
        }
    </style>
</head>
<body>
    <div id="container">
        <header>
            <span class="logo"></span>
            <h1>图片水印打码工具</h1>
        </header>
        <p class="desc">安全地为你的图片加水印，无任何网络请求，特别适合各种敏感证件（身份证，驾照，护照等）。<a href="https://github.com/joyqi/sfz">Github地址</a></p>

        <section class="card">
            <h2><span class="badge">1</span>选择图片</h2>
            <input type="file" id="image" autocomplete="off">
        </section>

        <section class="card">
            <h2><span class="badge">2</span>水印设置</h2>
            <input type="text" id="text" placeholder="请输入水印文字" autocomplete="off" maxlength="30">
            <div class="row">
                <label for="color">颜色</label>
                <input type="color" id="color" value="#0000FF" autocomplete="off">
                <span class="chip" id="value-color">#0000ff</span>
            </div>
            <div class="row">
                <label for="alpha">透明度</label>
                <input type="range" id="alpha" min="0" max="1" step="0.05" value="0.15" autocomplete="off">
                <span class="chip" id="value-alpha">0.15</span>
            </div>
            <div class="row">
                <label for="angle">角度</label>
                <input type="range" id="angle" min="-90" max="90" step="3" value="45" autocomplete="off">
                <span class="chip" id="value-angle">45°</span>
            </div>
            <div class="row">
                <label for="space">间隔</label>
                <input type="range" id="space" min="1" max="8" step="0.2" value="4" autocomplete="off">
                <span class="chip" id="value-space">4</span>
            </div>
            <div class="row">
                <label for="size">字号</label>
                <input type="range" id="size" min="0.5" max="3" step="0.05" value="1" autocomplete="off">
                <span class="chip" id="value-size">1</span>
            </div>
        </section>

        <section class="card info">
            <div class="info-item"><span>📐</span><span id="info-size">—</span></div>
            <div class="info-item"><span>💾</span><span id="info-weight">—</span></div>
            <div class="info-item"><span>✏️</span><span id="info-count">0 字</span></div>
        </section>

        <section class="card">
            <h2><span class="badge">3</span>点击图片下载</h2>
            <p id="graph"></p>
        </section>
    </div>
    <script src="./script.js"></script>
</body>
</html>
```

- [ ] **Step 2: 手动验证（浏览器打开 `public/index.html`，需 Task 1 已编译出 `public/script.js`）**

预期：
1. 页面为浅灰蓝底 + 3 张白色卡片 + 信息栏卡片，头部蓝色 logo 方块
2. 未选图时信息栏三列均显示「—」（字数显示 `0 字`）
3. 选图后 📐 显示 `W × H px`，💾 显示文件大小（如 `320.5 KB`），预览立即带水印
4. 拖动任意滑块 → 对应 chip 数字即时变化（如 `45°` → `60°`），预览约 120ms 后更新
5. 输入文字 → ✏️ 字数即时变化、预览更新；清空 → 水印消失、字数归零
6. 修改颜色 → `#0000ff` 变为新 hex
7. 鼠标悬停 canvas → 出现「点击下载」提示（title），边框变蓝
8. 无「实时刷新」复选框与「刷新」按钮

- [ ] **Step 3: 提交**

```bash
cd E:\Code\OpenSource\sfz && git add public/index.html && git commit -m "feat: card-style UI with live value chips and info bar"
```

---

### Task 3: 完整验证清单 + 截图确认

**Files:** 预期无代码改动（发现问题则修复并以 `fix:` 提交）；截图放 `docs/superpowers/specs/screenshots/`（是否提交截图由用户决定）

- [ ] **Step 1: 重新编译**

Run: `cd E:\Code\OpenSource\sfz && npm run build`
Expected: 无错误。

- [ ] **Step 2: 启动本地静态服务器**

Run: `python -m http.server 8000 --directory public`
Expected: `Serving HTTP on ... port 8000`，浏览器访问 `http://localhost:8000`
（若 python 不可用，用 Node 一行服务器：`node -e "require('http').createServer((q,s)=>{const f=require('fs'),p=require('path');let t=q.url==='/'?'index.html':q.url;f.readFile(p.join('public',t),(e,d)=>e?s.end('404'):s.end(d))}).listen(8000)"`）

- [ ] **Step 3: 逐项验证（规格验证清单，优先用浏览器自动化截图；若无可用工具则请用户逐项确认）**

先检查自动化工具：`npx playwright --version`（若有输出则可用；不要安装新依赖）。

清单：
1. 选图 → `info-size` 显示尺寸 ✓
2. 拖每个滑块 → chip 即时跳数、预览防抖后更新 ✓
3. 输入文字 → 字数实时更新、预览更新 ✓
4. 改颜色 → chip 显示新 hex、预览更新 ✓
5. 停止操作 → 💾 更新，且与实际下载文件大小一致（下载后对比文件属性）✓
6. 点击 canvas → 下载 PNG，文件名形如 `2026-09-20 143025.png` ✓
7. 未选图调整参数不报错；选非法文件（.txt）弹 alert ✓
8. 移动端宽度（≤560px，DevTools 设备模拟）布局正常 ✓
9. 桌面与移动宽度各截图一张，核对与规格「页面结构」一致

- [ ] **Step 4: 修复发现的问题**

如有缺陷：修复 → `npm run build` → 重跑对应清单项 → 提交：
```bash
cd E:\Code\OpenSource\sfz && git add src/script.coffee public/index.html && git commit -m "fix: <问题简述>"
```

- [ ] **Step 5: 收尾检查**

```bash
cd E:\Code\OpenSource\sfz && git status
```
Expected: 无遗漏的 `src/script.coffee`、`public/index.html` 改动；`pnpm-lock.yaml`、`.idea/` 保持未提交状态；`public/script.js` 为 gitignored。
