#!/bin/bash
set +H

# @function banb_copy
# @description Ansible-like file copy module with enhanced features
# @param src=SOURCE Source file or directory path
# @param dest=DEST Destination path (required)
# @param content=CONTENT Inline content to write
# @param owner=OWNER File owner
# @param group=GROUP File group
# @param mode=MODE File permissions (e.g. 0644)
# @param backup=yes|no Create backup before overwriting
# @param force=yes|no Force operation even if checks fail
# @param become=yes|no Run with elevated privileges
# @param recursive=yes|no Copy directories recursively
# @return 0 on success, 1 on error

banb_copy() {
    # Initialize variables with defaults
    local SRC="" DEST="" CONTENT="" OWNER="" GROUP="" MODE=""
    local BACKUP="no" FORCE="no" BECOME="no" RECURSIVE="no"
    
    # Parse arguments (Ansible-style key=value)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            src=*) SRC="${1#*=}" ;;
            dest=*) DEST="${1#*=}" ;;
            content=*) CONTENT="${1#*=}" ;;
            owner=*) OWNER="${1#*=}" ;;
            group=*) GROUP="${1#*=}" ;;
            mode=*) MODE="${1#*=}" ;;
            backup=*) BACKUP="${1#*=}" ;;
            force=*) FORCE="${1#*=}" ;;
            become=*) BECOME="${1#*=}" ;;
            recursive=*) RECURSIVE="${1#*=}" ;;
            help) _banb_copy_show_help; return 0 ;;
            *) echo "ERROR: Invalid parameter format: $1 (should be key=value)" >&2; return 1 ;;
        esac
        shift
    done
    
    # Validate required parameters
    if [[ -z "$DEST" ]]; then
        echo "ERROR: dest parameter is required" >&2
        return 1
    fi
    
    if [[ -n "$SRC" && -n "$CONTENT" ]]; then
        echo "ERROR: Cannot specify both src and content" >&2
        return 1
    fi
    
    if [[ -z "$SRC" && -z "$CONTENT" ]]; then
        echo "ERROR: Must specify either src or content" >&2
        return 1
    fi
    
    # Validate paths
    _banb_copy_validate_path "$DEST" "destination" || return 1
    if [[ -n "$SRC" ]]; then
        _banb_copy_validate_path "$SRC" "source" || return 1
    fi
    
    # Implement force option logic
    if [[ "$FORCE" != "yes" ]]; then
        if [[ "$DEST" =~ : ]]; then
            echo "ERROR: Invalid destination path (contains colon). Use force=yes to override." >&2
            return 1
        fi
    fi
    
    # Main copy logic
    if [[ -n "$SRC" ]]; then
        if [[ -d "$SRC" && "$RECURSIVE" == "yes" ]]; then
            _banb_copy_copy_dir "$SRC" "$DEST" "$BACKUP" "$BECOME" || return 1
        else
            _banb_copy_copy_file "$SRC" "$DEST" "$BACKUP" "$BECOME" || return 1
        fi
    else
        _banb_copy_write_content "$CONTENT" "$DEST" "$BACKUP" "$BECOME" || return 1
    fi
    
    # Set attributes if specified
    if [[ -n "$OWNER" || -n "$GROUP" ]]; then
        _banb_copy_set_ownership "$DEST" "$OWNER" "$GROUP" "$BECOME" || return 1
    fi
    if [[ -n "$MODE" ]]; then
        _banb_copy_set_permissions "$DEST" "$MODE" "$BECOME" || return 1
    fi
    
    echo "INFO: File operation completed successfully"
    return 0
}

# Internal helper functions
_banb_copy_validate_path() {
    local path="$1"
    local path_type="$2"
    
    # Basic path validation
    if [[ -z "$path" ]]; then
        echo "ERROR: ${path_type} path cannot be empty" >&2
        return 1
    fi
    
    # Check for dangerous patterns
    if [[ "$path" =~ \.\./\.\./ ]]; then
        echo "ERROR: ${path_type} path contains dangerous pattern" >&2
        return 1
    fi
    
    # For source, check if exists
    if [[ "$path_type" == "source" && ! -e "$path" ]]; then
        echo "ERROR: Source path does not exist: $path" >&2
        return 1
    fi
    
    return 0
}

_banb_copy_run_command() {
    local cmd="$1"
    local become="$2"
    
    if [[ "$become" == "yes" ]]; then
        sudo $cmd
    else
        $cmd
    fi
}

_banb_copy_copy_file() {
    local src="$1"
    local dest="$2"
    local backup="$3"
    local become="$4"
    
    # Create backup if needed
    if [[ "$backup" == "yes" && -e "$dest" ]]; then
        local backup_file="${dest}.bak.$(date +%s)"
        _banb_copy_run_command "cp "$dest" "$backup_file"" "$become" || return 1
    fi
    
    # Ensure destination directory exists
    local dest_dir
    dest_dir=$(dirname "$dest")
    if [[ ! -d "$dest_dir" ]]; then
        _banb_copy_run_command "mkdir -p "$dest_dir"" "$become" || return 1
    fi
    
    # Copy file
    _banb_copy_run_command "cp "$src" "$dest"" "$become" || return 1
}

_banb_copy_copy_dir() {
    local src="$1"
    local dest="$2"
    local backup="$3"
    local become="$4"
    
    # Create backup if needed
    if [[ "$backup" == "yes" && -e "$dest" ]]; then
        local backup_dir="${dest}.bak.$(date +%s)"
        _banb_copy_run_command "cp -r "$dest" "$backup_dir"" "$become" || return 1
    fi
    
    # Copy directory
    if [[ -d "$dest" ]]; then
        # If destination exists and is a directory, copy source into it
        local src_basename
        src_basename=$(basename "$src")
        _banb_copy_run_command "cp -r "$src" "$dest/$src_basename"" "$become" || return 1
    else
        # If destination doesn't exist, copy source to destination
        _banb_copy_run_command "cp -r "$src" "$dest"" "$become" || return 1
    fi
}

_banb_copy_write_content() {
    local content="$1"
    local dest="$2"
    local backup="$3"
    local become="$4"
    
    # Create backup if needed
    if [[ "$backup" == "yes" && -e "$dest" ]]; then
        local backup_file="${dest}.bak.$(date +%s)"
        _banb_copy_run_command "cp "$dest" "$backup_file"" "$become" || return 1
    fi
    
    # Ensure destination directory exists
    local dest_dir
    dest_dir=$(dirname "$dest")
    if [[ ! -d "$dest_dir" ]]; then
        _banb_copy_run_command "mkdir -p "$dest_dir"" "$become" || return 1
    fi
    
    # Write content
    if [[ "$become" == "yes" ]]; then
        printf "%s" "$content" | sudo tee "$dest" > /dev/null
    else
        printf "%s" "$content" | tee "$dest" > /dev/null
    fi
}

_banb_copy_set_ownership() {
    local path="$1"
    local owner="$2"
    local group="$3"
    local become="$4"
    
    if [[ -n "$owner" || -n "$group" ]]; then
        local target=""
        [[ -n "$owner" ]] && target="$owner"
        [[ -n "$group" ]] && target="${target}:${group}"
        _banb_copy_run_command "chown "$target" "$path"" "$become" || return 1
    fi
}

_banb_copy_set_permissions() {
    local path="$1"
    local mode="$2"
    local become="$3"
    
    _banb_copy_run_command "chmod "$mode" "$path"" "$become" || return 1
}

_banb_copy_show_help() {
    cat <<EOF
banb_copy - Ansible-like file copy module

Usage:
  banb_copy dest=PATH [src=SOURCE | content=TEXT]
            [owner=USER] [group=GROUP] [mode=MODE]
            [backup=yes] [force=yes] [become=yes] [recursive=yes]

Parameters:
  src=SOURCE       Source file or directory to copy
  dest=PATH       Destination path (required)
  content=TEXT    Content to write to destination
  owner=USER      Set file owner
  group=GROUP     Set file group
  mode=MODE       Set file permissions (e.g. 0644)
  backup=yes      Create backup before overwriting
  force=yes       Force operation even if checks fail
  become=yes      Run with elevated privileges
  recursive=yes   Copy directories recursively
  help            Show this help message

Examples:
  banb_copy src=/tmp/file.conf dest=/etc/file.conf owner=root mode=0644
  banb_copy dest=/etc/motd content="Welcome\\n"
  banb_copy src=/tmp/data dest=/opt/data recursive=yes
EOF
}

# Execute main function if not sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    banb_copy "$@"
fi