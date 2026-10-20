const BAR_ID = 'github-improvements';
const SCROLL_ID = 'github-improvements-scroll';
const REVIEWERS = '.js-discussion-sidebar-item[data-url*="sidebar%2Fshow%2Freviewers"]';
const TOKEN_KEY = 'github-improvements-token';

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

function mount() {
  mountBar();
  mountScrollButtons();
}

new MutationObserver(mount).observe(document.documentElement, { childList: true, subtree: true });
mount();
