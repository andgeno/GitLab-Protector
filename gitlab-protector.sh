#!/usr/bin/env bash
set -eu

################################################################################
## CONFIG
################################################################################

## NOTE:
## In case you need to change any of the defaults, please create a file
## /etc/default/gitlab-protector and use the same variable names in order
## to override the default values.

## Path to the hashed GitLab repositories.
DIR_GITLAB_HASHED_REPOS="/var/opt/gitlab/git-data/repositories/@hashed/"



################################################################################
## FUNCTIONS
################################################################################

## Print script usage.
function print_usage() {
    cat <<_EOF_
USAGE: $(basename "$0") [COMMAND] [OPTIONS...]

    COMMAND
        config, c [ARGS]       Starts interactive configuration menu.
        fix, f                 Fixes all dangling symlinks in repositories that use GitLab Protector.
        status, s              Displays an overview of the configuration status per repository.
        uninstall, u           Starts interactive uninstall menu for repositories.

    OPTIONS
        -h, --help             This help screen.

    ARGS for 'config'
        groups, g              Starts interactive configuration menu for groups.
        repository, repo, r    Starts interactive configuration menu for repositories.

_EOF_
}

## Finds all gitlab repos and stores them in REPO_* global variables.
function load_gitlab_repos() {
    local IFS=$'\n'
    local repo_paths=($(
        cd "$DIR_GITLAB_HASHED_REPOS"
        find . -type f -name config \
            | grep -v '.wiki.git/' \
            | grep -v '\+[0-9]+\+deleted.git/' \
            | xargs grep 'fullpath = ' \
            | sed -E 's|^./||;s|^(.+\.git)/config:\s+fullpath = (.+$)|\2\|\|\|\1|' \
            | grep -vE 'gitlab-instance-administrators-.+' \
            | sort -k1
    ))
    REPO_NAME=()
    REPO_PATH=()
    REPO_SYMLINK_INSTALLED=()
    REPO_SYMLINK_DANGLING=()
    local repo_raw
    for repo_raw in ${repo_paths[@]}
    do
        local repo_name="${repo_raw%|||*}"
        local repo_path="${repo_raw#*|||}"
        REPO_NAME+=("$repo_name")
        REPO_PATH+=("$repo_path")

        local file_symlink_src="$SCRIPTPATH/$PATH_GITLAB_PROTECTOR_SCRIPT"
        local file_symlink_dst="$DIR_GITLAB_HASHED_REPOS/$repo_path/custom_hooks/$PATH_GITLAB_PROTECTOR_SCRIPT"

        ## Does the symlink exist?
        if [[ -L "$file_symlink_dst" ]]
        then
            REPO_SYMLINK_INSTALLED+=(1)

            ## Does the symlink point to the correct location?
            if [[ "$file_symlink_src" == "$(readlink -f "$file_symlink_dst")" ]]
            then
                REPO_SYMLINK_DANGLING+=(0)
            else
                REPO_SYMLINK_DANGLING+=(1)
            fi
        else
            REPO_SYMLINK_INSTALLED+=(0)
            REPO_SYMLINK_DANGLING+=(0)
        fi
    done
    REPO_NUM=${#REPO_PATH[@]}
}

## Finds all user configs and stores them in USER_CONFIG_* global variables.
function load_user_configs() {
    USER_CONFIG_PATH=()
    USER_CONFIG_RULES=()

    local IFS=$'\n'
    local user_config_paths=($(
        cd "$DIR_USER_CONFIG" || exit 1
        find . -type f -name "repo.*.conf" \
            | sed -E 's|^./||' \
            | sort -k1
    ))

    local user_config_path
    for user_config_path in ${user_config_paths[@]}
    do
        USER_CONFIG_PATH+=("$user_config_path")
        local rules_num=$(
            cat "$DIR_USER_CONFIG/$user_config_path" \
                | grep -vE '^\s*#' \
                | sed '/^\s*$/d' \
                | wc -l
        )
        USER_CONFIG_RULES+=("$rules_num")
    done
    USER_CONFIG_NUM=${#USER_CONFIG_PATH[@]}
}

## Checks which user configs do have an existing repo and stores info in USER_CONFIG_HAS_REPO global variable.
function load_user_config_has_repo() {
    USER_CONFIG_HAS_REPO=()

    local i
    for (( i=0; i<USER_CONFIG_NUM; i++ ))
    do
        local user_config_path="${USER_CONFIG_PATH[$i]}"
        local user_config_hash="$(dash2slash "${user_config_path}")"
        user_config_hash="${user_config_hash#repo.}"
        user_config_hash="${user_config_hash%.conf}"

        local has_repo=0
        for (( j=0; j<REPO_NUM; j++ ))
        do
            local repo_path="${REPO_PATH[$j]}"
            local repo_hash="${repo_path%.git}"

            [[ "$repo_hash" == "$user_config_hash" ]] || continue
            if [[ -d "$DIR_GITLAB_HASHED_REPOS/$repo_path" ]]
            then
                has_repo=1
                break
            fi
        done
        USER_CONFIG_HAS_REPO+=( $has_repo )
    done
}

## Checks which repos do have an existing user config and stores info in REPO_HAS_USER_CONFIG global variable.
function load_repo_has_user_config() {
    REPO_HAS_USER_CONFIG=()

    local i
    for (( i=0; i<REPO_NUM; i++ ))
    do
        local repo_path="${REPO_PATH[$i]}"
            local repo_hash="${repo_path%.git}"
        local has_user_config=0
        for (( j=0; j<USER_CONFIG_NUM; j++ ))
        do
            local user_config_path="${USER_CONFIG_PATH[$j]}"
            local user_config_hash="$(dash2slash "${user_config_path}")"
            user_config_hash="${user_config_hash#repo.}"
            user_config_hash="${user_config_hash%.conf}"

            [[ "$repo_hash" == "$user_config_hash" ]] || continue
            if [[ -f "$DIR_USER_CONFIG/$user_config_path" ]]
            then
                has_user_config=1
                break
            fi
        done
        REPO_HAS_USER_CONFIG+=( $has_user_config )
    done
}

## Searches for an existing user config by a repo hash.
##
## @param repo_hash
## @returns index for USER_CONFIG_* global variables
function get_user_config_index_by_repo_hash() {
    local repo_hash="$1"
    local i
    for (( i=0; i<USER_CONFIG_NUM; i++ ))
    do
        local user_config_path="${USER_CONFIG_PATH[$i]}"
        local user_config_hash="$(dash2slash "${user_config_path}")"
        user_config_hash="${user_config_hash#repo.}"
        user_config_hash="${user_config_hash%.conf}"
        if [[ "$repo_hash" == "$user_config_hash" ]]
        then
            echo  $i
            return
        fi
    done
    echo -1
}

## Converts all slashes to dashes in input string.
##
## @returns Converted string
function slash2dash() {
    echo "${1//\//-}"
}

## Converts all dashes to slashes in input string.
##
## @returns Converted string
function dash2slash() {
    echo "${1//-/\/}"
}

## Runs the interactive configuration (main) menu.
## By passing arguments to this function a specific menu can be opened directly.
##
## @param args for 'config' command
function do_config() {
    if (( $# > 0 ))
    then
        case "$1" in
            groups|group|g)
                do_config_groups
                ;;
            repository|repo|r)
                do_config_repo
                ;;
            *)
                echo -e "\033[0;31;1mERROR:\033[0m Invalid choice." >&2
                ;;
        esac
        return
    fi

    while :
    do
        echo
        echo "  g: groups"
        echo "  r: repository"
        echo
        echo -n "What do you want to configure? "
        read
        case "$REPLY" in
            '')
                return
                ;;
            g)
                do_config_groups
                ;;
            r)
                do_config_repo
                ;;
            *)
                echo -e "\033[0;31;1mERROR:\033[0m Invalid choice." >&2
                ;;
        esac
    done
}

## Runs the interactive configuration menu for the global 'groups' configuration file.
## Before the configuration file is opened in the editor it will be checked whether
## a configuration file for 'groups' does already exist. If it does not exist a copy
## from the groups config template will be created first.
function do_config_groups() {
    file_config="$FILE_GROUPS"
    if [[ ! -e "$file_config" ]]
    then
        echo "Creating new configuration file from template ..."
        cp "$PATH_TEMPLATE_GROUPS_CONF" "$file_config"
    fi

    ${EDITOR:-vi} "$file_config"

    exit 0
}

## Runs the interactive configuration menu for selecting a repository to edit.
## Before a configuration file is opened in the editor it will be checked whether
## a configuration file for the selected repo does already exist. If it does not exist
## a copy from the repo config template will be created first.
function do_config_repo() {
    if (( REPO_NUM == 0 ))
    then
        echo -e "\033[0;31;1mERROR:\033[0m No GitLab repositories found. Create at least one first and try again." >&2
        return
    fi

    while :
    do
        echo

        local i
        for (( i=0; i<REPO_NUM; i++ ))
        do
            local repo_name="${REPO_NAME[$i]}"
            local repo_path="${REPO_PATH[$i]}"

            printf "  %3d: %s\n" \
                "$i" \
                "$repo_name"
        done

        echo
        echo -n "Which repository do you want to configure? "
        read

        local input="${REPLY// /}"

        [[ -n "${input}" ]] || break
        if ! [[ "$input" =~ ^[0-9]+ ]] || (( input >= REPO_NUM ))
        then
            echo -e "\033[0;31;1mERROR:\033[0m Invalid choice." >&2
            continue
        fi

        local i="$input"
        local repo_name="${REPO_NAME[$i]}"
        local repo_path="${REPO_PATH[$i]}"
        local repo_hash="${repo_path%.git}"
        local user_config_path="repo.$(slash2dash "${repo_hash}").conf"

        file_config="$DIR_USER_CONFIG/$user_config_path"
        if [[ ! -e "$file_config" ]]
        then
            echo "Creating new configuration file from template ..."
            cp "$PATH_TEMPLATE_REPO_CONF" "$file_config"
        fi

        ${EDITOR:-vi} "$file_config"

        install_or_update_config_by_repo_hash "$repo_hash"

        exit 0
    done
}

## Displays a status overview about each GitLab repo found and how many rules
## have been configured if any.
function do_status() {
    echo -e "  GitLab Hashed Repos         : \033[0;33;1m$DIR_GITLAB_HASHED_REPOS\033[0m"
    echo -e "  GitLab Protector user config: \033[0;33;1m$DIR_USER_CONFIG\033[0m"
    echo

    printf "  \033[0;37;1m%-74s\033[0m | \033[0;37;1m%-9s\033[0m | \033[0;37;1m%-5s\033[0m | \033[0;37;1m%s\033[0m\n" \
        "GITLAB HASHED REPOSITORY DIRECTORY" \
        "INSTALLED" \
        "RULES" \
        "REPOSITORY NAME"

    echo "  ---------------------------------------------------------------------------+-----------+-------+---------------------------------------"

    local i
    for (( i=0; i<REPO_NUM; i++ ))
    do
        local repo_name="${REPO_NAME[$i]}"
        local repo_path="${REPO_PATH[$i]}"
        local repo_hash="${repo_path%.git}"
        local has_user_config="${REPO_HAS_USER_CONFIG[$i]}"
        local user_config_rules
        if (( has_user_config == 1 ))
        then
            local index=$(get_user_config_index_by_repo_hash "$repo_hash")
            if [[ -n "$index" ]] && (( index >= 0 ))
            then
                user_config_rules="${USER_CONFIG_RULES[$index]}"
            else
                user_config_rules="?"
            fi
        else
            user_config_rules=""
        fi
        local installed
        local color_installed
        if (( ${REPO_SYMLINK_INSTALLED[$i]} == 1 ))
        then
            if (( ${REPO_SYMLINK_DANGLING[$i]} == 1 ))
            then
                installed="dangling"
                color_installed=$'\033[0;33;5m'
            else
                installed="yes"
                color_installed=$'\033[0;32;1m'
            fi
        else
            installed="no"
            color_installed=''
        fi

        printf "  %74s | ${color_installed}%9s\033[0m | %5s | %s\n" \
            "${repo_hash}.git" \
            "$installed" \
            "$user_config_rules" \
            "$repo_name"
    done
    echo

    for (( i=0; i<USER_CONFIG_NUM; i++ ))
    do
        local user_config_path="${USER_CONFIG_PATH[$i]}"
        local has_repo=${USER_CONFIG_HAS_REPO[$i]}
        if (( has_repo == 0 ))
        then
            (
            echo -e "\033[0;33;1mWARNING:\033[0m Repository is missing for configuration \`\033[0;33;1m$user_config_path\033[0m'."
            echo "The corresponding repository has probably been deleted. Delete this configuration file if you no longer need it."
            echo
            ) >&2
        fi
    done

    if [[ ! -r "$FILE_GROUPS" ]]
    then
        (
        echo -e "\033[0;33;1mWARNING:\033[0m No group configuration file found at \`\033[0;33;1m$FILE_GROUPS\033[0m'."
        echo -e "Use command '\033[0;36;1m$(basename "$0") config groups\033[0m' to resolve this issue."
        echo
        ) >&2
    fi
}

## Fixes all dangling symlinks by replacing them with the new/correct location.
function do_fix_dangling_symlinks() {
    local num_fixed=0
    local i
    for (( i=0; i<REPO_NUM; i++ ))
    do
        local repo_name="${REPO_NAME[$i]}"
        local repo_path="${REPO_PATH[$i]}"
        local repo_hash="${repo_path%.git}"

        if (( ${REPO_SYMLINK_INSTALLED[$i]} == 1 ))
        then
            if (( ${REPO_SYMLINK_DANGLING[$i]} == 1 ))
            then
                echo -e "\033[0;32;1m*\033[0m Fixing dangling symlink for repo \`\033[0;33;1m$repo_name\033[0m' ..."
                install_or_update_config_by_repo_hash "$repo_hash" none
                num_fixed=$(( num_fixed+1 ))
            fi
        fi
    done
    if (( num_fixed == 0 ))
    then
        echo "No dangling symlinks found. All good!"
    fi
}

## Runs the interactive configuration menu for uninstalling GitLab Protector for a repository.
## The uninstallation process is simply removing the symlink. It will NOT delete your user config.
function do_uninstall_repo() {
    if (( REPO_NUM == 0 ))
    then
        echo -e "\033[0;31;1mERROR:\033[0m No GitLab repositories found. Create at least one first and try again." >&2
        return
    fi

    while :
    do
        echo

        local uninstallable_repo_num=0
        local i
        for (( i=0; i<REPO_NUM; i++ ))
        do
            local repo_name="${REPO_NAME[$i]}"
            local repo_path="${REPO_PATH[$i]}"

            (( ${REPO_SYMLINK_INSTALLED[$i]} == 1 )) || continue
            uninstallable_repo_num=$(( uninstallable_repo_num + 1 ))

            printf "  %3d: %s\n" \
                "$i" \
                "$repo_name"
        done

        if (( uninstallable_repo_num == 0 ))
        then
            echo -e "\033[0;31;1mERROR:\033[0m No GitLab repositories with GitLab Protector installed were found." >&2
            return
        fi

        echo
        echo -n "For which repository do you want to uninstall GitLab Protector? "
        read

        local input="${REPLY// /}"

        [[ -n "${input}" ]] || break
        if ! [[ "$input" =~ ^[0-9]+ ]] || (( input >= REPO_NUM ))
        then
            echo -e "\033[0;31;1mERROR:\033[0m Invalid choice." >&2
            continue
        fi

        if (( ${REPO_SYMLINK_INSTALLED[$input]} != 1 ))
        then
            echo -e "\033[0;31;1mERROR:\033[0m Invalid choice. GitLab Protector is not installed for this repository." >&2
            continue
        fi

        local i="$input"
        local repo_name="${REPO_NAME[$i]}"
        local repo_path="${REPO_PATH[$i]}"
        local repo_hash="${repo_path%.git}"

        uninstall_symlink_by_repo_hash "$repo_hash"

        exit 0
    done

}

## Convenience method to load and prepare all required data at once.
function load_all() {
    load_gitlab_repos
    load_user_configs
    load_user_config_has_repo
    load_repo_has_user_config
}

## Installs or updates the symlink of a repo by the given repo hash.
##
## @param repo_hash
## @param verbosity {none|info}, default=info
function install_or_update_config_by_repo_hash() {
    local repo_hash="$1"
    local verbosity="${2:-info}"
    local repo_path="$DIR_GITLAB_HASHED_REPOS/${repo_hash}.git"

    local file_symlink_src="$SCRIPTPATH/$PATH_GITLAB_PROTECTOR_SCRIPT"
    local file_symlink_dst="$repo_path/custom_hooks/$PATH_GITLAB_PROTECTOR_SCRIPT"
    local dir_symlink_dst="$(dirname "$file_symlink_dst")"
    [[ -d "$dir_symlink_dst" ]] || mkdir -p "$dir_symlink_dst"

    if [[ ! -e "$file_symlink_dst" ]]
    then
        [[ "$verbosity" == "info" ]] && echo -e "Installing GitLab Protector in: \033[0;33;1m$file_symlink_dst\033[0m"
        ln -sf "$file_symlink_src" "$file_symlink_dst"
    fi
}

function check_env_exit_on_fail() {
    if [[ ! -d "$DIR_GITLAB_HASHED_REPOS" ]]
    then
        echo -e "\033[0;31;1mERROR:\033[0m GitLab directory with hashed repositories does not exist: \`\033[0;33;1m$DIR_GITLAB_HASHED_REPOS\033[0m'" >&2
        exit 1
    fi
}

## Uninstalls the symlink of a repo by the given repo hash.
##
## @param repo_hash
## @param verbosity {none|info}, default=info
function uninstall_symlink_by_repo_hash() {
    local repo_hash="$1"
    local verbosity="${2:-info}"
    local repo_path="$DIR_GITLAB_HASHED_REPOS/${repo_hash}.git"

    local file_symlink_dst="$repo_path/custom_hooks/$PATH_GITLAB_PROTECTOR_SCRIPT"

    if [[ -L "$file_symlink_dst" ]]
    then
        [[ "$verbosity" == "info" ]] && echo -e "Uninstalling GitLab Protector ..."
        rm "$file_symlink_dst"
    else
        echo -e "\033[0;31;1mERROR:\033[0m Could not uninstall GitLab Protector for selected repository. File \`$file_symlink_dst' is not a symlink or does not exist." >&2
    fi
}



################################################################################
## MAIN
################################################################################

SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
DIR_USER_CONFIG="$SCRIPTPATH/user-config"
FILE_GROUPS="$DIR_USER_CONFIG/groups.global.conf"
PATH_GITLAB_PROTECTOR_SCRIPT="pre-receive.d/net.twistedbytes.gitlab-protector.py"
PATH_TEMPLATE_REPO_CONF="$DIR_USER_CONFIG/repo.conf.TEMPLATE"
PATH_TEMPLATE_GROUPS_CONF="$DIR_USER_CONFIG/groups.global.conf.TEMPLATE"

REPO_NAME=()
REPO_PATH=()
REPO_HAS_USER_CONFIG=()
REPO_SYMLINK_INSTALLED=()
REPO_SYMLINK_DANGLING=()
REPO_NUM=0

USER_CONFIG_PATH=()
USER_CONFIG_HAS_REPO=()
USER_CONFIG_RULES=()
USER_CONFIG_NUM=0

## Optionally load custom settings configured for this system
[[ -r "/etc/default/gitlab-protector" ]] && . "/etc/default/gitlab-protector"

## Create user config directory if missing
[[ -d "$DIR_USER_CONFIG" ]] || mkdir "$DIR_USER_CONFIG" || exit 1

if (( $# == 0 ))
then
    print_usage >&2
    exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
    -h|--help|help)
        print_usage >&2
        exit 1
        ;;
    config|c)
        check_env_exit_on_fail
        load_all
        do_config $@
        ;;
    fix|f)
        check_env_exit_on_fail
        load_all
        do_fix_dangling_symlinks
        ;;
    status|s)
        check_env_exit_on_fail
        load_all
        do_status
        ;;
    uninstall|u)
        load_all
        do_uninstall_repo
        ;;
    *)
        echo "Unknown command \`$COMMAND'. Try '$(basename "$0") --help' for more information." >&2
        exit 1
        ;;
esac



