# zsh-opencode-profiles

Zsh plugin providing the `oc` command for managing [opencode](https://opencode.ai) profiles.

## Usage

```sh
oc                      # launch opencode with the default profile (personal)
oc -p minds             # launch opencode with the minds profile
oc -p work              # launch opencode with the work profile
oc --profile personal   # long form
```

## Profile Management

Copy an existing profile to a new one:

```sh
oc --copy personal work     # copy personal → work
oc -c personal work         # short form
oc --copy personal work -f # overwrite existing dest
oc -c personal work --force
```

Delete a profile:

```sh
oc --delete work     # delete the work profile
oc -d work           # short form
```

## Profiles

Profiles are discovered dynamically from `~/.config/opencode/profiles/*/opencode.jsonc`.
Any directory containing an `opencode.jsonc` file is a valid profile.

## Installation

Add to your `~/.config/zsh/zimrc`:

```zsh
zmodule ~/code/personal/zsh-opencode-profiles
```