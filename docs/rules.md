# Rules reference

Detour keeps its settings in `~/Library/Application Support/Detour/rules.json`. You can edit everything in the app (Settings → Destinations), but the file is plain JSON and Detour picks up changes as soon as you save it.

## How Detour decides

For every link, Detour walks through these steps and stops at the first one that gives a clear answer:

1. **Option key.** If you hold ⌥ while clicking, Detour always asks.
2. **Meeting apps.** With "Open Zoom, Teams and Slack links in their apps" turned on, those links skip the browser entirely.
3. **Your rules.** Each destination has a list of patterns. Destinations are checked in the order they appear in settings, so the first destination with a matching pattern wins.
4. **App rules set to "always".** Links from that app go to its destination, whatever the site.
5. **Google links.** Calendar invites contain the calendar owner's email address, and some Google links carry `authuser=<email>`. Detour looks that address up in the account map. Google Docs, Sheets, Slides and Drive files you opened before go to the profile where you opened them.
6. **Choices you taught it.** When you pick a destination in the picker (with "remember" on) or use "Open in…" from the menu bar, Detour remembers it for that site, or for that one file in the case of Google files.
7. **Your history.** If at least 80% of your visits to a site in the last 90 days were in one destination, and you visited it at least 5 times, the link goes there. For sites that host many workspaces (GitHub, GitLab, Bitbucket, Notion, Linear, Vercel and Figma teams) Detour looks at the workspace in the link first, so `github.com/acme` and `github.com/yourname` can go to different places.
8. **The app you clicked in.** App rules set to "new and unclear sites" handle sites without clear history. App rules set to "only to break a tie" only settle sites you've used in several places. And once at least 10 links from one app clearly went to the same destination (85% or more), Detour uses that for new sites from that app by itself. Only the last 50 links per app count, so when your habits change it backs off on its own, and Settings → Apps has a Forget button to start over.
9. **Ask.** Detour shows the picker when it has some evidence but nothing clear: sites in the ask list (Gmail, Google Docs and similar), sites you opened in more than one place without a clear favourite, and sites you visited only a few times (fewer than 5) in the last 90 days.
10. **Default.** Everything else opens in your default destination.

Before any of this, Detour removes tracking parameters (`utm_…`, `fbclid`, `gclid` and similar) from the link, unless you turned that off.

## Patterns

| Pattern | Matches |
|---|---|
| `example.com` | `example.com` and every subdomain, like `app.example.com` |
| `~word` | any site whose host contains `word` |
| `*.example.test` | any subdomain of `example.test` |
| `shop*.test` | `shop.test`, `shop2.test`, `shop-dev.test` (a `*` stays within one part of the host) |
| `url:*meet*` | the full link, with `*` matching anything |

Hosts are compared in lowercase, without `www.` and without a trailing dot.

## File format

```json
{
  "version": 2,
  "destinations": [
    {
      "id": "google-chrome-profile-1",
      "name": "Work",
      "appPath": "/Applications/Google Chrome.app",
      "bundleID": "com.google.Chrome",
      "profileDir": "Profile 1",
      "profileName": "Work",
      "account": "me@company.com",
      "color": "#4F8BFF",
      "patterns": ["company.atlassian.net", "~company"]
    },
    {
      "id": "firefox",
      "name": "Firefox",
      "appPath": "/Applications/Firefox.app",
      "bundleID": "org.mozilla.firefox",
      "color": "#FF7A1A",
      "patterns": ["youtube.com", "youtu.be"]
    },
    {
      "id": "google-chrome-default",
      "name": "Personal",
      "appPath": "/Applications/Google Chrome.app",
      "bundleID": "com.google.Chrome",
      "profileDir": "Default",
      "profileName": "Me",
      "color": "#34C759",
      "patterns": []
    }
  ],
  "defaultDestination": "google-chrome-default",
  "accountMap": {
    "company.com": "google-chrome-profile-1",
    "me@gmail.com": "google-chrome-default"
  },
  "askHosts": ["docs.google.com", "drive.google.com", "mail.google.com", "calendar.google.com", "meet.google.com"],
  "sourceRules": [
    { "app": "Slack", "target": "google-chrome-profile-1", "strength": "whenUnsure" },
    { "app": "Ferdium", "titleContains": "WhatsApp", "target": "google-chrome-default", "strength": "tieBreaker" }
  ],
  "cleanLinks": true,
  "openInApps": false
}
```

- `profileDir` is the folder name of a Chrome-family profile (`Default`, `Profile 1`, ...). Leave it out to open the browser as a whole.
- `profileName` is the profile's name in the browser. If the browser no longer has that name, Detour warns you in settings but keeps routing. If the profile folder is gone, its links go to your default destination.
- `accountMap` keys are a full email address or a domain. A full address wins over its domain.
- `sourceRules` match the app name you clicked in, and optionally part of its window title (needs Accessibility). `strength` is `always`, `whenUnsure` (new and unclear sites) or `tieBreaker` (only sites used in several places). Rules without a strength are tie-breakers.
- Add `"privateWindow": true` to a Chrome-family or Firefox destination to open its links in an incognito or private window.
- `cleanLinks` removes tracking parameters. `openInApps` opens Zoom, Teams and Slack links in their desktop apps when installed.

## Other files

| File | What's in it |
|---|---|
| `learned.json` | choices you taught Detour |
| `history-index.json` | a summary of your browser history: per site, how often you visited it in each destination |
| `decisions.jsonl` | a log of the last 90 days of decisions (site, app, destination, why). Handy to see what Detour did. |

Delete any of them to start that part fresh.
