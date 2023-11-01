#!/bin/bash

# Constants
HOME_DIR="/nclnfs/users"
DC_NAME="ncl"
DC_DOMAIN="in"
LDAP_PASSWD="a"
LDAP_LDIF_FILE="/tmp/user.ldif"


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

GenerateUID() {
  local start_uid=3000
  local max_uid=6000  

  # Find the first available UID in the range
  for ((uid = start_uid; uid <= max_uid; uid += 1)); do
    if ! id "$uid" &>/dev/null; then
      echo "$uid"
      return
    fi
  done

  error "Error: No available UID in the specified range."
  return 1
}

CreateLocalUser() {
    # print uid
    echo "UID: $(GenerateUID)" >&2

    local username="$1"                                                         # Username to create from the first argument
    useradd -m -u "$(GenerateUID)"  -d "$HOME_DIR/$username" "$username"        # Create the user with the next available UID
    local exit_code="$?"                                                        # Capture the exit code of the previous command

    # Display appropriate messages based on the exit code with colors
    case $exit_code in
        1)
            error "Error: Can't update the password file. User '$username' not created."
            ;;
        4)
            error "Error: UID is already in use. User '$username' not created."
            ;;
        9)
            error "Error: Username is already in use. User '$username' not created."
            ;;
        12)
            error "Error: Can't create the home directory for user '$username'. User not created."
            ;;
    esac

    echo "$username:$username" | sudo chpasswd                     # Set the password for the user
    sudo chage -d 0 "$username"                                    # Force the user to change their password on first login
    success "User '$username' successfully created and will be prompted to change their password on first login(Default password is same as their username)."
    printf "\n"
}

DeleteLocalUser(){
    local username="$1"
    local isExit="$2"
    userdel -r "$username"
    local exit_code="$?"


    case $exit_code in
        0)
            error "Error: Something went wrong. User '$username' deleted from local system." isExit
            ;;
        1)
            error "Error: Can't update the password file. User '$username' not deleted." isExit
            ;;
        6)
            error "Error: Specified user '$username' doesn't exist. User not deleted." isExit
            ;;
        8)
            error "Error: User '$username' is currently logged in. User not deleted." isExit
            ;;
        10)
            error "Error: Can't update the group file. User '$username' not deleted." isExit
            ;;
        12)
            error "Error: Can't remove the home directory for user '$username'. User not deleted." isExit
            ;;
    esac
}

GenerateUserLDIF() {
  local username="$1"
  local SUFFIX="dc=$DC_NAME,dc=$DC_DOMAIN"

  # Check if the user with the provided username exists
  if grep -q "$username" /etc/passwd; then
    local USER_ID="$username"
    local TARGET_USER=$(grep "$USER_ID" /etc/passwd)

    local USER_NAME="$(echo "$TARGET_USER" | cut -d':' -f5 | cut -d' ' -f1,2)"
    [ ! "$USER_NAME" ] && USER_NAME="$USER_ID"

    local LDAP_SN="$(echo "$USER_NAME" | cut -d' ' -f2)"
    [ ! "$LDAP_SN" ] && LDAP_SN="$USER_NAME"

    local LASTCHANGE_FLAG="$(grep "${USER_ID}:" /etc/shadow | cut -d':' -f3)"
    [ ! "$LASTCHANGE_FLAG" ] && LASTCHANGE_FLAG="0"

    local SHADOW_FLAG="$(grep "${USER_ID}:" /etc/shadow | cut -d':' -f9)"
    [ ! "$SHADOW_FLAG" ] && SHADOW_FLAG="0"

    local GROUP_ID="$(echo "$TARGET_USER" | cut -d':' -f4)"

    echo "dn: uid=$USER_ID,ou=People,$SUFFIX" >> "$LDAP_LDIF_FILE"
    echo "objectClass: inetOrgPerson" >> "$LDAP_LDIF_FILE"
    echo "objectClass: posixAccount" >> "$LDAP_LDIF_FILE"
    echo "objectClass: shadowAccount" >> "$LDAP_LDIF_FILE"
    echo "sn: $LDAP_SN" >> "$LDAP_LDIF_FILE"
    echo "givenName: $(echo "$USER_NAME" | awk '{print $1}')" >> "$LDAP_LDIF_FILE"
    echo "cn: $USER_NAME" >> "$LDAP_LDIF_FILE"
    echo "displayName: $USER_NAME" >> "$LDAP_LDIF_FILE"
    echo "uidNumber: $(echo "$TARGET_USER" | cut -d':' -f3)" >> "$LDAP_LDIF_FILE"
    echo "gidNumber: $(echo "$TARGET_USER" | cut -d':' -f4)" >> "$LDAP_LDIF_FILE"
    echo "userPassword: {crypt}$(grep "${USER_ID}:" /etc/shadow | cut -d':' -f2)" >> "$LDAP_LDIF_FILE"
    echo "gecos: $USER_NAME" >> "$LDAP_LDIF_FILE"
    echo "loginShell: $(echo "$TARGET_USER" | cut -d':' -f7)" >> "$LDAP_LDIF_FILE"
    echo "homeDirectory: $(echo "$TARGET_USER" | cut -d':' -f6)" >> "$LDAP_LDIF_FILE"
    echo "shadowExpire: $(passwd -S "$USER_ID" | awk '{print $7}')" >> "$LDAP_LDIF_FILE"
    echo "shadowFlag: $SHADOW_FLAG" >> "$LDAP_LDIF_FILE"
    echo "shadowWarning: $(passwd -S "$USER_ID" | awk '{print $6}')" >> "$LDAP_LDIF_FILE"
    echo "shadowMin: $(passwd -S "$USER_ID" | awk '{print $4}')" >> "$LDAP_LDIF_FILE"
    echo "shadowMax: $(passwd -S "$USER_ID" | awk '{print $5}')" >> "$LDAP_LDIF_FILE"
    echo "shadowLastChange: $LASTCHANGE_FLAG" >> "$LDAP_LDIF_FILE"
    
    echo "" >> "$LDAP_LDIF_FILE"
    echo "" >> "$LDAP_LDIF_FILE"
    
    echo "dn: cn=$USER_ID,ou=Group,$SUFFIX" >> "$LDAP_LDIF_FILE"
    echo "objectClass: posixGroup" >> "$LDAP_LDIF_FILE"
    echo "objectClass: top" >> "$LDAP_LDIF_FILE"
    echo "cn: $USER_ID" >> "$LDAP_LDIF_FILE"
    echo "userPassword: {crypt}$(grep "${USER_ID}:" /etc/shadow | cut -d':' -f2)" >> "$LDAP_LDIF_FILE"
    echo "gidNumber: $GROUP_ID" >> "$LDAP_LDIF_FILE"
  fi
}

CreateLDAPUser(){
    local username="$1"
    ldapadd -x -w "$LDAP_PASSWD" -D "cn=Manager,dc=$DC_NAME,dc=$DC_DOMAIN" -f "$LDAP_LDIF_FILE" 
    local exit_code="$?"

    case $exit_code in
        0)
            success "User '$username' successfully created in LDAP."
            ;;
        *)
            error "Error: Failed to create user '$username' in LDAP." false
            DeleteLocalUser "$username"                  # Delete the user from the local system
            ClearTempFiles                               # Remove the temporary files
            ;;
    esac

    ldappasswd -s "$username" -w "$LDAP_PASSWD" -D "cn=Manager,dc=$DC_NAME,dc=$DC_DOMAIN" -x "uid=$username,ou=People,dc=$DC_NAME,dc=$DC_DOMAIN"
    success "Password for user '$username' successfully set in LDAP."

    ClearTempFiles                                       # Remove the temporary files
}


# ==================== Main Script ====================
check_sudo
read -p "What is the username: " username                # Prompt the user for a username

ClearTempFiles
CreateLocalUser "$username"                              # Call the function to create a local user
GenerateUserLDIF "$username"                             # Call the function to generate the LDIF file for the user
CreateLDAPUser "$username"                               # Call the function to create the user in LDAP
ClearTempFiles