#!/bin/bash

# Constants
HOME_DIR="/nclnfs/users"
DC_NAME="ncl"
DC_DOMAIN="in"
LDAP_PASSWD="a"
LDAP_LDIF_FILE="/tmp/user.bak.ldif"

# ANSI color codes
GREEN='\033[0;32m' # Green
RED='\033[0;31m'   # Red
NC='\033[0m'       # No Color

success(){
    echo -e "${GREEN}$1${NC}" >&2
}

error(){
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

ClearTempFiles(){
    rm -f "$LDAP_LDIF_FILE"
}

DeleteLocalUser(){
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

DeleteLDAPUser(){
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

ListUsers(){
    local serial=0

    echo "List of users:" >&2
    while IFS=: read -r username _ _ _ _ home _; do
        if [[ "$home" == "${HOME_DIR}"* ]]; then
            ((serial++))
            echo "${serial}) $username" >&2
        fi
    done < /etc/passwd

    # If no users found, show error message and exit
    if [[ "$serial" -eq 0 ]]; then
        error "Error: No users found."
    fi

    read -p "Select a username to delete: " username
    # if username not in list and user's home directory is not in /nclnfs/users, then show error message and exit
    if ! grep -q "^${username}:" /etc/passwd || ! [[ "$(grep "^${username}:" /etc/passwd | cut -d: -f6)" == "${HOME_DIR}"* ]]; then
        error "Error: Invalid username '$username'."
    fi

    read -p "Enter the username again to confirm: " username2
    if [[ "$username" != "$username2" ]]; then
        error "Error: Username mismatch."
    fi

    error "Warning: This will delete the user '$username' from the system and LDAP." false
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
DeleteLDAPUser "$username"                               # Delete the user from LDAP
DeleteLocalUser "$username"                              # Delete the user from the local system
ClearTempFiles                                           # Remove the temporary files