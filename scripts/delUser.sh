#!/bin/bash

# Copyright (c) 2023, Shiv Nadar University, Delhi NCR, India. All Rights
# Reserved. Permission to use, copy, modify and distribute this software for
# educational, research, and not-for-profit purposes, without fee and without a
# signed license agreement, is hereby granted, provided that this paragraph and
# the following two paragraphs appear in all copies, modifications, and
# distributions.
#
# IN NO EVENT SHALL SHIV NADAR UNIVERSITY BE LIABLE TO ANY PARTY FOR DIRECT,
# INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST
# PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE.
#
# SHIV NADAR UNIVERSITY SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT
# NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE. THE SOFTWARE PROVIDED HEREUNDER IS PROVIDED "AS IS". SHIV
# NADAR UNIVERSITY HAS NO OBLIGATION TO PROVIDE MAINTENANCE, SUPPORT, UPDATES,
# ENHANCEMENTS, OR MODIFICATIONS.
#

#
# Revision History:
# Date          By                     Change Notes
# ------------  ---------------------- ------------------------------------------
# 27/11/23      Santhosh(sb875)        Updated with copy right notice and disclaimer.
# 
# ...
# ...more entries as needed

# Constants
HOME_DIR="/nclnfs/users"
HOME_BAK_DIR="/nclbak/users"
DC_NAME="ncl"
DC_DOMAIN="in"
LDAP_PASSWD="a"
LDAP_LDIF_FILE="/tmp/user.bak.ldif"

# ANSI color codes
GREEN='\033[0;32m' # Green
RED='\033[0;31m'   # Red
NC='\033[0m'       # No Color
INVERSE='\033[7m'  # Inverse
BOLD='\033[1m'     # Bold

emphasize() {
    # $1 = message
    # $2 = color = {RED, GREEN}
    echo -e "${!2}${BOLD}${INVERSE}$1${NC}${NC}${NC}" >&2
}

success() {
    echo -e "${GREEN}$1${NC}" >&2
}

error() {
    # $1 = message
    # $2 = exit = {true, false} (default = true) This is used to exit the script after showing the error message
    echo -e "${RED}$1${NC}" >&2
    [ "$2" = false ] && return
    exit 1
}

check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        error "Error: This script must be run as root (sudo)."
        exit 1
    fi
}

ClearTempFiles() {
    rm -f "$LDAP_LDIF_FILE"
}

ArchiveUserData() {
    # Ref: https://akashrajpurohit.com/blog/backup-users-home-directory-in-linux-using-tar-command/
    local username="$1"

    # Create a backup of the user's home directory using tar and compress it using gzip
    tar -zcpf "${HOME_BAK_DIR}/${username}.tar.gz" "${HOME_DIR}/${username}"
    local exit_code="$?"

    case $exit_code in
    0)
        success "User '$username' home directory successfully archived to '${HOME_BAK_DIR}/${username}.tar.gz'."
        ;;
    1)
        error "Error: Some files differ. User '$username' home directory not archived. User not deleted."
        ;;
    2)
        error "Error: Fatal error. User '$username' home directory not archived. User not deleted."
        ;;
    esac
}

ArchivalConfirmation() {
    local username="$1"

    # emphasize "Warning: This will archive the user '$username' home directory to '${HOME_BAK_DIR}/${username}.tar.gz'." RED
    emphasize "Warning: This will archive the user '$username' home directory to '${HOME_BAK_DIR}/${username}.tar.gz' ($(du -sh "${HOME_DIR}/${username}" | cut -f1))." RED

    read -p "Are you sure you want to archive user '$username'? (yes/no): " confirmation
    if [[ "$confirmation" == "yes" ]]; then
        # check if the user's home directory exists
        if ! [[ -d "${HOME_DIR}/${username}" ]]; then
            error "Error: User '$username' home directory not found."
        fi

        # check if the backup directory exists
        if ! [[ -d "$HOME_BAK_DIR" ]]; then
            mkdir -p "$HOME_BAK_DIR"
        fi

        ArchiveUserData "$username"
    else
        error "User archival canceled." false
    fi
}

DeleteLocalUser() {
    local username="$1"
    local isExit="$2"
    userdel -r "$username"
    local exit_code="$?"

    case $exit_code in
    1)
        error "Error: Can't update the password file. User '$username' not deleted."
        ;;
    2)
        error "Error: Invalid command syntax. User '$username' not deleted."
        ;;
    6)
        error "Error: Specified user doesn't exist. User '$username' not deleted."
        ;;
    8)
        error "Error: User currently logged in. User '$username' not deleted."
        ;;
    10)
        error "Error: Can't update group file. User '$username' not deleted."
        ;;
    12)
        error "Error: Can't remove home directory. User '$username' not deleted."
        ;;
    esac

    success "User '$username' successfully deleted locally."
}

DeleteLDAPUser() {
    local username="$1"

    ldapdelete -x -w "$LDAP_PASSWD" -D "cn=Manager,dc=$DC_NAME,dc=$DC_DOMAIN" "uid=$username,ou=People,dc=$DC_NAME,dc=$DC_DOMAIN"
    local exit_code="$?"

    case $exit_code in
    0)
        success "User '$username' successfully deleted from LDAP."
        ;;
    *)
        error "Error: Failed to delete user '$username' from LDAP." false
        ;;
    esac

    ldapdelete -x -w "$LDAP_PASSWD" -D "cn=Manager,dc=$DC_NAME,dc=$DC_DOMAIN" "cn=$username,ou=Group,dc=$DC_NAME,dc=$DC_DOMAIN"
    local exit_code="$?"

    case $exit_code in
    0)
        success "User group successfully deleted from LDAP."
        ;;
    *)
        error "Error: Failed to delete user group from LDAP." false
        ;;
    esac

    ClearTempFiles
}

ListUsers() {
    local serial=0

    while IFS=: read -r username _ _ _ _ home _; do
        if [[ "$home" == "${HOME_DIR}"* ]]; then
            ((serial++))
        fi
    done </etc/passwd

    # If no users found, show error message and exit
    if [[ "$serial" -eq 0 ]]; then
        error "Error: No users found."
    fi

    serial=0
    echo "List of users:" >&2
    while IFS=: read -r username _ _ _ _ home _; do
        if [[ "$home" == "${HOME_DIR}"* ]]; then
            ((serial++))
            echo "${serial}) $username" >&2
        fi
    done </etc/passwd

    read -p "Select a username to delete: " username
    # if username not in list and user's home directory is not in /nclnfs/users, then show error message and exit
    if ! grep -q "^${username}:" /etc/passwd || ! [[ "$(grep "^${username}:" /etc/passwd | cut -d: -f6)" == "${HOME_DIR}"* ]]; then
        error "Error: Invalid username '$username'."
    fi

    read -p "Enter the username again to confirm: " username2
    if [[ "$username" != "$username2" ]]; then
        error "Error: Username mismatch."
    fi

    emphasize "Warning: This will delete the user '$username' and their home directory from the system and LDAP." RED
    read -p "Are you sure you want to delete user '$username'? (yes/no): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        error "User deletion canceled."
    fi

    echo "$username"
}

# ==================== Main Script ====================
check_sudo
username=$(ListUsers) || exit 1

ClearTempFiles
ArchivalConfirmation "$username" # Archive the user's home directory
DeleteLDAPUser "$username"       # Delete the user from LDAP
DeleteLocalUser "$username"      # Delete the user from the local system
ClearTempFiles                   # Remove the temporary files
