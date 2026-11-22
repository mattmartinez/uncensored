#!/usr/bin/env bash
# install.sh: set up uncensored for this user, on Linux or macOS. Needs no root.
#
#   ./install.sh                     link uncensored into ~/.local/bin, write a config, test the jail
#   BIN_DIR=/other/bin ./install.sh  link it somewhere else
#
# On Linux the jail needs bubblewrap and socat; if either is missing this prints the command
# that installs them and stops. macOS has what it needs (sandbox-exec) built in.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bin_dir=${BIN_DIR:-$HOME/.local/bin}
conf=${XDG_CONFIG_HOME:-$HOME/.config}/uncensored/config
say() { echo "install: $*"; }

case $(uname -s) in
  Linux)
    need=""
    command -v bwrap >/dev/null || need="$need bubblewrap"
    command -v socat >/dev/null || need="$need socat"
    if [[ -n $need ]]; then
      say "missing:$need. Install with:"
      found=""
      for pm in "pacman:sudo pacman -S --needed" "apt-get:sudo apt-get install" "dnf:sudo dnf install" \
                "zypper:sudo zypper install" "apk:sudo apk add" "xbps-install:sudo xbps-install"; do
        command -v "${pm%%:*}" >/dev/null && { echo "  ${pm#*:}$need"; found=1; }
      done
      [[ -n $found ]] || echo "  your package manager's$need packages"
      echo "then run ./install.sh again."
      exit 1
    fi
    ;;
  Darwin)
    [[ -x /usr/bin/sandbox-exec ]] || { say "this macOS has no /usr/bin/sandbox-exec, which the jail needs"; exit 1; }
    ;;
  *)
    say "only Linux and macOS are supported"; exit 1 ;;
esac
command -v omp >/dev/null ||
  { say "omp isn't on your PATH. Install it first: https://github.com/can1357/oh-my-pi"; exit 1; }

mkdir -p "$bin_dir" && ln -sf "$here/uncensored" "$bin_dir/uncensored" || { say "FAILED to link into $bin_dir"; exit 1; }
say "linked $bin_dir/uncensored to $here/uncensored (git pull here updates it)"
if [[ -e $conf ]]; then
  say "kept your config, $conf"
else
  mkdir -p "$(dirname "$conf")" && cp "$here/config.example" "$conf" || { say "FAILED to write $conf"; exit 1; }
  say "wrote $conf; put your model in it"
fi
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) say "$bin_dir isn't on your PATH yet; add it in your shell's startup file" ;;
esac

say "testing the jail:"
"$here/uncensored" --check || { say "the jail test failed (FAIL lines above)"; exit 1; }
say "done. Add your model to $conf, then run: uncensored --check <model>, and: uncensored"
