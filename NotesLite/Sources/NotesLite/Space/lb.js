// 留白 lb 接口：空间主页访问笔记的唯一通道。所有请求都交给原生端校验和执行。
(() => {
  "use strict";
  const native = window.webkit && window.webkit.messageHandlers;
  const report = (detail) => {
    try { native.lbError.postMessage(detail); } catch (_) {}
  };
  window.addEventListener("error", (event) => {
    const target = event.target;
    if (target && target !== window && (target.src || target.href)) {
      report({ message: "资源加载失败：" + (target.src || target.href) });
      return;
    }
    report({
      message: String(event.message || "脚本错误"),
      source: event.filename || "",
      line: event.lineno || 0,
      column: event.colno || 0,
      stack: event.error && event.error.stack ? String(event.error.stack) : "",
    });
  }, true);
  window.addEventListener("unhandledrejection", (event) => {
    const reason = event.reason;
    report({
      message: "未处理的 Promise 错误：" + (reason && reason.message ? reason.message : String(reason)),
      stack: reason && reason.stack ? String(reason.stack) : "",
      code: reason && reason.code ? String(reason.code) : "",
    });
  });

  const call = (method, ...args) => {
    if (!native || !native.lb) return Promise.reject(Object.assign(new Error("lb 接口不可用。"), { code: "failed" }));
    return native.lb.postMessage({ method, args: args.map((a) => (a === undefined ? null : a)) }).then((reply) => {
      if (reply && reply.ok) return reply.result;
      const info = (reply && reply.error) || { code: "failed", message: "未知错误" };
      throw Object.assign(new Error(info.message), { code: info.code });
    });
  };

  const listeners = new Set();
  const plain = (value) => (value && typeof value === "object" ? JSON.parse(JSON.stringify(value)) : value);

  const lb = {
    scope: () => call("scope"),
    notes: (folder) => call("notes", folder),
    read: (path) => call("read", path),
    tables: (path) => call("tables", path),
    async query(source, options = {}) {
      const fn = typeof options.filter === "function" ? options.filter : null;
      const request = { ...options };
      if (fn) { delete request.filter; delete request.limit; }
      const result = await call("query", source, request);
      let rows = result.records.map((record) => {
        const { _row, ...fields } = record;
        Object.defineProperty(fields, "_row", { value: _row, enumerable: false });
        return fields;
      });
      if (fn) {
        rows = rows.filter(fn);
        if (options.limit != null) rows = rows.slice(0, options.limit);
      }
      Object.defineProperty(rows, "fields", { value: result.fields, enumerable: false });
      return rows;
    },
    append: (target, records, options) => call("append", target, plain(records), options || {}),
    update: (target, match, changes) => call("update", target, plain(match), plain(changes)),
    remove: (target, match) => call("remove", target, plain(match)),
    create: (path, content) => call("create", path, content == null ? "" : String(content)),
    write: (path, content) => call("write", path, content == null ? "" : String(content)),
    rename: (path, title) => call("rename", path, title),
    move: (path, folder) => call("move", path, folder),
    trash: (path) => call("trash", path),
    page: () => call("page"),
    writePage: (html) => call("writePage", String(html)),
    on(event, handler) {
      if (event !== "change" || typeof handler !== "function") throw Object.assign(new Error("只支持 lb.on(\"change\", 函数)。"), { code: "invalid" });
      listeners.add(handler);
      return () => listeners.delete(handler);
    },
    /** Today's date as `YYYY-MM-DD`, in local time. */
    today() {
      const d = new Date();
      return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
    },
  };

  Object.defineProperty(window, "__lbChange", {
    value(paths) {
      for (const handler of listeners) {
        try {
          const result = handler(paths);
          if (result && typeof result.catch === "function") result.catch((e) => report({ message: String(e && e.message ? e.message : e), stack: e && e.stack ? String(e.stack) : "" }));
        } catch (e) {
          report({ message: String(e && e.message ? e.message : e), stack: e && e.stack ? String(e.stack) : "" });
        }
      }
    },
  });
  Object.defineProperty(window, "lb", { value: Object.freeze(lb), enumerable: true });
})();
