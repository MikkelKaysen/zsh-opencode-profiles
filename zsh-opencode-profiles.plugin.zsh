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

_oc_valid_profile() {
    [[ -n "$1" && "$1" != . && "$1" != .. && "$1" =~ '^[A-Za-z0-9][A-Za-z0-9._-]*$' ]]
}

# These files are wrapper metadata only. OpenCode and its children keep their
# normal XDG/data directories so sessions and credentials remain shared.
_oc_v2_state_dir() {
    print -r -- "${XDG_STATE_HOME:-$HOME/.local/state}/oc/${1}"
}

_oc_v2_atomic_write() {
    local file="$1" value="$2" tmp="${1}.tmp.$$.$RANDOM"
    ( umask 077; print -rn -- "$value" >| "$tmp" ) || return 1
    command chmod 600 "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    mv -f -- "$tmp" "$file"
}

_oc_v2_pid_alive() {
    local pid="$1" stat
    [[ "$pid" == <-> ]] || return 1
    stat=$(ps -p "$pid" -o stat= 2>/dev/null) || return 1
    [[ -n "$stat" && "$stat" != *Z* ]]
}

_oc_v2_server_matches() {
    local pid="$1" port="$2" expected_start="$3" uid="$(id -u)" ps_uid ps_args actual_start
    [[ -n "$expected_start" ]] || return 1
    _oc_v2_pid_alive "$pid" || return 1
    ps_uid=$(ps -p "$pid" -o uid= 2>/dev/null) || return 1
    ps_args=$(ps -p "$pid" -o args= 2>/dev/null) || return 1
    actual_start=$(ps -p "$pid" -o lstart= 2>/dev/null) || return 1
    ps_uid=${ps_uid//[[:space:]]/}
    [[ "$ps_uid" == "$uid" && "$actual_start" == "$expected_start" &&
       "$ps_args" =~ '(^|[[:space:]/])opencode(\.exe)?[[:space:]]+serve([[:space:]]|$)' &&
       "$ps_args" == *"--hostname 127.0.0.1"* &&
       "$ps_args" =~ "(^|[[:space:]])--port[[:space:]]+${port}([[:space:]]|$)" ]]
}

_oc_v2_log_bound() {
    local port="$1" serve_log="$2"
    grep -E -- "server listening on http://127\\.0\\.0\\.1:${port}([^0-9]|$)" "$serve_log" >/dev/null 2>&1
}

_oc_v2_bind_failed() {
    local serve_log="$1"
    grep -Eiq 'EADDRINUSE|address already in use' "$serve_log" 2>/dev/null
}

_oc_v2_api_matches() {
    local pid="$1" port="$2" password="$3" config_fragment="$4" expected_start="$5" serve_log="$6"
    local url="http://127.0.0.1:${port}" info info_pid server_config
    _oc_v2_server_matches "$pid" "$port" "$expected_start" || return 1
    _oc_v2_log_bound "$port" "$serve_log" || return 1
    info=$(OPENCODE_PASSWORD="$password" opencode api --server "$url" get /api/info 2>/dev/null) || return 1
    info_pid=$(print -r -- "$info" | tr '\n' ' ' | sed -n 's/^[[:space:]]*{[^{}]*"pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\)[[:space:],}].*/\1/p')
    [[ "$info_pid" == <-> ]] || return 1
    [[ "$info_pid" == "$pid" ]] || return 1
    server_config=$(OPENCODE_PASSWORD="$password" opencode api --server "$url" get /api/config 2>/dev/null) || return 1
    [[ "$server_config" == *"$config_fragment"* ]]
}

_oc_v2_stop_owned() {
    local state_dir="$1" pid="$2" port="$3" password="$4" config_fragment="$5" expected_start="$6"
    local serve_log="${state_dir}/serve.log"
    if ! _oc_v2_server_matches "$pid" "$port" "$expected_start" ||
       ! _oc_v2_api_matches "$pid" "$port" "$password" "$config_fragment" "$expected_start" "$serve_log"; then
        print -u2 "Server ownership verification changed before stop; leaving PID ${pid} untouched."
        return 1
    fi
    # Recheck the stored start identity and command immediately before signaling.
    _oc_v2_server_matches "$pid" "$port" "$expected_start" || {
        print -u2 "Server identity changed before stop; leaving PID ${pid} untouched."
        return 1
    }
    kill -TERM "$pid" 2>/dev/null || {
        print -u2 "Could not signal the owned opencode server (PID ${pid}); it was not stopped."
        return 1
    }
    # OpenCode's graceful shutdown reaps every MCP child (a few seconds each)
    # and can drain attached clients, so allow 30s before declaring failure.
    local -i attempt
    for (( attempt = 0; attempt < 300; attempt++ )); do
        _oc_v2_pid_alive "$pid" || break
        if (( attempt == 50 )); then
            print -u2 "Still waiting for graceful shutdown of the opencode server (PID ${pid})…"
        fi
        sleep 0.1
    done
    if _oc_v2_pid_alive "$pid"; then
        print -u2 "Timed out waiting 30s for the owned opencode server (PID ${pid}) to exit; it was not force-killed."
        print -u2 "If it is still running, stop it manually: kill -9 ${pid}"
        print -u2 "Once the process is gone, the next oc command removes the leftover metadata automatically."
        return 1
    fi
    rm -f -- "${state_dir}/pid" "${state_dir}/start"
    print "Stopped opencode server (PID ${pid})"
}

_oc_v2_stop_spawned() {
    local pid="$1" port="$2" expected_start="$3"
    # This helper is used only for the child spawned by this invocation.
    _oc_v2_server_matches "$pid" "$port" "$expected_start" || return 1
    kill -TERM "$pid" 2>/dev/null || return 1
    local -i attempt
    for (( attempt = 0; attempt < 300; attempt++ )); do
        _oc_v2_pid_alive "$pid" || return 0
        sleep 0.1
    done
    ! _oc_v2_pid_alive "$pid"
}

_oc_v2_client() {
    local config_file="$1" password="$2" url="$3"
    shift 3
    local -a args=("$@")

    local -a known_cmds=(
        upgrade update uninstall acp api debug auth mcp plugin models
        stats mini run session service reload pair serve
    )

    local -i has_args=${#args[@]}
    local first="${args[1]:-}"

    # No forwarded args, or first arg is not a known subcommand → TUI (directory arg).
    if (( ! has_args )) || [[ ! " ${(j: :)known_cmds[@]} " == *" $first "* ]]; then
        OPENCODE_CONFIG="$config_file" OPENCODE_PASSWORD="$password" opencode --server "$url" "${args[@]}"
        return $?
    fi

    # First arg is 'run' or 'api' → routed to the profile server with --server after the subcommand.
    if [[ "$first" == "run" || "$first" == "api" ]]; then
        OPENCODE_CONFIG="$config_file" OPENCODE_PASSWORD="$password" \
            opencode "$first" --server "$url" "${args[@]:1}"
        return $?
    fi

    # Other known subcommand → local, config-based; no --server, no password.
    OPENCODE_CONFIG="$config_file" opencode "${args[@]}"
    return $?
}

_oc_v2_launch() (
    local config_file="$1" profile="$2"
    local -i want_restart="${3:-0}"
    local -i want_stop="${4:-0}"
    shift 4
    local -a args=("$@")

    _oc_valid_profile "$profile" || { print -u2 "Invalid profile name '${profile}'"; return 1; }
    local arg
    for arg in "${args[@]}"; do
        case "$arg" in
            --server|--server=*)
                print -u2 "oc controls the OpenCode --server URL for profile servers; remove the forwarded --server option."
                return 1
                ;;
            --standalone)
                print -u2 "oc manages the profile server; remove the forwarded --standalone option."
                return 1
                ;;
        esac
    done

    local state_dir
    state_dir=$(_oc_v2_state_dir "$profile")
    local lock_file="${state_dir}/wrapper.lock" lock_fd password_file="${state_dir}/password"
    local pid_file="${state_dir}/pid" port_file="${state_dir}/port" start_file="${state_dir}/start"
    local serve_log="${state_dir}/serve.log"
    local config_fragment="profiles/${profile}/opencode.jsonc"
    local pid port password candidate base checksum url start expected_start
    local -i attempt candidate_index

    if [[ ! -d "$state_dir" ]]; then
        if (( want_stop )); then
            print "No running opencode server for profile '${profile}'"
            return 0
        fi
        ( umask 077; mkdir -p -- "$state_dir" ) || { print -u2 "Cannot create metadata directory ${state_dir}"; return 1; }
    fi
    [[ ! -L "$state_dir" ]] || { print -u2 "Refusing symlink metadata directory ${state_dir}"; return 1; }
    command chmod 700 "$state_dir" 2>/dev/null || { print -u2 "Cannot protect metadata directory ${state_dir}"; return 1; }
    if (( want_stop )) && [[ ! -e "$pid_file" && ! -e "$port_file" && ! -e "$password_file" ]]; then
        print "No running opencode server for profile '${profile}'"
        return 0
    fi

    # The kernel releases this advisory lock if the wrapper exits unexpectedly,
    # avoiding stale lock directories. The daemon command closes its lock FD.
    if [[ -L "$lock_file" ]]; then
        print -u2 "Refusing symlink wrapper lock for profile '${profile}'"
        return 1
    fi
    if [[ ! -e "$lock_file" ]]; then
        ( umask 077; : >| "$lock_file" ) || { print -u2 "Cannot create profile lock file."; return 1; }
    fi
    command chmod 600 "$lock_file" 2>/dev/null || { print -u2 "Cannot protect profile lock file."; return 1; }
    zmodload zsh/system 2>/dev/null || { print -u2 "This zsh installation lacks zsystem flock support."; return 1; }
    if ! zsystem flock -t 5 -f lock_fd "$lock_file"; then
        print -u2 "Another oc operation is managing profile '${profile}'. Retry shortly."
        return 1
    fi

    if [[ -L "$password_file" ]]; then
        print -u2 "Refusing symlink password metadata for profile '${profile}'"
        return 1
    fi
    if [[ -L "$start_file" ]]; then
        print -u2 "Refusing symlink start-identity metadata for profile '${profile}'"
        return 1
    fi
    [[ ! -f "$password_file" ]] || command chmod 600 "$password_file" 2>/dev/null || {
        print -u2 "Cannot protect profile password metadata for '${profile}'"
        return 1
    }
    [[ ! -f "$start_file" ]] || command chmod 600 "$start_file" 2>/dev/null || {
        print -u2 "Cannot protect profile start-identity metadata for '${profile}'"
        return 1
    }

    local metadata_complete=0
    if [[ -f "$pid_file" && -f "$port_file" && -f "$password_file" && -f "$start_file" && ! -L "$password_file" && ! -L "$start_file" ]]; then
        pid=$(<"$pid_file")
        port=$(<"$port_file")
        password=$(<"$password_file")
        start=$(<"$start_file")
        if [[ "$pid" =~ '^[0-9]{1,10}$' && "$port" =~ '^[0-9]{5}$' &&
              -n "$start" &&
              "$password" =~ '^[0-9a-f]{64}$' ]]; then
            pid=$(( 10#$pid ))
            port=$(( 10#$port ))
            if (( pid > 0 && port >= 52000 && port <= 61999 )); then
                metadata_complete=1
            fi
        fi
    fi
    if (( ! metadata_complete )) && [[ -f "$pid_file" ]]; then
        pid=$(<"$pid_file")
        if [[ "$pid" =~ '^[0-9]{1,10}$' ]]; then
            pid=$(( 10#$pid ))
            if (( pid > 0 )) && _oc_v2_pid_alive "$pid"; then
                print -u2 "Profile '${profile}' has a live PID but incomplete wrapper metadata. Refusing to start or signal another process."
                return 1
            fi
        fi
    fi

    if (( metadata_complete )) && _oc_v2_server_matches "$pid" "$port" "$start"; then
        if ! _oc_v2_api_matches "$pid" "$port" "$password" "$config_fragment" "$start" "$serve_log"; then
            print -u2 "Profile '${profile}' has a live process (PID ${pid}) recorded as its server, but it could not be authenticated and config-verified. Refusing to attach, stop, or signal it."
            print -u2 "If this is a server lingering from a failed stop, wait for it to exit or stop it manually; once the process is gone, the next oc command removes the leftover metadata automatically."
            return 1
        fi
        if (( want_stop || want_restart )); then
            _oc_v2_stop_owned "$state_dir" "$pid" "$port" "$password" "$config_fragment" "$start" || return 1
            if (( want_stop )); then
                return 0
            fi
        else
            zsystem flock -u "$lock_fd" 2>/dev/null
            url="http://127.0.0.1:${port}"
            _oc_v2_client "$config_file" "$password" "$url" "${args[@]}"
            return $?
        fi
    elif (( metadata_complete )) && _oc_v2_pid_alive "$pid"; then
        print -u2 "Profile '${profile}' metadata points to a live process that cannot be proven to be its opencode server. Refusing to signal it."
        return 1
    elif (( want_stop )); then
        rm -f -- "$pid_file" "$start_file"
        print "No running opencode server for profile '${profile}'"
        return 0
    else
        # A dead PID is stale metadata; it is safe to discard without signaling.
        rm -f -- "$pid_file" "$start_file"
    fi

    if (( want_stop )); then
        print "No running opencode server for profile '${profile}'"
        return 0
    fi

    password=$(od -An -N32 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    if [[ ! "$password" =~ '^[0-9a-f]{64}$' ]]; then
        print -u2 "Could not generate a valid profile server password."
        return 1
    fi
    [[ ! -L "$serve_log" && ( ! -e "$serve_log" || -f "$serve_log" ) ]] || {
        print -u2 "Refusing server log that is a symlink or non-regular file: ${serve_log}"
        return 1
    }
    ( umask 077; command touch "$serve_log" ) || { print -u2 "Cannot create server log in ${state_dir}"; return 1; }
    command chmod 600 "$serve_log" 2>/dev/null || return 1
    _oc_v2_atomic_write "$password_file" "$password" || { print -u2 "Cannot securely write profile password metadata."; return 1; }

    if [[ -f "$port_file" ]]; then
        candidate=$(<"$port_file")
        if [[ "$candidate" =~ '^[0-9]{5}$' ]]; then
            candidate=$(( 10#$candidate ))
        fi
        if [[ "$candidate" == <-> && "$candidate" -ge 52000 && "$candidate" -le 61999 ]]; then
            base="$candidate"
        else
            base=""
        fi
    else
        base=""
    fi
    if [[ -z "$base" ]]; then
        checksum=$(printf '%s' "$profile" | cksum)
        checksum=${checksum%% *}
        base=$(( 52000 + checksum % 10000 ))
    fi

    for (( candidate_index = 0; candidate_index < 32; candidate_index++ )); do
        port=$(( 52000 + (base - 52000 + candidate_index) % 10000 ))
        _oc_v2_atomic_write "$port_file" "$port" || { print -u2 "Cannot write profile port metadata."; return 1; }
        # Replace only dead/missing PID metadata. Never signal an unverified PID.
        rm -f -- "$pid_file" "$start_file"
        [[ ! -L "$serve_log" && ( ! -e "$serve_log" || -f "$serve_log" ) ]] || {
            print -u2 "Refusing server log that is a symlink or non-regular file: ${serve_log}"
            return 1
        }
        : >| "$serve_log" || { print -u2 "Cannot reset server log in ${state_dir}"; return 1; }
        OPENCODE_CONFIG="$config_file" OPENCODE_SERVER_PASSWORD="$password" \
            nohup opencode serve --hostname 127.0.0.1 --port "$port" {lock_fd}>&- >> "$serve_log" 2>&1 &!
        pid=$!
        expected_start=$(ps -p "$pid" -o lstart= 2>/dev/null)
        if [[ -z "$expected_start" ]]; then
            if _oc_v2_pid_alive "$pid"; then
                _oc_v2_atomic_write "$pid_file" "$pid" 2>/dev/null
                print -u2 "Could not record start identity for live server PID ${pid}; leaving it untouched."
                return 1
            fi
            rm -f -- "$pid_file" "$start_file"
            continue
        fi
        if ! _oc_v2_atomic_write "$pid_file" "$pid" || ! _oc_v2_atomic_write "$start_file" "$expected_start"; then
            _oc_v2_stop_spawned "$pid" "$port" "$expected_start" 2>/dev/null
            print -u2 "Cannot write profile process identity metadata."
            return 1
        fi

        for (( attempt = 0; attempt < 40; attempt++ )); do
            if ! _oc_v2_pid_alive "$pid"; then
                break
            fi
            if _oc_v2_server_matches "$pid" "$port" "$expected_start" && _oc_v2_log_bound "$port" "$serve_log"; then
                if _oc_v2_api_matches "$pid" "$port" "$password" "$config_fragment" "$expected_start" "$serve_log"; then
                    url="http://127.0.0.1:${port}"
                    zsystem flock -u "$lock_fd" 2>/dev/null
                    _oc_v2_client "$config_file" "$password" "$url" "${args[@]}"
                    return $?
                fi
            fi
            sleep 0.25
        done

        if ! _oc_v2_pid_alive "$pid"; then
            rm -f -- "$pid_file" "$start_file"
            # A process that exits during startup is safe to retry on another port.
            continue
        fi
        if ! _oc_v2_server_matches "$pid" "$port" "$expected_start"; then
            print -u2 "Could not revalidate the spawned server PID ${pid}; leaving it untouched."
            return 1
        fi
        if ! _oc_v2_log_bound "$port" "$serve_log"; then
            if ! _oc_v2_stop_spawned "$pid" "$port" "$expected_start"; then
                print -u2 "Timed out waiting for the verified spawned server PID ${pid} to exit; no other process was signaled."
                print -u2 "If it is still running, stop it manually: kill -9 ${pid}"
                return 1
            fi
            if _oc_v2_bind_failed "$serve_log"; then
                rm -f -- "$pid_file" "$start_file"
                # Retry only when this process's log proves the bind was rejected.
                continue
            fi
            print -u2 "The spawned server did not prove a successful bind on port ${port}; it was terminated safely."
            return 1
        fi
        # Only clean up the child launched above, and only while both its
        # process identity and successful bind are still verifiable.
        if ! _oc_v2_server_matches "$pid" "$port" "$expected_start" ||
           ! _oc_v2_log_bound "$port" "$serve_log"; then
            print -u2 "Could not revalidate the bound spawned server PID ${pid}; it remains running for safety."
            return 1
        fi
        if ! _oc_v2_stop_spawned "$pid" "$port" "$expected_start"; then
            print -u2 "Could not safely stop the bound spawned server PID ${pid}; it remains running for safety."
            print -u2 "If it is still running, stop it manually: kill -9 ${pid}"
            return 1
        fi
        rm -f -- "$pid_file" "$start_file"
        print -u2 "Authenticated configuration verification failed for the spawned server on port ${port}; it was safely stopped."
        return 1
    done

    print -u2 "No safe loopback port was available for profile '${profile}' after 32 attempts."
    print -u2 "No process occupying a candidate port was stopped."
    return 1
)

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
        if ! _oc_valid_profile "$source_profile" || ! _oc_valid_profile "$dest_profile"; then
            print -u2 "Invalid profile name. Use letters, digits, dot, underscore, or hyphen; the first character must be alphanumeric."
            return 1
        fi
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
        if ! _oc_valid_profile "$delete_profile"; then
            print -u2 "Invalid profile name. Use letters, digits, dot, underscore, or hyphen; the first character must be alphanumeric."
            return 1
        fi
        local delete_dir="${profiles_dir}/${delete_profile}"
        if [[ ! -d "$delete_dir" ]]; then
            print -u2 "Profile '${delete_profile}' not found"
            return 1
        fi
        rm -rf "$delete_dir"
        print "Deleted profile '${delete_profile}'"
        return 0
    fi

    if ! _oc_valid_profile "$profile"; then
        print -u2 "Invalid profile name. Use letters, digits, dot, underscore, or hyphen; the first character must be alphanumeric."
        return 1
    fi

    local config_file="${profiles_dir}/${profile}/opencode.jsonc"

    local major
    major=$(_oc_opencode_major_version)
    if (( ${major:-0} < 2 )) && (( do_restart || do_stop )); then
        print -u2 "--stop and --restart are supported only with opencode v2 or newer."
        return 1
    fi

    # Stopping a v2 server does not require the profile config to still exist.
    if (( ${major:-0} >= 2 )) && (( do_stop )); then
        _oc_v2_launch "$config_file" "$profile" "$do_restart" "$do_stop" "${positionals[@]}"
        return $?
    fi

    if [[ ! -f "$config_file" ]]; then
        print -u2 "Profile '${profile}' not found at ${config_file}"
        print -u2 "Available profiles:"
        local dir
        for dir in "${profiles_dir}"/*/; do
            [[ -f "${dir}opencode.jsonc" ]] && print -u2 "  ${dir:t}"
        done
        return 1
    fi

    # v2 manages its own wrapper-launched loopback server; v1 honors OPENCODE_CONFIG.
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
