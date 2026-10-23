# Copyright (c) 2026 Mikkel Kaysen

# According to the Zsh Plugin Standard:
# http://zdharma.org/Zsh-100-Commits-Club/Zsh-Plugin-Standard.html

0=${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}
0=${${(M)0:#/*}:-$PWD/$0}

if [[ ${zsh_loaded_plugins[-1]} != */zsh-opencode-profiles && -z ${fpath[(r)${0:h}/functions]} ]] {
    fpath+=( "${0:h}/functions" )
}

# Standard hash for plugins, to not pollute the namespace
typeset -gA Plugins
Plugins[ZSH_OPENCODE_PROFILES_DIR]="${0:h}"

_oc_opencode_major_version() {
    # v2 prints "opencode v2.0.28", v1 prints e.g. "1.18.31".
    opencode --version 2>&1 | grep -oE '[0-9]+' | head -n 1
}

# v2 keeps one background service per state directory, pinned to a single
# fixed port. To let several profiles run at the same time, each profile gets
# its own state directory via XDG_STATE_HOME; that isolates its service
# registration and PTY daemon, so one profile's server never blocks another's.
# The service is started with `--port 0` so the OS picks a free port (no
# bookkeeping, no collisions). The shared data directory (db, auth, storage) is
# kept in place so sessions and credentials stay shared across profiles.
_oc_v2_state_dir() {
    print -r -- "${HOME}/.local/state/oc/${1}"
}

_oc_v2_launch() {
    local config_file="$1" profile="$2"
    local -i want_restart="${3:-0}"
    local -i want_stop="${4:-0}"
    shift 4
    local -a args=("$@")

    local state_dir
    state_dir=$(_oc_v2_state_dir "$profile")

    # opencode is a mise tool and may spawn mise. Keep mise's own state at the
    # user's real location so that only opencode's state is profile-scoped.
    local real_state="${XDG_STATE_HOME:-$HOME/.local/state}"

    # --stop: tear this profile's server down and exit.
    if (( want_stop )); then
        if [[ $(XDG_STATE_HOME="$state_dir" opencode service status 2>/dev/null) == http* ]]; then
            XDG_STATE_HOME="$state_dir" opencode service stop 2>/dev/null
            print "Stopped opencode service for profile '${profile}'"
        else
            print "No running opencode service for profile '${profile}'"
        fi
        return 0
    fi

    # --restart: replace this profile's server before (re)launching.
    if (( want_restart )); then
        XDG_STATE_HOME="$state_dir" opencode service stop 2>/dev/null
    fi

    local service_url
    service_url=$(XDG_STATE_HOME="$state_dir" opencode service status 2>/dev/null)

    # Attach if a service for this profile is already running with the right
    # config. Refuse (rather than kill) if the registered service is running a
    # different config — the user must opt in with --restart.
    if [[ "$service_url" == http* ]]; then
        local server_config
        server_config=$(XDG_STATE_HOME="$state_dir" opencode debug config 2>/dev/null)
        if [[ "$server_config" == *"profiles/${profile}/opencode.jsonc"* ]]; then
            XDG_STATE_HOME="$state_dir" MISE_STATE_DIR="$real_state/mise" opencode "${args[@]}"
            return $?
        fi
        print -u2 "Profile '${profile}' has a running service with a different config."
        print -u2 "Use 'oc -p ${profile} --restart' to replace it."
        return 1
    fi

    # No service for this profile: start a fresh one without touching any other
    # profile, then attach.
    mkdir -p "$state_dir"
    command nohup env XDG_STATE_HOME="$state_dir" MISE_STATE_DIR="$real_state/mise" \
        OPENCODE_CONFIG="$config_file" \
        opencode serve --service --port 0 >> "${state_dir}/serve.log" 2>&1 &!

    local -i attempt
    for (( attempt = 0; attempt < 30; attempt++ )); do
        service_url=$(XDG_STATE_HOME="$state_dir" opencode service status 2>/dev/null)
        [[ "$service_url" == http* ]] && break
        sleep 0.5
    done

    if [[ "$service_url" != http* ]]; then
        print -u2 "Timed out waiting for the '${profile}' service to start."
        print -u2 "Last lines of ${state_dir}/serve.log:"
        tail -n 20 "${state_dir}/serve.log" 2>/dev/null | sed 's/^/  /'
        return 1
    fi

    XDG_STATE_HOME="$state_dir" MISE_STATE_DIR="$real_state/mise" OPENCODE_CONFIG="$config_file" opencode "${args[@]}"
}

oc() {
    local profile="personal"
    local do_copy=0
    local do_force=0
    local do_delete=0
    local do_restart=0
    local do_stop=0
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
            -r|--restart)
                do_restart=1
                shift
                ;;
            -s|--stop)
                do_stop=1
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

    # v2 detects its own background service; v1 just honors OPENCODE_CONFIG.
    local major
    major=$(_oc_opencode_major_version)
    if (( ${major:-0} >= 2 )); then
        _oc_v2_launch "$config_file" "$profile" "$do_restart" "$do_stop" "${positionals[@]}"
    else
        OPENCODE_CONFIG="$config_file" opencode "${positionals[@]}"
    fi
}

# Generate opencode completion function.  Regenerate when opencode is newer.
# v2 produces clean static completions via --completions zsh; v1 uses the
# yargs completion command and needs post-processing to rename the function,
# add a $0: reply filter, and fix a broken autoload check.
(( ${+commands[opencode]} )) && () {
    local command=${commands[opencode]}
    [[ -z $command ]] && return 1

    local cachedir=$1
    local compfile=$cachedir/functions/_opencode
    [[ -d ${compfile:h} ]] || mkdir -p ${compfile:h}

    if [[ ! -e $compfile || $compfile -ot $command ]]; then
        local major
        major=$(_oc_opencode_major_version)
        if (( ${major:-0} >= 2 )); then
            opencode --completions zsh >| $compfile 2>/dev/null
        else
            opencode completion 2>/dev/null | \
                sed -e 's/_opencode_yargs_completions/_opencode/g' \
                    -e '/IFS=\$si/a\  reply=(${reply:#\\$0:*})' \
                    -e "s/\"'/\"/g" >| $compfile
        fi

        # If generation failed, remove the stale/empty file and skip.
        if [[ ! -s $compfile ]]; then
            rm -f $compfile
            return 1
        fi
        print -u2 -PR "* Detected a new version of 'opencode'. Regenerated completions."
    fi
} ${Plugins[ZSH_OPENCODE_PROFILES_DIR]}
