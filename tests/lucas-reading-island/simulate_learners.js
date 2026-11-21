// Experiment: simulated children playing Lucas Reading Island for 6 weeks.
// Uses the game's real lesson planner and spaced-repetition engine; only the child is simulated.
// Run:  node tests/lucas-reading-island/simulate_learners.js
//
// Learner model (simple, transparent): the chance of a first-try correct answer for an item is
//   p = min(0.97, chance + learnRate * timesAnsweredCorrectly) , minus a small forgetting penalty after days away.
// "chance" is about 1 in 3 (three choices). This is a rough model for comparing pacing, not a prediction for a real child.
const { chromium } = require('playwright');
const path = require('path');
const GAME = 'file://' + path.resolve(__dirname, '../../lucas-reading-island/index.html') + '?test=1';

// prior = head start above guessing; rate = gain per correct answer; forget = loss per day away (max 7 days).
const PROFILES = [
  { id: 'fast', label: 'Quick 6-year-old (knows some letters already)', prior: 0.12, rate: 0.16, forget: 0.03 },
  { id: 'typical', label: 'Typical 5-year-old', prior: 0.03, rate: 0.10, forget: 0.05 },
  { id: 'early', label: 'Young 4-year-old (just starting)', prior: 0, rate: 0.06, forget: 0.08 },
  { id: 'guesser', label: 'Guesser (taps randomly, barely learning)', prior: 0, rate: 0.01, forget: 0.05 },
];
const VERSION = process.argv.includes('--no-adapt') ? 'no-adapt' : 'adaptive';
const KIDS = 30, DAYS = 42, LESSONS_PER_DAY = 3;

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.addInitScript(() => { window.speechSynthesis && (speechSynthesis.speak = u => setTimeout(() => u.onend && u.onend(), 1)); });
  await page.goto(GAME);
  const report = [];
  for (const prof of PROFILES) {
    const res = await page.evaluate(({ prof, KIDS, DAYS, LESSONS_PER_DAY, adapt }) => {
      const R = window.__RI; const realNow = Date.now; let clock = realNow();
      Date.now = () => clock;
      const kids = [];
      for (let k = 0; k < KIDS; k++) {
        R.setState({}); R.state.settings.breakEvery = 0;
        const learned = {}; const lastDay = {};
        const m = { soundsDay: null, wordsDay: null, acc: [], maxWorking: 0, snapshots: {}, frustrated: 0, bored: 0, lessons: 0 };
        for (let day = 1; day <= DAYS; day++) {
          for (let l = 0; l < LESSONS_PER_DAY; l++) {
            // Child picks: newest unlocked reading world most of the time, numbers sometimes.
            const open = R.WORLDS.filter(w => R.worldUnlocked(w)).map(w => w.id);
            const reading = open.filter(w => w !== 'numbers');
            const r = Math.random();
            const world = r < 0.2 ? 'numbers' : (reading.length > 1 && r < 0.55) ? reading[reading.length - 2] : reading[reading.length - 1];
            const { qs } = R.buildPlan(world);
            let first = 0, scored = 0;
            for (const q of qs) {
              if (['intro', 'trace', 'sayIt'].includes(q.type)) continue;
              scored++;
              const n = learned[q.id] || 0;
              const away = lastDay[q.id] ? day - lastDay[q.id] : 0;
              const base = ['bigLittle', 'count', 'firstSound', 'build', 'blend', 'readIt'].includes(q.type) ? 3 : 3;
              const shown = adapt ? R.nChoices(q, base, world) : (q.box < 2 ? base : base + 1);
              const guess = q.type === 'build' ? 0.2 : 1 / shown;
              const p = Math.max(guess, Math.min(0.97, guess + prof.prior + prof.rate * n - prof.forget * Math.min(away, 7)));
              const ok = Math.random() < p;
              if (ok) { first++; learned[q.id] = n + 1; } else learned[q.id] = n + 0.5;   // learning from the corrected attempt
              lastDay[q.id] = day;
              R.applyAnswer(q.id, ok, !ok);
            }
            const acc = scored ? first / scored : 1;
            if (adapt) R.recordLesson(world, acc);
            m.acc.push(acc); m.lessons++;
            if (acc < 0.5) m.frustrated++;
            if (acc === 1) m.bored++;
            const working = Object.entries(R.state.items).filter(([id, v]) => id.startsWith(world === 'numbers' ? 'N' : world === 'letters' ? 'L' : world === 'sounds' ? 'S' : 'W') && v.b < 3).length;
            m.maxWorking = Math.max(m.maxWorking, working);
            if (m.soundsDay === null && R.worldUnlocked(R.WORLDS[2])) m.soundsDay = day;
            if (m.wordsDay === null && R.worldUnlocked(R.WORLDS[3])) m.wordsDay = day;
            clock += 25 * 60e3;
          }
          if ([7, 14, 28, 42].includes(day)) m.snapshots[day] = { letters: R.countBox('L:', 2), sounds: R.countBox('S:', 2), words: R.countBox('W:', 2), numbers: R.countBox('N:', 2) };
          clock += 24 * 3600e3 - LESSONS_PER_DAY * 25 * 60e3;
        }
        kids.push(m);
      }
      Date.now = realNow;
      const med = a => { const s = a.filter(x => x !== null).sort((x, y) => x - y); return s.length ? s[Math.floor(s.length / 2)] : null; };
      const never = key => kids.filter(k => k[key] === null).length;
      const avgAcc = kids.flatMap(k => k.acc).reduce((s, x) => s + x, 0) / kids.flatMap(k => k.acc).length;
      const snap = d => ['letters', 'sounds', 'words', 'numbers'].map(key => `${key} ${med(kids.map(k => k.snapshots[d][key]))}`).join(', ');
      return {
        soundsDay: med(kids.map(k => k.soundsDay)), soundsNever: never('soundsDay'),
        wordsDay: med(kids.map(k => k.wordsDay)), wordsNever: never('wordsDay'),
        avgAcc: Math.round(avgAcc * 100),
        frustratedPct: Math.round(100 * kids.reduce((s, k) => s + k.frustrated, 0) / kids.reduce((s, k) => s + k.lessons, 0)),
        perfectPct: Math.round(100 * kids.reduce((s, k) => s + k.bored, 0) / kids.reduce((s, k) => s + k.lessons, 0)),
        maxWorking: Math.max(...kids.map(k => k.maxWorking)),
        week1: snap(7), week2: snap(14), week4: snap(28), week6: snap(42),
      };
    }, { prof, KIDS, DAYS, LESSONS_PER_DAY, adapt: VERSION === "adaptive" });
    report.push({ ...prof, ...res });
  }
  await browser.close();
  console.log(`[${VERSION}] Simulated ${KIDS} children per profile, ${LESSONS_PER_DAY} lessons a day for ${DAYS} days (~${LESSONS_PER_DAY * 3} min/day).\n`);
  for (const r of report) {
    console.log(`## ${r.label}`);
    console.log(`  Sound Jungle opens: day ${r.soundsDay ?? '-'} (median)${r.soundsNever ? `, never for ${r.soundsNever}/${KIDS}` : ''}`);
    console.log(`  Word Volcano opens: day ${r.wordsDay ?? '-'} (median)${r.wordsNever ? `, never for ${r.wordsNever}/${KIDS}` : ''}`);
    console.log(`  First-try accuracy: ${r.avgAcc}% average | lessons under 50%: ${r.frustratedPct}% | perfect lessons: ${r.perfectPct}%`);
    console.log(`  Largest "still learning" set: ${r.maxWorking} items`);
    console.log(`  Known (median) week 1: ${r.week1}`);
    console.log(`                 week 2: ${r.week2}`);
    console.log(`                 week 4: ${r.week4}`);
    console.log(`                 week 6: ${r.week6}\n`);
  }
})();
