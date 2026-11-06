#!/usr/bin/env node
// Minimal Chrome DevTools Protocol helper for driving the VM's Chromium from a script
// or an agent. No dependencies (Node >= 22). Chromium must listen on the DevTools port
// on localhost: `chromium-cdp [url]` starts one. See docs/helper-tools.md.
//
//   cdp eval  '<js expression>'                   -> prints the JSON result
//   cdp click '<visible text>' [css]              -> real mouse click on the first
//                                                   visible element (default css:
//                                                   button,[role=menuitem],[role=option],a)
//                                                   whose text starts with <visible text>
//   cdp field '<label>' [css]                     -> clicks the first control after that label
//   cdp hover '<text>'                            -> moves the mouse over the element whose
//                                                   own text contains <text> (reveals hover menus)
//   cdp clickat <x> <y>                           -> real mouse click at page coordinates
//   cdp wheel <x> <y> <dy>                        -> mouse wheel at x,y (dy > 0 scrolls down;
//                                                   needs a visible tab, like shot)
//   cdp key <Key>                                 -> Enter, Escape, Tab, Backspace, Delete, Space,
//                                                   Arrow*, Home, End, PageUp, PageDown or one
//                                                   character; Shift+/Ctrl+/Alt+/Meta+ prefixes
//   cdp options                                   -> lists the options of an open dropdown
//   cdp upload <file> [file…]                     -> sets the files on the last input[type=file]
//                                                   (paths are on this machine; fires change)
//   cdp newline                                   -> Shift+Enter (line break where Enter sends)
//   cdp type  '<text>'                            -> inserts text into the focused field
//   cdp shot  <out.png>                           -> screenshot of the page (REDACT=sensitive|all
//                                                   runs redact-shot on it before anything else;
//                                                   CDP_CLIP="x,y,w,h" crops it)
//   cdp nav   <url>                               -> navigates without waiting for the load
//   cdp new   <url>                               -> opens a BACKGROUND tab, prints its target id
//                                                   (no focus change)
//   cdp close                                     -> closes the target (needs CDP_URL_MATCH)
//   cdp activate                                  -> brings the target to front: changes what the
//                                                   user sees, only when a screenshot needs it
//   cdp steps 'wait:1500' 'click:513,634' 'click:Save' 'type:hi' 'key:Enter' 'wheel:900,700,500'
//             'hover:Menu' 'shot:/tmp/a.png' 'eval:document.title' 'nav:https://…'
//                                                -> several steps in ONE session, viewport held
//
// Target: the first "page" whose id starts with $CDP_URL_MATCH (as printed by `cdp new`), else
// whose URL contains it, else the first page when it is unset. $CDP_PORT changes the port
// (default 9222). Every call times out after $CDP_TIMEOUT_MS (default 30000) and exits 5, so a
// hung or hidden tab cannot block a script forever. $CDP_VIEWPORT=WIDTHxHEIGHT emulates that
// viewport for the command (desktop layout in a small window; click/wheel coordinates are then
// in it) and clears it at the end.
//
// Exit codes: 1 usage, 2 no Chromium / no target, 3 not found or page error, 4 redaction
// failed (screenshot deleted), 5 timeout.

import { writeFileSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";

const [, , cmd, ...args] = process.argv;
const PORT = process.env.CDP_PORT || 9222;
const BASE = `http://127.0.0.1:${PORT}`;
const MATCH = process.env.CDP_URL_MATCH || "";
const TIMEOUT = Number(process.env.CDP_TIMEOUT_MS) || 30000;
const USAGE = "usage: cdp eval|click|field|hover|clickat|wheel|key|options|upload|newline|type|shot|nav|new|close|activate|steps (see the header of cdp.mjs)";

class Fail extends Error { constructor(msg, code = 3) { super(msg); this.code = code; } }
const sleep = ms => new Promise(r => setTimeout(r, ms));
const abs = f => (f.startsWith("/") ? f : `${process.cwd()}/${f}`);
const nums = (s, n, what) => {
  const v = String(s ?? "").split(",").map(Number);
  if (v.length !== n || v.some(x => !Number.isFinite(x))) throw new Fail(`${what}: expected ${n} numbers, got "${s ?? ""}"`, 1);
  return v;
};

async function http(path) {
  let res;
  try { res = await fetch(BASE + path, { signal: AbortSignal.timeout(TIMEOUT) }); }
  catch (e) {
    throw e.name === "TimeoutError"
      ? new Fail(`DevTools on 127.0.0.1:${PORT} did not answer in ${TIMEOUT} ms (CDP_TIMEOUT_MS to change)`, 5)
      : new Fail(`no Chromium DevTools on 127.0.0.1:${PORT} -- start one with: chromium-cdp`, 2);
  }
  const body = await res.text();
  if (!res.ok) throw new Fail(`${path}: HTTP ${res.status} ${body.trim()}`, 2);
  return body;
}

// One websocket session. Every call has its own deadline: a tab that never answers turns into
// a clear error instead of a script hanging forever.
async function connect(url) {
  const ws = new WebSocket(url);
  await new Promise((ok, ko) => {
    const t = setTimeout(() => ko(new Fail(`DevTools websocket did not open in ${TIMEOUT} ms`, 5)), TIMEOUT);
    ws.onopen = () => { clearTimeout(t); ok(); };
    ws.onerror = () => { clearTimeout(t); ko(new Fail(`cannot open the DevTools websocket ${url}`, 2)); };
  });
  let id = 0; const pending = new Map();
  ws.onmessage = m => {
    const d = JSON.parse(m.data); const p = d.id && pending.get(d.id);
    if (!p) return;
    pending.delete(d.id); clearTimeout(p.timer);
    d.error ? p.ko(new Fail(`${p.method}: ${d.error.message}`, 3)) : p.ok(d.result);
  };
  ws.onclose = () => { for (const p of pending.values()) { clearTimeout(p.timer); p.ko(new Fail("DevTools connection closed", 2)); } pending.clear(); };
  const send = (method, params = {}, { timeout = TIMEOUT, hint = "" } = {}) => new Promise((ok, ko) => {
    const i = ++id;
    const timer = setTimeout(() => {
      pending.delete(i);
      ko(new Fail(`${method} did not answer in ${timeout} ms${hint ? ` -- ${hint}` : ""} (CDP_TIMEOUT_MS to change)`, 5));
    }, timeout);
    pending.set(i, { ok, ko, timer, method });
    ws.send(JSON.stringify({ id: i, method, params }));
  });
  return { send, close: () => ws.close() };
}

async function pickPage() {
  const pages = JSON.parse(await http("/json/list")).filter(t => t.type === "page");
  const m = MATCH.toLowerCase();
  const page = (m && pages.find(t => t.id.toLowerCase().startsWith(m))) || pages.find(t => t.url.includes(MATCH));
  if (!page) throw new Fail(MATCH ? `no page matching ${MATCH}` : "no open page", 2);
  return page;
}
const browser = async () => connect(JSON.parse(await http("/json/version")).webSocketDebuggerUrl);

// Keys for `key`: [code, windowsVirtualKeyCode, text]. Enter carries "\r" so forms submit.
const KEYS = {
  Enter: ["Enter", 13, "\r"], Escape: ["Escape", 27], Tab: ["Tab", 9], Backspace: ["Backspace", 8],
  Delete: ["Delete", 46], Space: ["Space", 32, " "], ArrowUp: ["ArrowUp", 38], ArrowDown: ["ArrowDown", 40],
  ArrowLeft: ["ArrowLeft", 37], ArrowRight: ["ArrowRight", 39], Home: ["Home", 36], End: ["End", 35],
  PageUp: ["PageUp", 33], PageDown: ["PageDown", 34],
};
const MODS = { alt: 1, ctrl: 2, control: 2, meta: 4, cmd: 4, shift: 8 };

// Commands that act on a page, sharing one session (so `steps` can chain them).
function pageCommands({ send }) {
  const evaluate = async expr => {
    const r = await send("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true });
    if (r.exceptionDetails) throw new Fail(r.exceptionDetails.exception?.description || "eval error", 3);
    return r.result?.value;
  };
  const mouseClick = async (x, y) => {
    for (const type of ["mouseMoved", "mousePressed", "mouseReleased"])
      await send("Input.dispatchMouseEvent", { type, x, y, button: "left", clickCount: 1 });
  };
  const c = {
    evaluate,
    async eval([expr]) { console.log(JSON.stringify(await evaluate(expr), null, 2)); },
    async click([text, css]) { await c.find("click", text, css); },
    async field([label, css]) { await c.find("field", label, css); },
    // click: element whose text starts with a1.  field: the first control after the label a1.
    async find(kind, a1, a2) {
      const css = a2 || "button,[role=button],[role=menuitem],[role=option],[role=combobox],a";
      const rect = await evaluate(`(() => {
        const vis = e => e.checkVisibility ? e.checkVisibility() : e.getClientRects().length > 0;
        const root = [...document.querySelectorAll("[role=dialog]")].filter(vis).pop() || document;
        let el;
        if (${JSON.stringify(kind)} === "click") {
          const pick = r => [...r.querySelectorAll(${JSON.stringify(css)})]
            .find(x => vis(x) && x.innerText && x.innerText.trim().startsWith(${JSON.stringify(a1)}));
          // menus are often portalled outside the dialog: fall back to the whole page
          el = pick(root) || pick(document);
        } else {
          const label = [...root.querySelectorAll("label,span,div,p")]
            .find(x => vis(x) && x.childElementCount <= 1 && x.innerText && x.innerText.trim() === ${JSON.stringify(a1)});
          if (label) {
            const all = [...root.querySelectorAll(${JSON.stringify(css)} + ",input,textarea,[contenteditable=true]")].filter(vis);
            el = all.find(c => label.compareDocumentPosition(c) & Node.DOCUMENT_POSITION_FOLLOWING);
          }
        }
        if (!el) return null;
        el.scrollIntoView({ block: "center" });
        const r = el.getBoundingClientRect();
        return { x: r.x + r.width / 2, y: r.y + r.height / 2, text: (el.innerText || el.placeholder || el.tagName).trim().slice(0, 60) };
      })()`);
      if (!rect) throw new Fail(`not found: "${a1}"`, 3);
      await mouseClick(rect.x, rect.y);
      console.log(`clicked "${rect.text}" at ${Math.round(rect.x)},${Math.round(rect.y)}`);
    },
    async hover([text]) {
      const rect = await evaluate(`(() => {
        const el = [...document.querySelectorAll("*")]
          .filter(n => n.children.length === 0 && n.textContent.includes(${JSON.stringify(text)})).pop();
        if (!el) return null;
        el.scrollIntoView({ block: "center" });
        const r = el.getBoundingClientRect();
        return { x: r.x + Math.min(r.width / 2, 40), y: r.y + r.height / 2 };
      })()`);
      if (!rect) throw new Fail(`not found: "${text}"`, 3);
      await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: rect.x, y: rect.y });
      console.log(`hovering at ${Math.round(rect.x)},${Math.round(rect.y)}`);
    },
    async clickat([x, y]) {
      [x, y] = nums(`${x},${y}`, 2, "clickat <x> <y>");
      await mouseClick(x, y);
      console.log(`clicked at ${x},${y}`);
    },
    async wheel([x, y, dy]) {
      [x, y, dy] = nums(`${x},${y},${dy}`, 3, "wheel <x> <y> <dy>");
      // A wheel event waits for the scroll to be painted: like a screenshot, it needs a visible tab.
      const hint = "the tab is probably not visible; `cdp activate` brings it to front (changes what the user sees)";
      await send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y }, { hint });
      await send("Input.dispatchMouseEvent", { type: "mouseWheel", x, y, deltaX: 0, deltaY: dy }, { hint });
      console.log(`wheel ${dy} at ${x},${y}`);
    },
    async key([spec]) {
      if (!spec) throw new Fail("key <Key>: e.g. Enter, Escape, Tab, ArrowDown, Shift+Tab", 1);
      const parts = spec.length > 1 ? spec.split("+") : [spec]; const name = parts.pop() || "+";
      let modifiers = 0;
      for (const m of parts) {
        if (!(m.toLowerCase() in MODS)) throw new Fail(`key: unknown modifier "${m}"`, 1);
        modifiers |= MODS[m.toLowerCase()];
      }
      let code, vk, text;
      if (KEYS[name]) [code, vk, text] = KEYS[name];
      else if ([...name].length === 1) {
        const up = name.toUpperCase();
        code = /[A-Z]/.test(up) ? `Key${up}` : /[0-9]/.test(name) ? `Digit${name}` : "";
        vk = up.charCodeAt(0); text = name;
      } else throw new Fail(`key: unknown key "${name}" (Enter, Escape, Tab, Backspace, Delete, Space, Arrow*, Home, End, PageUp, PageDown, or one character)`, 1);
      // Text only without Ctrl/Alt/Meta: Ctrl+A is a shortcut, not an "a".
      if (modifiers & 7) text = undefined;
      const k = { key: KEYS[name] ? (name === "Space" ? " " : name) : name, code, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk, modifiers };
      await send("Input.dispatchKeyEvent", { type: text ? "keyDown" : "rawKeyDown", ...k, ...(text && { text, unmodifiedText: text }) });
      await send("Input.dispatchKeyEvent", { type: "keyUp", ...k });
      console.log(`key ${spec}`);
    },
    async upload(files) {
      files = files.map(abs);
      if (!files.length) throw new Fail("upload <file> [file…]", 1);
      const doc = await send("DOM.getDocument", { depth: 0 });
      const q = await send("DOM.querySelectorAll", { nodeId: doc.root.nodeId, selector: "input[type=file]" });
      const ids = q.nodeIds || [];
      if (!ids.length) throw new Fail("no input[type=file] on the page", 3);
      await send("DOM.setFileInputFiles", { nodeId: ids[ids.length - 1], files });
      console.log(`uploaded ${files.length} file(s) to input ${ids.length}/${ids.length}`);
    },
    async options() {
      const opts = await evaluate(`[...document.querySelectorAll("[role=option],[role=menuitem],[role=menuitemradio],[role=listbox] li")]
        .filter(e => e.checkVisibility ? e.checkVisibility() : e.getClientRects().length > 0)
        .map(e => e.innerText.trim()).filter(Boolean)`);
      console.log(JSON.stringify(opts, null, 2));
    },
    async newline() {
      // Shift+Enter: a line break in chat composers where Enter sends.
      const k = { key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, modifiers: 8 };
      await send("Input.dispatchKeyEvent", { type: "keyDown", ...k });
      await send("Input.dispatchKeyEvent", { type: "keyUp", ...k });
      console.log("shift+enter");
    },
    async type([text = ""]) {
      await send("Input.insertText", { text });
      console.log(`typed ${text.length} chars`);
    },
    async shot([out]) {
      if (!out) throw new Fail("shot <out.png>", 1);
      const params = { format: "png" };
      if (process.env.CDP_CLIP) {
        const [x, y, width, height] = nums(process.env.CDP_CLIP, 4, "CDP_CLIP=x,y,w,h");
        params.clip = { x, y, width, height, scale: 1 };
      }
      // Chromium only paints visible tabs, and captureScreenshot waits for a frame that never
      // comes for a background tab or a minimised window.
      const r = await send("Page.captureScreenshot", params, {
        hint: "the tab is probably not visible (background tab or minimised window); `cdp activate` brings it to front (changes what the user sees), or make it visible and retry",
      });
      writeFileSync(out, Buffer.from(r.data, "base64"));
      // REDACT=sensitive|all pixelates text in place before anything else touches the file
      // (redact-shot, docs/redact-shot.md). Without redact-shot the screenshot is deleted.
      if (process.env.REDACT) {
        const flags = process.env.REDACT === "all" ? ["--all"] : [];
        try { console.log(execFileSync("redact-shot", [out, ...flags], { encoding: "utf8" }).trim()); }
        catch (e) {
          rmSync(out, { force: true });
          throw new Fail(e.code === "ENOENT" ? "REDACT set but redact-shot is not installed; screenshot deleted" : `${e.message}; screenshot deleted`, 4);
        }
      }
      console.log(`saved ${out}`);
    },
    async nav([url]) {
      if (!url) throw new Fail("nav <url>", 1);
      // Page.navigate answers on commit, and a hash-only change in a single-page app may never
      // answer at all: give it a moment, then carry on either way.
      const reply = send("Page.navigate", { url }).catch(e => e);
      const r = await Promise.race([reply, sleep(Math.min(2000, TIMEOUT)).then(() => null)]);
      if (r instanceof Error) throw r;
      if (r?.errorText) throw new Fail(`nav ${url}: ${r.errorText}`, 3);
      console.log(r ? `navigated to ${url}` : `navigating to ${url} (not waited for)`);
    },
    async wait([ms]) {
      const n = Number(ms);
      if (!Number.isFinite(n) || n < 0) throw new Fail(`wait: "${ms}" is not milliseconds`, 1);
      await sleep(n);
    },
  };
  // steps: "name:argument". click takes x,y or a visible text; wheel x,y,dy; the rest one value.
  c.steps = async list => {
    if (!list.length) throw new Fail("steps 'wait:1500' 'click:513,634' 'type:hello' 'key:Enter' …", 1);
    for (const step of list) {
      const i = step.indexOf(":");
      const name = i < 0 ? step : step.slice(0, i), arg = i < 0 ? undefined : step.slice(i + 1);
      if (name === "click" && /^\s*-?[\d.]+\s*,\s*-?[\d.]+\s*$/.test(arg)) await c.clickat(arg.split(","));
      else if (name === "wheel") await c.wheel(String(arg ?? "").split(","));
      else if (["eval", "click", "field", "hover", "key", "type", "shot", "nav", "wait", "upload", "options", "newline"].includes(name))
        await c[name](arg === undefined ? [] : [arg]);
      else throw new Fail(`steps: unknown step "${step}"`, 1);
    }
  };
  return c;
}

const PAGE_CMDS = ["eval", "click", "field", "hover", "clickat", "wheel", "key", "options", "upload", "newline", "type", "shot", "nav", "steps"];

async function main() {
  if (cmd === "new") {
    if (!args[0]) throw new Fail("new <url>", 1);
    const b = await browser();
    try {
      // background: true opens the tab behind the current one; the user's focus stays put.
      const r = await b.send("Target.createTarget", { url: args[0], background: true });
      console.log(r.targetId);
    } finally { b.close(); }
  } else if (cmd === "close") {
    // Never "the first page": that may be the tab the user is reading.
    if (!MATCH) throw new Fail("close needs CDP_URL_MATCH (a target id from `cdp new`, or part of the URL)", 1);
    const page = await pickPage(); const b = await browser();
    try { await b.send("Target.closeTarget", { targetId: page.id }); console.log(`closed ${page.id}`); }
    finally { b.close(); }
  } else if (cmd === "activate") {
    const page = await pickPage();
    await http(`/json/activate/${page.id}`);
    console.log(`activated ${page.id}`);
  } else if (PAGE_CMDS.includes(cmd)) {
    const page = await pickPage();
    const s = await connect(page.webSocketDebuggerUrl);
    const c = pageCommands(s);
    let viewport = false;
    try {
      if (process.env.CDP_VIEWPORT) {
        const m = /^(\d+)x(\d+)$/.exec(process.env.CDP_VIEWPORT);
        if (!m) throw new Fail(`CDP_VIEWPORT must be WIDTHxHEIGHT, got "${process.env.CDP_VIEWPORT}"`, 1);
        await s.send("Emulation.setDeviceMetricsOverride", { width: +m[1], height: +m[2], deviceScaleFactor: 1, mobile: false });
        viewport = true;
        await c.evaluate("window.dispatchEvent(new Event('resize'))");
      }
      await c[cmd](args);
    } finally {
      if (viewport) {
        const quick = { timeout: Math.min(TIMEOUT, 5000) };
        try {
          await s.send("Emulation.clearDeviceMetricsOverride", {}, quick);
          await s.send("Runtime.evaluate", { expression: "window.dispatchEvent(new Event('resize'))" }, quick);
        } catch (e) { console.error(`warning: could not clear CDP_VIEWPORT: ${e.message}`); }
      }
      s.close();
    }
  } else {
    throw new Fail(USAGE, 1);
  }
}

let code = 0;
try { await main(); }
catch (e) { console.error(e instanceof Fail ? e.message : (e.stack || String(e))); code = e instanceof Fail ? e.code : 1; }
// Explicit: a navigate left unanswered on purpose must not keep the process alive.
process.exit(code);
