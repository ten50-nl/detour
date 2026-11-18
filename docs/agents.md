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

`which` gives the same answer as a click from an unknown app: your rules, Google account hints, what Detour learned and your browser history all count. App rules don't, because there is no source app. It only reads Detour's settings and never changes them.

## MCP server

`detour mcp` is an MCP server over stdio with three tools:

| Tool | Does |
|---|---|
| `which_browser` | Which destination, browser and profile a URL opens in, and why. Read only. |
| `open_link` | Opens a URL through Detour, exactly like a click. |
| `list_browsers` | Your destinations with browser and profile names. |

The server also gives the agent instructions: check Detour before browsing, match the result to the browser it controls, and tell you when they don't match.

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

Claude in Chrome connects to each Chrome profile as a separate browser. Out of the box they are called "Browser 1", "Browser 2" and so on, which tells Claude nothing about which profile is which.

Fix that once: ask Claude to switch browsers, click Connect in each profile and give it the same name as its Detour destination (for example Work and Personal). From then on Claude can match Detour's answer to the right connection.

Claude in Chrome asks you before switching between connected browsers, and Detour doesn't change that. What changes is that Claude knows which one to recommend, and warns you when you're about to do work things in your personal profile.

## Limits

- Not in the Mac App Store version yet. Its sandbox doesn't allow a command line tool.
- Firefox and Safari destinations are reported as such. Claude in Chrome can only drive Chromium browsers.
