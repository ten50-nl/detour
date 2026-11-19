# Detour for AI agents

AI agents open links too. Detour helps them land in the right browser profile.

## What already works

Links an agent opens through macOS, like `open https://...` from Claude Code or a terminal, already go through Detour, just like a click in any other app.

Agents that drive a browser directly, like Claude in Chrome, skip the system. For those Detour has a command line tool and an MCP server, so the agent can ask Detour which browser and profile a link belongs to.

## The `detour` command

It ships inside the app at `/Applications/Detour.app/Contents/Helpers/detour`. Homebrew puts it on your PATH.

```sh
detour which https://github.com/your-company/app
# Opens in Work (Google Chrome, profile "Work"): matches your rule github.com/your-company. URL: https://github.com/your-company/app

detour which https://docs.google.com/document/d/abc --json
detour browsers
detour open https://example.com     # opens it like a click
```

`which` gives the same answer as a click from an unknown app: your rules, Google account hints, what Detour learned and your browser history all count. App rules don't, because there is no source app. It only reads Detour's settings and never changes them. The one file the MCP server writes is `agent-browsers.json`, with the Claude in Chrome pairings.

## MCP server

`detour mcp` is an MCP server over stdio with four tools:

| Tool | Does |
|---|---|
| `which_browser` | Which destination, browser and profile a URL opens in, and why. Read only. |
| `open_link` | Opens a URL through Detour, exactly like a click. |
| `list_browsers` | Your destinations with browser and profile names. |
| `remember_browser` | Saves which Claude in Chrome connection belongs to a destination. |

The server also gives the agent instructions: check Detour before browsing, use the connection Detour remembered for that profile, and tell you when the browser in use doesn't match.

**Claude Code**

```sh
claude mcp add --scope user detour -- /Applications/Detour.app/Contents/Helpers/detour mcp
```

**Claude Desktop, Cursor and others**

```json
"detour": { "command": "/Applications/Detour.app/Contents/Helpers/detour", "args": ["mcp"] }
```

Settings → General → Use with AI agents has both with a copy button.

## Claude in Chrome

Claude in Chrome connects to each Chrome profile as a separate browser, called "Browser 1", "Browser 2" and so on. Those names tell Claude nothing, and a name you give a connection doesn't stick between sessions.

So Detour remembers the connection instead. The first time Claude needs a profile it doesn't know yet, it opens a tab in each unknown connection, asks you which window it appeared in, and saves the pairing with `remember_browser`. From then on `which_browser` returns the connection ID with the answer, and that ID stays the same across sessions. The pairings live in `agent-browsers.json` next to your Detour settings.

Claude in Chrome asks you before switching between connected browsers, and Detour doesn't change that. What changes is that Claude knows which one to recommend, and warns you when you're about to do work things in your personal profile.

## Limits

- Not in the Mac App Store version yet. Its sandbox doesn't allow a command line tool.
- Firefox and Safari destinations are reported as such. Claude in Chrome can only drive Chromium browsers.
