#!/bin/bash
print_green() {
  printf "\n"
  echo -e "\e[32m$1\e[0m"
}
print_red() {
  echo -e "\e[31m$1\e[0m"
}

yes_no_prompt() {
  local prompt_message=$1
  local user_input

  while true; do
    read -p "$prompt_message (y/n): " user_input
    case $user_input in
      [Yy]* )
        return 0
        ;;
      [Nn]* )
        return 1
        ;;
      * )
        echo "Please answer yes or no (y/n)."
        ;;
    esac
  done
}


# Function to check if a package is installed
is_package_installed() {
    local package_name="$1"

    # Check for Debian-based systems
    if command -v dpkg &> /dev/null; then
        dpkg -l "$package_name" &> /dev/null
        if [ $? -eq 0 ]; then
            return 0
        fi
    fi

    # Check for Red Hat-based systems
    if command -v rpm &> /dev/null; then
        rpm -q "$package_name" &> /dev/null
        if [ $? -eq 0 ]; then
            return 0
        fi
    fi

    return 1
}

is_folder_empty() {
  local dir=$1

  if [ -z "$(ls -A "$dir")" ]; then
    return 0  # true (folder is empty)
  else
    return 1  # false (folder is not empty)
  fi
}

is_folder_exists() {
  local dir=$1

  if [ -d "$dir" ]; then
    return 0  # true (folder exists)
  else
    return 1  # false (folder does not exist)
  fi
}

is_file_exists() {
	local file=$1

	if [ -f "$file" ]; then
      return 0  # true (file exists)
  else
      return 1  # false (file does not exist)
  fi
}

is_process_running() {
    pgrep -x "$1" &> /dev/null
    return $?
}

is_unique() {
	local string=$1
	local word_count

	word_count=$(echo "$string" | wc -w)
	if [ "$word_count" -eq 1 ]; then
		return 0
	else
		return 1
	fi
}


# Function to search for a string and get unique files containing the string
search_webserver_conf_files() {
    local webserver="$1"
    local search_string="$2"
    local $directory
    local grep_result

		if [ "$webserver" = "caddy" ]; then
			$directory="/etc/caddy"
			if ! is_folder_exists "$directory"; then
				print_red "Searching ${search_string} in '${directory}' but folder does not exist!"
			fi
			grep_result=$(grep -r "$search_string" --include="*.caddy" --include="Caddyfile" "$directory" | cut -d: -f1 | sort)
			if is_unique "$grep_result"; then
				webserver_conf_file=$grep_result
				return 0
			else
				print_red "Multiple caddy conf files found: ${grep_result}"
				exit 1
			fi
		fi

		# TODO Nginx check this
		if [ "$webserver" = "nginx" ]; then
			$directory="/etc/nginx/sites-enabled"
			if ! is_folder_exists "$directory"; then
				print_red "Searching ${search_string} in '${directory}' but folder does not exist!"
			fi
			grep_result=$(grep -r "$search_string" --include="*.conf" "$directory" | cut -d: -f1 | sort)
			if is_unique "$grep_result"; then
				webserver_conf_file=$grep_result
				return 0
			else
				print_red "Multiple nginx conf files found: ${grep_result}"
				exit 1
			fi
		fi
}


# -------------------------------------------------------------
# -------------------------------------------------------------
# -------------------------------------------------------------

print_green "Testing requirements..."

# Get first positional argument $1
if [ $# -ne 1 ]; then
    echo "Usage: $0 path/to/the/wordpress/site"
    exit 1
fi

src_folder=$1

# check path exists
# -----------------

if ! is_folder_exists "${src_folder}"; then
	print_red "Folder ${src_folder} does not exists"
	exit 1
fi

# check path is not empty
# -----------------------

if is_folder_empty "${src_folder}"; then
	print_red "Folder ${src_folder} is empty"
	exit 1
fi

# check wp-config exists
# ----------------------

if ! is_file_exists "${src_folder}"/wp-config.php; then
		print_red "File wp-config.php not found in ${src_folder}"
  	exit 1
fi

# Get webserver caddy or Nginx
# ----------------------------

# Check webserver
# ---------------
webserver=""

if which nginx > /dev/null 2>&1; then
  if is_process_running nginx; then
  	webserver="nginx"
	fi
fi

if which caddy > /dev/null 2>&1; then
	  if is_process_running caddy; then
    	webserver="caddy"
  	fi
fi

if [[ "$webserver" != "nginx" && "$webserver" != "caddy" ]]; then
  print_red "Error: nginx or caddy is not installed"
  exit 1
fi

print_green "WEBSERVER is ${webserver}"

# Get database name, site name, config files (php, webserver)
# ----------------------------

# get database name from wp-config.php
db_name=$(grep DB_NAME "${src_folder}"/wp-config.php | tr "'" ':' | tr '"' ':' | cut -d: -f4)
echo "Database name is ${db_name}"

# get webserver config file
webserver_conf_file=""
sitepath="${src_folder%/}"
sitename=$(echo "$sitepath" | awk -F'/' '{ print $(NF-1) }')
if search_webserver_conf_files "$webserver" "$sitename" ""

# Check root
#------------
if [[ $EUID -ne 0 ]]; then
  print_red "This script must be run as root."
  exit 1
fi

# Check PHP, MYSQL, PIGZ
packages=("php" "mysql" "pigz")

for package in "${packages[@]}"; do
    if ! is_package_installed "$package"; then
        echo "The package '$package' is not installed."
        exit 1
    fi
done

# Check services
# --------------

# Check if Mariadb commands for restoring the database are available
# ------------------------------------------------------------------
print_green "Check mysql command"
 if ! [ -x "$(command -v mysql)" ]; then
    print_red "ERROR: MySQL/MariaDB not installed (command mysql not found)."
    print_red "ERROR: No restore of database possible!"
    print_red "Cancel restore"
    exit 1
fi
print_green "mysql command OK"

print_green "Backup a wordpress site with database in "


