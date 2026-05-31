#!/usr/bin/env bash
# browser-eyes installer
set -euo pipefail

INSTALL_DIR="${HOME}/.local/share/browser-eyes"
BIN_DIR="${HOME}/.local/bin"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Installing to ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}" "${BIN_DIR}"
rm -rf "${INSTALL_DIR}/src"
cp -r "${SRC_DIR}/src" "${INSTALL_DIR}/"
cp "${SRC_DIR}/bin/browser-eyes" "${INSTALL_DIR}/"
chmod +x "${INSTALL_DIR}/browser-eyes" "${INSTALL_DIR}/src/"*.py

echo "==> Checking system deps"
need=()
command -v python3 >/dev/null || need+=("python3")

if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
  command -v grim >/dev/null || command -v gnome-screenshot >/dev/null \
    || command -v spectacle >/dev/null \
    || need+=("grim or gnome-screenshot or spectacle (wayland screenshot)")
else
  command -v scrot >/dev/null || command -v maim >/dev/null \
    || command -v import >/dev/null \
    || need+=("scrot or maim or imagemagick (x11 screenshot)")
fi

have_browser=0
for b in google-chrome google-chrome-stable chromium chromium-browser \
         brave-browser microsoft-edge vivaldi; do
  command -v "$b" >/dev/null && have_browser=1 && break
done
[ $have_browser -eq 0 ] && need+=("a chromium-family browser")

if [ ${#need[@]} -gt 0 ]; then
  echo "!! Missing system dependencies:"
  printf " - %s\n" "${need[@]}"
  echo "   (Daemon will report what's missing at runtime if you continue.)"
  echo ""
fi

echo "==> Creating Python venv"
python3 -m venv "${INSTALL_DIR}/venv"
"${INSTALL_DIR}/venv/bin/pip" install --quiet --upgrade pip
"${INSTALL_DIR}/venv/bin/pip" install --quiet \
  aiohttp websockets "mcp>=1.0.0"

echo "==> Installing launcher to ${BIN_DIR}/browser-eyes"
cat > "${BIN_DIR}/browser-eyes" <<'LAUNCHER'
#!/usr/bin/env bash
INSTALL_DIR="${HOME}/.local/share/browser-eyes"
exec "${INSTALL_DIR}/venv/bin/python" "${INSTALL_DIR}/src/daemon.py" "$@"
LAUNCHER
chmod +x "${BIN_DIR}/browser-eyes"

echo "==> Registering MCP server with Claude Code"
if command -v claude >/dev/null; then
  claude mcp remove browser-eyes 2>/dev/null || true
  claude mcp add browser-eyes -- "${BIN_DIR}/browser-eyes" mcp \
    || echo "   (auto-register failed — add it manually below)"
else
  echo "   'claude' command not found — register manually:"
  echo "   claude mcp add browser-eyes -- ${BIN_DIR}/browser-eyes mcp"
fi

echo ""
echo "================================================================"
echo "  Installed."
echo ""
echo "  Quick start:"
echo "    1. Ensure ${BIN_DIR} is on PATH"
echo "    2. browser-eyes start        # launches daemon + browser"
echo "    3. browser-eyes status       # confirm it's alive"
echo "    4. Browse around in the spawned window"
echo "    5. In Claude Code, ask things like:"
echo "         what's on my screen?"
echo "         list all my cookies for google.com"
echo "         show me the network requests on this page"
echo "         download every CSS file from this site"
echo "         intercept api.foo.com/users and return {test: true}"
echo "         emulate iPhone 15"
echo "         run document.cookie in the console"
echo ""
echo "  CLI:"
echo "    browser-eyes ops              # list all 80+ operations"
echo "    browser-eyes exec list_tabs   # call any op from the shell"
echo "    browser-eyes tail             # live event stream"
echo "    browser-eyes logs 50          # last 50 events"
echo "    browser-eyes stop"
echo "================================================================"
