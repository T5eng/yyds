// Headless API used by the iOS app (JavaScriptCore) and the Scriptable shortcut.
// Donor-statistics path only: no libheif, no ffmpeg, no DOM. Matches the
// on-device-validated `--linear-thumb reuse-thumbnail --scene-stats donor`
// configuration of nathanatgit/Shalielie v0.5.0.
(function (root) {
  function b64ToU8(b64) {
    var bin = atob(b64);
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  function u8ToB64(bytes) {
    var CHUNK = 0x8000;
    var parts = [];
    for (var i = 0; i < bytes.length; i += CHUNK) {
      parts.push(String.fromCharCode.apply(null, bytes.subarray(i, i + CHUNK)));
    }
    return btoa(parts.join(""));
  }

  function asU8(input) {
    if (input instanceof Uint8Array) return input;
    if (input instanceof ArrayBuffer) return new Uint8Array(input);
    if (ArrayBuffer.isView(input)) {
      return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
    }
    throw new Error("NOT_HEIC");
  }

  function sniff(b) {
    if (b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "jpeg";
    if (b.length > 7 && b[0] === 0x89 && b[1] === 0x50) return "png";
    if (b.length > 11 && String.fromCharCode(b[4], b[5], b[6], b[7]) === "ftyp") {
      var brand = String.fromCharCode(b[8], b[9], b[10], b[11]);
      return /^(hei|mif|msf|avi)/.test(brand) ? "heic" : "iso";
    }
    return "unknown";
  }

  function profileFromEmbedded(p) {
    var retained = new Map();
    var keys = Object.keys(p.payloads);
    for (var i = 0; i < keys.length; i++) {
      retained.set(Number(keys[i]), b64ToU8(p.payloads[keys[i]]));
    }
    return {
      manifest: p.manifest,
      ftyp: b64ToU8(p.ftyp),
      meta: b64ToU8(p.meta),
      mn54: b64ToU8(p.mn54),
      retained: retained,
    };
  }

  var profileCache = new Map();
  function getProfile(name) {
    if (!profileCache.has(name)) {
      var raw = EMBEDDED_PROFILES[name];
      if (!raw) throw new Error("UNSUPPORTED");
      profileCache.set(name, profileFromEmbedded(raw));
    }
    return profileCache.get(name);
  }

  function jsonable(value) {
    return JSON.parse(JSON.stringify(value, function (_k, v) {
      if (v instanceof Map) {
        var o = {};
        v.forEach(function (val, key) { o[String(key)] = val; });
        return o;
      }
      if (v instanceof Uint8Array) return undefined;
      return v;
    }));
  }

  function wrapError(err) {
    var msg = (err && err.message) ? String(err.message) : String(err);
    if (msg === "NOT_HEIC" || msg === "ALREADY_HAS_TEXTURE" || msg === "NO_THUMBNAIL" || msg === "UNSUPPORTED") {
      return err instanceof Error ? err : new Error(msg);
    }
    if (msg === "This HEIC isn't supported yet.") return new Error("UNSUPPORTED");
    if (/already has texture_styles/i.test(msg)) return new Error("ALREADY_HAS_TEXTURE");
    if (/no native Photographic Style/i.test(msg)) return new Error("UNSUPPORTED");
    var wrapped = new Error("UNSUPPORTED");
    wrapped.detail = msg;
    return wrapped;
  }

  /**
   * @param {Uint8Array|ArrayBuffer} input
   * @param {{texture?: boolean}} [opts]
   * @returns {Promise<{data: Uint8Array, dataBase64: string, report: object, mode: string, filenameSuffix: string}>}
   */
  async function port(input, opts) {
    opts = opts || {};
    var bytes = asU8(input);
    if (sniff(bytes) !== "heic") throw new Error("NOT_HEIC");

    try {
      var d = discoverHeic(bytes);
      if (d.stylesItem !== null) {
        if (hasTexture(d.infos)) throw new Error("ALREADY_HAS_TEXTURE");
        var tex = addTexture(bytes);
        return {
          data: tex.data,
          dataBase64: u8ToB64(tex.data),
          report: jsonable(tex.report),
          mode: "texture",
          filenameSuffix: "_TextureGrain.HEIC",
        };
      }
      if (d.thumbnail === null) throw new Error("NO_THUMBNAIL");
      var name = selectProfile(PROFILE_INDEX, d.primaryTiles.length, d.hdrTiles.length);
      var profile = getProfile(name);
      var patched = await patch(bytes, profile, {
        sceneStats: "donor",
        texture: opts.texture !== false,
      });
      return {
        data: patched.data,
        dataBase64: u8ToB64(patched.data),
        report: jsonable(patched.report),
        mode: "port",
        filenameSuffix: "_PhotographicStyle.HEIC",
      };
    } catch (err) {
      throw wrapError(err);
    }
  }

  /**
   * Base64 in / base64 out, for hosts that cannot pass TypedArrays (Scriptable, some Shortcuts bridges).
   */
  async function portBase64(b64, opts) {
    var result = await port(b64ToU8(b64), opts);
    return {
      dataBase64: result.dataBase64,
      report: result.report,
      mode: result.mode,
      filenameSuffix: result.filenameSuffix,
    };
  }

  function inspect(input) {
    var bytes = asU8(input);
    var kind = sniff(bytes);
    if (kind !== "heic") return { kind: kind };
    var d = discoverHeic(bytes);
    return {
      kind: "heic",
      primaryTiles: d.primaryTiles.length,
      hdrTiles: d.hdrTiles.length,
      hasThumbnail: d.thumbnail !== null,
      hasStyles: d.stylesItem !== null,
      hasTexture: hasTexture(d.infos),
    };
  }

  root.PhotographicStylePort = {
    VERSION: VERSION,
    SOURCE: "nathanatgit/Shalielie",
    sniff: sniff,
    inspect: function (input) {
      try { return inspect(input); }
      catch (err) { throw wrapError(err); }
    },
    port: port,
    portBase64: portBase64,
    b64ToU8: b64ToU8,
    u8ToB64: u8ToB64,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
