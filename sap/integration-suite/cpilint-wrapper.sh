#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# Script name:  cpilint-wrapper.sh
# Description:  CPILint wrapper
# Author:       Vadim Klimov
# License:      MIT License
# Usage:        cpilint-wrapper.sh <command> [options]
# ---------------------------------------------------------------------------

set -euo pipefail

# Main
main() {
    [[ "$#" -lt 1 ]] && err "Command is not specified"
    command=$1 && shift

    [[ "$command" == "help" || "$command" == "--help" || "$command" == "-h" ]] && usage

    valid_commands=(
        "inspect-local-iflows"
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

    config_default=~/.config/cpilint/config.yaml
    [[ -z "${config:-}" ]] && info "CPILint configuration file is not specified" &&
        info "Using default location: $config_default" && config=$config_default
    cpilint_config_file="$(eval echo "$config")"
    info "CPILint configuration file: $cpilint_config_file"
    [[ ! -f "$cpilint_config_file" ]] && err "CPILint configuration file does not exist"

    dir="$(yq '.repo_dir' "$cpilint_config_file")"
    [[ "$dir" == "null" ]] && err "Repository directory is not specified in CPILint configuration file"
    repo_dir="$(eval echo "$dir")"
    info "Repository directory: $repo_dir"
    [[ ! -d "$repo_dir" ]] && err "Repository directory does not exist"

    tmp_dir_default="$TMPDIR/cpilint"
    dir="$(yq '.tmp_dir' "$cpilint_config_file")"
    [[ "$dir" == "null" ]] && info "Temporary directory is not specified in CPILint configuration file" &&
        info "Using default location: $tmp_dir_default" && dir=$tmp_dir_default
    tmp_dir="$(eval echo "$dir")"
    info "Temporary directory: $tmp_dir"

    rules_file_default=~/.config/cpilint/rules.xml
    file="$(yq '.rules_file' "$cpilint_config_file")"
    [[ "$file" == "null" ]] && info "Rules file is not specified in CPILint configuration file" &&
        info "Using default location: $rules_file_default" && file=$rules_file_default
    rules_file="$(eval echo "$file")"
    info "Rules file: $rules_file"
    [[ ! -f "$rules_file" ]] && err "Rules file does not exist"

    cd "$repo_dir" || err "Cannot navigate to repository directory"

    ${command//-/_}
}

# CPILint: Inspect iFlows stored in local Git repository
inspect_local_iflows() {
    git rev-parse --is-inside-work-tree &>/dev/null || err "Directory does not contain Git working tree"

    git_staged_files=$(git diff --staged --name-only)
    [[ -z "${git_staged_files:-}" ]] && err "Staging area does not contain staged files"
    packages_iflows=$(cut -d '/' -f1,2 <<<"$git_staged_files" | sort --unique)

    for package_iflow in $packages_iflows; do
        (
            package=$(dirname "$package_iflow")
            iflow=$(basename "$package_iflow")
            cd "$repo_dir/$package/$iflow" || err "Cannot navigate to iFlow directory: $_"
            mkdir -p "$tmp_dir/$package"
            zip --quiet --recurse-paths "$tmp_dir/$package/$iflow.zip" .
        ) &
    done

    wait

    cpilint \
        -rules "$rules_file" \
        -files "$tmp_dir/*/*" \
        -skipvercheck || true

    rm -rf "$tmp_dir"
}

# Usage message
usage() {
    echo "Description:"
    echo "  CPILint wrapper"
    echo
    echo "Usage:"
    echo "  $(basename "$0") <command> [options]"
    echo
    echo "Commands:"
    echo "  inspect-local-iflows    Inspect iFlows stored in local Git repository"
    echo
    echo "Options:"
    echo "  -c    Path to CPILint configuration file (default: ~/.config/cpilint/config.yaml)"
    echo
    echo "References:"
    echo "  CPILint (https://github.com/mwittrock/cpilint) - Automated governance of your SAP Cloud Integration flows"
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
