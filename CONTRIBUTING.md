# Contributing to Detour

Thanks for helping out. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug

Open an [issue](https://github.com/ten50nl/detour/issues/new/choose) with the bug template. The most useful things to include:

- your macOS version and Detour version (Settings → General)
- the link that went to the wrong place, and where you expected it
- what Settings → Test a link says about that link ("Decided by" and "Why")

Please remove anything private from links before you paste them.

## Suggesting a feature

Open an issue with the feature template and describe the situation you're in, not only the solution. "Links from Teams meetings keep opening in my personal profile" helps more than "add a Teams option".

## Working on the code

You need Xcode 16 or later.

```sh
git clone https://github.com/ten50nl/detour.git
cd detour
swift test
DETOUR_CONFIG_DIR=/tmp/detour-dev scripts/build-app.sh
open build/Detour.app
```

- `Sources/DetourCore` holds all routing logic and has no AppKit. Every change there needs a test in `Tests/DetourCoreTests`.
- `Sources/Detour` is the app: onboarding, picker, menu bar and settings.
- `DETOUR_CONFIG_DIR` keeps your test settings away from your real ones, and `DETOUR_DEMO=1` shows made-up browsers and profiles, handy for screenshots.

Keep pull requests small and focused, run `swift test` before you open one, and describe how you tested it.

## Code of conduct

Be kind and assume good intent. That's it.
