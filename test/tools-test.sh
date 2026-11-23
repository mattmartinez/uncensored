#!/usr/bin/env bash
# Which tools reach the model? Runs omp against a fake model server (fake-server.py) that logs
# the tools each request offers, with a home and a starting folder full of tool sources: an omp
# extension, MCP servers in omp's mcp.json and Claude Code's ~/.claude.json, and a .mcp.json in
# the folder. Then:
#
#   control   plain omp --no-tools, no jail: shows what leaks (informational)
#   closed    uncensored as installed: must offer no tools at all
#   TOOLS     uncensored with TOOLS=read: must offer exactly "read"
#   MCP       uncensored with MCP_CONFIG: must offer the MCP tool and nothing from the extension
#
#   test/tools-test.sh        needs python3 and omp (plus bwrap and socat on Linux)
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
uncensored=$here/../uncensored
base=/tmp; [[ $(uname -s) == Linux ]] && base=${XDG_RUNTIME_DIR:-/tmp}
t=$(mktemp -d "$base/uncensored-test.XXXXXX") || exit 1
t=$(cd "$t" && pwd -P)
srv=""
# the wait reaps the server quietly; without it bash 3.2 prints "Terminated: 15" for it
cleanup() { [[ -n $srv ]] && { kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null; }; rm -rf -- "$t"; }
trap cleanup EXIT
bad=0
# macOS has no timeout(1); without it a hung run just isn't cut off
tmo() { if command -v timeout >/dev/null; then timeout "$@"; else shift; "$@"; fi; }
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; bad=1; }

# the real python3, by full path: macOS's /usr/bin/python3 can be a stub that asks to install
# the developer tools, and the jail needs to be able to read where python lives
py=$(command -v python3) || { echo "tools-test needs python3"; exit 1; }
py=$(readlink -f "$py" 2>/dev/null || echo "$py")
py_root=$(dirname "$(dirname "$py")")
"$py" -I "$here/fake-server.py" "$t/requests.log" "$t/port" & srv=$!
for _ in $(seq 1 50); do [[ -s $t/port ]] && break; sleep 0.1; done
port=$(cat "$t/port" 2>/dev/null) || { echo "the fake server did not start"; exit 1; }

# a home and a folder full of tool sources
fh=$t/home
mkdir -p "$fh/.omp/agent/extensions" "$t/project/.omp"
mcp() { printf '{"mcpServers": {"%s": {"command": "%s", "args": ["-I", "%s"]}}}\n' "$1" "$py" "$here/mcp-probe.py"; }
mcp from_omp > "$fh/.omp/agent/mcp.json"
mcp from_claude > "$fh/.claude.json"
mcp from_project > "$t/project/.mcp.json"
mcp from_project_omp > "$t/project/.omp/mcp.json"
cp "$here/probe-extension.ts" "$fh/.omp/agent/extensions/"
printf 'providers:\n  fake:\n    baseUrl: http://127.0.0.1:%s/v1\n    auth: none\n    api: openai-completions\n    models:\n      - id: test\n        contextWindow: 32768\n        maxTokens: 1024\n' "$port" > "$fh/.omp/agent/models.yml"
# share the real omp's unpacked native libraries, if it has them, instead of unpacking 140 MB
[[ -d $HOME/.omp/natives ]] && ln -s "$HOME/.omp/natives" "$fh/.omp/natives"

tools_seen() { "$py" -I -c 'import json,sys; print(json.dumps(sorted({t for l in open(sys.argv[1]) for t in json.loads(l)})))' "$t/requests.log"; }
requests() { [[ -s $t/requests.log ]] && wc -l < "$t/requests.log" | tr -d ' ' || echo 0; }

# control: plain omp, no jail
: > "$t/requests.log"
(cd "$t/project" && HOME=$fh tmo 120 omp --model fake/test --no-session --no-tools --offline -p "say ok" < /dev/null > "$t/out" 2>&1)
echo "info  plain omp --no-tools offered: $(tools_seen)"

run() {  # name, config lines...
  local name=$1; shift
  : > "$t/requests.log"
  { printf '%s\n' "$@"; echo "model \"fake\" url=http://127.0.0.1:$port/v1 id=test reasoning=no"; } > "$t/config"
  (cd "$t/project" && HOME=$fh UNCENSORED_CONFIG=$t/config UNCENSORED_STATE=$t/state UNCENSORED_PRINT="say ok" \
     tmo 120 "$uncensored" < /dev/null > "$t/out-$name" 2>&1)
  local rc=$?
  (( rc == 0 )) || { fail "$name: uncensored exited $rc"; sed 's/^/      /' "$t/out-$name" | tail -5; return 1; }
  (( $(requests) > 0 )) || { fail "$name: no request reached the fake server"; return 1; }
  return 0
}

if run closed; then
  [[ $(tools_seen) == '[]' ]] && pass "closed: no tools offered" || fail "closed: offered $(tools_seen)"
fi
if run tools 'TOOLS="read"'; then
  [[ $(tools_seen) == '["read"]' ]] && pass "TOOLS=read: offered only read" || fail "TOOLS=read: offered $(tools_seen)"
fi
mcp only_this > "$t/mcp.json"
if run mcp "MCP_CONFIG=\"$t/mcp.json\"" "READ_DIRS=\"$here $py_root\""; then
  seen=$(tools_seen)
  if [[ $seen == *only_this* && $seen != *from_* && $seen != *extension_probe* ]]; then
    pass "MCP_CONFIG: offered only its own MCP server's tool ($seen)"
  else
    fail "MCP_CONFIG: offered $seen"
  fi
fi
(( bad )) && echo "tools-test: FAILED" || echo "tools-test: all passed"
exit $bad
