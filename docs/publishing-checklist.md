# Publishing Checklist

- Confirm the repository contains no real logs, wallets, passwords, or generated `.codex` history databases.
- Keep `config/connections.conf` ignored; publish only `config/connections.conf.example`.
- Confirm `LICENSE` is present and correct.
- Run `make test`.
- Run a live smoke test against a disposable SQLcl saved connection.
- Confirm `git status --ignored --short` shows only expected ignored runtime files.
