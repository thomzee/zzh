# zzh

A fast **SSH server launcher for your terminal**. Pick a server from an
[`fzf`](https://github.com/junegunn/fzf) fuzzy list and it hands off to a live
`ssh` session — no more remembering hosts, ports, users, and key paths.

> A Go implementation of the same idea lives in [`../zzh-go`](../zzh-go); this
> bash version is the primary one.

```
ssh > prod
  Select a server — type to filter, enter to connect
> prod-web   deploy@10.0.0.5
  staging    ubuntu@staging.example.com
  bastion    admin@bastion.example.com
```

When connected, the server name is shown in the terminal **tab/window title**
(macOS Terminal.app, Linux terminals, iTerm) and, under **iTerm2**, as a
**badge** watermark — so you always know which host you're on. Both are cleared
when the session ends (including on Ctrl-C or a dropped connection).

## Requirements

- `bash` (works on the macOS system bash 3.2)
- [`jq`](https://jqlang.github.io/jq/) — JSON parsing (`brew install jq`)
- [`fzf`](https://github.com/junegunn/fzf) — fuzzy selector (`brew install fzf`)
- [`sshpass`](https://sourceforge.net/projects/sshpass/) **only if** you use
  password auth (`brew install sshpass`)

## How it works

`zzh` reads a `.zzh.yaml` config containing a single `credsFile` pointing at
your server list:

```yaml
credsFile: "/Users/you/.zzh-creds.json"
```

The config is searched for in this order (first match wins):

1. The directory of the `zzh` script (symlinks are resolved, so a symlinked
   `zzh` on your PATH still finds the config next to the real script)
2. `~/.zzh.yaml`
3. `$XDG_CONFIG_HOME/zzh/config.yaml` (defaults to `~/.config/zzh/config.yaml`)
4. `./.zzh.yaml` in the current directory

`creds.json` is an array of servers:

```json
[
  { "name": "prod-web", "host": "10.0.0.5", "port": 22, "user": "deploy", "password": "s3cret" },
  { "name": "staging", "host": "staging.example.com", "port": 2222, "user": "ubuntu", "keyPath": "~/.ssh/id_ed25519" },
  { "name": "bastion", "host": "bastion.example.com", "user": "admin" }
]
```

| Field      | Required | Notes                                       |
| ---------- | -------- | ------------------------------------------- |
| `name`     | yes      | label shown in fzf, used by the filter      |
| `host`     | yes      | hostname or IP                              |
| `user`     | yes      | SSH user                                    |
| `port`     | no       | defaults to `22`                            |
| `password` | no       | auto-login via `sshpass`                    |
| `keyPath`  | no       | private key path; `~` is expanded           |

Connection is chosen per server by which field is set:

1. `keyPath` → `ssh -i <keyPath> -p <port> user@host`
2. `password` → `sshpass -p <password> ssh -p <port> user@host`
3. neither → `ssh -p <port> user@host`

Every connection is made with `-o StrictHostKeyChecking=accept-new`, so the
**first** time you connect to a host its key is trusted and saved to
`~/.ssh/known_hosts` automatically — no `yes/no` prompt (which `zzh` can't
answer, since it hands off to `ssh` only after `fzf` has taken over stdin). If a
host's key ever *changes*, the connection is still refused, keeping the usual
trust-on-first-use protection against man-in-the-middle attacks.

On selection the script runs ssh, dropping you into the remote shell; you're
back at your prompt when the session ends.

## Install (run `zzh` from anywhere)

Symlink the script into a directory on your PATH:

```bash
# macOS (Apple Silicon Homebrew)
ln -sf "$PWD/zzh.sh" /opt/homebrew/bin/zzh

# Intel macOS / Linux
ln -sf "$PWD/zzh.sh" /usr/local/bin/zzh    # may need sudo
```

Then set up your server list and config:

```bash
cp creds.example.json ~/.zzh-creds.json
chmod 600 ~/.zzh-creds.json
$EDITOR ~/.zzh-creds.json

# put the config next to the script (or use ~/.zzh.yaml)
printf 'credsFile: "%s/.zzh-creds.json"\n' "$HOME" > .zzh.yaml

zzh   # from any directory
```

## Security

- `creds.json` may contain plaintext passwords — keep it `chmod 600` and never
  commit it (it's git-ignored). Prefer `keyPath` over `password`.
- Host keys are accepted on first use (`StrictHostKeyChecking=accept-new`) and
  pinned in `known_hosts`; a later key *change* aborts the connection. If you
  need to re-trust a host after a legitimate rebuild, remove its old entry with
  `ssh-keygen -R <host>`.

## Development

```bash
bash test.sh   # run the unit tests (no bats required)
```

## License

MIT
