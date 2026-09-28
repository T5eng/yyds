// Minimal polyfills for JavaScriptCore (iOS app) and Scriptable.
// The ported modules only need atob / TextEncoder; everything else is ES2017+.
(function (root) {
  var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  if (typeof root.atob !== "function") {
    root.atob = function (s) {
      s = String(s).replace(/[^A-Za-z0-9+/]/g, "");
      var out = "";
      for (var i = 0; i < s.length; i += 4) {
        var a = B64.indexOf(s[i]);
        var b = B64.indexOf(s[i + 1]);
        var c = B64.indexOf(s[i + 2]);
        var d = B64.indexOf(s[i + 3]);
        out += String.fromCharCode((a << 2) | (b >> 4));
        if (s[i + 2] !== undefined && c >= 0) out += String.fromCharCode(((b & 15) << 4) | (c >> 2));
        if (s[i + 3] !== undefined && d >= 0) out += String.fromCharCode(((c & 3) << 6) | d);
      }
      return out;
    };
  }
  if (typeof root.btoa !== "function") {
    root.btoa = function (s) {
      s = String(s);
      var out = "";
      for (var i = 0; i < s.length; i += 3) {
        var c1 = s.charCodeAt(i) & 0xff;
        var c2 = i + 1 < s.length ? s.charCodeAt(i + 1) & 0xff : 0;
        var c3 = i + 2 < s.length ? s.charCodeAt(i + 2) & 0xff : 0;
        out += B64[c1 >> 2];
        out += B64[((c1 & 3) << 4) | (c2 >> 4)];
        out += i + 1 < s.length ? B64[((c2 & 15) << 2) | (c3 >> 6)] : "=";
        out += i + 2 < s.length ? B64[c3 & 63] : "=";
      }
      return out;
    };
  }
  if (typeof root.TextEncoder !== "function") {
    root.TextEncoder = function () {};
    root.TextEncoder.prototype.encode = function (str) {
      str = String(str);
      var bytes = [];
      for (var i = 0; i < str.length; i++) {
        var c = str.charCodeAt(i);
        if (c < 0x80) bytes.push(c);
        else if (c < 0x800) bytes.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
        else if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
          var c2 = str.charCodeAt(++i);
          var u = 0x10000 + ((c & 0x3ff) << 10) + (c2 & 0x3ff);
          bytes.push(0xf0 | (u >> 18), 0x80 | ((u >> 12) & 0x3f),
            0x80 | ((u >> 6) & 0x3f), 0x80 | (u & 0x3f));
        } else bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
      }
      return new Uint8Array(bytes);
    };
  }
})(typeof globalThis !== "undefined" ? globalThis : this);
