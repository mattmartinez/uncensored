# uncensored

Chat with an uncensored model in [omp](https://github.com/can1357/oh-my-pi), jailed. Out of the box omp can reach the model's server and nothing else: no tools, no other network, none of your files. Every hole has a setting, so you can open them one at a time.

I have a habit of opening omp, picking one of my uncensored models and forgetting to keep it jailed. So this does it for me.

## What's closed

| Hole | Closed by default | Opened by |
|---|---|---|
| Tools | No tools at all, including extension tools and MCP servers (see below) | `TOOLS="read,grep"` |
| Network | Only the model's server. No DNS, nothing else | `ALLOW_NET="host:port ..."`, or `all` |
| Your files | Home hidden, filesystem read-only. omp writes only to a throwaway home | `READ_DIRS`, `WRITE_DIRS` |
| Project config | omp starts in an empty folder | `START_DIR` |
| MCP servers | None | `MCP_CONFIG` (its servers run inside the jail) |
| Your omp setup | None of your omp settings, logins, extensions or other providers. omp knows about one model | `OMP_FLAGS` for anything else |
| Chat history | Saved in `~/.local/state/uncensored/sessions` | `SAVE_SESSIONS=no` saves nothing |

`uncensored --dry-run` lists what's open before you chat, and the same list prints each time a chat starts.

## Why not just `omp --no-tools`

`--no-tools` turns off omp's built-in tools. Tools from extensions and MCP servers still reach the model. `test/tools-test.sh` runs omp 19.1.0 against a fake model server that logs what omp offers. Plain `omp --no-tools` offered:

- a tool from an extension in `~/.omp/agent/extensions`
- a tool from an MCP server in the starting folder's `.omp/mcp.json`
- omp's own `report_issue` tool, unless you've said no to its auto-QA

Per its docs, omp also picks up MCP servers from Claude Code, Codex, Cursor and other tools' configs. And `--offline` only keeps omp's helper features on the model's provider; it isn't a firewall.

## Install

Linux or macOS, with omp already installed.

```bash
git clone https://github.com/mattmartinez/uncensored ~/.local/share/uncensored
~/.local/share/uncensored/install.sh
```

The installer links `uncensored` into `~/.local/bin`, writes `~/.config/uncensored/config` from `config.example`, and tests the jail. On Linux the jail needs bubblewrap and socat; if they're missing, the installer prints the command for your package manager. macOS has sandbox-exec built in.

Then add your model to `~/.config/uncensored/config`:

```bash
model "gpt-oss 20B abliterated" url=http://127.0.0.1:8080/v1 id=gpt-oss-20b-abliterated context=131072
```

`config.example` explains every setting, including `key='!command'` for API keys and `before=` / `after=` commands for servers that hold one model at a time.

## Use

```bash
uncensored                 # pick a model
uncensored gpt             # the first model whose label contains "gpt"
uncensored --list
uncensored --dry-run gpt   # what's open, and the omp command
uncensored --check gpt     # test the jail, and that it can reach this model's server (wakes it, if it loads on demand)
test/tools-test.sh         # which tools reach the model (needs python3)
```

## How it works

Each chat gets a throwaway home in a private temporary folder. It holds an omp config with one model and nothing else, and it's deleted when omp exits. omp runs with `--no-tools --no-extensions --offline` from an empty folder.

- **Linux:** [bubblewrap](https://github.com/containers/bubblewrap) runs omp with its own empty network, a read-only filesystem, and `/home`, `/tmp` and `/run` replaced by empty folders. A pair of socat relays connects the model's port, and only that port, through a socket file. A remote server's name is pointed at the relay in the jail's `/etc/hosts`, so TLS still checks the right name.
- **macOS:** `sandbox-exec` with a profile that denies all network except the model's port, denies reading your home and writing anywhere outside the throwaway home.

The API key command, if you use one, runs outside the jail, so the jail never sees the file it comes from.

## Limits

- Tested on Linux (Arch) and macOS 27 (Apple silicon). On macOS, remote model servers and `ALLOW_NET` hosts haven't been tried yet.
- Tested with omp 19.1.0. A later omp could add another way to load tools; `test/tools-test.sh` will show it.
- On Linux, extra `ALLOW_NET` hosts need ports from 1024 up, because the jail can't listen below 1024. The model's own server can be on any port.
- On macOS, sandbox-exec can't name a remote host, so a remote model server (or `ALLOW_NET` host) opens its port to every host. A server on localhost is exact. Apple marks sandbox-exec as deprecated.
- This jails omp. It doesn't jail the server running the model. A stranger's modified weights deserve their own sandbox; mine runs llama-server as a systemd service with `DynamicUser`, `ProtectSystem=strict`, `ProtectHome` and `IPAddressAllow=localhost`.
