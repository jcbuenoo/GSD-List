# Lucas Reading Island

A playful, self-contained learn-to-read game for 4 to 6 year olds, made for Lucas (the child's name can be changed
in the Grown-ups area). Open `index.html` in any modern browser
(Chrome, Edge, Safari, Firefox; tablet or phone works best). No install, no account, no tracking. Progress is saved
in the browser on that device.

Children explore an island with Ziggy, a friendly little dragon, through four worlds:

| World | What children learn | Activities |
|---|---|---|
| **Letter Meadow** | Recognising letters and their names | Meet-the-letter cards, pop the matching balloon, pop the letter you hear, big-and-little letter partners, finger tracing |
| **Number Nook** | Numbers 0 to 10 and counting | Meet-the-number cards, pop the number you hear, touch-to-count with ten-frames |
| **Sound Jungle** (unlocks after 8 letters) | Letter sounds (phonics) and first sounds in words | Which letter says /s/?, first-sound pictures, "Your turn! Say it!" |
| **Word Volcano** (unlocks after 10 sounds) | Blending 2 and 3 letter words | Tap-and-slide blending, build-the-word letter tiles, read the word and pick the picture |

## Rewards and motivation

- XP for every answer, level-ups with a celebration, and a new hat for Ziggy at levels 2 to 8
- A sticker from a gift box after every lesson (40 to collect in the Sticker Book)
- Stars, combo streaks (3 in a row), a daily goal of 3 lessons, and a day streak
- Praise is about effort and strategy ("You kept trying!"), never "you're smart"

## The learning science built in

- **Systematic synthetic phonics** in a high-utility order (s a t i p n first), so real words are readable early
- **Look-alike letters** (b/d, p/q, m/n...) are introduced far apart and kept out of each other's way while new, then deliberately contrasted once known
- **Letter names and sounds** taught with **keyword pictures** (s, sun)
- **Phonemic awareness**: first-sound isolation and oral blending
- **Decodable words only**: a word appears only after all of its letter sounds have been taught
- **Gradual release** (I do, we do, you do): teaching card, guided blending, building with tiles, reading alone
- **Spaced repetition** (Leitner boxes 0 to 5, with due times from hours to a week) and **retrieval practice**
- **Small working set**: new items are added only when about 75% of current ones are learned, with at most 5 in progress
- **Multisensory tracing** and **saying sounds aloud** (production effect)
- **Errorless scaffolding**: gentle retry, the answer is highlighted after 2 misses, and Ziggy helps finish
- **Adaptive difficulty**: after hard lessons, no new material is added and new items show fewer choices
- **Impulse guard**: rapid random tapping pauses the choices briefly ("Let's listen first")
- **Names and sounds together**: Sound Jungle also reviews letter names, so they keep progressing
- **Easier blends first**: words starting with stretchable sounds (s, m, f…) come before words starting with stops (t, p)
- **Competence feedback**: results show what the child now knows, not just prizes
- **Short lessons** (about 2 to 4 minutes), optional **wiggle breaks** and **daily time limits**
- **Andika** typeface, designed for beginning readers; lowercase first by default

The Grown-ups area (behind a simple adult math gate) explains each point with research references, shows a
mastery map of every letter, sound, number and word, lists the trickiest items to practise together, and has settings
(voice, speed, letter case, lesson length, breaks, time limits, unlock all, reset).

## Tests and experiment

See [TEST_REPORT.md](TEST_REPORT.md) for bug-test results, a simulated-learner experiment and a
developmental-psychology review.

```bash
node tests/lucas-reading-island/run_tests.js
```

```bash
node tests/lucas-reading-island/simulate_learners.js
```

Both need Playwright with Chromium. The game exposes a test hook only when opened with `?test=1`.

## Inspiration

Inspired by how popular early-reading products (ABCmouse, Teach Your Monster to Read, Duolingo ABC, Hooked on Phonics,
Reading Eggs) combine a map of worlds, short activities and collectable rewards. Everything here (characters, art,
names, activities and code) is original.

## Known limitations

- **Voice is the device's text-to-speech.** Letter names sound right, but isolated phonemes are approximations
  ("buh" for /b/, "ah" for short a, "aw" for short o), and quality varies by device and browser. Each sound is
  followed by its keyword ("like sun") to make it clear. Recorded human audio would be a worthwhile upgrade.
- **"Say it!" does not grade pronunciation.** It's a production-practice step. The optional microphone mode
  (off by default; Chrome/Edge only) uses the browser's speech recognition, which may send audio to the browser
  maker's servers, and only checks that the child spoke.
- **Emoji pictures** depend on the device's emoji font; very old devices may show some as boxes.
- Progress lives in one browser's local storage; clearing site data erases it and it doesn't sync between devices.
