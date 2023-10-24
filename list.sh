HOME_DIR="/nclnfs/users"

# ANSI color codes
GREEN='\033[0;32m' # Green
RED='\033[0;31m'   # Red
NC='\033[0m'       # No Color


error(){
    echo -e "${RED}$1${NC}"
    [ "$2" = false ] && return
    exit 1
}

ListUsers(){
    local serial=0

    echo "List of users:"
    while IFS=: read -r username _ _ _ _ home _; do
        if [[ "$home" == "${HOME_DIR}"* ]]; then
            ((serial++))
            echo "${serial}) $username"
        fi
    done < /etc/passwd

    # If no users found, show error message and exit
    if [[ "$serial" -eq 0 ]]; then
        error "Error: No users found."
    fi
}

ConfirmUser(){
    read -p "Select a username to delete: " username
    # if username not in list and user's home directory is not in /nclnfs/users, then show error message and exit
    if ! grep -q "^${username}:" /etc/passwd || ! [[ "$(grep "^${username}:" /etc/passwd | cut -d: -f6)" == "${HOME_DIR}"* ]]; then
        error "Error: Invalid username '$username'."
    fi

    read -p "Enter the username again to confirm: " username2
    if [[ "$username" != "$username2" ]]; then
        error "Error: Username mismatch."
    fi

    read -p "Are you sure you want to delete user '$username'? (yes/no): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        error "User deletion canceled."
    fi

    echo "$username"
}

ListUsers
selectedUser=$(ConfirmUser)

echo "$selectedUser"