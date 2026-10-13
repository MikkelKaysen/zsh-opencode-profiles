# Copyright (c) 2026 Mikkel Kaysen

# According to the Zsh Plugin Standard:
# http://zdharma.org/Zsh-100-Commits-Club/Zsh-Plugin-Standard.html

0=${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}
0=${${(M)0:#/*}:-$PWD/$0}

if [[ ${zsh_loaded_plugins[-1]} != */zsh-opencode-profiles && -z ${fpath[(r)${0:h}/functions]} ]] {
    fpath+=( "${0:h}/functions" )
}
oc() {
    local profile="personal"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--profile)
                profile="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                break
                ;;
        esac
    done

    local config_file="${HOME}/.config/opencode/profiles/${profile}/opencode.jsonc"

    if [[ ! -f "$config_file" ]]; then
        print -u2 "Profile '${profile}' not found at ${config_file}"
        print -u2 "Available profiles:"
        local dir
        for dir in "${HOME}/.config/opencode/profiles"/*/; do
            [[ -f "${dir}opencode.jsonc" ]] && print -u2 "  ${dir:t}"
        done
        return 1
    fi

    OPENCODE_CONFIG="$config_file" opencode "$@"
}