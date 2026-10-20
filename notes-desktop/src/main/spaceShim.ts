// The `space` object every space homepage sees, defined in the page before its own scripts run, and
// the same object under the old app's name `lb`, kept for good. It only shapes requests and replies;
// the space page's preload carries them to main, and the core library checks and does everything.
// Ported from the old app's lb.js.
export const spaceShim = `(() => {
  "use strict";
  const bridge = window.__notesSpace;
  const call = (method, ...args) => {
    if (!bridge) return Promise.reject(Object.assign(new Error("space 接口不可用。"), { code: "failed" }));
    return bridge.call(method, args.map((a) => (a === undefined ? null : a))).then((reply) => {
      if (reply && reply.ok) return reply.result;
      const info = (reply && reply.error) || { code: "failed", message: "未知错误" };
      throw Object.assign(new Error(info.message), { code: info.code });
    });
  };
  const plain = (value) => (value && typeof value === "object" ? JSON.parse(JSON.stringify(value)) : value);
  const listeners = new Set();

  const space = {
    scope: () => call("scope"),
    notes: (folder) => call("notes", folder),
    read: (path) => call("read", path),
    tables: (path) => call("tables", path),
    async query(source, options = {}) {
      const fn = typeof options.filter === "function" ? options.filter : null;
      const request = { ...options };
      if (fn) { delete request.filter; delete request.limit; }
      const result = await call("query", source, plain(request));
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
    append(target, records, options) {
      // A new table takes its header from the fields in the order the page wrote them.
      const request = { ...(options || {}) };
      if (!request.header) {
        const header = [];
        for (const record of Array.isArray(records) ? records : [records]) {
          for (const key of Object.keys(record || {})) if (!header.includes(key)) header.push(key);
        }
        request.header = header;
      }
      return call("append", target, plain(records), plain(request));
    },
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
      if (event !== "change" || typeof handler !== "function") throw Object.assign(new Error('只支持 space.on("change", 函数)。'), { code: "invalid" });
      listeners.add(handler);
      return () => listeners.delete(handler);
    },
    /** Today's date as YYYY-MM-DD, in local time. */
    today() {
      const d = new Date();
      return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    },
  };
  if (bridge) bridge.onChange((paths) => { for (const handler of listeners) { try { handler(paths); } catch (e) { setTimeout(() => { throw e; }); } } });

  // 错误条: what goes wrong on the page reaches the app. Uncaught errors and rejections, resources that
  // fail to load (images, scripts, styles: their error events don't bubble, so they are caught on the
  // way down), and what the components report as "space:problem".
  const report = (problem) => { if (bridge) bridge.error(problem); };
  const stackOf = (error) => (error && typeof error.stack === "string" ? error.stack : "");
  window.addEventListener("error", (event) => {
    const target = event.target;
    if (target && target !== window && target.nodeType === 1) {
      const url = target.currentSrc || target.src || target.href || "";
      let shown = url;
      try { shown = decodeURI(url); } catch (_) {}
      report({ message: "资源加载失败：<" + target.localName + "> " + shown });
    } else {
      report({ message: event.message, source: event.filename, line: event.lineno, column: event.colno, stack: stackOf(event.error) });
    }
  }, true);
  window.addEventListener("unhandledrejection", (event) => {
    const reason = event.reason;
    report({ message: "未处理的 Promise 拒绝：" + (reason && reason.message ? reason.message : String(reason)), stack: stackOf(reason) });
  });
  window.addEventListener("space:problem", (event) => report({ message: String(event.detail && event.detail.message) }));
  Object.freeze(space);
  Object.defineProperty(window, "space", { value: space, enumerable: true });
  Object.defineProperty(window, "lb", { value: space, enumerable: true });
})();`;
