// Automated tests for Lucas Reading Island.
// Run:  node tests/lucas-reading-island/run_tests.js
// Needs Playwright with Chromium (require('playwright')).
const { chromium } = require('playwright');
const path = require('path');

const GAME = 'file://' + path.resolve(__dirname, '../../lucas-reading-island/index.html');
const results = [];
function check(name, ok, detail = '') { results.push({ name, ok: !!ok, detail }); }

// Speech is replaced with a recorder that finishes instantly, so tests run fast and we can audit what Ziggy says.
const SPEECH_STUB = () => {
  window.__spoken = [];
  if (window.speechSynthesis) {
    speechSynthesis.speak = u => { window.__spoken.push(u.text); setTimeout(() => u.onend && u.onend(), 5); };
  }
};

async function fresh(browser, opts = {}) {
  const ctx = await browser.newContext({ viewport: opts.viewport || { width: 400, height: 860 } });
  const page = await ctx.newPage();
  page.errors = [];
  page.on('pageerror', e => page.errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error' && !/fonts\.(googleapis|gstatic)/.test(m.text())) page.errors.push(m.text()); });
  if (opts.init) await page.addInitScript(opts.init);
  await page.addInitScript(SPEECH_STUB);
  await page.goto(GAME + '?test=1');
  return page;
}

async function logicTests(browser) {
  const p = await fresh(browser);
  const r = await p.evaluate(() => {
    const R = window.__RI, out = [];
    const t = (name, ok, detail = '') => out.push({ name, ok: !!ok, detail: String(detail) });
    const L = R.LETTERS, V = 'aeiou';
    const seed = boxes => { R.setState({}); for (const [id, b] of Object.entries(boxes)) R.state.items[id] = { b, s: 1, c: 1, w: 0, t: 0 }; };

    // --- distractors ---
    let bad = [];
    for (let trial = 0; trial < 3000; trial++) {
      const world = trial % 2 ? 'sounds' : 'letters';
      const box = trial % 6; const target = L[trial % 26]; const n = 2 + (trial % 2);
      seed(Object.fromEntries(L.slice(0, 3 + (trial % 24)).map(l => [(world === 'sounds' ? 'S:' : 'L:') + l, 2])));
      const d = R.distractLetters(target, n, world, box);
      if (d.length !== n) bad.push(`count ${target}:${d}`);
      if (d.includes(target)) bad.push(`target ${target}`);
      if (new Set(d).size !== d.length) bad.push(`dupe ${target}:${d}`);
      if (world === 'sounds' && d.some(x => (R.SAME_SOUND[target] || '').includes(x))) bad.push(`same-sound ${target}:${d}`);
      if (box < 2 && d.some(x => (R.CONF[target] || '').includes(x))) bad.push(`confusable-while-new ${target}:${d}`);
    }
    t('Letter distractors: right count, unique, never the answer, no same-sound or look-alike traps for new letters', !bad.length, bad.slice(0, 5));

    bad = [];
    for (const target of ['b', 'd', 'p', 'm', 'n']) {
      seed(Object.fromEntries(L.map(l => ['L:' + l, 3])));
      let hits = 0; for (let k = 0; k < 50; k++) if (R.distractLetters(target, 3, 'letters', 3).some(x => R.CONF[target].includes(x))) hits++;
      if (hits < 50) bad.push(`${target}: ${hits}/50`);
    }
    t('Known look-alike letters are deliberately contrasted (b with d etc.)', !bad.length, bad);

    bad = [];
    seed(Object.fromEntries(L.map(l => ['S:' + l, 1])));
    for (let k = 0; k < 400; k++) {
      const target = L[k % 26]; const d = R.distractLetters(target, 3, 'sounds', k % 2);
      const vowels = d.filter(x => V.includes(x)).length;
      if (V.includes(target) ? vowels > 0 : vowels > 1) bad.push(`${target}: ${d.join('')}`);
    }
    t('Sound games for new items avoid short-vowel-vs-short-vowel choices (hardest sounds to hear apart)', !bad.length, `${bad.length}/400 e.g. ${bad.slice(0, 4).join(', ')}`);

    bad = [];
    for (let k = 0; k < 500; k++) {
      const target = k % 11; const d = R.distractNums(target, 3, k % 5);
      if (d.length !== 3 || d.includes(target) || new Set(d).size !== 3 || d.some(x => x < 0 || x > 10)) bad.push(`${target}:${d}`);
    }
    t('Number distractors: 3 unique numbers 0-10, never the answer', !bad.length, bad.slice(0, 5));

    // --- picture choices ---
    const AMBIG = [['mug', 'cup'], ['sad', 'mad']];
    bad = []; let ambig = 0;
    seed(Object.fromEntries(L.map(l => ['S:' + l, 2])));
    for (const w of Object.keys(R.CVC)) for (let k = 0; k < 40; k++) {
      const d = R.pickPics(w, 2), all = [w, ...d];
      if (d.includes(w) || new Set(all.map(x => R.CVC[x])).size !== 3) bad.push(`${w}:${d}`);
      if (AMBIG.some(([a, b]) => all.includes(a) && all.includes(b))) ambig++;
    }
    t('Picture choices: never duplicate pictures or the answer twice', !bad.length, bad.slice(0, 5));
    t('Picture choices never pair near-identical meanings (mug/cup, sad/mad)', ambig === 0, `${ambig} ambiguous sets in ${Object.keys(R.CVC).length * 40} draws`);

    // --- content checks ---
    const IRREGULAR = ['is', 'as', 'has', 'his', 'of', 'was'];
    const irr = [...R.WORDS2, ...Object.keys(R.CVC)].filter(w => IRREGULAR.includes(w));
    t('Every reading word is regularly decodable (no words like "is" where s says /z/)', !irr.length, irr);
    t('Every word only uses taught letters', R.WORD_ORDER.every(w => [...w].every(c => L.includes(c))));
    const keyPics = Object.entries(R.KEY).map(([l, [w, e]]) => [l, w, e]);
    const clashes = [];
    for (const [l, w, e] of keyPics) for (const [cw, ce] of Object.entries(R.CVC)) if (ce === e && cw[0] !== l && cw !== w) clashes.push(`${l}=${w} vs ${cw} (${e})`);
    t('Keyword pictures do not reuse a picture that means another word with a different first sound', !clashes.length, clashes);
    const emojiSeen = {}; const dupPic = [];
    for (const [w, e] of Object.entries(R.CVC)) { if (emojiSeen[e]) dupPic.push(`${emojiSeen[e]}/${w}`); emojiSeen[e] = w; }
    t('Each reading word has its own picture', !dupPic.length, dupPic);

    // --- learning engine ---
    seed({});
    const w0 = R.WORLDS.find(w => w.id === 'letters');
    t('First lesson introduces exactly 2 new letters', R.planNew(w0).length === 2, R.planNew(w0));
    seed({ 'L:s': 0, 'L:a': 0, 'L:t': 0, 'L:i': 0, 'L:p': 0, 'L:n': 0 });
    t('No new letters while the working set is full and unlearned', R.planNew(w0).length === 0);
    seed(Object.fromEntries(L.map(l => ['L:' + l, 5])));
    t('Nothing new once every letter is seen', R.planNew(w0).length === 0);

    seed(Object.fromEntries('satipn'.split('').map(l => ['S:' + l, 3])));
    let undecodable = [];
    for (let k = 0; k < 40; k++) {
      const plan = R.buildPlan('words');
      plan.qs.forEach(q => { if (![...q.val].every(c => 'satipn'.includes(c))) undecodable.push(q.val); });
      plan.qs.forEach(q => R.applyAnswer(q.id, true, false));
    }
    t('Word lessons only ever use words made of sounds already taught', !undecodable.length, [...new Set(undecodable)]);

    seed(Object.fromEntries(L.slice(0, 7).map(l => ['L:' + l, 2])));
    const locked = !R.worldUnlocked(R.WORLDS[2]);
    seed(Object.fromEntries(L.slice(0, 8).map(l => ['L:' + l, 2])));
    t('Sound Jungle stays locked at 7 letters and opens at 8', locked && R.worldUnlocked(R.WORLDS[2]));

    seed({ 'L:s': 0 }); for (let k = 0; k < 9; k++) R.applyAnswer('L:s', false, true);
    const lo = R.state.items['L:s'].b; for (let k = 0; k < 9; k++) R.applyAnswer('L:s', true, false);
    t('Leitner boxes stay within 0..5', lo === 0 && R.state.items['L:s'].b === 5);

    bad = [];
    for (const world of ['letters', 'numbers', 'sounds', 'words']) {
      seed(world === 'words' ? Object.fromEntries(L.map(l => ['S:' + l, 2])) : {});
      for (let k = 0; k < 25; k++) {
        const { qs, newItems } = R.buildPlan(world);
        const core = qs.filter(q => q.type !== 'intro' && q.type !== 'trace' && q.type !== 'sayIt');
        for (let i = 1; i < core.length; i++) if (core[i].id === core[i - 1].id && new Set(core.map(q => q.id)).size > 1) bad.push(`${world}: repeat ${core[i].id}`);
        newItems.forEach(id => { if (core.filter(q => q.id === id).length < 2) bad.push(`${world}: new ${id} once`); });
        const firstNonIntro = qs.findIndex(q => q.type !== 'intro');
        if (qs.slice(firstNonIntro).some(q => q.type === 'intro')) bad.push(`${world}: intro not first`);
        if (qs.some(q => q.type === 'firstSound' && 'xq'.includes(q.val))) bad.push(`${world}: firstSound for ${qs.find(q => q.type === 'firstSound' && 'xq'.includes(q.val)).val}`);
        qs.forEach(q => R.applyAnswer(q.id, Math.random() < 0.8, Math.random() < 0.2));
      }
    }
    t('Lesson plans: intros first, new items practised at least twice, no back-to-back repeats, no first-sound task for x/q', !bad.length, [...new Set(bad)].slice(0, 6));

    R.setState({ streak: { count: 5, last: '2020-01-01' } });
    t('A broken day streak shows 0, not the old count', R.streakNow() === 0);
    let mono = true; for (let l = 1; l < 30; l++) if (R.levelNeed(l + 1) <= R.levelNeed(l)) mono = false;
    t('Each level needs more XP than the last', mono);

    // Adaptive difficulty
    seed(Object.fromEntries(L.slice(0, 4).map(l => ['L:' + l, 2])));
    const before = R.planNew(w0).length;
    [0.4, 0.5, 0.45].forEach(a => R.recordLesson('letters', a));
    const after = R.planNew(w0).length;
    t('After hard lessons (<65% right), no new letters are added until things improve', before === 1 && after === 0, `before ${before}, after ${after}`);
    const qNew = { box: 0 };
    t('After hard lessons, brand-new items show only 2 choices', R.nChoices(qNew, 3, 'letters') === 2 && R.nChoices(qNew, 3, 'numbers') === 3);
    [0.9, 0.9, 0.9, 0.9].forEach(a => R.recordLesson('letters', a));
    t('Once lessons go well again, new letters come back', R.planNew(w0).length === 1);

    // Letter A pronunciation: "ay" is read as "aye" (sounds like I); a bare "A" before a word is read as "uh".
    const sp = R.speakable;
    t('Letter A is never spelled "ay" for the voice, and F is not "eff" (spelled out as E-F-F)', R.NAME.a === 'A' && R.NAME.f === 'F' && !Object.values(R.NAME).some(v => v === 'ay' || v === 'eff'));
    t('"A" before a word gets a comma so it is said as the letter name',
      sp('A says') === 'A, says' && sp('Big A and little A are partners!') === 'Big A, and little A, are partners!' &&
      sp('Pop the letter A!') === 'Pop the letter A!' && sp('Find a word') === 'Find a word' && sp('Say "A"!') === 'Say A,!',
      [sp('A says'), sp('Big A and little A are partners!'), sp('Find a word')]);

    // Letter names travel with sounds
    seed(Object.fromEntries(L.slice(0, 8).map(l => ['L:' + l, 2])));
    let nameQs = 0;
    for (let k = 0; k < 10; k++) { const { qs } = R.buildPlan('sounds'); nameQs += qs.filter(q => q.kind === 'L').length; qs.forEach(q => R.applyAnswer(q.id, true, false)); }
    t('Sound Jungle lessons also review letter names', nameQs >= 8, nameQs + ' name questions in 10 lessons');
    return out;
  });
  r.forEach(x => check('[logic] ' + x.name, x.ok, x.detail));
  check('[logic] no page errors', !p.errors.length, p.errors);
  await p.context().close();
}

// Plays a lesson by tapping like a child who guesses (first unanswered choice each time).
async function playLesson(p, world) {
  await p.click(`[data-act=world][data-w=${world}]`);
  for (let step = 0; step < 120; step++) {
    await p.waitForTimeout(250);
    try { const r = await lessonStep(p); if (r) return r; } catch (e) { if (!/not attached|detached|not visible|Timeout/.test(e.message)) throw e; }
  }
  return 'timeout';
}
// One tap of the bot. Returns a value only when the lesson is over.
async function lessonStep(p) {
  {
    const ov = await p.$('.overlay .card button'); if (ov) await ov.click();
    if (await p.$('[data-act=again]')) return 'results';
    if (await p.$('#bdone')) return 'break';
    const st = await p.$('#stage'); if (!st) { await p.waitForTimeout(600); return (await p.$('[data-act=again]')) ? 'results' : 'left-lesson'; }
    if (await p.$('#stage #ok')) { await p.click('#ok'); return; }
    if (await p.$('#stage #said')) { await p.click('#said'); return; }
    if (await p.$('#stage #tink')) { const s = await p.$('#tskip'); if (s) { await s.click(); return; }
      const box = await (await p.$('#tink')).boundingBox(); await p.mouse.move(box.x + 10, box.y + 10); await p.mouse.down(); await p.mouse.move(box.x + box.width - 10, box.y + box.height - 10, { steps: 4 }); await p.mouse.up(); await p.click('#tdone'); return; }
    if (await p.$('#stage .slots')) { const b = (await p.$$('.bank .choice.hint:not(.used)'))[0] || (await p.$$('.bank .choice:not(.used)'))[0]; if (b) await b.click({ force: true }); return; }
    if ((await p.$('#stage #slide')) && !(await p.$('#stage .choice[data-v]'))) { await p.click('#slide'); await p.waitForTimeout(300); return; }
    const c = await p.$('#stage .choice[data-v]:not([disabled]):not(.right)'); if (c) await c.click({ force: true });
  }
  return null;
}

async function uiTests(browser) {
  // Full playthrough of every world, unlocked, with speech audit.
  const p = await fresh(browser);
  await p.evaluate(() => { const s = window.__RI.state; s.unlockAll = true; s.settings.breakEvery = 0; });
  await p.click('[data-act=start]');
  const outcomes = [];
  for (const w of ['letters', 'letters', 'numbers', 'numbers', 'sounds', 'sounds', 'words', 'words', 'words']) {
    const o = await playLesson(p, w);
    if (o !== 'results') outcomes.push(`${w}:${o} @ ${(await p.textContent('#app')).replace(/\s+/g, ' ').slice(0, 160)}`);
    else outcomes.push(w + ':' + o);
    if (await p.$('[data-act=quit]')) { await p.click('[data-act=quit]'); await p.click('[data-act=quityes]'); }
    if (await p.$('[data-act=home]')) await p.click('[data-act=home]');
  }
  check('[ui] 9 lessons across all four worlds finish with a results screen', outcomes.every(o => o.endsWith(':results')), outcomes);
  const spoken = await p.evaluate(() => window.__spoken);
  const weird = spoken.filter(s => /undefined|NaN|null|\[object/.test(s));
  check('[ui] Ziggy never says "undefined"/"NaN"/"null"', !weird.length, weird.slice(0, 5));
  check('[ui] Ziggy talked during the lessons', spoken.length > 50, spoken.length + ' utterances');
  for (const scr of ['stickers', 'closet']) { await p.click(`.homebar [data-act=${scr}]`); await p.click('[data-act=home]'); }
  await p.click('[data-act=gate]'); await p.click('[data-ok=true]');
  check('[ui] Grown-ups area opens after the math gate', !!(await p.$('.parent')));
  await p.click('[data-act=reset1]');
  const stillThere = (await p.evaluate(() => window.__RI.state.totals.lessons)) > 0;
  await p.click('[data-act=reset2]');
  check('[ui] Reset needs two taps, then erases progress', stillThere && (await p.evaluate(() => window.__RI.state.totals.lessons)) === 0);
  check('[ui] no page errors during playthrough', !p.errors.length, p.errors.slice(0, 5));
  await p.context().close();

  // Small phone width: no sideways scrolling on any screen, big enough touch targets.
  const s = await fresh(browser, { viewport: { width: 320, height: 640 } });
  await s.click('[data-act=start]');
  const ov = []; const small = [];
  const measure = async label => {
    if (await s.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1)) ov.push(label);
    const tiny = await s.evaluate(() => [...document.querySelectorAll('#stage .choice, #stage .tile, .node .disc, .hear')].filter(e => { const r = e.getBoundingClientRect(); return r.width && (r.width < 64 || r.height < 64); }).length);
    if (tiny) small.push(`${label}:${tiny}`);
  };
  await measure('home');
  await s.evaluate(() => { window.__RI.state.unlockAll = true; window.__RI.state.settings.breakEvery = 0; });
  for (const w of ['letters', 'numbers', 'sounds', 'words']) {
    await s.click(`[data-act=world][data-w=${w}]`); await s.waitForTimeout(400); await measure(w);
    await s.click('[data-act=quit]'); await s.waitForTimeout(200);
    const yes = await s.$('[data-act=quityes]'); if (yes) await yes.click();
  }
  await s.click('[data-act=gate]'); await s.click('[data-ok=true]'); await measure('grown-ups');
  check('[ui] 320px-wide phone: no sideways scrolling', !ov.length, ov);
  check('[ui] Touch targets for children are at least 64px', !small.length, small);
  await s.context().close();

  // Child-safety / UX regressions (expected behaviour).
  const q = await fresh(browser);
  await q.click('[data-act=start]');
  await q.click('[data-act=world][data-w=letters]'); await q.waitForTimeout(400);
  await q.click('[data-act=quit]'); await q.waitForTimeout(200);
  check('[child UX] One accidental tap on ✕ does not throw away the lesson (asks first)', !!(await q.$('#stage')));
  await q.context().close();

  const v = await fresh(browser);
  await v.evaluate(() => { const s = window.__RI.state; s.settings.voice = false; s.settings.breakEvery = 0; });
  await v.click('[data-act=start]');
  await v.click('[data-act=world][data-w=numbers]');
  await v.waitForTimeout(400);
  // Advance until a "find the same number" question (its answer is visible on screen), then time the success moment.
  let gap = -1;
  for (let k = 0; k < 15 && gap < 0; k++) {
    await v.waitForTimeout(400);
    if (await v.$('#ok')) { await v.click('#ok'); continue; }
    gap = await v.evaluate(async () => {
      const target = document.querySelector('#stage .target-card'); if (!target) return -1;
      const right = [...document.querySelectorAll('#stage .choice[data-v]')].find(b => b.textContent.trim() === target.textContent.trim());
      if (!right) return -1;
      const t0 = performance.now(); right.click();
      while (document.querySelector('#stage .choice.right') && performance.now() - t0 < 5000) await new Promise(r => setTimeout(r, 20));
      return Math.round(performance.now() - t0);
    });
    if (gap < 0) { const c = await v.$('#stage .choice[data-v]:not([disabled])'); if (c) await c.click({ force: true }).catch(() => {}); await v.waitForTimeout(1200); }
  }
  check('[child UX] With voice off, the "correct!" moment stays on screen long enough to notice (>= 800ms)', gap >= 800, gap + 'ms');
  await v.context().close();

  const b = await fresh(browser);
  await b.evaluate(() => { const s = window.__RI.state; s.unlockAll = true; s.settings.breakEvery = 0; 'satipnc'.split('').forEach(l => s.items['S:' + l] = { b: 2, s: 1, c: 1, w: 0, t: 0 }); ['at', 'it', 'in', 'an'].forEach(w => s.items['W:' + w] = { b: 3, s: 1, c: 1, w: 0, t: 0 }); });
  await b.click('[data-act=start]');
  let found = false;
  for (let tries = 0; tries < 8 && !found; tries++) {
    await b.click('[data-act=world][data-w=words]'); await b.waitForTimeout(400);
    for (let k = 0; k < 8 && !found; k++) {
      if ((await b.$('#stage #slide')) && (await b.$('#stage #pics'))) found = true;
      else { const c = await b.$('#stage .choice[data-v]:not([disabled])'); if (c) await c.click({ force: true }); else if (await b.$('#slide')) await b.click('#slide'); await b.waitForTimeout(500); }
    }
    if (!found) { await b.click('[data-act=quit]'); const y = await b.$('[data-act=quityes]'); if (y) await y.click(); }
  }
  if (found) {
    await b.click('#slide'); await b.waitForTimeout(800);
    const wrong = await b.$('#pics .choice[data-v]'); await wrong.click({ force: true }); await b.waitForTimeout(200);
    const marked = await b.$$eval('#pics .choice.wrong, #pics .choice.right', e => e.length);
    await b.click('#slide'); await b.waitForTimeout(800);
    const after = await b.$$eval('#pics .choice.wrong, #pics .choice.right', e => e.length);
    check('[bug] Re-blending after the pictures appear keeps the child\'s answers (does not reset the question)', marked > 0 && after === marked, `before ${marked}, after ${after}`);
  } else check('[bug] Re-blending after the pictures appear keeps answers', false, 'could not reach a blend question');
  await b.context().close();

  // Impulse guard: two fast wrong taps → "slow down, let's listen", choices pause.
  const g = await fresh(browser);
  await g.evaluate(() => { window.__RI.state.settings.breakEvery = 0; });
  await g.click('[data-act=start]'); await g.click('[data-act=world][data-w=letters]'); await g.waitForTimeout(400);
  let guarded = null;
  for (let k = 0; k < 6 && guarded === null; k++) {
    if (await g.$('#ok')) { await g.click('#ok'); await g.waitForTimeout(400); continue; }
    guarded = await g.evaluate(async () => {
      const target = document.querySelector('#stage .target-card'); if (!target) return null;
      const wrong = [...document.querySelectorAll('#stage .choice[data-v]')].filter(b => b.textContent.trim() !== target.textContent.trim());
      if (wrong.length < 2) return null;
      window.__spoken.length = 0; wrong[0].click(); await new Promise(r => setTimeout(r, 300)); wrong[1].click();
      await new Promise(r => setTimeout(r, 200));
      const right = [...document.querySelectorAll('#stage .choice[data-v]')].find(b => b.textContent.trim() === target.textContent.trim());
      right.click(); await new Promise(r => setTimeout(r, 100));
      return { said: window.__spoken.some(s => /slow down/i.test(s)), blockedDuringPause: !right.classList.contains('right') };
    });
    if (guarded === null) { const c = await g.$('#stage .choice[data-v]:not([disabled])'); if (c) await c.click({ force: true }).catch(() => {}); await g.waitForTimeout(1500); }
  }
  check('[child UX] Rapid random tapping triggers "let\'s listen first" and a short pause', guarded && guarded.said && guarded.blockedDuringPause, guarded);
  await g.context().close();

  // Regression: tapping a letter tile in the middle of a blend used to freeze the Slide button forever.
  const f = await fresh(browser);
  await f.evaluate(() => {
    const s = window.__RI.state; s.unlockAll = true; s.settings.breakEvery = 0;
    'satipnc'.split('').forEach(l => s.items['S:' + l] = { b: 2, s: 1, c: 1, w: 0, t: 0 });
    // slow speech for this test so a tap can land mid-blend
    speechSynthesis.speak = u => { window.__spoken.push(u.text); setTimeout(() => u.onend && u.onend(), 300); };
  });
  await f.click('[data-act=start]'); await f.click('[data-act=world][data-w=words]'); await f.waitForTimeout(400);
  let reached = false;
  for (let k = 0; k < 12 && !reached; k++) {
    if ((await f.$('#stage #slide')) && !(await f.$('#stage .choice[data-v]'))) reached = true;
    else { const c = await f.$('#stage .choice[data-v]:not([disabled])'); if (c) await c.click({ force: true }); await f.waitForTimeout(1500); }
  }
  if (reached) {
    await f.click('#slide'); await f.waitForTimeout(150);
    await f.click('#stage .tile'); await f.waitForTimeout(500);   // interrupt
    await f.click('#slide');
    await f.waitForSelector('#stage .choice[data-v]', { timeout: 8000 }).catch(() => {});
    check('[bug] Interrupting a blend (tapping a letter) does not freeze the Slide button', !!(await f.$('#stage .choice[data-v]')));
  } else check('[bug] Interrupting a blend does not freeze the Slide button', false, 'could not reach a blend');
  await f.context().close();

  // Robustness: storage blocked or corrupted.
  const blocked = await fresh(browser, { init: () => { Object.defineProperty(window, 'localStorage', { get() { throw new Error('blocked'); } }); } });
  await blocked.click('[data-act=start]');
  check('[robust] Game still works when browser storage is blocked', !!(await blocked.$('.island')) && !blocked.errors.length, blocked.errors);
  await blocked.context().close();
  const corrupt = await fresh(browser, { init: () => { try { localStorage.setItem('ziggy-reading-island-v1', '{"level":"x",garbage'); } catch {} } });
  await corrupt.click('[data-act=start]');
  check('[robust] Corrupted saved data falls back to a fresh start', !!(await corrupt.$('.island')) && !corrupt.errors.length, corrupt.errors);
  await corrupt.context().close();

  // Daily limit and grown-up override.
  const lim = await fresh(browser);
  await lim.evaluate(() => { const s = window.__RI.state; s.settings.dailyLimit = 10; const d = new Date(); s.today = { date: `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`, lessons: 4, ms: 11 * 60000, override: false }; });
  await lim.click('[data-act=start]'); await lim.click('[data-act=world][data-w=letters]'); await lim.waitForTimeout(200);
  const rest = (await lim.textContent('#app')).includes('done for today');
  await lim.click('.panel [data-act=gate]'); await lim.click('[data-ok=true]'); await lim.click('[data-act=home]');
  await lim.click('[data-act=world][data-w=letters]'); await lim.waitForTimeout(300);
  check('[ui] Daily time limit shows the rest screen; a grown-up can unlock more time', rest && !!(await lim.$('#stage')));
  await lim.context().close();
}

(async () => {
  const browser = await chromium.launch();
  try { await logicTests(browser); await uiTests(browser); }
  catch (e) { check('test runner crashed', false, e.stack); }
  await browser.close();
  let pass = 0;
  for (const r of results) {
    console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name}${!r.ok && r.detail !== '' ? '\n      → ' + JSON.stringify(r.detail) : ''}`);
    if (r.ok) pass++;
  }
  console.log(`\n${pass}/${results.length} passed`);
  process.exit(pass === results.length ? 0 : 1);
})();
