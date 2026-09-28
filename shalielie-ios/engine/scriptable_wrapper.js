// Scriptable entry point. Paste this whole file as one Scriptable script named
// "Photographic Style Port". Shortcuts can then run it with a HEIC file as input
// and receive a patched HEIC as output.
//
// 快捷指令推荐流程：
//   1. 接收「文件」（分享表单）或「从文件选择」
//   2. 运行脚本「Photographic Style Port」（Scriptable）
//   3. 存储文件 / 分享
// 不要用「从相册选择」：iOS 会把 HEIC 转成 JPEG，风格元数据会丢。

function dataFromAnything(value) {
  if (value == null) return null;
  if (typeof Data !== "undefined" && value instanceof Data) return value;
  if (typeof value === "string") {
    var fm = FileManager.local();
    if (fm.fileExists(value)) return fm.read(value);
    // Already base64?
    try { return Data.fromBase64String(value); } catch (e) { return null; }
  }
  if (Array.isArray(value) && value.length) return dataFromAnything(value[0]);
  if (typeof value === "object") {
    if (typeof value.getBase64 !== "undefined") {
      try { return Data.fromBase64String(value.getBase64()); } catch (e) {}
    }
    if (value.data) return dataFromAnything(value.data);
    if (value.path) return dataFromAnything(value.path);
    if (value.filePath) return dataFromAnything(value.filePath);
    if (value.base64) return Data.fromBase64String(value.base64);
  }
  return null;
}

function outputName(original, suffix) {
  var base = original || "IMG";
  return base.replace(/\.(heic|heif)$/i, "") + suffix;
}

function errorText(code) {
  switch (String(code)) {
    case "NOT_HEIC":
      return "这不是原始 HEIC。请从「文件」App 选择照片，不要从「照片」选（会被转成 JPEG）。";
    case "ALREADY_HAS_TEXTURE":
      return "这张照片已经带有质感/颗粒，无需再处理。";
    case "NO_THUMBNAIL":
      return "这张照片没有内嵌缩略图，iPhone 上无法处理，请用电脑上的命令行工具。";
    case "UNSUPPORTED":
      return "这张 HEIC 的布局还不支持（目前只有 48/12 和 45/15 两种）。";
    default:
      return "处理失败：" + code;
  }
}

async function processOne(data, filename) {
  var b64 = data.toBase64String();
  var result = await PhotographicStylePort.portBase64(b64);
  var out = Data.fromBase64String(result.dataBase64);
  return {
    data: out,
    filename: outputName(filename, result.filenameSuffix),
    mode: result.mode,
    report: result.report,
  };
}

async function run() {
  var param = args.shortcutParameter;
  var inApp = typeof config !== "undefined" && config.runsInApp;

  try {
    var filename = "IMG.HEIC";
    var input = dataFromAnything(param);

    if (!input && inApp) {
      var picked = await DocumentPicker.open(["public.heic", "public.heif", "public.image"]);
      if (!picked || !picked.length) {
        Script.setShortcutOutput(null);
        return;
      }
      var fm = FileManager.local();
      filename = picked[0].split("/").pop();
      input = fm.read(picked[0]);
    }

    if (!input) {
      throw new Error("NOT_HEIC");
    }

    if (param && typeof param === "object" && !Array.isArray(param)) {
      filename = param.fileName || param.filename || param.name || filename;
    }

    var result = await processOne(input, filename);

    if (inApp) {
      try {
        var fmOut = FileManager.local();
        var outPath = fmOut.joinPath(fmOut.temporaryDirectory, result.filename);
        fmOut.write(outPath, result.data);
        await ShareSheet.present([outPath]);
      } catch (e) {
        console.log(e);
      }
    }

    // Shortcuts「存储文件」需要 Data / 文件，不要包一层对象。
    Script.setShortcutOutput(result.data);
  } catch (err) {
    var code = (err && err.message) ? err.message : String(err);
    var text = errorText(code);
    if (inApp) {
      await new Alert(text).present();
    }
    if (typeof Script.complete === "function") {
      Script.setShortcutOutput({ error: code, message: text });
    }
    throw new Error(text);
  }
}

await run();
