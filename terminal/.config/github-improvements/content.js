const BAR_ID = 'github-improvements';
const SCROLL_ID = 'github-improvements-scroll';
const REVIEWERS = '.js-discussion-sidebar-item[data-url*="sidebar%2Fshow%2Freviewers"]';
const TOKEN_KEY = 'github-improvements-token';
const FILE_TABLE = 'table[aria-labelledby="folders-and-files"]';
const FORKS_STAT = 'h3 + div > a[href$="/forks"]';
const DATABASE_ICON = 'M1 3.5c0-.626.292-1.165.7-1.59.406-.422.956-.767 1.579-1.041C4.525.32 6.195 0 8 0c1.805 0 3.475.32 4.722.869.622.274 1.172.62 1.578 1.04.408.426.7.965.7 1.591v9c0 .626-.292 1.165-.7 1.59-.406.422-.956.767-1.579 1.041C11.476 15.68 9.806 16 8 16c-1.805 0-3.475-.32-4.721-.869-.623-.274-1.173-.62-1.579-1.04-.408-.426-.7-.965-.7-1.591Zm1.5 0c0 .133.058.318.282.551.227.237.591.483 1.101.707C4.898 5.205 6.353 5.5 8 5.5c1.646 0 3.101-.295 4.118-.742.508-.224.873-.471 1.1-.708.224-.232.282-.417.282-.55 0-.133-.058-.318-.282-.551-.227-.237-.591-.483-1.101-.707C11.102 1.795 9.647 1.5 8 1.5c-1.646 0-3.101.295-4.118.742-.508.224-.873.471-1.1.708-.224.232-.282.417-.282.55Zm0 4.5c0 .133.058.318.282.551.227.237.591.483 1.101.707C4.898 9.705 6.353 10 8 10c1.646 0 3.101-.295 4.118-.742.508-.224.873-.471 1.1-.708.224-.232.282-.417.282-.55V5.724c-.241.15-.503.286-.778.407C11.475 6.68 9.805 7 8 7c-1.805 0-3.475-.32-4.721-.869a6.15 6.15 0 0 1-.779-.407Zm0 2.225V12.5c0 .133.058.318.282.55.227.237.592.484 1.1.708 1.016.447 2.471.742 4.118.742 1.647 0 3.102-.295 4.117-.742.51-.224.874-.47 1.101-.707.224-.233.282-.418.282-.551v-2.275c-.241.15-.503.285-.778.406-1.247.549-2.917.869-4.722.869-1.805 0-3.475-.32-4.721-.869a6.327 6.327 0 0 1-.779-.406Z';
const DOWNLOAD_ICON = 'M2.75 14A1.75 1.75 0 0 1 1 12.25v-2.5a.75.75 0 0 1 1.5 0v2.5c0 .138.112.25.25.25h10.5a.25.25 0 0 0 .25-.25v-2.5a.75.75 0 0 1 1.5 0v2.5A1.75 1.75 0 0 1 13.25 14Z M7.25 7.689V2a.75.75 0 0 1 1.5 0v5.689l1.97-1.969a.749.749 0 1 1 1.06 1.06l-3.25 3.25a.749.749 0 0 1-1.06 0L4.22 6.78a.749.749 0 1 1 1.06-1.06l1.97 1.969Z';
const apiCache = new Map();

const STATUS_BY_TOOLTIP = [
  [/^Awaiting requested review from (.+)$/, 'pending'],
  [/^(.+) approved these changes$/, 'approved'],
  [/^(.+) requested changes$/, 'changes'],
  [/^(.+) left review comments$/, 'commented'],
];

function pullRef() {
  const m = location.pathname.match(/^\/([^/]+)\/([^/]+)\/pull\/(\d+)\/?$/);
  return m && { owner: m[1], repo: m[2], number: m[3] };
}

function viewerLogin() {
  return document.querySelector('meta[name="user-login"]')?.content;
}

function pullAuthor() {
  return document.querySelector('a.author')?.textContent.trim();
}

function token() {
  let value = localStorage.getItem(TOKEN_KEY);
  if (!value) {
    value = prompt('GitHub token with pull request write access. It is saved in this browser.')?.trim();
    if (value) localStorage.setItem(TOKEN_KEY, value);
  }
  return value;
}

async function approve(button, error) {
  const { owner, repo, number } = pullRef();
  const auth = token();
  if (!auth) return;
  button.disabled = true;
  error.textContent = '';
  try {
    const res = await fetch(`https://api.github.com/repos/${owner}/${repo}/pulls/${number}/reviews`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${auth}`, Accept: 'application/vnd.github+json' },
      body: JSON.stringify({ event: 'APPROVE' }),
    });
    if (res.ok) return location.reload();
    if (res.status === 401) localStorage.removeItem(TOKEN_KEY);
    const body = await res.json().catch(() => ({}));
    error.textContent = body.errors?.map(e => e.message ?? e).join(', ') || body.message || `GitHub returned ${res.status}`;
  } catch (e) {
    error.textContent = e.message;
  }
  button.disabled = false;
}

function reviewerStatuses(reviewers) {
  return [...reviewers.querySelectorAll('tool-tip')].flatMap(tip => {
    const text = tip.textContent.trim();
    for (const [pattern, status] of STATUS_BY_TOOLTIP) {
      const match = text.match(pattern);
      if (!match) continue;
      const row = tip.closest('.d-flex');
      const targetId = tip.getAttribute('for');
      const target = targetId && reviewers.querySelector(`#${CSS.escape(targetId)}`);
      return [{
        login: match[1],
        status,
        text,
        href: row?.querySelector('a.assignee')?.getAttribute('href') ?? `/${match[1]}`,
        avatar: row?.querySelector('img')?.src,
        icon: target?.querySelector('svg'),
        reRequest: row?.querySelector('button[name="re_request_reviewer_id"]'),
      }];
    }
    return [];
  });
}

function buildChip({ login, status, text, href, avatar, icon, reRequest }) {
  const chip = document.createElement('span');
  chip.className = `gi-chip gi-chip-${status}`;
  chip.title = text;

  const link = document.createElement('a');
  link.href = href;
  if (avatar) {
    const img = document.createElement('img');
    img.src = avatar;
    img.alt = '';
    link.append(img);
  }
  link.append(login);
  chip.append(link);
  if (icon) chip.append(icon.cloneNode(true));

  if (reRequest) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'gi-rerequest';
    button.title = 'Re-request review';
    button.append(reRequest.querySelector('svg').cloneNode(true));
    button.addEventListener('click', () => reRequest.click());
    chip.append(button);
  }
  return chip;
}

function render(bar, reviewers) {
  const statuses = reviewerStatuses(reviewers);
  const signature = JSON.stringify(statuses.map(({ login, status, reRequest }) => [login, status, !!reRequest]));
  const chips = bar.querySelector('.gi-chips');
  if (chips.dataset.signature !== signature) {
    chips.dataset.signature = signature;
    chips.replaceChildren(...statuses.map(buildChip));
  }
  const login = viewerLogin();
  const approved = statuses.some(s => s.login === login && s.status === 'approved');
  bar.querySelector('.gi-approve').hidden = approved || login === pullAuthor();
}

function buildBar() {
  const bar = document.createElement('div');
  bar.id = BAR_ID;
  bar.innerHTML = `
    <div class="gi-reviewers"></div>
    <div class="gi-chips"></div>
    <div class="gi-approve">
      <button type="button" class="btn btn-sm btn-primary">Approve</button>
      <span class="gi-error"></span>
    </div>`;
  const [button, error] = bar.querySelector('.gi-approve').children;
  button.addEventListener('click', () => approve(button, error));
  return bar;
}

function mountBar() {
  const mergebox = document.querySelector('[data-testid="mergebox-border-container"]');
  if (!pullRef() || !mergebox) return;
  let bar = document.getElementById(BAR_ID);
  if (!bar) {
    bar = buildBar();
    mergebox.after(bar);
  }
  const slot = bar.querySelector('.gi-reviewers');
  const reviewers = [...document.querySelectorAll(REVIEWERS)].find(el => !bar.contains(el));
  if (reviewers) slot.replaceChildren(reviewers);
  if (slot.firstElementChild) render(bar, slot.firstElementChild);
}

function scrollIcon(path) {
  return `<svg viewBox="0 0 20 20" width="18" height="18" aria-hidden="true"><path d="${path}" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
}

function mountScrollButtons() {
  if (document.getElementById(SCROLL_ID)) return;
  const nav = document.createElement('div');
  nav.id = SCROLL_ID;
  nav.innerHTML = `
    <button type="button" title="Scroll to top" aria-label="Scroll to top">${scrollIcon('M4 3h12 M5 13l5-5 5 5')}</button>
    <hr>
    <button type="button" title="Scroll to bottom" aria-label="Scroll to bottom">${scrollIcon('M4 17h12 M5 7l5 5 5-5')}</button>`;
  const [top, , bottom] = nav.children;
  top.addEventListener('click', () => window.scrollTo({ top: 0, behavior: 'instant' }));
  bottom.addEventListener('click', () =>
    window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'instant' }),
  );
  document.body.append(nav);
}

function octicon(path, className = '') {
  return `<svg class="octicon ${className}" viewBox="0 0 16 16" width="16" height="16" fill="currentColor" aria-hidden="true"><path d="${path}"/></svg>`;
}

function formatBytes(bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  let i = 0;
  while (bytes >= 1024 && i < units.length - 1) {
    bytes /= 1024;
    i++;
  }
  return `${i ? bytes.toFixed(1) : bytes} ${units[i]}`;
}

function cached(key, load) {
  if (!apiCache.has(key)) apiCache.set(key, load().catch(() => null));
  return apiCache.get(key);
}

async function githubApi(path, accept = 'application/vnd.github+json') {
  const auth = localStorage.getItem(TOKEN_KEY);
  const res = await fetch(`https://api.github.com${path}`, {
    headers: { Accept: accept, ...(auth && { Authorization: `Bearer ${auth}` }) },
  });
  if (!res.ok) throw new Error(`GitHub returned ${res.status}`);
  return res;
}

function repoTree(owner, repo, oid) {
  const key = `/repos/${owner}/${repo}/git/trees/${oid}`;
  return cached(key, async () => {
    const { tree, truncated } = await (await githubApi(`${key}?recursive=1`)).json();
    const blobs = tree.filter(entry => entry.type === 'blob');
    const sizes = new Map();
    for (const { path, size } of blobs) {
      sizes.set(path, size);
      // A truncated tree misses files, so folder totals would undercount.
      if (truncated) continue;
      for (let i = path.lastIndexOf('/'); i > 0; i = path.lastIndexOf('/', i - 1)) {
        const folder = path.slice(0, i);
        sizes.set(folder, (sizes.get(folder) ?? 0) + size);
      }
    }
    return { blobs, sizes };
  });
}

function pageEntries(pagePath) {
  return cached(pagePath, async () => {
    const res = await fetch(pagePath, { headers: { Accept: 'application/json' } });
    const { payload } = await res.json();
    const { refInfo, tree } = payload.codeViewTreeRoute ?? payload.codeViewRepoRoute;
    const [, owner, repo] = pagePath.split('/');
    const source = { owner, repo, oid: refInfo.currentOid };
    const { sizes } = await repoTree(owner, repo, source.oid);
    return new Map(
      tree.items
        .filter(({ path }) => sizes.has(path))
        .map(({ name, path, contentType }) => [
          name,
          { name, path, size: sizes.get(path), isFile: contentType === 'file', source },
        ]),
    );
  });
}

function encodePath(path) {
  return path.split('/').map(encodeURIComponent).join('/');
}

async function fetchRaw({ owner, repo, oid }, path) {
  const res = await fetch(`/${owner}/${repo}/raw/${oid}/${encodePath(path)}`);
  if (!res.ok) throw new Error(`GitHub returned ${res.status}`);
  return res;
}

function saveBlob(name, blob) {
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(link.href));
}

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});

function crc32(data) {
  let c = 0xffffffff;
  for (let i = 0; i < data.length; i++) c = CRC_TABLE[(c ^ data[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

async function deflate(data) {
  const stream = new Blob([data]).stream().pipeThrough(new CompressionStream('deflate-raw'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

function littleEndian(fields) {
  const bytes = new Uint8Array(fields.reduce((total, [, size]) => total + size, 0));
  const view = new DataView(bytes.buffer);
  let at = 0;
  for (const [value, size] of fields) {
    if (size === 2) view.setUint16(at, value, true);
    else view.setUint32(at, value, true);
    at += size;
  }
  return bytes;
}

function zip(entries) {
  const now = new Date();
  const time = (now.getHours() << 11) | (now.getMinutes() << 5) | (now.getSeconds() >> 1);
  const date = ((now.getFullYear() - 1980) << 9) | ((now.getMonth() + 1) << 5) | now.getDate();
  const encoder = new TextEncoder();
  const records = [];
  const directory = [];
  let offset = 0;
  for (const { name, mode, crc, size, compressed } of entries) {
    const nameBytes = encoder.encode(name);
    const shared = [[0x0800, 2], [8, 2], [time, 2], [date, 2], [crc, 4], [compressed.length, 4], [size, 4], [nameBytes.length, 2], [0, 2]];
    const header = littleEndian([[0x04034b50, 4], [20, 2], ...shared]);
    records.push(header, nameBytes, compressed);
    directory.push(
      littleEndian([[0x02014b50, 4], [0x0314, 2], [20, 2], ...shared, [0, 2], [0, 2], [0, 2], [parseInt(mode, 8) * 0x10000, 4], [offset, 4]]),
      nameBytes,
    );
    offset += header.length + nameBytes.length + compressed.length;
  }
  const directorySize = directory.reduce((total, part) => total + part.length, 0);
  const end = littleEndian([[0x06054b50, 4], [0, 2], [0, 2], [entries.length, 2], [entries.length, 2], [directorySize, 4], [offset, 4], [0, 2]]);
  return new Blob([...records, ...directory, end], { type: 'application/zip' });
}

async function downloadFile({ name, path, source }) {
  const data = await (await fetchRaw(source, path)).arrayBuffer();
  // A text type makes Chrome append .txt to names like .zshrc.
  saveBlob(name, new Blob([data], { type: 'application/octet-stream' }));
}

async function downloadFolder({ path, size, source }, progress) {
  const { blobs } = await repoTree(source.owner, source.repo, source.oid);
  const files = blobs.filter(blob => blob.path.startsWith(`${path}/`));
  // Zip without the Zip64 extension caps entries and offsets.
  if (files.length > 0xffff || size >= 2 ** 32) throw new Error('Folder is too large to zip');
  const root = path.slice(path.lastIndexOf('/') + 1);
  const entries = new Array(files.length);
  let next = 0;
  let done = 0;
  await Promise.all(Array.from({ length: 8 }, async () => {
    while (next < files.length) {
      const i = next++;
      const data = new Uint8Array(await (await fetchRaw(source, files[i].path)).arrayBuffer());
      entries[i] = {
        name: `${root}/${files[i].path.slice(path.length + 1)}`,
        mode: files[i].mode,
        crc: crc32(data),
        size: data.length,
        compressed: await deflate(data),
      };
      progress(++done, files.length);
    }
  }));
  saveBlob(`${root}.zip`, zip(entries));
}

function buildSize(entry) {
  const el = document.createElement('span');
  el.className = 'gi-file-size';
  const label = document.createTextNode(formatBytes(entry.size));
  const button = document.createElement('button');
  button.type = 'button';
  button.title = `Download ${entry.name}${entry.isFile ? '' : ' as a zip'}`;
  button.setAttribute('aria-label', button.title);
  button.innerHTML = octicon(DOWNLOAD_ICON);
  button.addEventListener('click', async () => {
    button.disabled = true;
    el.removeAttribute('title');
    try {
      if (entry.isFile) await downloadFile(entry);
      else await downloadFolder(entry, (done, total) => (label.textContent = `${done}/${total}`));
      label.textContent = formatBytes(entry.size);
    } catch (e) {
      label.textContent = 'Failed';
      el.title = e.message;
    }
    button.disabled = false;
  });
  el.append(label, button);
  return el;
}

function entryRows(table) {
  return [...table.querySelectorAll('tr.react-directory-row')].flatMap(row => {
    const cell = row.querySelector('.react-directory-row-name-cell-large-screen .react-directory-filename-column');
    const link = cell?.querySelector('a.Link--primary');
    if (!link) return [];
    return [{ row, cell, name: link.textContent }];
  });
}

function mountFileSizes() {
  const table = document.querySelector(FILE_TABLE);
  if (!table) return;
  const pending = entryRows(table).filter(({ row, name }) => row.dataset.giName !== name);
  if (!pending.length) return;
  const pagePath = location.pathname;
  pageEntries(pagePath).then(entries => {
    if (!entries || location.pathname !== pagePath) return;
    for (const { row, cell, name } of pending) {
      row.dataset.giName = name;
      cell.querySelector('.gi-file-size')?.remove();
      const entry = entries.get(name);
      if (entry) cell.append(buildSize(entry));
    }
  });
}

function mountRepoSize() {
  for (const forks of document.querySelectorAll(FORKS_STAT)) {
    const item = forks.parentElement;
    const [, owner, repo] = forks.getAttribute('href').split('/');
    const key = `/repos/${owner}/${repo}`;
    const current = () => item.nextElementSibling?.classList.contains('gi-repo-size') && item.nextElementSibling;
    if (current()?.dataset.repo === key) continue;
    cached(key, async () => (await githubApi(key)).json()).then(info => {
      if (!info || !item.isConnected || current()?.dataset.repo === key) return;
      current()?.remove();
      const stat = document.createElement('div');
      stat.className = `${item.className} gi-repo-size color-fg-muted`;
      stat.dataset.repo = key;
      stat.title = 'Repository size';
      stat.innerHTML = `${octicon(DATABASE_ICON, 'mr-2')}<strong>${formatBytes(info.size * 1024)}</strong> size`;
      item.after(stat);
    });
  }
}

function mount() {
  mountBar();
  mountScrollButtons();
  mountFileSizes();
  mountRepoSize();
}

new MutationObserver(mount).observe(document.documentElement, { childList: true, subtree: true });
mount();
