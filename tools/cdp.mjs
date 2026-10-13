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
//   cdp options                                   -> lists the options of an open dropdown
//   cdp upload <file> [file…]                     -> sets the files on the last input[type=file]
//                                                   (paths are on this machine; fires change)
//   cdp newline                                   -> Shift+Enter (line break where Enter sends)
//   cdp type  '<text>'                            -> inserts text into the focused field
//   cdp shot  <out.png>                           -> screenshot of the page (REDACT=sensitive|all
//                                                   runs redact-shot on it before anything else)
//
// Target: the first "page" whose URL contains $CDP_URL_MATCH, or the first page when it is
// unset. $CDP_PORT changes the port (default 9222).

const [, , cmd, a1, a2] = process.argv;
const require_path = f => (f.startsWith("/") ? f : `${process.cwd()}/${f}`);
const PORT = process.env.CDP_PORT || 9222;
const MATCH = process.env.CDP_URL_MATCH || "";

let targets;
try { targets = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json(); }
catch { console.error(`no Chromium DevTools on 127.0.0.1:${PORT} -- start one with: chromium-cdp`); process.exit(2); }
const page = targets.find(t => t.type === "page" && t.url.includes(MATCH));
if (!page) { console.error(MATCH ? `no page matching ${MATCH}` : "no open page"); process.exit(2); }

const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((ok, ko) => { ws.onopen = ok; ws.onerror = ko; });
let id = 0; const pending = new Map();
ws.onmessage = m => { const d = JSON.parse(m.data); if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); } };
const send = (method, params = {}) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const evaluate = async expr => {
  const r = await send("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true });
  if (r.result?.exceptionDetails) throw new Error(r.result.exceptionDetails.exception?.description || "eval error");
  return r.result?.result?.value;
};

try {
  if (cmd === "eval") {
    console.log(JSON.stringify(await evaluate(a1), null, 2));
  } else if (cmd === "click" || cmd === "field") {
    // click: element whose text starts with a1.  field: the first control after the label a1.
    const css = a2 || "button,[role=button],[role=menuitem],[role=option],[role=combobox],a";
    const rect = await evaluate(`(() => {
      const vis = e => e.checkVisibility ? e.checkVisibility() : e.getClientRects().length > 0;
      const root = [...document.querySelectorAll("[role=dialog]")].filter(vis).pop() || document;
      let el;
      if (${JSON.stringify(cmd)} === "click") {
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
    if (!rect) { console.error(`not found: "${a1}"`); process.exit(3); }
    for (const type of ["mouseMoved", "mousePressed", "mouseReleased"])
      await send("Input.dispatchMouseEvent", { type, x: rect.x, y: rect.y, button: "left", clickCount: 1 });
    console.log(`clicked "${rect.text}" at ${Math.round(rect.x)},${Math.round(rect.y)}`);
  } else if (cmd === "hover") {
    const rect = await evaluate(`(() => {
      const el = [...document.querySelectorAll("*")]
        .filter(n => n.children.length === 0 && n.textContent.includes(${JSON.stringify(a1)})).pop();
      if (!el) return null;
      el.scrollIntoView({ block: "center" });
      const r = el.getBoundingClientRect();
      return { x: r.x + Math.min(r.width / 2, 40), y: r.y + r.height / 2 };
    })()`);
    if (!rect) { console.error(`not found: "${a1}"`); process.exit(3); }
    await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: rect.x, y: rect.y });
    console.log(`hovering at ${Math.round(rect.x)},${Math.round(rect.y)}`);
  } else if (cmd === "clickat") {
    const x = Number(a1), y = Number(a2);
    for (const type of ["mouseMoved", "mousePressed", "mouseReleased"])
      await send("Input.dispatchMouseEvent", { type, x, y, button: "left", clickCount: 1 });
    console.log(`clicked at ${x},${y}`);
  } else if (cmd === "upload") {
    const files = process.argv.slice(3).map(f => (require_path(f)));
    const doc = await send("DOM.getDocument", { depth: 0 });
    const q = await send("DOM.querySelectorAll", { nodeId: doc.result.root.nodeId, selector: "input[type=file]" });
    const ids = q.result?.nodeIds || [];
    if (!ids.length) { console.error("no input[type=file] on the page"); process.exit(3); }
    await send("DOM.setFileInputFiles", { nodeId: ids[ids.length - 1], files });
    console.log(`uploaded ${files.length} file(s) to input ${ids.length}/${ids.length}`);
  } else if (cmd === "options") {
    const opts = await evaluate(`[...document.querySelectorAll("[role=option],[role=menuitem],[role=menuitemradio],[role=listbox] li")]
      .filter(e => e.checkVisibility ? e.checkVisibility() : e.getClientRects().length > 0)
      .map(e => e.innerText.trim()).filter(Boolean)`);
    console.log(JSON.stringify(opts, null, 2));
  } else if (cmd === "newline") {
    // Shift+Enter: a line break in chat composers where Enter sends.
    const k = { key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, modifiers: 8 };
    await send("Input.dispatchKeyEvent", { type: "keyDown", ...k });
    await send("Input.dispatchKeyEvent", { type: "keyUp", ...k });
    console.log("shift+enter");
  } else if (cmd === "type") {
    await send("Input.insertText", { text: a1 });
    console.log(`typed ${a1.length} chars`);
  } else if (cmd === "shot") {
    const r = await send("Page.captureScreenshot", { format: "png" });
    (await import("node:fs")).writeFileSync(a1, Buffer.from(r.result.data, "base64"));
    // REDACT=sensitive|all pixelates text in place before anything else touches the file
    // (redact-shot, docs/redact-shot.md). Without redact-shot the screenshot is deleted.
    if (process.env.REDACT) {
      const { execFileSync } = await import("node:child_process");
      const flags = process.env.REDACT === "all" ? ["--all"] : [];
      try { console.log(execFileSync("redact-shot", [a1, ...flags], { encoding: "utf8" }).trim()); }
      catch (e) {
        (await import("node:fs")).rmSync(a1, { force: true });
        console.error(e.code === "ENOENT" ? "REDACT set but redact-shot is not installed; screenshot deleted" : e.message);
        process.exit(4);
      }
    }
    console.log(`saved ${a1}`);
  } else {
    console.error("usage: eval|click|field|hover|clickat|options|upload|newline|type|shot"); process.exit(1);
  }
} finally { ws.close(); }
