# 风格移植 — iPhone 快捷指令 / iOS App

把 [nathanatgit/Shalielie](https://github.com/nathanatgit/Shalielie) 的摄影风格移植做成 **iPhone 上能跑** 的两种形态：

1. **iOS App「风格移植」**（推荐）：带快捷指令动作 `Port Photographic Style`，以及分享扩展  
2. **Scriptable 脚本**：不用 Xcode，装免费的 Scriptable 就能给快捷指令调用  

快捷指令本身没有 Python，也跑不了 `photographic_style_port.py`。这里把 Shalielie 已经验证过的 **网页 JS 引擎**（和 Python 无编码器模式字节级对齐）打成一份无 DOM 的 `engine.js`，交给 JavaScriptCore / Scriptable 执行。照片全程在本机处理。

当前引擎对应 Shalielie **v0.5.0**（`0.5.0-web`），走 `--linear-thumb reuse-thumbnail --scene-stats donor` 这条已在真机验证的路径。

## 你应该选哪条路

| 方式 | 需要什么 | 在快捷指令里 | 适合谁 |
|---|---|---|---|
| **iOS App** | Mac + Xcode，签到你的 iPhone | 搜索动作「Port Photographic Style / 加上摄影风格」 | 想要分享表、存相册、长期用 |
| **Scriptable** | 免费 App [Scriptable](https://scriptable.app) | 「运行脚本」动作 | 不想编译、马上试 |
| 电脑 CLI / 网页 | 见原仓库 | 不能直接跑脚本 | 缺缩略图、要批量、要 `--light-maps target` |

两条路都有同一个限制：**必须提供原始 `.HEIC` 文件**。从「照片」App 选图会被 iOS 转成 JPEG，风格元数据全部丢掉。请从「文件」App 选，或用「分享文件」，不要用「选照片」。

## 快捷指令怎么搭（装好 App 之后）

1. 打开「快捷指令」→ 新快捷指令  
2. 点最上面「快捷指令名称」旁的信息按钮，打开 **显示在分享表单**，接受类型勾选 **文件**（不要只勾图片）  
3. 动作顺序：

   - **获取文件**（或分享表单传入的文件）  
   - **重复处理每个项目**  
     - **Port Photographic Style**（App 动作；「加入质感/颗粒」默认开）  
     - **存储文件** 到 iCloud/「文件」，或 **分享**  
   - （可选）用本 App 的「存入相册」把 HEIC **原样** 写入照片图库  

装的是 Scriptable 而不是 Xcode App 时，把第二步换成 **运行脚本 → Photographic Style Port**，脚本输入选「快捷指令输入」。

处理后在「照片」里打开这张图，编辑界面应出现风格调色盘；iOS 27 还会有质感/颗粒。结果因照片而异，原项目也说明未经 Apple 验证。

## 用 Scriptable（不用 Xcode）

1. iPhone 安装 [Scriptable](https://apps.apple.com/app/scriptable/id1405459188)  
2. 把 [`shortcuts/PhotographicStylePort.js`](shortcuts/PhotographicStylePort.js) 全文拷进 Scriptable，脚本名保存为 **Photographic Style Port**  
3. 在 Scriptable 里直接运行，会弹出文件选择（选 HEIC）  
4. 或按上一节接到快捷指令的「运行脚本」

脚本约 370 KB（内嵌了两份 donor profile），粘贴需要几秒。

## 用 Xcode 编译 iOS App

需要：Mac、Xcode 15+、免费 Apple ID 即可签到自己的 iPhone（每 7 天重签一次）。

```text
shalielie-ios/ios/PhotographicStylePort.xcodeproj
```

1. 用 Xcode 打开该工程  
2. 选中 target **PhotographicStylePort**，在 Signing 里选你的 Team  
3. 把 Bundle ID `app.shalielie.port` 改成你自己的（扩展 `app.shalielie.port.ShareExtension` 也要一起改）  
4. 插上 iPhone，运行  

App 能做的事：

- 从「文件」多选 HEIC 并处理  
- 分享文件 / 用 PhotoKit **按 HEIC 资源** 写入相册（不是导出 JPEG）  
- 分享表单：在「文件」里把 HEIC 分享到「风格移植」  
- 快捷指令动作：`PortPhotographicStyleIntent`  

## 引擎

```text
python3 engine/build_engine.py
node tests/test_engine.mjs
```

会重新生成：

- `engine/engine.js` — JavaScriptCore / Node 用  
- `ios/PhotographicStylePort/Engine.js` — 打进 App  
- `shortcuts/PhotographicStylePort.js` — Scriptable 整包  

`engine/vendor/` 是 Shalielie `web/src` 与 `web/profiles` 的快照（MIT）。升级上游时覆盖 vendor 再跑 build。

网页版原址：https://nathanatgit.github.io/Shalielie/

## 做不到的

- 没有内嵌缩略图的 HEIC（浏览器/JSC 没有 HEVC 编码器）  
- 不是 48/12 或 45/15 tile 布局的照片  
- 从「照片」App 挑出来的 JPEG  
- 把普通照片变成人像（人像遮罩只从原图拷，不会凭空生成）  

这些请继续用电脑上的 [Shalielie CLI](https://github.com/nathanatgit/Shalielie)。

## 许可

本目录新增的 Swift / 打包脚本以 MIT 发布。内嵌的移植逻辑和 donor profile 来自 Shalielie，版权归原作者，见 `LICENSE.shalielie`。

本工具与 Apple 无关，也未经 Apple 验证。请处理副本，保留原图。
