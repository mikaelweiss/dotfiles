import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, dirname, basename, join } from 'node:path';
import { createRequire } from 'node:module';
import { homedir } from 'node:os';
import { pathToFileURL } from 'node:url';

const [, , input] = process.argv;
if (!input) { console.error('usage: node render.mjs <brief.json>'); process.exit(2); }
const brief = JSON.parse(readFileSync(input, 'utf8'));
const outDir = dirname(resolve(input));
const stem = basename(input).replace(/\.json$/, '');
const isReview = brief.mode === 'review';
const findings = brief.findings || { blockers: [], nonBlockers: [] };

const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const riskName = { low: 'Low', med: 'Medium', high: 'High' };
const bars = { low: 1, med: 2, high: 3 };
const prioIcon = (r) => `<svg class="prio" width="16" height="16" viewBox="0 0 16 16"><rect x="1.5" y="8" width="3" height="6" rx="1" class="${bars[r] >= 1 ? 'on' : ''}"/><rect x="6.5" y="5" width="3" height="9" rx="1" class="${bars[r] >= 2 ? 'on' : ''}"/><rect x="11.5" y="2" width="3" height="12" rx="1" class="${bars[r] >= 3 ? 'on' : ''}"/></svg>`;
const chip = (inner, cls = '') => `<span class="chip ${cls}">${inner}</span>`;
const chevron = '<button class="more" type="button" aria-label="Details"><svg width="16" height="16" viewBox="0 0 16 16"><path d="M6 4l4 4-4 4" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg></button>';

const behaviors = brief.behaviors || [];
const questions = brief.questions || [];
const changedFiles = brief.changed_files || [];
let n = 0;

const status = (id) => isReview ? '' : `<label class="status" title="Approve"><input type="checkbox" id="ok-${id}" data-id="${id}"><svg width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.5" class="ring"/><circle cx="8" cy="8" r="6.5" class="fill"/><path d="M5 8.3l2 2 4-4.6" class="tick"/></svg></label>`;
const fileSpan = ([kind, path]) => `<span class="file"><span class="fk fk-${kind}">${kind === 'create' ? '+' : '~'}</span>${esc(path)}</span>`;
const fileLine = (files) => files.length ? `<div class="files">${files.map(fileSpan).join('')}</div>` : '';
const testChip = (t) => {
  if (t === null || t === undefined) return chip('<i class="dot-yellow"></i>No test');
  if (typeof t === 'string') return chip(`<i class="dot-green"></i>${esc(t)}`);
  if (t.gap) return chip('<i class="dot-red"></i>No test', 'chip-bad');
  return '';
};
const detail = (id, text) => `
  <div class="detail" id="detail-${id}" hidden>
    ${text ? `<p>${esc(text)}</p>` : ''}
    ${isReview ? '' : `<textarea id="txt-${id}" data-id="${id}" rows="2" placeholder="Note on ${id}…"></textarea>`}
  </div>`;

const behaviorRows = behaviors.map((b) => {
  const id = ++n;
  const verify = isReview ? chip(`<i class="${b.verified ? 'dot-green' : 'dot-red'}"></i>${esc(b.verified || 'Not verified')}`, b.verified ? '' : 'chip-bad') : '';
  return `
  <li class="row" data-row="${id}">
    <div class="head">
      <div class="line">
        <span class="key">${id}</span>
        ${status(id)}
        <div class="main"><span class="before">${esc(b.before)}</span><span class="arrow">→</span><span class="after">${esc(b.after)}</span></div>
        <div class="props">${verify}${isReview ? '' : testChip(b.test)}${chip(prioIcon(b.risk))}${chevron}</div>
      </div>
      ${fileLine(b.files || [])}
    </div>
    ${detail(id, b.detail)}
  </li>`;
}).join('');

const questionRows = questions.map((q) => {
  const id = ++n;
  const opts = (q.options || []).map((o, i) => {
    const letter = String.fromCharCode(97 + i);
    const rec = o === q.recommend;
    return `<label class="opt"><input type="radio" name="q-${id}" value="${letter}" data-id="${id}" ${rec ? 'checked' : ''}><span class="opt-l">${letter}</span><span>${esc(o)}${rec ? '<em>recommended</em>' : ''}</span></label>`;
  }).join('');
  return `
  <li class="row static" data-row="${id}">
    <div class="line">
      <span class="key">${id}</span>
      <div class="main wrap"><span class="after">${esc(q.q)}</span></div>
    </div>
    ${q.detail ? `<p class="qdetail">${esc(q.detail)}</p>` : ''}
    <div class="opts">${opts}</div>
    ${isReview ? '' : `<div class="qnote"><textarea id="txt-${id}" data-id="${id}" rows="1" placeholder="Or type what you want instead…"></textarea></div>`}
  </li>`;
}).join('');

const referenced = new Set([
  ...behaviors.flatMap((b) => (b.files || []).map(([, p]) => p)),
  ...((brief.map?.nodes || []).flatMap((x) => x.files || [])),
]);
const explained = (path) => [...referenced].some((r) => path === r || path.endsWith('/' + r) || r.endsWith('/' + path));
const unexplained = changedFiles.filter(([, p]) => !explained(p));
const ledgerRows = unexplained.map((f) => {
  const id = ++n;
  return `
  <li class="row" data-row="${id}">
    <div class="head"><div class="line">
      <span class="key">${id}</span>
      ${status(id)}
      <div class="main">${fileSpan(f)}</div>
      <div class="props">${chip('<i class="dot-red"></i>Not explained', 'chip-bad')}${chevron}</div>
    </div></div>
    ${detail(id, 'No behavior line or map node names this file. Tick to accept it as is, or say what it is for.')}
  </li>`;
}).join('');

const group = (title, count, body) => `
  <section class="group" data-group="${title.replace(/\W+/g, '-').toLowerCase()}">
    <header tabindex="0"><svg width="10" height="10" viewBox="0 0 10 10"><path d="M2 3.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg><span class="gtitle">${title}</span><span class="gcount">${count}</span></header>
    <div class="gbody">${body.trim().startsWith('<li') ? `<ul>${body}</ul>` : body}</div>
  </section>`;

const fileCount = changedFiles.length || referenced.size;
const riskCounts = ['high', 'med', 'low'].map((r) => [r, behaviors.filter((b) => b.risk === r).length]).filter(([, c]) => c);
const flowRows = (brief.flows || []).map((f, i) => {
  const id = 'flow-' + i;
  const body = f.steps?.length
    ? `<ol class="steps">${f.steps.map((st) => `<li>${esc(st)}</li>`).join('')}</ol>`
    : `<p>${esc(f.effect || '')}</p>`;
  return `
  <li class="row" data-row="${id}">
    <div class="head"><div class="line">
      <span class="key"></span>
      <div class="main"><span class="after">${esc(f.name)}</span></div>
      <div class="props">${(f.items || []).map((x) => chip(String(x))).join('')}${chevron}</div>
    </div></div>
    <div class="detail" id="detail-${id}" hidden>${body}</div>
  </li>`;
}).join('');
const touchedRows = (brief.touched || []).map((t) => `<li class="prop"><svg class="ico" viewBox="0 0 16 16"><path d="M2 4a1 1 0 0 1 1-1h3l2 2h5a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/></svg><span class="prop-v">${esc(t.name)}</span><span class="prop-n">${t.files === 1 ? '1 file' : t.files + ' files'}</span></li>`).join('');

const mapSvg = (m) => {
  if (!m || !m.nodes?.length) return '';
  const layers = m.layers || [...new Set(m.nodes.map((x) => x.layer))];
  const W = 184, GAP = 72, PAD = 12, LINE = 17, HEAD = 34, VGAP = 18, TOP = 28;
  const pos = new Map();
  let maxH = 0;
  layers.forEach((l, ci) => {
    let y = TOP;
    m.nodes.filter((x) => x.layer === l).forEach((x) => {
      const h = HEAD + (x.files?.length ? x.files.length * LINE + PAD : 0);
      pos.set(x.id, { x: ci * (W + GAP), y, w: W, h, node: x });
      y += h + VGAP;
    });
    maxH = Math.max(maxH, y);
  });
  const colOf = (id) => layers.indexOf(pos.get(id).node.layer);
  const colBottom = layers.map((l) => Math.max(TOP, ...m.nodes.filter((x) => x.layer === l).map((x) => pos.get(x.id).y + pos.get(x.id).h)));
  const edges = (m.edges || []).filter((e) => pos.has(e.from) && pos.has(e.to));
  const outs = new Map(), ins = new Map();
  edges.forEach((e) => { outs.set(e.from, [...(outs.get(e.from) || []), e]); ins.set(e.to, [...(ins.get(e.to) || []), e]); });
  const slot = (list, e, box) => box.y + box.h * (list.indexOf(e) + 1) / (list.length + 1);
  const longEdges = edges.filter((e) => colOf(e.to) - colOf(e.from) > 1);
  const busOf = (e) => Math.max(...colBottom.slice(colOf(e.from) + 1, colOf(e.to))) + 24 + longEdges.indexOf(e) * 14;
  const edgeSvg = edges.map((e) => {
    const a = pos.get(e.from), b = pos.get(e.to);
    const y1 = slot(outs.get(e.from), e, a), y2 = slot(ins.get(e.to), e, b);
    const x1 = a.x + a.w, x2 = b.x;
    const ca = colOf(e.from), cb = colOf(e.to);
    let d;
    if (cb - ca === 1) {
      const c = (x2 - x1) / 2;
      d = `M${x1},${y1} C${x1 + c},${y1} ${x2 - c},${y2} ${x2},${y2}`;
    } else if (cb > ca) {
      const bus = busOf(e), xm1 = x1 + GAP / 2, xm2 = x2 - GAP / 2;
      d = `M${x1},${y1} C${xm1},${y1} ${xm1},${bus} ${xm1 + 24},${bus} L${xm2 - 24},${bus} C${xm2},${bus} ${xm2},${y2} ${x2},${y2}`;
    } else {
      const sx = a.x + a.w / 2, sy = a.y + a.h, tx = b.x + b.w / 2, ty = b.y;
      d = `M${sx},${sy} C${sx},${sy + 30} ${tx},${ty - 30} ${tx},${ty}`;
    }
    const label = e.label ? `<text class="elabel elabel-${e.kind}" x="${x1 + 8}" y="${y1 - 5}">${esc(e.label)}</text>` : '';
    return `<path class="edge edge-${e.kind}" d="${d}" marker-end="url(#arrow-${e.kind})"/>${label}`;
  }).join('');
  maxH = Math.max(maxH, ...longEdges.map((e) => busOf(e) + 8));
  const nodeSvg = [...pos.values()].map(({ x, y, w, h, node }) => {
    const cls = node.changed ? `node changed-${node.changed}` : 'node';
    const files = (node.files || []).map((f, i) => `<text class="file" x="${x + PAD}" y="${y + HEAD + i * LINE + 4}">${esc(f)}</text>`).join('');
    const badge = node.changed ? `<text class="badge badge-${node.changed}" x="${x + w - PAD}" y="${y + 21}" text-anchor="end">${node.changed === 'create' ? 'new' : 'edited'}</text>` : '';
    return `<g class="${cls}"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="6"/><text class="name" x="${x + PAD}" y="${y + 21}">${esc(node.name)}</text>${badge}${files}</g>`;
  }).join('');
  const width = layers.length * W + (layers.length - 1) * GAP;
  const layerSvg = layers.map((l, i) => `<text class="layer" x="${i * (W + GAP)}" y="14">${esc(l)}</text>`).join('');
  const marker = (k, c) => `<marker id="arrow-${k}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="${c}"/></marker>`;
  return `<div class="map"><svg viewBox="-2 0 ${width + 4} ${maxH}" width="100%" style="max-width:${width + 4}px;height:auto"><defs>${marker('new', '#27a644')}${marker('existing', '#62666d')}${marker('removed', '#eb5757')}</defs>${layerSvg}${edgeSvg}${nodeSvg}</svg></div>`;
};

const findingRows = (list, cls) => list.map((f) => `<li class="row static"><div class="line"><span class="key"></span><div class="main"><span class="after">${esc(f)}</span></div>${cls ? `<div class="props">${chip('<i class="dot-red"></i>Blocker', 'chip-bad')}</div>` : ''}</div></li>`).join('');
const findingsBlock = isReview && (findings.blockers.length || findings.nonBlockers.length)
  ? group('Blockers', findings.blockers.length, findingRows(findings.blockers, true) || '<p class="qdetail">None</p>') + group('Non-blockers', findings.nonBlockers.length, findingRows(findings.nonBlockers, false) || '<p class="qdetail">None</p>')
  : (isReview ? group('Blockers', 0, '<p class="qdetail">None. Nothing stops this from merging.</p>') : '');

const deltaBlock = brief.delta?.length
  ? group('Changed since the proposal', brief.delta.length, brief.delta.map((d) => `<li class="row static"><div class="line">${chip(`<i class="dot-${{ added: 'green', dropped: 'red', changed: 'yellow' }[d.kind]}"></i>${d.kind}`)}<div class="main wrap">${esc(d.text)}</div></div></li>`).join(''))
  : '';

const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(brief.title)}</title>
<style>
@font-face{font-family:"Inter Variable";font-weight:100 900;font-display:swap;font-style:normal;src:url(https://static.linear.app/fonts/InterVariable.woff2?v=4.1) format("woff2")}
@font-face{font-family:"Berkeley Mono";font-weight:100 900;font-display:swap;src:url(https://static.linear.app/fonts/Berkeley-Mono-Variable.woff2?v=3.2) format("woff2")}
:root{--font:"Inter Variable","SF Pro Display",-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;--mono:"Berkeley Mono",ui-monospace,"SF Mono",Menlo,monospace;
--window:#09090a;--pane:#121213;--card:#1a1a1b;--raised:#232325;--hover:#1a1a1b;--code:#242425;--line:#1f1f21;--chip-border:#2a2a2c;
--text:#f7f8f8;--text-2:#d0d6e0;--text-3:#8a8f98;--text-4:#62666d;--green:#27a644;--red:#eb5757;--yellow:#f0bf00;--blue:#4ea7fc}
*{box-sizing:border-box}
html{background:var(--window)}
body{margin:0;background:var(--window);color:var(--text);font:400 15px/1.6 var(--font);letter-spacing:-.011em;font-feature-settings:"cv01","ss03";-webkit-font-smoothing:antialiased;padding:8px}
.pane{background:var(--pane);border-radius:8px;min-height:calc(100vh - 16px)}
.top{height:48px;display:flex;align-items:center;justify-content:space-between;padding:0 24px;font-size:13px;color:var(--text-3)}
.crumb{display:flex;align-items:center;gap:10px}.crumb .cur{color:var(--text)}.crumb .sep{color:var(--text-4)}
.pill{height:28px;padding:0 12px;border-radius:9999px;border:0;background:var(--raised);color:var(--text);font:510 13px/1 var(--font);display:inline-flex;align-items:center;gap:6px;cursor:pointer}
.pill:hover{background:#2a2a2c}
.body{display:flex;gap:48px;padding:40px 56px 64px 84px}
.main-col{flex:1;min-width:0;max-width:900px}
.rail{width:300px;flex:none;padding-top:6px}
h1{font:590 24px/1.35 var(--font);letter-spacing:-.012em;margin:0 0 14px}
.lede{color:var(--text-2);margin:0 0 36px;max-width:760px}
.group{margin-bottom:28px}
.group header{display:flex;align-items:center;gap:8px;height:32px;color:var(--text-3);font-size:13px;font-weight:510;cursor:pointer;user-select:none;border-radius:4px;padding:0 4px;margin-left:-4px}
.group header:hover{background:var(--hover)}
.group header svg{transition:transform .12s}
.group.closed header svg{transform:rotate(-90deg)}
.group.closed .gbody{display:none}
.group header .gtitle{color:var(--text)}
.group ul{list-style:none;margin:0;padding:0}
.row{border-radius:6px}
.row .head{border-radius:6px;padding:4px 0;cursor:pointer}
.row .head:hover{background:var(--hover)}
.row.open .head{background:var(--hover);border-radius:6px 6px 0 0}
.line{display:flex;align-items:center;gap:12px;min-height:36px;padding:2px 10px 2px 6px}
.key{color:var(--text-4);font-size:13px;width:18px;flex:none;text-align:right;font-variant-numeric:tabular-nums}
.status{flex:none;display:inline-flex;cursor:pointer;color:var(--text-3)}
.status input{position:absolute;opacity:0;width:0;height:0}
.status .ring{fill:none;stroke:currentColor;stroke-width:1.5;stroke-dasharray:2 2.2}
.status .fill{fill:var(--green);opacity:0}
.status .tick{fill:none;stroke:#fff;stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round;opacity:0}
.status input:checked ~ svg .ring{opacity:0}
.status input:checked ~ svg .fill,.status input:checked ~ svg .tick{opacity:1}
.main{flex:1;min-width:0}
.before{color:var(--text-3)}.arrow{color:var(--text-4);margin:0 8px}.after{color:var(--text);font-weight:500}
.props{display:flex;align-items:center;gap:6px;flex:none}
.chip{display:inline-flex;align-items:center;gap:7px;height:26px;padding:0 9px;border:1px solid var(--chip-border);border-radius:9999px;background:transparent;font:500 12px/1 var(--font);color:var(--text-2);white-space:nowrap;max-width:320px;overflow:hidden;text-overflow:ellipsis}
.chip i{width:8px;height:8px;border-radius:50%;flex:none}
.chip-bad{color:var(--red)}
.dot-green{background:var(--green)}.dot-red{background:var(--red)}.dot-yellow{background:var(--yellow)}
.prio rect{fill:#3a3a3c}.prio rect.on{fill:var(--text-2)}.chip .prio{margin:0 -2px}
.more{width:24px;height:24px;border:0;border-radius:4px;background:transparent;color:var(--text-4);cursor:pointer;display:inline-flex;align-items:center;justify-content:center;margin-left:2px}
.more:hover{background:var(--raised);color:var(--text)}
.more svg{transition:transform .12s}
.row.open .more svg{transform:rotate(90deg)}
.files{display:flex;flex-wrap:wrap;gap:4px 14px;padding:0 10px 6px 62px;font:12px/1.6 var(--mono);color:var(--text-3)}
.file{white-space:nowrap}
.fk{display:inline-block;width:12px;color:var(--text-4)}
.fk-create{color:var(--green)}
.detail{padding:10px 12px 12px 62px;display:flex;flex-direction:column;gap:10px;color:var(--text-2);font-size:14px}
.detail[hidden]{display:none}
.detail p{margin:0;max-width:720px}
textarea{width:100%;font:inherit;font-size:14px;padding:9px 12px;border:1px solid var(--chip-border);background:var(--window);color:var(--text);border-radius:8px;resize:vertical;display:block}
textarea::placeholder{color:var(--text-3)}
textarea:focus{outline:none;border-color:var(--text-4)}
.detail textarea{max-width:720px}
.opts{display:flex;flex-direction:column;gap:2px;padding:2px 10px 4px 50px}
.opt{display:flex;align-items:center;gap:10px;height:30px;padding:0 8px;border-radius:6px;cursor:pointer;color:var(--text-2)}
.opt:hover{background:var(--hover)}
.opt input{position:absolute;opacity:0;width:0;height:0}
.opt-l{width:20px;height:20px;border-radius:50%;border:1px solid var(--chip-border);display:inline-flex;align-items:center;justify-content:center;font-size:11px;color:var(--text-3);flex:none}
.opt input:checked ~ .opt-l{background:var(--text);border-color:var(--text);color:var(--pane);font-weight:590}
.opt input:checked ~ span:last-child{color:var(--text)}
.opt input:focus-visible ~ .opt-l{outline:2px solid var(--blue);outline-offset:2px}
.opt em{font-style:normal;color:var(--text-4);font-size:12px;margin-left:8px}
.qdetail{margin:0;padding:0 10px 6px 62px;color:var(--text-3);font-size:13px}
.qnote{padding:4px 12px 10px 58px;max-width:780px}
.notes{margin-top:40px;padding-top:28px;border-top:1px solid var(--line)}
.notes h2{font:590 17px/1.4 var(--font);margin:0 0 12px}
.notes-actions{display:flex;align-items:center;gap:14px;margin-top:12px}
.hint{color:var(--text-3);font-size:13px}
.steps{margin:0;padding-left:18px;color:var(--text-2);max-width:720px}
.steps li{padding:2px 0}
:focus-visible{outline:2px solid var(--blue);outline-offset:1px}
.rail h3{font:400 14px/1 var(--font);color:var(--text-3);margin:0 0 10px}
.rail section + section{margin-top:26px}
.rail ul{list-style:none;margin:0;padding:0}
.prop{display:flex;align-items:center;gap:10px;height:36px;font-size:15px}
.prop svg.ico{width:16px;height:16px;flex:none;color:var(--text-3)}
.prop .prio{flex:none}
.prop-v{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.prop-n{color:var(--text-4);font-size:13px;font-variant-numeric:tabular-nums}
.labels{display:flex;flex-wrap:wrap;gap:8px}
.map{padding:8px 0 4px 6px}
.map svg{font-family:var(--font);display:block}
.map .layer{fill:var(--text-4);font-size:11px;font-weight:510;letter-spacing:.02em}
.map .node rect{fill:var(--card);stroke:var(--chip-border);stroke-width:1}
.map .node.changed-edit rect{stroke:var(--text-3)}
.map .node.changed-create rect{stroke:var(--green)}
.map .name{fill:var(--text);font-size:13px;font-weight:510}
.map .badge{font-size:10px;font-weight:510;fill:var(--text-3)}
.map .badge-create{fill:var(--green)}
.map .file{fill:var(--text-3);font-family:var(--mono);font-size:10.5px}
.map .edge{fill:none;stroke-width:1.3}
.map .edge-new{stroke:#27a644}.map .edge-existing{stroke:#62666d}.map .edge-removed{stroke:#eb5757;stroke-dasharray:4 3}
.map .elabel{font-size:10px;fill:var(--text-3)}.map .elabel-new{fill:#4fbf6f}
@media (max-width:900px){.body{flex-direction:column;padding:32px 20px}.rail{width:auto}.line{flex-wrap:wrap;padding:8px 6px}.main{flex-basis:100%;order:3;white-space:normal}.props{margin-left:auto}.files,.detail,.opts,.qnote,.qdetail{padding-left:12px}}
</style></head><body><div class="pane">
<div class="top">
  <div class="crumb"><span>${isReview ? 'Review' : 'Proposal'}</span><span class="sep">›</span><span class="cur">${esc(brief.title)}</span>${brief.branch ? `<span class="sep">›</span><span>${esc(brief.branch)}</span>` : ''}</div>
</div>
<div class="body">
<main class="main-col">
<h1>${esc(brief.title)}</h1>
<p class="lede">${esc(brief.user)}</p>
${group('Behavior changes', behaviors.length, behaviorRows)}
${findingsBlock}
${(brief.flows || []).length ? group('Flows to test', brief.flows.length, flowRows) : ''}
${brief.map ? group('How it fits together', (brief.map.nodes || []).filter((x) => x.changed).length + ' changed', mapSvg(brief.map)) : ''}
${questions.length ? group('Decide', questions.length, questionRows) : ''}
${unexplained.length ? group('Files no line explains', unexplained.length, ledgerRows) : ''}
${deltaBlock}
${isReview ? '' : `<div class="notes"><h2>Notes</h2><textarea id="notes" rows="4" placeholder="Anything else. Included when you copy notes."></textarea><div class="notes-actions"><button id="copy" class="pill" type="button">Copy notes ↑</button><span class="hint">Paste into chat. Anything not listed counts as approved.</span></div></div>`}
</main>
<aside class="rail">
  <section>
    <h3>Properties</h3>
    <ul>
      <li class="prop"><svg class="ico" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="prop-v">${isReview ? 'Review' : 'Proposal'}</span></li>
      <li class="prop"><svg class="ico" viewBox="0 0 16 16"><path d="M3 4h10M3 8h10M3 12h6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg><span class="prop-v">${behaviors.length} behavior changes</span></li>
      <li class="prop"><svg class="ico" viewBox="0 0 16 16"><path d="M3 2h7l3 3v9H3z M10 2v3h3" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/></svg><span class="prop-v">${fileCount} files, ${fileCount - unexplained.length} explained</span></li>
      ${riskCounts.map(([r, c]) => `<li class="prop">${prioIcon(r)}<span class="prop-v">${c} ${riskName[r].toLowerCase()} risk</span></li>`).join('')}
    </ul>
  </section>
  <section>
    <h3>Touched</h3>
    <ul>${touchedRows}</ul>
  </section>
</aside>
</div>
</div>
<script>
(() => {
  const key = 'brief:' + location.pathname;
  let state = {};
  try { state = JSON.parse(localStorage.getItem(key) || '{}'); } catch {}
  const save = () => { try { localStorage.setItem(key, JSON.stringify(state)); } catch {} };
  const get = (id) => state[id] || {};
  const set = (id, patch) => { state[id] = { ...get(id), ...patch }; save(); };
  const toggle = (id, force) => {
    const d = document.getElementById('detail-' + id); if (!d) return;
    d.hidden = force === undefined ? !d.hidden : !force;
    document.querySelector('.row[data-row="' + id + '"]').classList.toggle('open', !d.hidden);
  };
  document.querySelectorAll('.row[data-row] .head').forEach((h) => h.addEventListener('click', (e) => {
    if (e.target.closest('input,label')) return;
    toggle(h.parentElement.dataset.row);
  }));
  document.querySelectorAll('.group').forEach((g) => {
    const id = g.dataset.group;
    if (get('group:' + id).closed) g.classList.add('closed');
    const flip = () => { g.classList.toggle('closed'); set('group:' + id, { closed: g.classList.contains('closed') }); };
    const h = g.querySelector('header');
    h.addEventListener('click', flip);
    h.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); flip(); } });
  });
  document.querySelectorAll('input[type=checkbox][data-id]').forEach((c) => {
    c.checked = !!get(c.dataset.id).ok;
    c.addEventListener('change', () => set(c.dataset.id, { ok: c.checked }));
  });
  document.querySelectorAll('input[type=radio][data-id]').forEach((r) => {
    const st = get(r.dataset.id); if (st.pick) r.checked = st.pick === r.value;
    r.addEventListener('change', () => set(r.dataset.id, { pick: r.value }));
  });
  document.querySelectorAll('textarea[data-id]').forEach((t) => {
    const s = get(t.dataset.id);
    if (s.note) { t.value = s.note; if (document.getElementById('detail-' + t.dataset.id)) toggle(t.dataset.id, true); }
    t.addEventListener('input', () => set(t.dataset.id, { note: t.value }));
  });
  const notes = document.getElementById('notes');
  if (notes) { notes.value = get('notes').text || ''; notes.addEventListener('input', () => set('notes', { text: notes.value })); }
  const copy = document.getElementById('copy');
  if (copy) copy.addEventListener('click', async () => {
    const lines = [];
    document.querySelectorAll('.row[data-row]').forEach((r) => {
      const id = r.dataset.row; if (!/^[0-9]+$/.test(id)) return; const parts = [];
      const pick = r.querySelector('input[type=radio]:checked'); if (pick) parts.push(pick.value);
      const ok = r.querySelector('input[type=checkbox]'); if (ok && ok.checked) parts.push('ok');
      const note = ((document.getElementById('txt-' + id) || {}).value || '').trim(); if (note) parts.push(note);
      if (parts.length) lines.push(id + '. ' + parts.join(', '));
    });
    const extra = (notes?.value || '').trim();
    const out = ['---', '## Notes from ' + JSON.stringify(${JSON.stringify(brief.title)})];
    if (lines.length) out.push(...lines);
    if (extra) out.push('Other: ' + extra);
    if (!lines.length && !extra) out.push('No notes, all approved');
    out.push('---');
    const text = out.join('\\n');
    const label = copy.textContent;
    try { await navigator.clipboard.writeText(text); copy.textContent = 'Copied ✓'; } catch { copy.textContent = 'Copy failed'; }
    setTimeout(() => { copy.textContent = label; }, 1800);
  });
})();
</script></body></html>`;

const htmlPath = join(outDir, stem + '.html');
const pngPath = join(outDir, stem + '.png');
const mdPath = join(outDir, stem + '.md');
writeFileSync(htmlPath, html);

const mdFiles = (files) => (files || []).map(([k, p]) => `${k === 'create' ? '+' : '~'} \`${p}\``).join('<br>');
const md = [
  `## ${brief.title}`,
  '',
  brief.user || '',
  '',
  '### Behavior changes',
  '',
  '| # | Before → After | Risk | ' + (isReview ? 'Verified by' : 'Test') + ' | Files |',
  '|---|---|---|---|---|',
  ...behaviors.map((b, i) => `| ${i + 1} | ${b.before} → **${b.after}** | ${riskName[b.risk] || b.risk} | ${isReview ? (b.verified || 'not verified') : (typeof b.test === 'string' ? b.test : 'no test')} | ${mdFiles(b.files)} |`),
  '',
  ...(isReview ? ['### Blockers', '', ...(findings.blockers.length ? findings.blockers.map((f) => `- ${f}`) : ['none']), '', '### Non-blockers', '', ...(findings.nonBlockers.length ? findings.nonBlockers.map((f) => `- ${f}`) : ['none']), ''] : []),
  ...((brief.flows || []).length ? ['### Flows to test', '', ...brief.flows.flatMap((f) => [`**${f.name}** (${(f.items || []).join(', ')})`, ...(f.steps || []).map((st, i) => `${i + 1}. ${st}`), ...(f.effect ? [f.effect] : []), '']), ] : []),
  ...((brief.touched || []).length ? ['### Touched', '', ...brief.touched.map((t) => `- ${t.name} (${t.files} ${t.files === 1 ? 'file' : 'files'})`), ''] : []),
  ...(unexplained.length ? ['### Files no line explains', '', ...unexplained.map(([k, p]) => `- ${k === 'create' ? '+' : '~'} \`${p}\``), ''] : []),
  ...((brief.delta || []).length ? ['### Changed since the proposal', '', ...brief.delta.map((d) => `- **${d.kind}** ${d.text}`), ''] : []),
].join('\n');
writeFileSync(mdPath, md);

const findPlaywright = () => {
  const req = createRequire(import.meta.url);
  const candidates = [
    () => req.resolve('playwright-core'),
    () => createRequire(join(process.cwd(), 'package.json')).resolve('playwright-core'),
    () => join(homedir(), 'code/surestake/node_modules/playwright-core/index.mjs'),
  ];
  for (const c of candidates) {
    try { const p = c(); if (existsSync(p)) return p; } catch {}
  }
  return null;
};

let png = false;
const pw = findPlaywright();
if (pw) {
  try {
    const { chromium } = await import(pathToFileURL(pw).href);
    const browser = await chromium.launch();
    const page = await browser.newPage({ viewport: { width: 1400, height: 900 }, deviceScaleFactor: 2 });
    await page.goto(pathToFileURL(htmlPath).href);
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: pngPath, fullPage: true });
    await browser.close();
    png = true;
  } catch (err) {
    console.error(`no png: ${err.message.split('\n')[0]}`);
  }
} else {
  console.error('no png: playwright-core not found (run npm install in this skill folder, or run from a repo that has it)');
}
console.log(htmlPath);
console.log(mdPath);
if (png) console.log(pngPath);
