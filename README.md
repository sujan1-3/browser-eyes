# browser-eyes

Full Chrome DevTools, operated by Claude Code. Linux. 80+ tools across
inspect, edit, intercept, emulate, debug, profile.

## What it does

A daemon launches a chromium-based browser with CDP enabled, holds
persistent connections, mirrors every domain (DOM, network, console,
debugger, CSS, storage, fetch, performance, security), and exposes
everything over a Unix socket. An MCP server sits on top so Claude Code
can call any of it as a tool.

You get:

- **See** — desktop screenshots, tab viewport, full-page captures, element captures
- **Inspect** — DOM, CSS, JS, accessibility tree, every loaded resource, cookies, localStorage, sessionStorage, IndexedDB, service workers, security state
- **Edit live** — DOM (set_html, attributes, remove), CSS (live stylesheet edit or `<style>` override), JS (Debugger.setScriptSource), cookies, all storage
- **Network** — full request/response capture, response bodies, curl export, HAR export, URL blocking, header injection
- **File overrides** — DevTools "Local Overrides": intercept any URL pattern, serve your own content
- **Page control** — navigate, reload, back/forward, print to PDF, save HTML
- **Tabs** — list, open, close, focus
- **Emulation** — device presets, custom viewport, geolocation, user agent, timezone, locale, dark mode, network throttling, CPU throttling, offline
- **Interaction** — click, type, scroll, hover, keypress, focus
- **Debugger** — pause, resume, step over/into/out, breakpoints with conditions
- **Performance** — runtime metrics, JS+CSS coverage, heap snapshots
- **Search** — grep across every loaded resource on the page

## Architecture

```
Claude Code --MCP/stdio--> mcp_server.py
                              |
                              v unix socket
                          daemon.py  (long-lived)
                              |
            +-----------------+------------------+
            v                 v                  v
       CDP client       screen capture     SQLite ring buffer
       (multiplexed     (grim/scrot)       (10 min of events)
       WS to browser
       + per-target)
                              |
                              v
                  Chromium (--remote-debugging-port=9222)
```

The daemon outlives Claude Code sessions, so the browser doesn't relaunch
every time. The MCP server is stateless. They talk over a Unix socket in
`~/.local/state/browser-eyes/`.

## Install

```bash
cd browser-eyes
./install.sh
```

System dependencies (install with your package manager):

- **Wayland**: grim, or gnome-screenshot, or spectacle
- **X11**: scrot, or maim, or imagemagick's `import`
- **Browser**: chromium, google-chrome, brave-browser, etc.

Firefox isn't supported — CDP is chromium-only.

## Use

```bash
browser-eyes start          # launch daemon + dedicated browser window
browser-eyes status         # health check
browser-eyes ops            # list every available operation
browser-eyes tail           # live event stream
browser-eyes logs 50        # last 50 events
browser-eyes stop
```

Then in Claude Code, just ask:

- "what's on my screen" → `see_screen`
- "screenshot just this page" → `screenshot_full_page`
- "show me all the network requests" → `list_requests`
- "what was in the response from /api/login" → `list_requests` then `response_body`
- "give me a curl for that XHR" → `get_curl`
- "export the network log as HAR" → `export_har`
- "list all cookies for github.com" → `cookies_list`
- "clear localStorage" → `local_storage_clear`
- "download every CSS file on this page" → `list_resources` then `get_resource`
- "intercept api.example.com/users and return test data" → `override_create`
- "emulate an iPhone 15" → `set_device`
- "throttle to slow 3G" → `set_network_conditions`
- "force dark mode" → `set_dark_mode`
- "fake my location to Tokyo" → `set_geolocation`
- "click the login button" → `click`
- "what does the element at 500, 300 look like" → `inspect_at_point`
- "find every place apiKey appears in the page resources" → `search_in_resources`
- "take a heap snapshot" → `heap_snapshot`

Or call any op directly from the shell:

```bash
browser-eyes exec list_tabs
browser-eyes exec navigate url=https://example.com
browser-eyes exec cookies_list domain=github.com
browser-eyes exec set_device preset=iphone15
browser-eyes exec run_js code='document.title'
```

## File overrides (DevTools "Local Overrides")

Intercept any URL pattern, serve your own content. Survives page navigation.

```bash
# replace an API response
browser-eyes exec override_create \
    url_pattern='*/api/user/me' \
    content='{"name":"admin","is_admin":true}' \
    mime_type=application/json

# replace a script with a local file
browser-eyes exec override_create \
    url_pattern='*/static/app.js' \
    local_path=/tmp/my_patched.js \
    mime_type=application/javascript

browser-eyes exec override_list
browser-eyes exec override_clear
```

Under the hood: the daemon enables `Fetch.enable` with your patterns, and
the global event handler answers each `Fetch.requestPaused` with
`Fetch.fulfillRequest` if a pattern matches, else `continueRequest`.

## Live editing

```bash
# inject custom CSS (always works, persists till reload)
browser-eyes exec edit_css content='body { background: red !important }'

# patch a JS source by script_id (get id from list_scripts)
browser-eyes exec list_scripts
browser-eyes exec edit_js script_id=42 content='/* new source */'

# DOM
browser-eyes exec set_html selector='h1' html='<h1>pwned</h1>'
browser-eyes exec set_attribute selector='a' name='href' value='https://evil.example'
browser-eyes exec remove_element selector='.cookie-banner'

# storage
browser-eyes exec cookies_set cookies='[{"name":"session","value":"abc","domain":"example.com","path":"/"}]'
browser-eyes exec local_storage_set key=theme value=dark
```

## Device presets

`set_device preset=` accepts: `iphone15`, `iphone_se`, `ipad`, `pixel8`,
`galaxy_s23`, `desktop`. Add more in `handlers.py`'s `DEVICE_PRESETS`.

## Where state lives

```
~/.local/state/browser-eyes/
├── daemon.sock              unix socket the MCP server talks to
├── daemon.pid               for stop/status
├── daemon.log               daemon stdout/stderr
├── events.db                SQLite ring buffer (10 min)
├── browser_profile/         chromium profile (separate from your normal one)
├── frames/                  rolling desktop screenshots
├── overrides/               file bodies for active overrides
└── exports/                 saved files (HAR, PDFs, screenshots, resources)
```

## Notes / gotchas

- The daemon uses a **dedicated browser profile** at
  `~/.local/state/browser-eyes/browser_profile/`. It doesn't read your
  normal Chrome data. To use real sessions, copy your profile in or change
  `--user-data-dir` in `daemon.py`.
- CDP is open on `localhost:9222` while the daemon runs. Anything local
  that can hit loopback can drive your browser. Stop the daemon when
  you're not using it on shared machines.
- Ring buffer is 10 min / 120 frames. Adjust `RING_BUFFER_SECS` and
  `MAX_FRAMES_ON_DISK` in `daemon.py`.
- `screen_loop` captures the whole desktop. For browser-only frames, use
  `screenshot_tab` or `screenshot_full_page` (which go through CDP).
- File overrides only fire while a page is loading. If you want to swap
  content for already-loaded scripts, reload the page after creating
  the override.
- `edit_js` needs a `script_id` from `list_scripts` — IDs come from
  `Debugger.scriptParsed` events, so they only exist for scripts loaded
  after the daemon attached. Reload if you don't see what you want.
- `edit_css` falls back to a `<style>` injection if it can't resolve a
  stylesheet id. That's almost always fine.

## Extending

Adding a new op:

1. Write `async def op_my_thing(state, args)` in `handlers.py`
2. Add it to the `HANDLERS` dict at the bottom
3. Add a `(name, description, schema)` tuple to `TOOLS` in `mcp_server.py`
4. Restart the daemon and reconnect Claude Code

Things worth adding:

- Tab-only screenshots via `Page.captureScreenshot` per-tab on the timer
  instead of desktop frames
- Input recording from `/dev/input/event*` (needs `input` group on linux)
- Audio capture via `parec` for sites with audio elements
- A long-running coverage mode that persists across navigations
- WebSocket frame capture (`Network.webSocketFrameReceived`) for sites
  with realtime channels
- Auth helpers: import/export cookies from your real browser
- Fuzzing helper: replay a captured request with mutated params
