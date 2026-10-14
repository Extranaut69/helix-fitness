# Helix

Helix is a fitness app for iPhone and Apple Watch. Every morning it gives each person one answer: how hard to train today, and how much to eat.

When you open the app, the Today screen is already a colour. Green means go hard, amber means train as planned, and lilac means take a recovery day. The colour comes from your readiness score, which is built from your HRV, resting heart rate, sleep and training load. Below it are the calories you have left, your meals as a timeline, and your weight trend. The Watch face uses the same colour.

Helix uses only free, open or on-device technology. There are no paid APIs, no accounts and no servers.

## What it does

- **Readiness, 0 to 100.** Uses HRV and resting heart rate compared with your own baseline, plus sleep and training load. It sets the day's colour and how hard the session is.
- **Calorie and macro targets.** Built from the energy your own Apple Watch measures, not a generic formula, and adjusted for your goal and for training days.
- **Portions measured, not guessed.** The LiDAR camera on Pro iPhones maps the height of food on the plate and turns volume into grams.
- **Food recognition and barcodes.** Photos are recognised on the phone. Packaged food is looked up in Open Food Facts.
- **Training.** Each session is chosen by goal and readiness. Weights go up automatically when you hit every rep, and you log sets with one tap on the Watch.
- **A coach.** Ask what to eat next, whether to train hard, or how your progress is going. It answers from your own data, on the phone.
- **Family and friends.** Each person has their own targets, goal and diet.

## Built on

| Part | Uses |
|---|---|
| Watch data | HealthKit: active and resting energy, HRV, resting heart rate, sleep stages, VO₂ max, body mass, workouts |
| Food recognition | Apple Vision instance masks, plus Apple's built-in classifier or your own open-source Core ML model |
| Portion size | ARKit LiDAR scene depth: height above the plate times pixel footprint gives volume, and volume times density gives grams |
| Nutrition data | Bundled USDA FoodData Central values (public domain) |
| Barcodes | VisionKit scanner and [Open Food Facts](https://world.openfoodfacts.org) (open data, no key) |
| Coach | Apple Foundation Models (on-device, iOS 26 with Apple Intelligence), with a rule-based fallback |

## What's here

```
prototype/index.html     Clickable web prototype with sample data (open it in any browser)
ios/project.yml          XcodeGen spec that generates Helix.xcodeproj
ios/Shared/              Code shared by iPhone and Watch: targets, readiness, sync payloads, colours and type
ios/Helix/               iPhone app (SwiftUI and SwiftData)
  App/                   App entry, AppModel (active person, targets, Watch sync)
  Health/                HealthKit reads and nutrition writes
  Food/                  Food database, recogniser, LiDAR portion estimator, scan and barcode screens
  Training/ Plan/ Coach/ Today/ Profile/ UI/ Sync/
  Resources/foods.json   Nutrition table (add foods here)
ios/HelixWatch/          Watch app: readiness, live heart-rate zones, workout session, set logging
```

## Design

One idea carries the look: **the readiness colour**. It fills the top of the Today screen and the Watch face, and it appears nowhere else as decoration. Everything around it is kept plain: a cool grey-white surface (graphite in dark mode), one blue for buttons, and structure made with spacing and timelines instead of a stack of cards.

- **Type:** one family at several widths. The score is set compressed and heavy, titles condensed, and body text at normal width. Numbers use tabular figures so columns line up. The iPhone uses SF Pro widths (`.width(.compressed)`) and the prototype uses Archivo, both free.
- **Colour:** the readiness colours are green `#23C16B`, amber `#FFB21E` and lilac `#9B8CFF`, always with dark text on top. Recovery days are lilac, not red, because rest is part of the plan, not a failure.
- **Motion:** there is one animation. When Today opens, the score counts up. It is skipped when Reduce Motion is on, and the real score always shows at rest.
- **Plain words:** the readiness signals are named Sleep, Recovery and Resting heart, each with a status such as Good or Low. The raw values (HRV in ms, the load ratio) are details, not headlines.

The tokens live in three places that must stay in sync: the `:root` block in [`prototype/index.html`](prototype/index.html), [`ios/Shared/Style.swift`](ios/Shared/Style.swift) (readiness colours and type, shared with the Watch) and [`ios/Helix/UI/Theme.swift`](ios/Helix/UI/Theme.swift) (light and dark surface colours, spacing).

## Build it (needs a Mac)

HealthKit, ARKit and LiDAR only run in a native app, so you need a Mac with **Xcode 26**. Xcode 15 or later also works, but without the on-device coach.

1. `brew install xcodegen`
2. `cd ios && xcodegen`. This creates `Helix.xcodeproj`.
3. Open it, select the **Helix** target, go to **Signing & Capabilities**, and choose your team. A free Apple ID is enough to install on your own phone. Change `bundleIdPrefix` in `project.yml` to something unique, such as `com.yourname.helix`.
4. Plug in your iPhone, turn on Developer Mode, and press Run. The Watch app installs with it.

With a free Apple ID, the app stops opening after 7 days and you have to press Run again. To share with family or friends through TestFlight, or to publish on the App Store, you need the Apple Developer Program, which costs $99 a year. That fee is Apple's, not this app's.

**LiDAR** is on iPhone 12 Pro and later Pro models. Other iPhones use photo recognition with typical serving sizes, and you adjust the grams yourself.

## Cloud build (no Mac needed)

[`.github/workflows/ios-build.yml`](.github/workflows/ios-build.yml) compiles both apps on a GitHub macOS runner with Xcode 26 every time you push changes under `ios/`. It only checks that the code compiles. Nothing is signed, installed or published. You can also start it by hand from **Actions → iOS build → Run workflow**.

To read the results:

1. Open the repo on GitHub and go to the **Actions** tab. Each push gets a run with two jobs, **Build Helix** (iPhone) and **Build HelixWatch** (Watch).
2. A green tick means that app compiled. A red cross means it didn't.
3. For a failed run, open it and scroll to the **summary**. It lists every `error:` line with its file and line number, for example `ios/Helix/Food/ScanView.swift:42:17: error: ...`.
4. The full log is attached at the bottom of the run under **Artifacts** (`build-log-Helix`, `build-log-HelixWatch`) for 14 days.

Free minutes: macOS runners are free and unlimited on **public** repositories. On a **private** repository they use your free monthly Actions minutes, and macOS minutes count 10 times. A free account's 2,000 minutes is about 200 macOS minutes, or roughly 15 to 20 builds. A green cloud build does not replace testing on a real iPhone: HealthKit, LiDAR and the Watch link can only be checked on devices.

## Better food recognition (optional, still free)

Without extra setup, Helix uses Apple's built-in image classifier, which knows many foods but not every dish. For better results, add a food-specific model named `FoodClassifier.mlmodel` to `ios/Helix/Resources/` and regenerate the project. Two free ways to get one:

- **Create ML (easiest, on a Mac):** download the open [Food-101](https://data.vision.ee.ethz.ch/cvl/datasets_extra/food-101/) dataset, open Create ML, choose Image Classifier, point it at the image folders, train, and export. Add Indian or other regional dishes by adding folders of your own photos.
- **Convert an open-source model:** take an image classifier fine-tuned on Food-101 from Hugging Face (check its licence) and convert it with `coremltools`.

Classifier labels are matched to nutrition data through the `aliases` in `foods.json`. Add aliases there when a label doesn't match.

## How the numbers are calculated

- **Calories:** resting energy plus the 7-day average active energy from the Watch, then adjusted for the goal: fat loss −20%, muscle gain +10%, recomposition +5% on training days and −12% on rest days. Each week the weight trend is compared with the goal pace, and the target moves by 150 kcal if progress is off.
- **Macros:** protein 1.6 to 2.2 g per kg depending on goal, and fat at least 0.8 g per kg (about 27% of calories). Carbs fill the rest. Endurance goals use 6 g per kg of carbs on training days and 3.5 g per kg on rest days.
- **Readiness:** 35% HRV against your 28-day baseline, 20% resting heart rate against baseline, 30% sleep against 8 hours, and 15% load ratio (7-day against 28-day active energy). 75 and above is go hard, 55 to 74 is train as planned, and below 55 is a recovery day.
- **People without a Watch:** HealthKit belongs to the phone's owner, so only one profile per iPhone links to it. Other people on the same device get estimated energy (Mifflin–St Jeor and activity level). For the best results, each person installs Helix on their own iPhone.

## Status

Both apps compile with Xcode 26 in the cloud build, but they have **not been run on a device yet**. Test LiDAR portion accuracy against a kitchen scale before relying on it. The web prototype runs as it is.

Helix gives general fitness guidance, not medical advice.
