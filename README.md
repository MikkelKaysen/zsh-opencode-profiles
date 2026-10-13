# zsh-opencode-profiles

Zsh plugin providing the `oc` command for managing [opencode](https://opencode.ai) profiles.

## Usage

```sh
oc                      # launch opencode with the default profile (personal)
oc -p minds             # launch opencode with the minds profile
oc -p work              # launch opencode with the work profile
oc --profile personal   # long form
```

## Profiles

Profiles are discovered dynamically from `~/.config/opencode/profiles/*/opencode.jsonc`.
Any directory containing an `opencode.jsonc` file is a valid profile.

## Installation

Add to your `~/.config/zsh/zimrc`:

```zsh
zmodule ~/code/personal/zsh-opencode-profiles
```