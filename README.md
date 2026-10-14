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

### Profiles

Profiles are discovered dynamically from `~/.config/opencode/profiles/*/opencode.jsonc`.
Any directory containing an `opencode.jsonc` file is a valid profile.

## License

[MIT](./LICENSE) — Copyright (c) 2026 Mikkel Kaysen
