# Lucas Reading Island: test report

Date: 2026-11-21. Covers automated bug tests, a learner-simulation experiment, and a developmental-psychology
review (an expert walkthrough with three child profiles).

**What this is not:** no real children played the game. The "user test" is a structured expert review, and the
experiment uses simulated learners. Both are good at finding problems, but neither can say how much Lucas will
learn. The last section has a short plan for a real trial with Lucas.

## 1. Automated tests

`node tests/lucas-reading-island/run_tests.js` runs **40 checks** in headless Chromium: game logic through a test
hook, real tap-through play of every world, phone layouts, child-safety behaviour and robustness.
**Result: 40/40 pass**, on repeated runs.

### Bugs found and fixed

| # | Problem | How it was found | Effect on a child | Status |
|---|---|---|---|---|
| 1 | **"Slide & blend" froze for good** if anything else spoke mid-blend (tapping a letter tile or 🔊) | Test bot got stuck | Child stuck on the question and unable to continue | Fixed + regression test |
| 2 | A brand-new item could fill 4 of 6 questions, often back to back | Logic test | Monotonous lesson; the same question twice in a row | Fixed (max 2 per lesson) + test |
| 3 | "is" was taught as a sound-it-out word, but its s says /z/ | Content test | Taught a wrong decoding | Removed |
| 4 | Keyword picture for i (inchworm 🐛) was the same as the picture for "bug" | Content test | "i" taught with a picture children call "bug" | Replaced with a drawn igloo |
| 5 | mug/cup and sad/mad could appear as choices in the same question | Logic test (2% of draws) | Two "right-looking" answers | Fixed + test |
| 6 | New sounds could be quizzed vowel against vowel (a / e / u) | Logic test (30% of draws) | Hardest sounds to tell apart, made worse by the computer voice | Fixed: new sounds get at most one vowel option |
| 7 | "New number" card was wider than a small phone (338px on a 320px screen) | Layout test | Sideways scrolling | Fixed |
| 8 | One tap on ✕ threw the lesson away instantly | Child-safety test | Accidental exits are common at 4–5 | Now asks "Stop playing?", with "Keep playing" as the big default |
| 9 | With the voice off, the "correct!" moment flashed for about 0.3 s | Timing test | Child never sees the success feedback | Now at least about 1.1 s |
| 10 | Pressing Slide again after the pictures appeared reset the question and wiped the child's answers | Interface test | Lost progress and confusion | Fixed + test |
| 11 | The opening instruction cut off a slide the child had already started | Code review during fix 1 | Blend silently aborted | Fixed |
| 12 | Wiggle-break timer counted idle time on the map | Code review | Break demanded right after opening the app | Now counts lesson time only |
| 13 | A broken day streak still showed the old number | Code review + test | Misleading | Shows 0 |
| 14 | Weak pictures (dig ⛏️, zip 🤐, sit 🪑, tap 🚰) | Picture audit | Child can read the word and still "fail" the picture | Removed |
| 15 | First-sound question for q used a crown 👑 (sounds like c) | Picture audit | Wrong answer looks right | First-sound task skipped for q and x |

The tests also confirmed things that work: distractors never include the answer or duplicates; look-alike letters
are kept apart while new and contrasted once known; words only ever use taught sounds; levels and boxes stay in
range; the game survives blocked or corrupted storage; the daily limit and grown-up override work; and Ziggy never
says "undefined" or "NaN" (checked over 50+ utterances).

## 2. Experiment: simulated children over 6 weeks

`node tests/lucas-reading-island/simulate_learners.js` runs the game's real lesson planner and spaced-repetition
engine with 30 simulated children per profile, 3 lessons a day for 42 days. The learner model is deliberately
simple (each correct answer raises the chance of the next one, and days away lower it). It's useful for comparing
versions, not for predicting a real child.

**Before the fixes**, three pacing problems showed up:
- **Too much failure for younger kids.** The typical 5-year-old averaged 60% first-try accuracy and the young
  4-year-old 51%, with 39% of the young child's lessons under 50%. Learning research generally aims for
  about 70–85% success, and young children disengage when they fail more than they succeed.
- **Letter names stalled at about 15 of 26** once a child moved on to Sound Jungle.
- **Random tappers just failed.** 63% of their lessons were under 50%, with nothing to intervene.

**What changed:**
- **Adaptive difficulty.** After hard lessons (under 65% right) no new material is added, and new items
  show 2 choices instead of 3.
- **Letter names travel with sounds.** Introducing a sound also introduces its letter name, and every Sound
  Jungle lesson reviews one letter name.
- **Impulse guard.** Two quick wrong taps pause the choices briefly ("Whoa, slow down! Let's listen first.")
  and tell the grown-ups.

**After vs before (same simulated children; adaptive difficulty on vs off):**

| Profile | Avg first-try accuracy | Lessons under 50% | Sound Jungle opens | Word Volcano opens | Week 6: letters / sounds / words known |
|---|---|---|---|---|---|
| Quick 6-year-old | 74% → **75%** | 6% → **5%** | day 4 → 4 | day 15 → 14 | 22/26/28 → 21/26/30 |
| Typical 5-year-old | 60% → **65%** | 22% → **17%** | day 6 → 6 | day 20 → 21 | 19/20/17 → 19/18/16 |
| Young 4-year-old | 51% → **59%** | 39% → **26%** | day 8 → 10 | day 28 → 33 | 18/13/6 → 17/13/5 |
| Random guesser | 40% → **48%** | 63% → **48%** | day 22 → 26 | never → never | 10/3/0 → 9/2/0 |

Letter names known by week 6 rose from about 16/15/14 (first version) to 21/19/17 for the quick, typical and young
profiles. That comparison is approximate: the first run used a slightly different version of the model.

**Takeaways:**
- Adaptive difficulty noticeably cut frustration for younger and struggling children, at a cost of a few days'
  pace and about the same learning.
- Accuracy for the typical and young profiles is still below the 70% comfort zone. The next lever is real data
  from Lucas, not more tuning against a made-up model.
- The game correctly doesn't push a guesser forward. It now also slows them down and tells the grown-up.
- At 9 minutes a day, a typical 5-year-old reaches reading 3-letter words in about 3 weeks. That's plausible for
  a game used as a supplement to reading with an adult.

## 3. Developmental-psychology review

**Method:** a cognitive walkthrough of every screen as three typical children, checked against what's known
about 4–6-year-olds' attention, working memory, motor skills, motivation and early literacy.

- **Child A, 4 years:** can't read, knows a few letters, 5–8 minute attention span, imprecise taps, taps
  impulsively.
- **Child B, 5 years:** knows about 10 letter names, some sounds, enjoys collecting things.
- **Child C, 6 years:** knows most letters, impatient with easy material, motivated by levels.

### What works well
- **Fits pre-readers.** Every instruction is spoken, there's a replay button on every question, and nothing
  requires reading. The speech bubble is for grown-ups.
- **Fits young motor skills.** Choices are 92–132px (tested at 64px or more even on a 320px phone), there's no
  dragging except optional tracing, and tracing has a forgiving fallback.
- **Fits working memory.** 3 choices for new items, at most about 5 items in progress, and 2–4 minute lessons.
- **Kind error handling.** Gentle "Oops! Try again", the answer is highlighted after 2 tries, and Ziggy finishes
  a word build after 3. Children practise success instead of failure.
- **Good teaching sequence.** Teaching card, then guided blending, then building with tiles, then reading alone.
- **Effort praise** ("You kept trying!") rather than ability praise, in line with Mueller & Dweck (1998).
- **Personal greeting.** Hearing their own name ("Hi, Lucas!") reliably grabs a young child's attention.
- **Privacy.** No accounts, ads or data collection, and the microphone is off by default.

### Concerns and recommendations

| Area | Concern | Severity | Action |
|---|---|---|---|
| **Voice quality** | The computer voice adds "uh" to stop sounds ("buh" for /b/) and blurs short vowels. Teaching sounds with an added "uh" makes blending harder ("buh-a-tuh" doesn't sound like "bat"). **Biggest remaining learning risk.** | High | **Recommended:** record a real person saying the 26 sounds (about 10 minutes). I can add a "record your voice" option for the grown-ups area. |
| Reward density | XP, stars, levels, hats, stickers, combos and streaks all at once. Strong expected rewards for finishing tasks can lower children's own interest over time (Deci, Koestner & Ryan, 1999). | Medium | **Partly fixed:** results now show competence feedback ("You know 8 letters!" plus the letters). **For you to decide:** make stickers an occasional surprise rather than every lesson, hide the 🔥 combo counter for under-5s, and drop stars or give them a use. They currently do nothing, which confuses children. |
| Streaks | 4–6-year-olds don't track days; streaks mostly pressure parents. | Low | Fixed so a broken streak shows 0 with no "lost" message. Could move to the grown-ups area only. |
| Impulsive tapping | Inhibitory control is still developing at 4. Fast guessing gets feedback without learning. | Medium | **Fixed:** "Let's listen first" pause, plus a grown-up tip. |
| Frustration for young or struggling kids | See experiment. | Medium | **Fixed:** adaptive difficulty. |
| Blending order | Words starting with a stretchable sound (s, m, f…) are easier to blend than ones starting with a stop (t, p). | Low | **Fixed:** these come first among words that become readable at the same time. |
| Tracing | Many 4-year-olds can't yet form letters precisely. | Low | Forgiving scoring, lower bar after each try, Next after two tries. |
| Accidental exits | Common at this age. | Medium | **Fixed:** "Stop playing?" confirmation. |
| Locked worlds | Can frustrate ("I want the volcano!"). | Low | Ziggy explains what opens it. Fine as is. |
| Grown-up gate | A strong 6-year-old might solve "14 + 5". | Low | Fine for 4–5. Could switch to a harder gate if Lucas gets past it. |
| Hearing or language | Fully audio-dependent and English-only. | Info | Not suitable for deaf or hard-of-hearing children without changes. |
| Screen time | Short sessions, breaks and limits are good. Shared use is better than solo. | Info | The grown-ups area now nudges co-play when a child struggles. |

## 4. Suggested real trial with Lucas (about 1 week)

1. **Before:** show Lucas the 26 lowercase letters on paper in random order. Note which ones Lucas can name and
   what sound Lucas gives for each (2 minutes).
2. **Play:** 2–3 lessons a day, with an adult nearby for the first 2 days.
3. **Watch for:** sighs, rapid tapping, looking away, asking to stop (frustration); smiling, repeating sounds
   aloud, asking for more (engagement); any picture Lucas names differently from the game (send me those).
4. **Check the grown-ups area** daily: first-try accuracy should mostly sit around 65–85%.
5. **After a week:** repeat the letter check and compare. Send me the notes and I'll tune the pacing to Lucas.
