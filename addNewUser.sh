#!/bin/bash

# Variables
# nfs folder
nfs_folder="nclnfs/users"
dc_name="ncl"
dc_domain="in"

# Function to check if the script is run as sudo
check_sudo() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (sudo)." >&2
    exit 1
  fi
}

generate_user_ldif() {
  local username="$1"
  local user_ldif_file="$2"
  local SUFFIX="dc=$dc_name,dc=$dc_domain"

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

    echo "dn: uid=$USER_ID,ou=People,$SUFFIX" >> "$user_ldif_file"
    echo "objectClass: inetOrgPerson" >> "$user_ldif_file"
    echo "objectClass: posixAccount" >> "$user_ldif_file"
    echo "objectClass: shadowAccount" >> "$user_ldif_file"
    echo "sn: $LDAP_SN" >> "$user_ldif_file"
    echo "givenName: $(echo "$USER_NAME" | awk '{print $1}')" >> "$user_ldif_file"
    echo "cn: $USER_NAME" >> "$user_ldif_file"
    echo "displayName: $USER_NAME" >> "$user_ldif_file"
    echo "uidNumber: $(echo "$TARGET_USER" | cut -d':' -f3)" >> "$user_ldif_file"
    echo "gidNumber: $(echo "$TARGET_USER" | cut -d':' -f4)" >> "$user_ldif_file"
    echo "userPassword: {crypt}$(grep "${USER_ID}:" /etc/shadow | cut -d':' -f2)" >> "$user_ldif_file"
    echo "gecos: $USER_NAME" >> "$user_ldif_file"
    echo "loginShell: $(echo "$TARGET_USER" | cut -d':' -f7)" >> "$user_ldif_file"
    echo "homeDirectory: $(echo "$TARGET_USER" | cut -d':' -f6)" >> "$user_ldif_file"
    echo "shadowExpire: $(passwd -S "$USER_ID" | awk '{print $7}')" >> "$user_ldif_file"
    echo "shadowFlag: $SHADOW_FLAG" >> "$user_ldif_file"
    echo "shadowWarning: $(passwd -S "$USER_ID" | awk '{print $6}')" >> "$user_ldif_file"
    echo "shadowMin: $(passwd -S "$USER_ID" | awk '{print $4}')" >> "$user_ldif_file"
    echo "shadowMax: $(passwd -S "$USER_ID" | awk '{print $5}')" >> "$user_ldif_file"
    echo "shadowLastChange: $LASTCHANGE_FLAG" >> "$user_ldif_file"
    
    echo "" >> "$user_ldif_file"
    echo "" >> "$user_ldif_file"
    
    echo "dn: cn=$USER_ID,ou=Group,$SUFFIX" >> "$user_ldif_file"
    echo "objectClass: posixGroup" >> "$user_ldif_file"
    echo "objectClass: top" >> "$user_ldif_file"
    echo "cn: $USER_ID" >> "$user_ldif_file"
    echo "userPassword: {crypt}$(grep "${USER_ID}:" /etc/shadow | cut -d':' -f2)" >> "$user_ldif_file"
    echo "gidNumber: $GROUP_ID" >> "$user_ldif_file"

  fi
}

# Function to validate the username
validate_username() {
  local username="$1"

  # Check if the username contains invalid characters
  if [[ ! "$username" =~ ^[a-zA-Z0-9_.][a-zA-Z0-9_.-]*\$?$ ]]; then
    echo "Error: Invalid username format."
    echo "Usernames may contain only lower and upper case letters, digits, underscores, or dashes."
    echo "They can end with a dollar sign. Dashes are not allowed at the beginning of the username."
    echo "Fully numeric usernames and usernames '.' or '..' are also disallowed."
    echo "It is not recommended to use usernames beginning with a '.' character."
    return 1
  fi

  # Check if the username is numeric
  if [[ "$username" =~ ^[0-9]+$ ]]; then
    echo "Error: Usernames cannot consist of only numeric characters."
    return 1
  fi
}

# Main script
check_sudo

read -p "What is the username: " username

# Validate the username
while ! validate_username "$username"; do
  read -p "Please enter a valid username: " username
done

# Create the user
sudo adduser -m -d "/$nfs_folder/$username" "$username"
# sudo adduser -m "$username"
# sudo mkhomedir_helper "$username"

if [ $? -ne 0 ]; then
  echo "Error: Failed to create the user '$username'."
  exit 1
fi

# Set permissions
sudo chmod 777 "/$nfs_folder/$username"
if [ $? -ne 0 ]; then
 echo "Error: Failed to set permissions for '/$nfs_folder/$username'."
 exit 1
fi

read -s -p "Enter the password for the user '$username': " password

# Set the user's password
echo "$username:$password" | sudo chpasswd

# Prompt the user to change their password on first login
# printf "\n"
# sudo chage -d 0 "$username"
# echo "User '$username' will be prompted to change their password on first login."

# Additional Steps
user_passwd_file="/root/$username"
user_ldif_file="/root/$username.ldif"

# Error handling function
handle_error() {
  local error_message="$1"
  echo "Error: $error_message"
  exit 1
}

# Step 1: Extract user information to a file
# grep "$username" /etc/passwd > "$user_passwd_file" || handle_error "Failed to extract user information."

# Step 2: Generate LDIF file
generate_user_ldif "$username" "$user_ldif_file" || handle_error "Failed to generate LDIF file."
# /usr/share/migrationtools/migrate_passwd.pl "$user_passwd_file" "$user_ldif_file" || handle_error "Failed to generate LDIF file."

# Step 3: Add user to LDAP
ldapadd -x -w "$password" -D "cn=Manager,dc=$dc_name,dc=$dc_domain" -f "$user_ldif_file" || handle_error "Failed to add user to LDAP."
# ldappasswd -S -W -D "cn=Manager,dc=$dc_name,dc=$dc_domain" -x "uid=$username,ou=People,dc=$dc_name,dc=$dc_domain" || handle_error "Error in adding ldap passwd"

# Step 4: Clean up files
# rm -f "$user_passwd_file" "$user_ldif_file" || handle_error "Failed to remove temporary files."
rm -f "$user_ldif_file" || handle_error "Failed to remove temporary files."

echo "User '$username' successfully created and added to LDAP."

