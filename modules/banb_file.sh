#!/bin/bash
# @module banb_file
# @desc Ansible-like file module for Bash
# @param path (required) - Target file/directory path
# @param state - file|directory|link|absent|touch (default: file)
# @param owner - File owner
# @param group - File group
# @param mode - Octal permissions (e.g. 0644)
# @param src - Source path for links
# @param recurse - yes|no for directory operations
# @param force - yes|no to force operations
# @return 0 on success, 1 on error

banb_file() {
    local TARGET_PATH="" STATE="file" OWNER="" GROUP="" MODE=""
    local SRC_PATH="" RECURSE="no" FORCE="no"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            path=*) TARGET_PATH="${1#*=}";;
            state=*) STATE="${1#*=}";;
            owner=*) OWNER="${1#*=}";;
            group=*) GROUP="${1#*=}";;
            mode=*) MODE="${1#*=}";;
            src=*) SRC_PATH="${1#*=}";;
            recurse=*) RECURSE="${1#*=}";;
            force=*) FORCE="${1#*=}";;
            *) echo "Unknown parameter: $1"; return 1;;
        esac
        shift
    done

    # Validate parameters
    [[ -z "$TARGET_PATH" ]] && { echo "path parameter is required"; return 1; }
    [[ ! "$STATE" =~ ^(file|directory|link|absent|touch)$ ]] && { echo "Invalid state: $STATE"; return 1; }
    [[ "$STATE" == "link" && -z "$SRC_PATH" ]] && { echo "src required for state=link"; return 1; }

    # Core operations
    case "$STATE" in
        file)
            if [[ ! -e "$TARGET_PATH" ]]; then
                touch "$TARGET_PATH" || return 1
                echo "Created file: $TARGET_PATH"
            elif [[ ! -f "$TARGET_PATH" ]]; then
                [[ "$FORCE" == "yes" ]] && { rm -rf "$TARGET_PATH" && touch "$TARGET_PATH" || return 1; } || \
                { echo "Path exists but is not a file: $TARGET_PATH"; return 1; }
            fi
            ;;

        directory)
            local mkdir_opts=""
            [[ "$RECURSE" == "yes" ]] && mkdir_opts="-p"

            if [[ ! -e "$TARGET_PATH" ]]; then
                mkdir $mkdir_opts "$TARGET_PATH" || return 1
                echo "Created directory: $TARGET_PATH"
            elif [[ ! -d "$TARGET_PATH" ]]; then
                [[ "$FORCE" == "yes" ]] && { rm -rf "$TARGET_PATH" && mkdir $mkdir_opts "$TARGET_PATH" || return 1; } || \
                { echo "Path exists but is not a directory: $TARGET_PATH"; return 1; }
            fi
            ;;

        link)
            if [[ ! -e "$TARGET_PATH" ]]; then
                ln -sf "$SRC_PATH" "$TARGET_PATH" || return 1
                echo "Created symlink: $TARGET_PATH -> $SRC_PATH"
            elif [[ ! -L "$TARGET_PATH" ]]; then
                [[ "$FORCE" == "yes" ]] && { rm -rf "$TARGET_PATH" && ln -sf "$SRC_PATH" "$TARGET_PATH" || return 1; } || \
                { echo "Path exists but is not a symlink: $TARGET_PATH"; return 1; }
            fi
            ;;

        absent)
            [[ -e "$TARGET_PATH" ]] && { rm -rf "$TARGET_PATH" || return 1; }
            ;;

        touch)
            touch "$TARGET_PATH" || return 1
            ;;
    esac

    # Set attributes if specified
    [[ -n "$OWNER" ]] && chown "$OWNER" "$TARGET_PATH"
    [[ -n "$GROUP" ]] && chgrp "$GROUP" "$TARGET_PATH"
    [[ -n "$MODE" ]] && chmod "$MODE" "$TARGET_PATH"

    return 0
}
