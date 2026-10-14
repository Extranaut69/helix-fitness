# Helix Fitness

A personal fitness app for iPhone and Apple Watch. Each person gets their own plan: calorie and macro targets set from their own Apple Watch energy data, a daily readiness score from HRV, resting heart rate, sleep and training load, LiDAR-measured meal portions, a coach, workouts and meal plans.

It uses only free, open or on-device technology. There are no paid APIs and no servers.

| Feature | How it works | Cost |
|---|---|---|
| Watch data | HealthKit: active and resting energy, HRV, resting HR, sleep stages, VO₂ max, body mass, workouts | Free |
| Food recognition | Apple Vision instance masks, plus Apple's built-in classifier or your own open-source Core ML model, all on the device | Free |
| Portion size | ARKit LiDAR scene depth: height above the plate × pixel footprint gives volume, and volume × density gives grams | Free |
| Nutrition data | Bundled USDA FoodData Central values (public domain) | Free |
| Barcodes | VisionKit scanner + [Open Food Facts](https://world.openfoodfacts.org) (open data, no key) | Free |
| AI coach | Apple Foundation Models (on-device, iOS 26 + Apple Intelligence), with a rule-based fallback | Free |

## What's here

```
prototype/index.html     Clickable web prototype with sample data (open in any browser)
ios/project.yml          XcodeGen spec → generates Helix.xcodeproj
ios/Shared/              Engines shared by iPhone + Watch (targets, readiness, sync payloads)
ios/Helix/               iPhone app (SwiftUI + SwiftData)
  App/                   App entry, AppModel (active person, targets, Watch sync)
  Health/                HealthKit reads and nutrition writes
  Food/                  Food DB, recogniser, LiDAR portion estimator, scan + barcode UI
  Training/ Plan/ Coach/ Today/ Profile/ UI/ Sync/
  Resources/foods.json   Nutrition table (add foods here)
ios/HelixWatch/          Watch app: readiness, live HR zones, workout session, set logging
```

## Build it (needs a Mac)

HealthKit, ARKit and LiDAR only run in a native app, so you need a Mac with **Xcode 26** (Xcode 15 or later also works, but without the on-device AI coach).

1. `brew install xcodegen`
2. `cd ios && xcodegen`. This creates `Helix.xcodeproj`.
3. Open it, select the **Helix** target, go to **Signing & Capabilities**, and choose your team. A free Apple ID is enough to install on your own phone. Change `bundleIdPrefix` in `project.yml` to something unique, such as `com.yourname.helix`.
4. Plug in your iPhone, enable Developer Mode on it, and press Run. The Watch app installs with it.

With a free Apple ID, the app stops opening after 7 days and you have to press Run again. To share with family or friends through TestFlight, or to publish on the App Store, you need the Apple Developer Program, which costs $99 a year. That fee is Apple's, not this app's.

**LiDAR** is on iPhone 12 Pro and later Pro models. Other iPhones use photo recognition with typical serving sizes, and you adjust the grams yourself.

## Cloud build (no Mac needed)

[`.github/workflows/ios-build.yml`](.github/workflows/ios-build.yml) compiles both apps on a GitHub macOS runner with Xcode 26 every time you push changes under `ios/`. It only checks that the code compiles: nothing is signed, installed or published. You can also start it by hand from **Actions → iOS build → Run workflow**.

Reading the results:

1. Open the repo on GitHub and go to the **Actions** tab. Each push gets a run with two jobs, **Build Helix** (iPhone) and **Build HelixWatch** (Watch).
2. A green tick means that app compiled. A red cross means it didn't.
3. For a failed run, open it and scroll to the **summary**: it lists every `error:` line with its file and line number, for example `ios/Helix/Food/ScanView.swift:42:17: error: ...`.
4. The full log is attached at the bottom of the run under **Artifacts** (`build-log-Helix`, `build-log-HelixWatch`) for 14 days.

Free minutes: macOS runners are free and unlimited on **public** repositories. On a **private** repository they use your free monthly Actions minutes, and macOS minutes count 10× (a free account's 2,000 minutes is about 200 macOS minutes, or roughly 15–20 builds). A green cloud build does not replace testing on a real iPhone: HealthKit, LiDAR and the Watch link can only be checked on devices.

## Better food recognition (optional, still free)

Without extra setup, Helix uses Apple's built-in image classifier, which knows many foods but not all dishes. For better results, add a food-specific model named `FoodClassifier.mlmodel` to `ios/Helix/Resources/` and regenerate the project. Two free ways to get one:

- **Create ML (easiest, on a Mac):** download the open [Food-101](https://data.vision.ee.ethz.ch/cvl/datasets_extra/food-101/) dataset, open Create ML, choose Image Classifier, point it at the image folders, train, and export. Add Indian or other regional dishes by adding folders of your own photos.
- **Convert an open-source model:** take an image classifier fine-tuned on Food-101 from Hugging Face (check its licence) and convert it with `coremltools`.

Classifier labels are mapped to nutrition data through the `aliases` in `foods.json`. Add aliases there when a label doesn't match.

## How the numbers are calculated

- **Calories:** resting energy + 7-day average active energy from the Watch, then adjusted for the goal (fat loss −20%, muscle gain +10%, recomposition +5% on training days and −12% on rest days). Each week the weight trend is compared with the goal pace, and the target moves ±150 kcal if progress is off.
- **Macros:** protein 1.6–2.2 g/kg depending on goal, fat at least 0.8 g/kg (about 27% of calories), carbs fill the rest. Endurance goals use 6 g/kg carbs on training days and 3.5 g/kg on rest days.
- **Readiness (0–100):** 35% HRV vs your 28-day baseline, 20% resting HR vs baseline, 30% sleep vs 8 h, 15% load ratio (7-day vs 28-day active energy).
- **People without a Watch:** HealthKit belongs to the phone's owner, so only one profile per iPhone links to it. Other people on the same device get estimated energy (Mifflin–St Jeor and activity level). For the best results, each person installs Helix on their own iPhone.

## Status

Both apps compile cleanly with Xcode 26 in the cloud build (see above), but they have **not been run on a device yet**. Test LiDAR portion accuracy against a kitchen scale before relying on it. The web prototype runs as-is.

Helix gives general fitness guidance, not medical advice.
