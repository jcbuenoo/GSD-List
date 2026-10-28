// Draws the layouts exported by tests/layout_export.lua in Chromium, saves a
// screenshot per tab and checks for clipped text, overlaps and out-of-window elements.
// Usage: node tests/render_layout.js <dir with layout-*.json>
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const dir = process.argv[2];
const files = fs.readdirSync(dir).filter(f => /^layout-.*\.json$/.test(f)).sort();

const page_html = (items) => `<!doctype html><html><head><meta charset="utf-8"><style>
body{margin:0;width:1920px;height:1080px;background:#1d2a1d;position:relative;overflow:hidden;
  font-family:"DejaVu Sans",Verdana,sans-serif}
.e{position:absolute;box-sizing:border-box}
.Frame.backdrop{background:rgba(10,10,14,.92);border:3px solid #8a7a52;border-radius:6px}
.Button{background:linear-gradient(#a8261b,#5c0e08);border:1px solid #c9a227;border-radius:3px;color:#ffd200;
  font-size:11px;display:flex;align-items:center;justify-content:center;white-space:nowrap;overflow:hidden}
.Button.locked{background:linear-gradient(#e0442f,#8f1a10)}
.Button.row,.Button.plain{background:none;border:none}
.CheckButton{border:2px solid #aaa;background:#222;border-radius:3px;color:#ffd200;font-size:18px;line-height:18px;text-align:center}
.EditBox{background:#0b0b0b;border:1px solid #777;color:#fff;font-size:11px;padding:2px 5px;white-space:nowrap;overflow:hidden}
.Slider{background:#2b2b2b;border-left:1px solid #555}
.FontString{color:#ffd200;line-height:1.15}
.FontString.white{color:#fff}
.FontString.nowrap{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.Texture.icon{background:#3a3a50;border:1px solid #666}
</style></head><body>${items}</body></html>`;

// WoW colour codes -> spans
function colorize(text) {
  const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  let out = '', open = 0;
  const re = /\|c([0-9a-fA-F]{8})|\|r|\|H.*?\|h(.*?)\|h|\n/g;
  let last = 0, m;
  while ((m = re.exec(text))) {
    out += esc(text.slice(last, m.index));
    if (m[0] === '\n') out += '<br>';
    else if (m[0] === '|r') { if (open) { out += '</span>'; open--; } }
    else if (m[1]) { out += `<span style="color:#${m[1].slice(2)}">`; open++; }
    else out += esc(m[2]);
    last = re.lastIndex;
  }
  out += esc(text.slice(last));
  while (open--) out += '</span>';
  return out;
}

const WHITE_FONTS = /Highlight/;

function render(items) {
  const byId = {};
  items.forEach(e => (byId[e.id] = e));
  return items.map(e => {
    if (e.name === 'UIParent') return '';
    const cls = ['e', e.kind];
    let inner = '', style = `left:${e.x}px;top:${e.y}px;width:${e.w}px;height:${e.h}px;`;
    if (e.backdrop) cls.push('backdrop');
    if (e.kind === 'Frame' && e.name === 'AuctionFrame') style += 'background:#3b2a14;border:3px solid #6b5426;';
    if (e.kind === 'Button') {
      if (e.locked) cls.push('locked');
      if (e.text === undefined) cls.push('plain');
      inner = colorize(e.text || '');
    }
    if (e.kind === 'CheckButton') inner = e.checked ? '&#10003;' : '';
    if (e.kind === 'EditBox') {
      inner = colorize(e.text || '');
      if (e.multi) style += 'white-space:pre;overflow:hidden;font-family:monospace;height:auto;';
    }
    if (e.name === 'Minimap') style += 'border-radius:50%;background:#2a4a2a;border:3px solid #777;';
    if (e.kind === 'Texture') {
      if (e.color) style += `background:rgba(${e.color.slice(0, 3).map(c => Math.round(c * 255)).join(',')},${e.color[3]});`;
      else if (e.texture) cls.push('icon');
      else return '';
    }
    if (e.kind === 'FontString') {
      if (!e.text) return '';
      if (WHITE_FONTS.test(e.font || '')) cls.push('white');
      if (/Disable/.test(e.font || '')) style += 'color:#808080;';
      if (e.fixedWidth && !e.wrap) cls.push('nowrap');
      style += `font-size:${e.size}px;text-align:${(e.justify || 'CENTER').toLowerCase()};`;
      // WoW lays text out from the anchor; let it overflow downward like the client does
      style += 'height:auto;min-height:' + e.h + 'px;';
      if (!e.fixedWidth) style += 'width:auto;white-space:nowrap;';
      inner = colorize(e.text);
    }
    if (e.kind === 'Frame' && !e.backdrop && e.name !== 'AuctionFrame') style += 'pointer-events:none;';
    return `<div class="${cls.join(' ')}" data-id="${e.id}" style="${style}">${inner}</div>`;
  }).join('\n');
}

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  const report = {};
  for (const f of files) {
    const items = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    await page.setContent(page_html(render(items)));
    const result = await page.evaluate((items) => {
      const byId = {};
      items.forEach(e => (byId[e.id] = e));
      const ancestor = (a, b) => { for (let p = byId[b.parent]; p; p = byId[p.parent]) if (p === a) return true; return false; };
      const win = items.find(e => e.name === 'MarketIntelExportFrame') || items.find(e => e.name === 'MarketIntelFrame');
      const inWindow = e => { for (let p = e; p; p = byId[p.parent]) if (p === win) return true; return false; };
      const box = el => { const r = el.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; };
      // actual rendered extent of a text element (not its box)
      const textBox = el => {
        const range = document.createRange(); range.selectNodeContents(el);
        const r = range.getBoundingClientRect();
        if (r.width === 0) return null;
        const outer = el.getBoundingClientRect();
        const clipped = el.classList.contains('nowrap');
        return clipped ? { x: Math.max(r.left, outer.left), y: r.top, w: Math.min(r.right, outer.right) - Math.max(r.left, outer.left), h: r.height }
                       : { x: r.left, y: r.top, w: r.width, h: r.height };
      };
      const overlap = (a, b) => a.x < b.x + b.w - 1 && b.x < a.x + a.w - 1 && a.y < b.y + b.h - 1 && b.y < a.y + a.h - 1;
      const issues = { truncated: [], overlaps: [], outside: [] };
      const nodes = [];
      for (const el of document.querySelectorAll('.e')) {
        const e = byId[+el.dataset.id];
        if (!inWindow(e) || e === win) continue;
        if (e.kind === 'FontString' && el.classList.contains('nowrap') && el.scrollWidth > el.clientWidth + 1) {
          issues.truncated.push({ text: el.textContent, width: Math.round(el.clientWidth), needs: el.scrollWidth });
        }
        const isText = e.kind === 'FontString';
        const isControl = ['Button', 'EditBox', 'CheckButton'].includes(e.kind) && !el.classList.contains('plain');
        if (!isText && !isControl) continue;
        const b = isText ? textBox(el) : box(el);
        if (!b) continue;
        nodes.push({ e, b, label: isText ? el.textContent.slice(0, 40) : `[${e.kind} ${e.text || ''}]` });
        const wb = { x: win.x + 8, y: win.y + 8, w: win.w - 16, h: win.h - 16 };
        if (e.multi) continue;
        if (b.x < wb.x - 0.5 || b.y < wb.y - 0.5 || b.x + b.w > wb.x + wb.w + 0.5 || b.y + b.h > wb.y + wb.h + 0.5) {
          issues.outside.push(nodes[nodes.length - 1].label);
        }
      }
      for (let i = 0; i < nodes.length; i++) for (let j = i + 1; j < nodes.length; j++) {
        const a = nodes[i], b = nodes[j];
        if (ancestor(a.e, b.e) || ancestor(b.e, a.e)) continue;
        if (overlap(a.b, b.b)) issues.overlaps.push(`${a.label}  <->  ${b.label}`);
      }
      return { issues, win: { x: win.x, y: win.y, w: win.w, h: win.h } };
    }, items);
    const name = f.replace(/^layout-|\.json$/g, '');
    await page.screenshot({ path: path.join(dir, `tab-${name}.png`),
      clip: { x: result.win.x - 10, y: result.win.y - 10, width: result.win.w + 140, height: result.win.h + 20 } });
    if (name === 'deals' || name === 'resized') await page.screenshot({ path: path.join(dir, name + '-full.png') });
    report[name] = result.issues;
  }
  await browser.close();
  console.log(JSON.stringify(report, null, 1));
})();
