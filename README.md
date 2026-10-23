# zsh-opencode-profiles

A Zsh plugin providing the `oc` command for managing [opencode](https://opencode.ai) profiles.

## Requirements

- [opencode](https://opencode.ai) must be installed and available on your `$PATH`.

## Installation

### zinit

```zsh
zinit light mikkelkaysen/zsh-opencode-profiles
```

### Oh My Zsh

Clone the repository into your custom plugins directory:

```zsh
git clone https://github.com/mikkelkaysen/zsh-opencode-profiles.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-opencode-profiles
```

Then add `zsh-opencode-profiles` to your plugins list in `~/.zshrc`:

```zsh
plugins=(... zsh-opencode-profiles)
```

### zimfw

Add the following to your `~/.zimrc`:

```zsh
zmodule mikkelkaysen/zsh-opencode-profiles
```

Then run:

```zsh
zimfw install
```

## Features

When `opencode` is found on the system, the plugin:

1. Generates the opencode completion function (`_opencode`) and regenerates it when the `opencode` binary is newer.
2. Supports both opencode v1 and v2:
   - **v2**: Uses `opencode --completions zsh` (static completion script, works out of the box).
   - **v1**: Uses `opencode completion` (dynamic yargs completions, post-processed to rename the function to `_opencode`, add a `$0:` reply filter, and repair a broken autoload check).

## Usage

```sh
oc                      # launch opencode with the default profile (personal)
oc -p minds             # launch opencode with the minds profile
oc -p work              # launch opencode with the work profile
oc --profile personal   # long form
oc -p work --restart    # stop + restart the work profile's server, then attach
oc -p work --stop       # stop the work profile's server and exit
```

### Profile Management

Copy an existing profile to a new one:

```sh
oc --copy personal work     # copy personal → work
oc -c personal work         # short form
oc --copy personal work -f  # overwrite existing dest
oc -c personal work --force # overwrite existing dest
```

Delete a profile:

```sh
oc --delete work     # delete the work profile
oc -d work           # short form
```

### Background Servers (v2)

With opencode v2, `oc` starts and manages an ordinary `opencode serve` process
for each profile. Each server binds only to `127.0.0.1` on a deterministic
profile-specific port in the range `52000`–`61999`; if that port is occupied,
`oc` tries up to 31 following ports. It never kills a process to free a port.
The wrapper attaches through OpenCode's native `--server` option, so different
profiles can run concurrently without using OpenCode's global service
registration:

`oc` routes forwarded opencode subcommands through a helper: the TUI (and any
unknown first argument, e.g. a target directory) attaches via `--server`;
`run` and `api` are routed to the profile server with `--server` placed after
the subcommand; all other known subcommands (e.g. `plugin check`, `debug
config`) run locally against the profile's config without `--server` or a
password. Forwarded `--server` and `--standalone` options are always rejected.

```sh
oc -p work          # TUI — attaches via --server to the profile server
oc -p minds         # TUI — attaches to the minds server too — both run
oc -p work --restart # stop the verified work server, start a fresh one
oc -p work --stop    # stop the verified work server and exit
oc -p minds plugin check   # local subcommand, runs against the minds config
oc -p work run "hello"     # routed to the work profile's server
```

- Wrapper-only metadata and logs are stored under
  `${XDG_STATE_HOME:-$HOME/.local/state}/oc/<profile>/` (directory mode `700`,
  password file mode `600`). OpenCode and its children continue using the
  normal shared XDG/data directories; sessions and credentials are not
  partitioned by profile.
- Each profile server gets a generated password. `oc` supplies it through the
  server/client password environment variables, and authenticates its
  ownership check before attach or stop. Passwords are not printed.
- `--stop` and `--restart` act only when PID, user, server command, loopback
  hostname, port, authenticated server PID, and profile config can all be
  verified. If ownership/configuration cannot be proven, `oc` refuses to
  attach or signal the process. A port conflict is skipped; if 32 candidates
  cannot be started safely, the command fails without stopping the occupant.
- Plain `opencode` and its global service are left alone. `oc` does not use
  `opencode service stop` or OpenCode's service registry.

> **Migration note:** Servers left running by the previous XDG-isolated
> implementation are not discovered or stopped automatically. They may remain
> active after upgrading. Review the process and its command line yourself and
> stop only a server you can positively identify as an old profile-specific
> `opencode serve --service` process; do not use the global `opencode service
> stop` command as a migration shortcut.

### Profiles

Profiles are discovered dynamically from `~/.config/opencode/profiles/*/opencode.jsonc`.
Any directory containing an `opencode.jsonc` file is a valid profile.

## License

[MIT](./LICENSE) — Copyright (c) 2026 Mikkel Kaysen
