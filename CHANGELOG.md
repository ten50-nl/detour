# Changelog

## 1.5.0

- Rewrite links: swap a site for another before it opens, like x.com to xcancel.com or reddit.com to old.reddit.com (Settings → General).
- Export and import your settings as a JSON file, or show it in Finder to keep it in your dotfiles. Importing backs up your current settings first.
- Settings → Test a link shows the link as it will open, after rewrites and tracking removal.

## 1.4.0

- Settings is now a native macOS settings window with a toolbar.
- The picker sits on a frosted glass background, and the menu bar shows browser icons.
- Shortcuts actions: "Open link with Detour" and "Where does a link open?".
- Spotify, Music, Discord, Linear and Notion links can open in their apps, next to Zoom, Teams and Slack.
- Also coming to the Mac App Store.

## 1.3.0

- Optional automatic update check, off by default. Turn it on in settings or during setup and Detour asks GitHub once a day for a new version, then installs it in place after checking the signature. Homebrew installs get the brew command instead.
- "Check for updates" in the menu bar.
- Learning per app now looks at your last 50 links from that app only, so it follows you when your habits change. Settings → Apps has a Forget button per app.
- Moved to the ten50-nl organisation on GitHub. Old links and the Homebrew tap keep working.

## 1.2.0

- App rules in settings: send links from an app (Slack, Teams, Messages, ...) to a destination, either always, for new and unclear sites, or only to break a tie.
- Learns per app: once most links from an app go to the same place, new sites from that app go there too.
- Workspace-aware learning for GitHub, GitLab, Bitbucket, Notion, Linear, Vercel and Figma teams.
- Removes tracking parameters from links (on by default).
- Optionally opens Zoom, Teams and Slack links in their desktop apps.
- Destinations can open in an incognito or private window.
- Smart start suggests app rules for chat apps you have installed.

## 1.1.0

- Learns from your Safari history too, so Safari counts as a destination in history, suggestions and Smart start.

## 1.0.0

First public release.

- Routes every link to the right browser or browser profile, based on your rules, Google account hints, choices you taught it and your browsing history.
- Picker for links it can't place, with number keys. Hold ⌥ while clicking to always choose yourself.
- Onboarding that finds your browsers and profiles and suggests rules from your history.
- Menu bar list of recent links with "Open in…" to correct and teach.
- "Test a link" in settings shows where any link would go, and why.
- Supports Chrome, Brave, Edge, Vivaldi and Chromium profiles, plus any other browser as a whole.
