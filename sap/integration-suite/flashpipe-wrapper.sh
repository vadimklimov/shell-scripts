#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# Script name:  flashpipe-wrapper.sh
# Description:  FlashPipe wrapper
# Author:       Vadim Klimov
# License:      MIT License
# Usage:        flashpipe-wrapper.sh <command> [options]
# ---------------------------------------------------------------------------

set -euo pipefail

# Main
main() {
    [[ "$#" -lt 1 ]] && err "Command is not specified"
    command=$1 && shift

    [[ "$command" == "help" || "$command" == "--help" || "$command" == "-h" ]] && usage

    valid_commands=(
        "snapshot-tenant-to-repo"
        "sync-repo-latest-commit-to-tenant"
    )

    is_command_valid=false

    for valid_command in "${valid_commands[@]}"; do
        [[ "$command" == "$valid_command" ]] && is_command_valid=true && break
    done

    [[ "$is_command_valid" != true ]] && err "Unknown command: $command"

    while getopts ":c:" option; do
        case "$option" in
        c) config="$OPTARG" ;;
        \?) err "Invalid option: -$OPTARG" ;;
        :) err "Argument missing for option -$OPTARG" ;;
        esac
    done

    config_default=~/.config/flashpipe/config.yaml
    [[ -z "${config:-}" ]] && info "FlashPipe configuration file is not specified" &&
        info "Using default location: $config_default" && config=$config_default
    flashpipe_config_file="$(eval echo "$config")"
    info "FlashPipe configuration file: $flashpipe_config_file"
    [[ ! -f "$flashpipe_config_file" ]] && err "FlashPipe configuration file does not exist"

    tenant="$(yq '.tmn-host' "$flashpipe_config_file")"
    [[ "$tenant" == "null" ]] && err "SAP Cloud Integration tenant is not specified in FlashPipe configuration file"
    info "SAP Cloud Integration tenant: $tenant"

    dir="$(yq '.dir-git-repo' "$flashpipe_config_file")"
    [[ "$dir" == "null" ]] && err "Repository directory is not specified in FlashPipe configuration file"
    git_repo_dir="$(eval echo "$dir")"
    info "Local directory: $git_repo_dir"
    [[ ! -d "$git_repo_dir" ]] && err "Repository directory does not exist"

    cd "$git_repo_dir" || err "Cannot navigate to repository directory"

    ${command//-/_}
}

# FlashPipe: Snapshot tenant workspace to local Git repository
snapshot_tenant_to_repo() {
    git rev-parse --is-inside-work-tree &>/dev/null || git init

    flashpipe snapshot \
        --config "$flashpipe_config_file" \
        --git-commit-msg "Tenant workspace snapshot"
}

# FlashPipe: Synchronize changes contained in latest Git commit to tenant
sync_repo_latest_commit_to_tenant() {
    git rev-parse --is-inside-work-tree &>/dev/null || err "Directory does not contain Git working tree"

    git_latest_commit_files=$(git show --name-only --pretty=format:)
    [[ -z "${git_latest_commit_files:-}" ]] && err "Latest commit does not contain changed files"
    packages=$(cut -d '/' -f1 <<<"$git_latest_commit_files" | sort --unique)

    for package in $packages; do
        flashpipe sync \
            --config "$flashpipe_config_file" \
            --target tenant \
            --package-id "$package" \
            --dir-git-repo "$package" \
            &
    done

    wait
}

# Usage message
usage() {
    echo "Description:"
    echo "  FlashPipe wrapper"
    echo
    echo "Usage:"
    echo "  $(basename "$0") <command> [options]"
    echo
    echo "Commands:"
    echo "  snapshot-tenant-to-repo              Snapshot tenant workspace to local Git repository"
    echo "  sync-repo-latest-commit-to-tenant    Synchronize changes contained in latest Git commit to tenant"
    echo
    echo "Options:"
    echo "  -c    Path to FlashPipe configuration file (default: ~/.config/flashpipe/config.yaml)"
    echo
    echo "References:"
    echo "  FlashPipe (https://github.com/engswee/flashpipe) - The CI/CD Companion for SAP Integration Suite"
    exit 0
}

# Info message
info() {
    echo "$*"
}

# Error message and exit
err() {
    echo "$*" >&2
    exit 1
}

main "$@"
