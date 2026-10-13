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
    local do_copy=0
    local do_force=0
    local do_delete=0
    local -a positionals

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--profile)
                profile="$2"
                shift 2
                ;;
            -c|--copy)
                do_copy=1
                shift
                ;;
            -f|--force)
                do_force=1
                shift
                ;;
            -d|--delete)
                do_delete=1
                shift
                ;;
            --)
                shift
                positionals+=("$@")
                break
                ;;
            *)
                positionals+=("$1")
                shift
                ;;
        esac
    done 

    local profiles_dir="${HOME}/.config/opencode/profiles"

    if (( do_copy )); then
        if [[ ${#positionals[@]} -lt 2 ]]; then
            print -u2 "Usage: oc --copy <source> <dest> [--force]"
            return 1
        fi
        local source_profile="${positionals[1]}" dest_profile="${positionals[2]}"
        local source_dir="${profiles_dir}/${source_profile}"
        local dest_dir="${profiles_dir}/${dest_profile}"
        if [[ ! -d "$source_dir" ]]; then
            print -u2 "Source profile '${source_profile}' not found"
            return 1
        fi
        if [[ -d "$dest_dir" ]] && (( ! do_force )); then
            print -u2 "Destination profile '${dest_profile}' already exists. Use --force to overwrite."
            return 1
        fi
        rm -rf "$dest_dir"
        cp -r "$source_dir" "$dest_dir"
        print "Copied profile '${source_profile}' to '${dest_profile}'"
        return 0
    fi

    if (( do_delete )); then
        if [[ ${#positionals[@]} -lt 1 ]]; then
            print -u2 "Usage: oc --delete <profile>"
            return 1
        fi
        local delete_profile="${positionals[1]}"
        local delete_dir="${profiles_dir}/${delete_profile}"
        if [[ ! -d "$delete_dir" ]]; then
            print -u2 "Profile '${delete_profile}' not found"
            return 1
        fi
        rm -rf "$delete_dir"
        print "Deleted profile '${delete_profile}'"
        return 0
    fi

    local config_file="${profiles_dir}/${profile}/opencode.jsonc"

    if [[ ! -f "$config_file" ]]; then
        print -u2 "Profile '${profile}' not found at ${config_file}"
        print -u2 "Available profiles:"
        local dir
        for dir in "${profiles_dir}"/*/; do
            [[ -f "${dir}opencode.jsonc" ]] && print -u2 "  ${dir:t}"
        done
        return 1
    fi

    OPENCODE_CONFIG="$config_file" opencode "${positionals[@]}"
}