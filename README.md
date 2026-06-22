# zzh (bash)

A fast **SSH server launcher for your terminal** — bash port of the Go
[`../zzh`](../zzh). Pick a server from an [`fzf`](https://github.com/junegunn/fzf)
fuzzy list and it hands off to a live `ssh` session. Same `creds.json` schema
and `.zzh.yaml` config as its Go sibling.

```
ssh > prod
  Select a server — type to filter, enter to connect
> prod-web   deploy@10.0.0.5
  staging    ubuntu@staging.example.com
  bastion    admin@bastion.example.com
```

## Requirements

- `bash` (works on the macOS system bash 3.2)
- [`jq`](https://jqlang.github.io/jq/) — JSON parsing (`brew install jq`)
- [`fzf`](https://github.com/junegunn/fzf) — fuzzy selector (`brew install fzf`)
- [`sshpass`](https://sourceforge.net/projects/sshpass/) **only if** you use
  password auth (`brew install sshpass`)

## How it works

`zzh.sh` reads a `.zzh.yaml` (looked up next to the script, then in the current
directory) containing a single `credsFile` pointing at your server list:

```yaml
credsFile: "/Users/you/.zzh-creds.json"
```

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

On selection the script `exec`s ssh, replacing itself, so you land in a fully
interactive remote shell; back to your prompt when the session ends.

## Install

```bash
chmod +x zzh.sh
sudo cp zzh.sh /usr/local/bin/zzh        # optional: put it on PATH

cp creds.example.json ~/.zzh-creds.json
chmod 600 ~/.zzh-creds.json
$EDITOR ~/.zzh-creds.json

# config next to the script (or in your working dir)
printf 'credsFile: "%s/.zzh-creds.json"\n' "$HOME" > /usr/local/bin/.zzh.yaml

zzh
```

## Security

- `creds.json` may contain plaintext passwords — keep it `chmod 600` and never
  commit it (it's git-ignored). Prefer `keyPath` over `password`.

## Development

```bash
bash test.sh   # run the unit tests (no bats required)
```

## License

MIT
