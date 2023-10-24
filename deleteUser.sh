#!/bin/bash

dc_name="ncl"
dc_domain="in"

# Function to check if the script is run as sudo
check_sudo() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (sudo)." >&2
    exit 1
  fi
}

# Function to display the list of users
list_users() {
 echo "List of Users Who Can Log In:"
  while IFS=: read -r username password uid gid info home shell; do
    if [[ -n "$shell" && "$shell" != "/sbin/nologin" && "$shell" != "/usr/sbin/nologin" && "$shell" != "/bin/false" ]]; then
      echo "$username"
    fi
  done < /etc/passwd
}

# Function to delete a user
delete_user() {
  local username="$1"
  read -p "Are you sure you want to delete user '$username'? (yes/no): " confirmation
  if [[ "$confirmation" == "yes" ]]; then
    sudo userdel -r "$username"
    if [ $? -eq 0 ]; then
      echo "$username successfully deleted."
    else
      echo "Error: Failed to delete user '$username'."
    fi
  else
    echo "User deletion canceled."
  fi
}


# Function to remove a user from LDAP
remove_user_from_ldap() {
  local username="$1"
  
  # Customize the LDAP command to remove the user (replace with your LDAP configuration)
  ldapdelete -v -c -D "cn=Manager,dc=$dc_name,dc=$dc_domain" -W "uid=$username,ou=People,dc=$dc_name,dc=$dc_domain"
  ldapdelete -v -c -D "cn=Manager,dc=$dc_name,dc=$dc_domain" -W "cn=$username,ou=Group,dc=$dc_name,dc=$dc_domain"
  
  if [ $? -ne 0 ]; then
    echo "Error: Failed to remove user '$username' from LDAP."
    return 1
  fi
  
  echo "User '$username' successfully removed from LDAP."
}

# Main script
check_sudo
list_users

read -p "Select a user to delete: " user_to_delete

# Ensure the selected user exists
if id "$user_to_delete" &>/dev/null; then
  read -p "Confirm deletion of user '$user_to_delete' (type the username again): " confirm_username
  if [[ "$user_to_delete" == "$confirm_username" ]]; then
    echo "Warning: Deleting user '$user_to_delete' will remove all user data."
    # Remove the user from LDAP
    remove_user_from_ldap "$user_to_delete"
   
    delete_user "$user_to_delete"
  else
    echo "Error: Usernames do not match. Deletion canceled."
  fi
else
  echo "Error: User '$user_to_delete' does not exist."
fi
