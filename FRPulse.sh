#!/bin/bash

# Define colors for better terminal output
HEADER_COLOR='\033[1;38;5;208m'      # Deep Orange for headers/titles
SUCCESS_COLOR='\033[1;38;5;46m'     # Bright Green for success messages
ERROR_COLOR='\033[1;38;5;196m'      # Bright Red for error messages
PROMPT_COLOR='\033[1;38;5;220m'     # Gold for prompts/user input
INFO_COLOR='\033[1;38;5;39m'        # Deep Sky Blue for informational messages
MENU_OPTION_COLOR='\033[1;38;5;141m' # Medium Purple for main menu options
SUB_MENU_OPTION_COLOR='\033[1;38;5;75m' # Light Blue Green for sub-menu options
DEFAULT_TEXT_COLOR='\033[0;38;5;250m' # Light Gray for general text
BOLD_HIGHLIGHT='\033[1;38;5;201m'   # Deep Pink for bold highlights
RESET='\033[0m'                     # No Color

# --- Global Paths and Markers ---
# Use readlink -f to get the canonical path of the script, resolving symlinks and /dev/fd/ issues
TRUST_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$TRUST_SCRIPT_PATH")"
SETUP_MARKER_FILE="/var/lib/frpulse/.setup_complete"

# --- Script Version ---
SCRIPT_VERSION="1.0.0" # Define the script version for FRPulse

# --- Helper Functions ---

# Function to draw a colored line for menu separation
draw_line() {
  local color="$1"
  local char="$2"
  local length=${3:-40} # Default length 40 if not provided
  printf "${color}"
  for ((i=0; i<length; i++)); do
    printf "$char"
  done
  printf "${RESET}\n"
}

# Function to print success messages in green
print_success() {
  local message="$1"
  echo -e "${SUCCESS_COLOR}✅ $message${RESET}" # Green color for success messages
}

# Function to print error messages in red
print_error() {
  local message="$1"
  echo -e "${ERROR_COLOR}❌ $message${RESET}" # Red color for error messages
}

# Function to show service logs and return to a "menu"
show_service_logs() {
  local service_name="$1"
  clear # Clear the screen before showing logs
  echo -e "${INFO_COLOR}--- Displaying Logs for Service $service_name ---${RESET}" # Blue color for header

  # Display the last 50 lines of logs for the specified service
  # --no-pager ensures the output is direct to the terminal without opening 'less'
  sudo journalctl -u "$service_name" -n 50 --no-pager

  echo ""
  echo -e "${PROMPT_COLOR}Press any key to return to the previous menu...${RESET}" # Yellow color for prompt
  read -n 1 -s -r # Read a single character, silent, raw input

  clear
}

# Function to draw a green line (used for main menu border)
draw_green_line() {
  echo -e "${SUCCESS_COLOR}+--------------------------------------------------------+${RESET}"
}

# --- Validation Functions ---

# Function to validate an email address
validate_email() {
  local email="$1"
  if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$ ]]; then
    return 0 # Valid
  else
    return 1 # Invalid
  fi
}

# Function to validate a port number
validate_port() {
  local port="$1"
  if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
    return 0 # Valid
  else
    return 1 # Invalid
  fi
}

# Function to validate a domain or IP address
validate_host() {
  local host="$1"
  # Regex for IPv4 address
  local ipv4_regex="^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
  # Regex for IPv6 address (simplified, covers common formats including compressed ones)
  local ipv6_regex="^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){1,7}:(\b[0-9a-fA-F]{1,4}\b){1,7}$|^([0-9a-fA-F]{1,4}:){1,6}(:[0-9a-fA-F]{1,4}){1,2}$|^([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,3}$|^([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,4}$|^([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,5}$|^([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,6}$|^[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,7})|:)$|^::((:[0-9a-fA-F]{1,7})|[0-9a-fA-F]{1,4})$|^[0-9a-fA-F]{1,4}::([0-9a-fA-F]{1,4}:){0,5}[0-9a-fA-F]{1,4}$|^::([0-9a-fA-F]{1,4}:){0,6}[0-9a-fA-F]{1,4}$"
  # Regex for domain name
  local domain_regex="^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,6}$"

  if [[ "$host" =~ $ipv4_regex ]] || [[ "$host" =~ $ipv6_regex ]] || [[ "$host" =~ $domain_regex ]]; then
    return 0 # Valid
  else
    return 1 # Invalid
  fi
}

# Function to generate a random password
generate_random_password() {
  # Generate a random 16-character alphanumeric string
  head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16
}

# Update cron job logic to include FRPulse
reset_timer() {
  local service_to_restart="$1" # Optional: service name passed as argument

  clear
  echo ""
  draw_line "${INFO_COLOR}" "=" 40
  echo -e "${INFO_COLOR}     ⏰ Schedule Service Restart${RESET}"
  draw_line "${INFO_COLOR}" "=" 40
  echo ""

  if [[ -z "$service_to_restart" ]]; then
    echo -e "👉 ${DEFAULT_TEXT_COLOR}Which service do you want to restart (e.g., 'nginx', 'frpulse-server-myname', 'frpulse-client-myclient')? ${RESET}"
    read -p "" service_to_restart
    echo ""
  fi

  if [[ -z "$service_to_restart" ]]; then
    print_error "Service name cannot be empty. Scheduling cancelled."
    echo ""
    echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
    read -p ""
    return 1
  fi

  if [ ! -f "/etc/systemd/system/${service_to_restart}.service" ]; then
    print_error "Service '$service_to_restart' does not exist on this system. Cannot schedule restart."
    echo ""
    echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
    read -p ""
    return 1
  fi

  echo -e "${INFO_COLOR}Scheduling restart for service: ${DEFAULT_TEXT_COLOR}$service_to_restart${RESET}"
  echo ""
  echo "Please select a time interval for periodic service restart:"
  echo -e "  ${PROMPT_COLOR}1)${RESET} ${DEFAULT_TEXT_COLOR}Every 30 minutes${RESET}"
  echo -e "  ${PROMPT_COLOR}2)${RESET} ${DEFAULT_TEXT_COLOR}Every 1 hour${RESET}"
  echo -e "  ${PROMPT_COLOR}3)${RESET} ${DEFAULT_TEXT_COLOR}Every 2 hours${RESET}"
  echo -e "  ${PROMPT_COLOR}4)${RESET} ${DEFAULT_TEXT_COLOR}Every 4 hours${RESET}"
  echo -e "  ${PROMPT_COLOR}5)${RESET} ${DEFAULT_TEXT_COLOR}Every 6 hours${RESET}"
  echo -e "  ${PROMPT_COLOR}6)${RESET} ${DEFAULT_TEXT_COLOR}Every 12 hours${RESET}"
  echo -e "  ${PROMPT_COLOR}7)${RESET} ${DEFAULT_TEXT_COLOR}Every 24 hours${RESET}"
  echo ""
  read -p "👉 Enter your choice (1-7): " choice
  echo ""

  local cron_minute=""
  local cron_hour=""
  local cron_day_of_month="*"
  local cron_month="*"
  local cron_day_of_week="*"
  local description=""
  local cron_tag="FRPulse"

  case "$choice" in
    1)
      cron_minute="*/30"
      cron_hour="*"
      description="every 30 minutes"
      ;;
    2)
      cron_minute="0"
      cron_hour="*/1"
      description="every 1 hour"
      ;;
    3)
      cron_minute="0"
      cron_hour="*/2"
      description="every 2 hours"
      ;;
    4)
      cron_minute="0"
      cron_hour="*/4"
      description="every 4 hours"
      ;;
    5)
      cron_minute="0"
      cron_hour="*/6"
      description="every 6 hours"
      ;;
    6)
      cron_minute="0"
      cron_hour="*/12"
      description="every 12 hours"
      ;;
    7)
      cron_minute="0"
      cron_hour="0"
      description="every 24 hours (daily at midnight)"
      ;;
    *)
      echo -e "${ERROR_COLOR}❌ Invalid choice. No cron job will be scheduled.${RESET}"
      echo ""
      echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
      return 1
      ;;
  esac

  echo -e "${INFO_COLOR}Scheduling restart for '$service_to_restart' $description...${RESET}"
  echo ""
  
  local cron_command="/usr/bin/systemctl restart $service_to_restart >> /var/log/${cron_tag}_cron.log 2>&1"
  local cron_job_entry="$cron_minute $cron_hour $cron_day_of_month $cron_month $cron_day_of_week $cron_command # ${cron_tag} automated restart for $service_to_restart"

  local temp_cron_file=$(mktemp)
  if ! sudo crontab -l &> /dev/null; then
      echo "" | sudo crontab -
  fi
  sudo crontab -l > "$temp_cron_file"

  # Remove existing cron jobs for FRPulse for this service
  sed -i "/# FRPulse automated restart for $service_to_restart$/d" "$temp_cron_file"

  echo "$cron_job_entry" >> "$temp_cron_file"

  if sudo crontab "$temp_cron_file"; then
    print_success "Successfully scheduled restart for '$service_to_restart' $description."
    echo -e "${INFO_COLOR}   Cron job entry is:${RESET}"
    echo -e "${DEFAULT_TEXT_COLOR}   $cron_job_entry${RESET}"
    echo -e "${INFO_COLOR}   Logs will be written to: ${DEFAULT_TEXT_COLOR}/var/log/${cron_tag}_cron.log${RESET}"
  else
    print_error "❌ Cron job scheduling failed. Check permissions or cron service status.${RESET}"
  fi

  rm -f "$temp_cron_file"

  echo ""
  echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
  read -p ""
}

delete_cron_job_action() {
  clear
  echo ""
  draw_line "${ERROR_COLOR}" "=" 40
  echo -e "${ERROR_COLOR}     🗑️ Delete Scheduled Restart (Cron)${RESET}"
  draw_line "${ERROR_COLOR}" "=" 40
  echo ""

  echo -e "${INFO_COLOR}🔍 Searching for FRPulse services with scheduled restarts...${RESET}"

  mapfile -t services_with_cron < <(sudo crontab -l 2>/dev/null | grep -E "# FRPulse automated restart for" | awk '{print $NF}' | sort -u)

  local service_names=()
  for service_comment in "${services_with_cron[@]}"; do
    local extracted_name=$(echo "$service_comment" | sed -E 's/# FRPulse automated restart for //')
    service_names+=("$extracted_name")
  done

  if [ ${#service_names[@]} -eq 0 ]; then
    print_error "❌ No FRPulse services with scheduled cron jobs found."
    echo ""
    echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
    read -p ""
    return 1
  fi

  echo -e "${INFO_COLOR}📋 Please select a service to delete its scheduled restart:${RESET}"
  service_names+=("Back to previous menu")
  select selected_service_name in "${service_names[@]}"; do
    if [[ "$selected_service_name" == "Back to previous menu" ]]; then
      echo -e "${PROMPT_COLOR}Returning to previous menu...${RESET}"
      echo ""
      return 0
    elif [ -n "$selected_service_name" ]; then
      break
    else
      print_error "Invalid choice. Please enter a valid number."
    fi
  done
  echo ""

  if [[ -z "$selected_service_name" ]]; then
    print_error "No service selected. Operation cancelled."
    echo ""
    echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
    read -p ""
    return 1
  fi

  echo -e "${INFO_COLOR}Attempting to delete cron job for '$selected_service_name'...${RESET}"

  local temp_cron_file=$(mktemp)
  if ! sudo crontab -l &> /dev/null; then
      print_error "Crontab is empty or inaccessible. Nothing to delete."
      rm -f "$temp_cron_file"
      echo ""
      echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
      read -p ""
      return 1
  fi
  sudo crontab -l > "$temp_cron_file"

  # Remove existing cron jobs for FRPulse for this service
  sed -i "/# FRPulse automated restart for $selected_service_name$/d" "$temp_cron_file"

  echo "$cron_job_entry" >> "$temp_cron_file"

  if sudo crontab "$temp_cron_file"; then
    print_success "Successfully deleted scheduled restart for '$selected_service_name'."
    echo -e "${DEFAULT_TEXT_COLOR}You can verify with: ${PROMPT_COLOR}sudo crontab -l${RESET}"
  else
    print_error "❌ Deleting cron job failed. It might not exist or there's a permission issue.${RESET}"
  fi

  rm -f "$temp_cron_file"

  echo ""
  echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
  read -p ""
}

# Renamed to reflect FRPulse management
uninstall_frpulse_action() {
  clear
  echo ""
  echo -e "${ERROR_COLOR}⚠️ Are you sure you want to uninstall FRPulse and all associated files and services? (y/N): ${RESET}"
  read -p "" confirm
  echo ""

  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "🧹 Uninstalling FRPulse and cleaning up..."

    # Stop and disable all frpulse-server-* and frpulse-client-* services
    echo "Searching for FRPulse services to remove..."
    mapfile -t frpulse_services < <(sudo systemctl list-unit-files --full --no-pager | grep '^frpulse-.*\.service' | awk '{print $1}')

    if [ ${#frpulse_services[@]} -gt 0 ]; then
      echo "🛑 Stopping and disabling FRPulse services..."
      for service_file in "${frpulse_services[@]}"; do
        local service_name=$(basename "$service_file")
        echo "  - Processing $service_name..."
        sudo systemctl stop "$service_name" > /dev/null 2>&1
        sudo systemctl disable "$service_name" > /dev/null 2>&1
        sudo rm -f "/etc/systemd/system/$service_name" > /dev/null 2>&1
      done
      print_success "All FRPulse services stopped, disabled, and removed."
    else
      echo "⚠️ No FRPulse services found to remove."
    fi

    sudo systemctl daemon-reload # Reload daemon after removing services

    # Remove frpulse config folder
    if [ -d "$(pwd)/frpulse" ]; then
      echo "🗑️ Deleting 'frpulse' configuration folder..."
      rm -rf "$(pwd)/frpulse"
      print_success "'frpulse' configuration folder successfully deleted."
    else
      echo "⚠️ 'frpulse' configuration folder not found."
    fi

    # Remove frps and frpc binaries
    if [ -f "/usr/local/bin/frps" ]; then
      echo "🗑️ Deleting frps binary..."
      sudo rm -f "/usr/local/bin/frps"
      print_success "frps binary deleted."
    fi
    if [ -f "/usr/local/bin/frpc" ]; then
      echo "🗑️ Deleting frpc binary..."
      sudo rm -f "/usr/local/bin/frpc"
      print_success "frpc binary deleted."
    fi

    # Remove FRPulse related cron jobs
    echo -e "${INFO_COLOR}🧹 Deleting any FRPulse related cron jobs...${RESET}"
    (sudo crontab -l 2>/dev/null | grep -v "# FRPulse automated restart for") | sudo crontab -
    print_success "Related cron jobs deleted."

    # Remove setup marker file
    if [ -f "$SETUP_MARKER_FILE" ]; then
      echo "🗑️ Deleting setup marker file..."
      sudo rm -f "$SETUP_MARKER_FILE"
      print_success "Setup marker file deleted."
    fi

    print_success "FRPulse uninstallation and cleanup complete."
  else
    echo -e "${PROMPT_COLOR}❌ Uninstallation cancelled.${RESET}"
  fi
  echo ""
  echo -e "${PROMPT_COLOR}Press Enter to return to the main menu...${RESET}"
  read -p ""
}

# Update install_frpulse_action to install FRP
install_frpulse_action() {
  clear
  echo ""
  draw_line "${INFO_COLOR}" "=" 40
  echo -e "${INFO_COLOR}     📥 Installing FRPulse (FRP)${RESET}"
  draw_line "${INFO_COLOR}" "=" 40
  echo ""

  echo -e "${INFO_COLOR}Downloading and installing the latest FRP...${RESET}"

  # Find the latest frp release for linux_amd64
  local frp_latest_release_url=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep "browser_download_url" | grep "linux_amd64.tar.gz" | cut -d '"' -f 4)

  if [ -z "$frp_latest_release_url" ]; then
    print_error "❌ Error: Could not find the latest FRP download URL. Please check your internet connection."
    echo ""
    echo -e "${PROMPT_COLOR}Press Enter to return to the main menu...${RESET}"
    return 1
  fi

  local frp_archive_name=$(basename "$frp_latest_release_url")
  local frp_extract_dir=$(echo "$frp_archive_name" | sed 's/\.tar\.gz//')

  echo "Downloading: $frp_latest_release_url"
  if curl -L -o "/tmp/$frp_archive_name" "$frp_latest_release_url"; then
    print_success "FRP file successfully downloaded."
  else
    print_error "❌ Error: FRP download failed."
    rm -f "/tmp/$frp_archive_name"
    echo ""
    echo -e "${PROMPT_COLOR}Press Enter to return to the main menu...${RESET}"
    return 1
  fi

  echo "Extracting files..."
  if tar -xzf "/tmp/$frp_archive_name" -C "/tmp/"; then
    print_success "Files successfully extracted."
  else
    print_error "❌ Error: FRP file extraction failed."
    rm -f "/tmp/$frp_archive_name"
    echo ""
    echo -e "${PROMPT_COLOR}Press Enter to return to the main menu...${RESET}"
    return 1
  fi

  echo "Moving binaries to /usr/local/bin..."
  sudo mv "/tmp/$frp_extract_dir/frps" "/usr/local/bin/"
  sudo mv "/tmp/$frp_extract_dir/frpc" "/usr/local/bin/"
  sudo chmod +x "/usr/local/bin/frps" "/usr/local/bin/frpc"
  
  # --- Diagnostic: Verify file presence immediately after move ---
  echo "Verifying frps and frpc binaries in /usr/local/bin/..."
  if [ -f "/usr/local/bin/frps" ]; then
    print_success "frps found at /usr/local/bin/frps"
  else
    print_error "frps NOT found at /usr/local/bin/frps"
  fi
  if [ -f "/usr/local/bin/frpc" ]; then
    print_success "frpc found at /usr/local/bin/frpc"
  else
    print_error "frpc NOT found at /usr/local/bin/frpc"
  fi
  # --- End Diagnostic ---

  # Force shell to rehash its command lookup table (unlikely to be the issue for -f but harmless)
  hash -r

  print_success "FRP binaries successfully installed."

  echo "Cleaning up temporary files..."
  rm -rf "/tmp/$frp_archive_name" "/tmp/$frp_extract_dir"
  print_success "FRPulse installation complete!"
  echo ""
  echo -e "${PROMPT_COLOR}Press Enter to return to the main menu...${RESET}"
  read -p ""
}

# New function for adding an FRPulse server
add_new_frpulse_server_action() {
  clear
  echo ""
  draw_line "${INFO_COLOR}" "=" 40
  echo -e "${INFO_COLOR}     ➕ Add New FRPulse Server${RESET}"
  draw_line "${INFO_COLOR}" "=" 40
  echo ""

  # Check for frps executable
  if ! command -v frps &> /dev/null; then
    echo -e "${ERROR_COLOR}❗ frps binary not found.${RESET}"
    echo -e "${PROMPT_COLOR}Please run 'Install FRPulse' option from the main menu first.${RESET}"
    echo ""
    echo -e "${PROMPT_COLOR}Press Enter to return to the main menu...${RESET}"
    return
  fi

  local server_name
  while true; do
    echo -e "👉 ${INFO_COLOR}Enter server name (e.g., myserver, only alphanumeric, hyphens, underscores allowed):${RESET} "
    read -p "" server_name_input
    server_name=$(echo "$server_name_input" | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')
    if [[ -n "$server_name" ]]; then
      break
    else
      print_error "Server name cannot be empty!"
    fi
  done
  echo ""

  local service_name="frpulse-server-$server_name"
  local config_dir="$(pwd)/frpulse"
  local config_file_path="$config_dir/frps-$server_name.toml" # Changed to .toml
  local service_file="/etc/systemd/system/${service_name}.service"

  if [ -f "$service_file" ]; then
    echo -e "${ERROR_COLOR}❌ A service with this name already exists: $service_name.${RESET}"
    echo ""
    echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
    read -p ""
    return
  fi

  mkdir -p "$config_dir" # Ensure frpulse config directory exists

  echo -e "${INFO_COLOR}⚙️ Server Configuration:${RESET}"

  local listen_port
  while true; do
    echo -e "👉 ${DEFAULT_TEXT_COLOR}Enter listen port (1-65535, e.g., 7000):${RESET} "
    read -p "" listen_port_input
    listen_port=${listen_port_input:-7000}
    if validate_port "$listen_port"; then
      break
    else
      print_error "Invalid port number. Please enter a number between 1 and 65535."
    fi
  done
  echo ""

  local token
  while true; do
    echo -e "👉 ${DEFAULT_TEXT_COLOR}Enter authentication token (e.g., mysecrettoken123):${RESET} "
    read -p "" token
    if [[ -n "$token" ]]; then
      break
    else
      print_error "Token cannot be empty!"
    fi
  done
  echo ""

  local dashboard_port=""
  local dashboard_user="admin"
  local dashboard_pwd=$(generate_random_password) # Generate a random password for dashboard

  echo -e "👉 ${DEFAULT_TEXT_COLOR}Do you want to enable the management dashboard? (Y/n, default: n):${RESET} "
  read -p "" enable_dashboard_choice
  enable_dashboard_choice=${enable_dashboard_choice:-n}

  if [[ "$enable_dashboard_choice" =~ ^[Yy]$ ]]; then
    while true; do
      echo -e "👉 ${DEFAULT_TEXT_COLOR}Enter dashboard port (e.g., 7500):${RESET} "
      read -p "" dashboard_port_input
      if validate_port "$dashboard_port_input"; then
        dashboard_port="$dashboard_port_input"
        break
      else
        print_error "Invalid port number. Please enter a number between 1 and 65535."
      fi
    done
    print_success "Management dashboard enabled. Username: $dashboard_user, Password: $dashboard_pwd !!! Write it somewhere!!!"
  else
    echo -e "${PROMPT_COLOR}Management dashboard disabled.${RESET}"
  fi
  echo ""

  local use_tls_choice
  local tls_config_toml=""
  local tls_enabled="false" # Default to false
  local certs_dir="/etc/letsencrypt/live"
  local tls_cert_file=""
  local tls_key_file=""

  echo -e "👉 ${DEFAULT_TEXT_COLOR}Do you want to enable TLS (SSL) for this server? (Y/n, default: Y):${RESET} "
  read -p "" use_tls_choice
  use_tls_choice=${use_tls_choice:-Y}

  if [[ "$use_tls_choice" =~ ^[Yy]$ ]]; then
    tls_enabled="true"
    if [ ! -d "$certs_dir" ]; then
      print_error "❌ Certificate folder not found at $certs_dir."
      print_error "   Please ensure Certbot is installed and certificates have been obtained."
      echo -e "${PROMPT_COLOR}Press Enter to return to the main menu...${RESET}"
      read -p ""
      return
    fi

    mapfile -t cert_domains < <(sudo find "$certs_dir" -maxdepth 1 -mindepth 1 -type d ! -name "README" -exec basename {} \;)

    if [ ${#cert_domains[@]} -eq 0 ]; then
      print_error "❌ No SSL certificates found in $certs_dir." # Updated message
      print_error "   Please obtain a new certificate from the 'Certificate Management' menu first." # Updated message
      echo -e "${PROMPT_COLOR}Press Enter to return to the main menu...${RESET}"
      read -p ""
      return
    fi

    echo -e "${INFO_COLOR}Available SSL Certificates:${RESET}"
    for i in "${!cert_domains[@]}"; do
      echo -e "  ${PROMPT_COLOR}$((i+1)))${RESET} ${DEFAULT_TEXT_COLOR}${cert_domains[$i]}${RESET}"
    done

    local cert_choice
    while true; do
      echo -e "👉 ${DEFAULT_TEXT_COLOR}Select a certificate by number to use for the FRPulse server:${RESET} "
      read -p "" cert_choice
      if [[ "$cert_choice" =~ ^[0-9]+$ ]] && [ "$cert_choice" -ge 1 ] && [ "$cert_choice" -le ${#cert_domains[@]} ]; then
        break
      else
        print_error "Invalid choice. Please enter a valid number."
      fi
    done
    local selected_domain_name="${cert_domains[$((cert_choice-1))]}"
    tls_cert_file="$certs_dir/$selected_domain_name/fullchain.pem"
    tls_key_file="$certs_dir/$selected_domain_name/privkey.pem"

    if [ ! -f "$tls_cert_file" ] || [ ! -f "$tls_key_file" ]; then
      print_error "❌ Selected SSL certificate files not found: $tls_cert_file or $tls_key_file."
      print_error "   Server setup cancelled."
      echo ""
      echo -e "${PROMPT_COLOR}Press Enter to return to the main menu...${RESET}"
      read -p ""
      return
    fi
    print_success "Selected certificate for TLS: $selected_domain_name"
    tls_config_toml="cert_file = \"$tls_cert_file\"
key_file = \"$tls_key_file\""
  else
    echo -e "${PROMPT_COLOR}TLS disabled for this server.${RESET}"
  fi
  echo ""

  # Create the FRPulse server config file (TOML)
  echo -e "${INFO_COLOR}📝 Creating frps-$server_name.toml configuration file...${RESET}"
  cat <<EOF > "$config_file_path"
# frps-$server_name.toml
[common]
bind_port = $listen_port
token = "$token"
tls_enable = $tls_enabled
$tls_config_toml
log_file = "/var/log/frps-$server_name.log"
log_level = "info"
log_max_days = 3
EOF

  if [[ -n "$dashboard_port" ]]; then
    cat <<EOF >> "$config_file_path"

dashboard_port = $dashboard_port
dashboard_user = "$dashboard_user"
dashboard_pwd = "$dashboard_pwd"
EOF
  fi

  print_success "frps-$server_name.toml successfully created at $config_file_path."

  # Create the systemd service file
  echo -e "${INFO_COLOR}🔧 Creating systemd service file for FRPulse server '$server_name'...${RESET}"
  cat <<EOF | sudo tee "$service_file" > /dev/null
[Unit]
Description=FRPulse Server - $server_name
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c "$config_file_path"
Restart=always
RestartSec=5
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

  echo -e "${INFO_COLOR}🔧 Reloading systemd daemon...${RESET}"
  sudo systemctl daemon-reload

  echo -e "${INFO_COLOR}🚀 Enabling and starting FRPulse service '$service_name'...${RESET}"
  sudo systemctl enable "$service_name" > /dev/null 2>&1
  sudo systemctl start "$service_name" > /dev/null 2>&1

  print_success "FRPulse server '$server_name' started as $service_name."

  echo ""
  echo -e "${PROMPT_COLOR}Would you like to view the logs for $service_name now? (y/N): ${RESET}"
  read -p "" view_logs_choice
  echo ""

  if [[ "$view_logs_choice" =~ ^[Yy]$ ]]; then
    show_service_logs "$service_name"
  fi

  echo ""
  echo -e "${PROMPT_COLOR}Press Enter to return to the main menu...${RESET}"
  read -p ""
}

# Function to parse a TOML file and return common section and proxies
# Usage: parse_frpc_toml <config_file_path>
# Returns: common_section_content (global variable), proxy_array (global array)
parse_frpc_toml() {
    local config_file="$1"
    common_section_content=""
    proxy_array=()
    local in_common=false
    local in_proxy=false
    local current_proxy_block=""
    local proxy_index=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim leading/trailing whitespace from the line
        local trimmed_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [[ "$trimmed_line" =~ ^\[common\] ]]; then
            in_common=true
            in_proxy=false
            continue
        elif [[ "$trimmed_line" =~ ^\[\[proxies\]\] ]]; then
            if [ -n "$current_proxy_block" ]; then
                proxy_array[proxy_index]="$current_proxy_block"
                proxy_index=$((proxy_index+1))
            fi
            current_proxy_block="[[proxies]]" # Start new block clean
            in_common=false
            in_proxy=true
            continue
        elif [[ "$trimmed_line" =~ ^\[.*\] ]]; then # Another section starts
            if [ -n "$current_proxy_block" ]; then
                proxy_array[proxy_index]="$current_proxy_block"
                proxy_index=$((proxy_index+1))
            fi
            current_proxy_block=""
            in_common=false
            in_proxy=false
        fi

        if "$in_common"; then
            if [ -n "$trimmed_line" ] && ! [[ "$trimmed_line" =~ ^\[common\] ]]; then # Avoid adding empty lines or the [common] header itself
                common_section_content+="$trimmed_line"$'\n'
            fi
        elif "$in_proxy"; then
            if [ -n "$trimmed_line" ] && ! [[ "$trimmed_line" =~ ^\[\[proxies\]\] ]]; then # Avoid adding empty lines or the [[proxies]] header itself
                current_proxy_block+=$'\n'"$trimmed_line"
            fi
        fi
    done < "$config_file"

    # Add the last proxy block if it exists
    if [ -n "$current_proxy_block" ]; then
        proxy_array[proxy_index]="$current_proxy_block"
    fi
}


# Function to reconstruct and save the TOML file
# Usage: reconstruct_frpc_toml <config_file_path> <common_section_content> <proxy_array>
reconstruct_frpc_toml() {
    local config_file="$1"
    local common_content="$2"
    local -n proxies_ref=$3 # Use nameref for array

    echo "$common_content" > "$config_file"
    for proxy_block in "${proxies_ref[@]}"; do
        echo -e "\n$proxy_block" >> "$config_file"
    done
}


# New function for adding an FRPulse client
add_new_frpulse_client_action() {
  clear
  echo ""
  draw_line "${INFO_COLOR}" "=" 40
  echo -e "${INFO_COLOR}     ➕ Add New FRPulse Client${RESET}"
  draw_line "${INFO_COLOR}" "=" 40
  echo ""

  # Check for frpc executable
  if ! command -v frpc &> /dev/null; then
    echo -e "${ERROR_COLOR}❗ frpc binary not found.${RESET}"
    echo -e "${PROMPT_COLOR}Please run 'Install FRPulse' option from the main menu first.${RESET}"
    echo ""
    echo -e "${PROMPT_COLOR}Press Enter to return to the main menu...${RESET}"
    return
  fi

  local client_name
  while true; do
    echo -e "👉 ${INFO_COLOR}Enter client name (e.g., myclient, only alphanumeric, hyphens, underscores allowed):${RESET} "
    read -p "" client_name_input
    client_name=$(echo "$client_name_input" | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')
    if [[ -n "$client_name" ]]; then
      break
    else
      print_error "Client name cannot be empty!"
    fi
  done
  echo ""

  local service_name="frpulse-client-$client_name"
  local config_dir="$(pwd)/frpulse"
  local config_file_path="$config_dir/frpc-$client_name.toml" # Changed to .toml
  local service_file="/etc/systemd/system/${service_name}.service"

  if [ -f "$service_file" ]; then
    echo -e "${ERROR_COLOR}❌ A service with this name already exists: $service_name.${RESET}"
    echo ""
    echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
    read -p ""
    return
  fi

  mkdir -p "$config_dir" # Ensure frpulse config directory exists

  echo -e "${INFO_COLOR}⚙️ Client Configuration:${RESET}"

  local server_address
  while true; do
    echo -e "👉 ${DEFAULT_TEXT_COLOR}Enter server address (IPv4/IPv6 or domain, e.g., example.com, 192.168.1.1):${RESET} "
    read -p "" server_address
    if validate_host "$server_address"; then
      break
    else
      print_error "Invalid server address format. Please try again."
    fi
  done
  echo ""

  local server_port
  while true; do
    echo -e "👉 ${DEFAULT_TEXT_COLOR}Enter server port (1-65535, e.g., 7000):${RESET} "
    read -p "" server_port_input
    server_port=${server_port_input:-7000}
    if validate_port "$server_port"; then
      break
    else
      print_error "Invalid port number. Please enter a number between 1 and 65535."
    fi
  done
  echo ""

  local token
  while true; do
    echo -e "👉 ${DEFAULT_TEXT_COLOR}Enter authentication token for the FRPulse server:${RESET} "
    read -p "" token
    if [[ -n "$token" ]]; then
      break
    else
      print_error "Token cannot be empty!"
    fi
  done
  echo ""

  local use_tls_client_choice
  local client_tls_enabled="true" # Default to true for client, assuming server uses TLS
  echo -e "👉 ${DEFAULT_TEXT_COLOR}Does the FRPulse server use TLS (SSL)? (Y/n, default: Y):${RESET} "
  read -p "" use_tls_client_choice
  use_tls_client_choice=${use_tls_client_choice:-Y}

  if [[ "$use_tls_client_choice" =~ ^[Nn]$ ]]; then
    client_tls_enabled="false"
    echo -e "${PROMPT_COLOR}Client TLS disabled.${RESET}"
  else
    echo -e "${SUCCESS_COLOR}Client TLS enabled (connecting to TLS-enabled server).${RESET}"
  fi
  echo ""

  local proxy_configs_toml=""
  local proxy_counter=1

  echo -e "${INFO_COLOR}Port Forwarding Settings:${RESET}"
  echo -e "You can forward multiple ports."
  echo -e "For each port, you will specify the local port, remote port, and protocol."
  echo -e "Type 'done' to finish."
  echo ""

  while true; do
    echo -e "--- Proxy Settings #${proxy_counter} ---"
    local local_port
    while true; do
      echo -e "👉 ${DEFAULT_TEXT_COLOR}Enter local port (e.g., 8080):${RESET} "
      read -p "" local_port_input
      if [[ "$local_port_input" == "done" ]]; then
        break 2 # Exit both loops
      fi
      if validate_port "$local_port_input"; then
        local_port="$local_port_input"
        break
      else
        print_error "Invalid port number. Please enter a number between 1 and 65535."
      fi
    done

    local remote_port
    while true; do
      echo -e "👉 ${DEFAULT_TEXT_COLOR}Enter remote port (e.g., 80):${RESET} "
      read -p "" remote_port_input
      if validate_port "$remote_port_input"; then
        remote_port="$remote_port_input"
        break
      else
        print_error "Invalid port number. Please enter a number between 1 and 65535."
      fi
    done

    local protocol_choice
    local protocol_type
    echo -e "👉 ${DEFAULT_TEXT_COLOR}Select protocol (1) TCP, (2) UDP, (3) HTTP, (4) HTTPS (default: 1):${RESET} "
    read -p "" protocol_choice
    protocol_choice=${protocol_choice:-1}

    case "$protocol_choice" in
      1) protocol_type="tcp" ;;
      2) protocol_type="udp" ;;
      3) protocol_type="http" ;;
      4) protocol_type="https" ;;
      *) protocol_type="tcp" ; print_error "Invalid choice. Defaulting to TCP." ;;
    esac

    proxy_configs_toml+="
[[proxies]]
name = \"${protocol_type}_${client_name}_${proxy_counter}\"
type = \"${protocol_type}\"
"
    # Conditionally add local_ip for TCP/UDP
    if [[ "$protocol_type" == "tcp" || "$protocol_type" == "udp" ]]; then
      proxy_configs_toml+="local_ip = \"127.0.0.1\""$'\n'
    fi

    proxy_configs_toml+="local_port = ${local_port}"$'\n'
    proxy_configs_toml+="remote_port = ${remote_port}"$'\n'

    if [[ "$protocol_type" == "http" || "$protocol_type" == "https" ]]; then
      local custom_domain
      echo -e "👉 ${DEFAULT_TEXT_COLOR}Custom domain name for this HTTP/HTTPS proxy (optional, e.g., sub.yourdomain.com):${RESET} "
      read -p "" custom_domain
      if [[ -n "$custom_domain" ]]; then
        proxy_configs_toml+="custom_domains = [\"${custom_domain}\"]" # TOML array for custom_domains
      fi
    fi

    proxy_counter=$((proxy_counter+1))
    echo ""
    echo -e "${PROMPT_COLOR}Add another port? (y/N):${RESET}"
    read -p "" add_more_ports
    if ! [[ "$add_more_ports" =~ ^[Yy]$ ]]; then
      break
    fi
    echo ""
  done
  echo ""

  # Create the FRPulse client config file (TOML)
  echo -e "${INFO_COLOR}📝 Creating frpc-$client_name.toml configuration file...${RESET}"
  cat <<EOF > "$config_file_path"
# frpc-$client_name.toml
[common]
server_addr = "$server_address"
server_port = $server_port
token = "$token"
tls_enable = $client_tls_enabled
log_file = "/var/log/frpc-$client_name.log"
log_level = "info"
log_max_days = 3
$proxy_configs_toml
EOF
  print_success "frpc-$client_name.toml successfully created at $config_file_path."

  # Create the systemd service file
  echo -e "${INFO_COLOR}🔧 Creating systemd service file for FRPulse client '$client_name'...${RESET}"
  cat <<EOF | sudo tee "$service_file" > /dev/null
[Unit]
Description=FRPulse Client - $client_name
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frpc -c "$config_file_path"
Restart=always
RestartSec=5
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

  echo -e "${INFO_COLOR}🔧 Reloading systemd daemon...${RESET}"
  sudo systemctl daemon-reload

  echo -e "${INFO_COLOR}🚀 Enabling and starting FRPulse service '$service_name'...${RESET}"
  sudo systemctl enable "$service_name" > /dev/null 2>&1
  sudo systemctl start "$service_name" > /dev/null 2>&1

  print_success "FRPulse client '$client_name' started as $service_name."

  echo ""
  echo -e "${PROMPT_COLOR}Would you like to view the logs for $service_name now? (y/N): ${RESET}"
  read -p "" view_logs_choice
  echo ""

  if [[ "$view_logs_choice" =~ ^[Yy]$ ]]; then
    show_service_logs "$service_name"
  fi

  echo ""
  echo -e "${PROMPT_COLOR}Press Enter to return to the main menu...${RESET}"
  read -p ""
}

# --- Initial Setup Function ---
# This function performs one-time setup tasks like installing dependencies
# and creating the 'trust' command symlink.
perform_initial_setup() {
  # Check if initial setup has already been performed
  if [ -f "$SETUP_MARKER_FILE" ]; then
    echo -e "${PROMPT_COLOR}Initial setup already performed. Skipping dependency installation.${RESET}"
    return 0 # Exit successfully
  fi

  echo -e "${INFO_COLOR}Performing initial setup (installing dependencies)...${RESET}"

  # Install required tools
  echo -e "${INFO_COLOR}Updating package list and installing dependencies...${RESET}"
  sudo apt update
  sudo apt install -y build-essential curl pkg-config libssl-dev git figlet certbot cron

  sudo mkdir -p "$(dirname "$SETUP_MARKER_FILE")" # Ensure directory exists for marker file
  sudo touch "$SETUP_MARKER_FILE" # Create marker file only if all initial setup steps succeed
  print_success "Initial setup complete."
  echo ""
  return 0
}

# --- New: Function to get a new SSL certificate using Certbot ---
get_new_certificate_action() {
  clear
  echo ""
  draw_line "${INFO_COLOR}" "=" 40
  echo -e "${INFO_COLOR}     ➕ Get New SSL Certificate${RESET}"
  draw_line "${INFO_COLOR}" "=" 40
  echo ""

  echo -e "${INFO_COLOR}🌐 Domain and Email for SSL Certificate:${RESET}"
  echo -e "  (e.g., yourdomain.com)"
  
  local domain
  while true; do
    echo -e "👉 ${DEFAULT_TEXT_COLOR}Please enter your domain:${RESET} "
    read -p "" domain
    if validate_host "$domain"; then
      break
    else
      print_error "Invalid domain or IP address format. Please try again."
    fi
  done
  echo ""

  local email
  while true; do
    echo -e "👉 ${DEFAULT_TEXT_COLOR}Please enter your email:${RESET} "
    read -p "" email
    if validate_email "$email"; then
      break
    else
      print_error "Invalid email format. Please try again."
    fi
  done
  echo ""

  local cert_path="/etc/letsencrypt/live/$domain"

  if [ -d "$cert_path" ]; then
    print_success "SSL certificate for $domain already exists. Skipping Certbot."
  else
    echo -e "${INFO_COLOR}🔐 Requesting SSL certificate with Certbot...${RESET}"
    echo -e "${PROMPT_COLOR}Ensure port 80 is open and not in use by another service.${RESET}"
    if sudo certbot certonly --standalone -d "$domain" --non-interactive --agree-tos -m "$email"; then
      print_success "SSL certificate successfully obtained for $domain."
    else
      print_error "❌ Failed to obtain SSL certificate for $domain. Check Certbot logs for details."
      print_error "   Ensure your domain points to this server and port 80 is open."
    fi
  fi
  echo ""
  echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
  read -p ""
}

# --- New: Function to delete existing SSL certificates ---
delete_certificates_action() {
  clear
  echo ""
  draw_line "${ERROR_COLOR}" "=" 40
  echo -e "${ERROR_COLOR}     🗑️ Delete SSL Certificates${RESET}"
  draw_line "${ERROR_COLOR}" "=" 40
  echo ""

  echo -e "${INFO_COLOR}🔍 Searching for existing SSL certificates...${RESET}"
  # Find directories under /etc/letsencrypt/live/ that are not 'README'
  mapfile -t cert_domains < <(sudo find /etc/letsencrypt/live -maxdepth 1 -mindepth 1 -type d ! -name "README" -exec basename {} \;)

  if [ ${#cert_domains[@]} -eq 0 ]; then
    print_error "No SSL certificates found to delete."
    echo ""
    echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
    return 0
  fi

  echo -e "${INFO_COLOR}📋 Please select a certificate to delete:${RESET}"
  # Add a "Back to previous menu" option
  cert_domains+=("Back to previous menu")
  select selected_domain in "${cert_domains[@]}"; do
    if [[ "$selected_domain" == "Back to previous menu" ]]; then
      echo -e "${PROMPT_COLOR}Returning to previous menu...${RESET}"
      echo ""
      return 0
    elif [ -n "$selected_domain" ]; then
      break
    else
      print_error "Invalid choice. Please enter a valid number."
    fi
  done
  echo ""

  if [[ -z "$selected_domain" ]]; then
    print_error "No certificate selected. Deletion cancelled."
    echo ""
    echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
    read -p ""
    return 0
  fi

  echo -e "${ERROR_COLOR}⚠️ Are you sure you want to delete the certificate for '$selected_domain'? (y/N): ${RESET}"
  read -p "" confirm_delete
  echo ""

  if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
    echo -e "${INFO_COLOR}🗑️ Deleting certificate for '$selected_domain' using Certbot...${RESET}"
    if sudo certbot delete --cert-name "$selected_domain"; then
      print_success "Certificate for '$selected_domain' successfully deleted."
    else
      print_error "❌ Failed to delete certificate for '$selected_domain'. Check Certbot logs."
    fi
  else
    echo -e "${PROMPT_COLOR}Deletion for '$selected_domain' cancelled.${RESET}"
  fi

  echo ""
  echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
  read -p ""
}

# --- New: Certificate Management Menu Function ---
certificate_management_menu() {
  while true; do
    clear
    echo ""
    draw_line "${PROMPT_COLOR}" "=" 40
    echo -e "${INFO_COLOR}     🔐 Certificate Management${RESET}"
    draw_line "${PROMPT_COLOR}" "=" 40
    echo ""
    echo -e "  ${PROMPT_COLOR}1)${RESET} ${DEFAULT_TEXT_COLOR}Get New Certificate${RESET}"
    echo -e "  ${PROMPT_COLOR}2)${RESET} ${DEFAULT_TEXT_COLOR}Delete Certificates${RESET}"
    echo -e "  ${PROMPT_COLOR}3)${RESET} ${DEFAULT_TEXT_COLOR}Back to Main Menu${RESET}"
    echo ""
    draw_line "${PROMPT_COLOR}" "-" 40
    echo -e "👉 ${INFO_COLOR}Your choice:${RESET} "
    read -p "" cert_choice
    echo ""

    case $cert_choice in
      1)
        get_new_certificate_action
        ;;
      2)
        delete_certificates_action
        ;;
      3)
        echo -e "${PROMPT_COLOR}Returning to main menu...${RESET}"
        break # Break out of this while loop to return to main menu
        ;;
      *)
        echo -e "${ERROR_COLOR}❌ Invalid option.${RESET}"
        echo ""
        echo -e "${PROMPT_COLOR}Press Enter to continue...${RESET}"
        read -p ""
        ;;
    esac
  done
}


# --- Main Script Execution ---
set -e # Exit immediately if a command exits with a non-zero status

# Perform initial setup (will run only once)
perform_initial_setup || { echo "Initial setup failed. Exiting."; exit 1; }

while true; do
  # Clear terminal and show logo
  clear
  echo -e "${INFO_COLOR}"
  figlet -f slant "FRPulse" # Changed to FRPulse
  echo -e "${INFO_COLOR}"
  draw_line "${INFO_COLOR}" "=" 80 # Decorative line
  echo ""
  echo -e "Developed by ErfanXRay => ${BOLD_HIGHLIGHT}https://github.com/Erfan-XRay/FRPulse${RESET}"
  echo -e "Telegram Channel => ${BOLD_HIGHLIGHT}@Erfan_XRay${RESET}"
  echo -e "Tunnel script based on ${INFO_COLOR}FRP (Fast Reverse Proxy)${RESET}" # Generic description
  echo ""
  # Get server IP addresses
  SERVER_IPV4=$(hostname -I | awk '{print $1}')

  draw_line "${INFO_COLOR}" "=" 40 # Decorative line
  echo -e "${INFO_COLOR}     🌐 Server Information${RESET}"
  draw_line "${INFO_COLOR}" "=" 40 # Decorative line
  echo -e "  ${DEFAULT_TEXT_COLOR}IPv4 Address: ${PROMPT_COLOR}$SERVER_IPV4${RESET}"
  
  # Check script installation status based on frpc and frps binaries
  if [ -f "/usr/local/bin/frps" ] && [ -f "/usr/local/bin/frpc" ]; then
    echo -e "  ${DEFAULT_TEXT_COLOR}Script Status: ${SUCCESS_COLOR}✅ Installed${RESET}"
  else
    echo -e "  ${DEFAULT_TEXT_COLOR}Script Status: ${ERROR_COLOR}❌ Not Installed${RESET}"
  fi

  echo -e "  ${DEFAULT_TEXT_COLOR}Script Version: ${PROMPT_COLOR}$SCRIPT_VERSION${RESET}"
  draw_line "${INFO_COLOR}" "=" 40 # Decorative line
  echo "" # Added for spacing

  # Menu
  echo "Select an option:"
  echo ""
  echo -e "${MENU_OPTION_COLOR}1) Install FRPulse${RESET}"
  echo -e "${MENU_OPTION_COLOR}2) FRPulse Tunnel Management${RESET}"
  echo -e "${MENU_OPTION_COLOR}3) Certificate Management${RESET}"
  echo -e "${MENU_OPTION_COLOR}4) Uninstall FRPulse and Cleanup${RESET}"
  echo -e "${MENU_OPTION_COLOR}5) Exit${RESET}"
  echo ""
  read -p "👉 Your choice: " choice

  case $choice in
    1)
      install_frpulse_action
      ;;
    2) # FRPulse tunnel management
      while true; do
        clear
        echo ""
        draw_line "${INFO_COLOR}" "=" 40
        echo -e "${INFO_COLOR}     🌐 FRPulse Tunnel Management${RESET}"
        draw_line "${INFO_COLOR}" "=" 40
        echo ""
        echo -e "  ${SUB_MENU_OPTION_COLOR}1)${RESET} ${DEFAULT_TEXT_COLOR}Server (Iran)${RESET}"
        echo -e "  ${SUB_MENU_OPTION_COLOR}2)${RESET} ${DEFAULT_TEXT_COLOR}Client (Kharej)${RESET}"
        echo -e "  ${SUB_MENU_OPTION_COLOR}3)${RESET} ${DEFAULT_TEXT_COLOR}Back to Main Menu${RESET}"
        echo ""
        draw_line "${INFO_COLOR}" "-" 40
        echo -e "👉 ${INFO_COLOR}Your choice:${RESET} "
        read -p "" frpulse_tunnel_choice
        echo ""

        case $frpulse_tunnel_choice in
          1) # FRPulse Server Management
            while true; do
              clear
              echo ""
              draw_line "${INFO_COLOR}" "=" 40
              echo -e "${INFO_COLOR}     🔧 FRPulse Server Management${RESET}"
              draw_line "${INFO_COLOR}" "=" 40
              echo ""
              echo -e "  ${SUB_MENU_OPTION_COLOR}1)${RESET} ${DEFAULT_TEXT_COLOR}Add New FRPulse Server${RESET}"
              echo -e "  ${SUB_MENU_OPTION_COLOR}2)${RESET} ${DEFAULT_TEXT_COLOR}View FRPulse Server Logs${RESET}"
              echo -e "  ${SUB_MENU_OPTION_COLOR}3)${RESET} ${DEFAULT_TEXT_COLOR}Delete an FRPulse Server${RESET}"
              echo -e "  ${SUB_MENU_OPTION_COLOR}4)${RESET} ${DEFAULT_TEXT_COLOR}Schedule FRPulse Server Restart${RESET}"
              echo -e "  ${SUB_MENU_OPTION_COLOR}5)${RESET} ${DEFAULT_TEXT_COLOR}Delete Scheduled Restart${RESET}"
              echo -e "  ${SUB_MENU_OPTION_COLOR}6)${RESET} ${DEFAULT_TEXT_COLOR}Back to Previous Menu${RESET}"
              echo ""
              draw_line "${INFO_COLOR}" "-" 40
              echo -e "👉 ${INFO_COLOR}Your choice:${RESET} "
              read -p "" frpulse_srv_choice
              echo ""

              case $frpulse_srv_choice in
                1)
                  add_new_frpulse_server_action
                  ;;
                2)
                  clear
                  echo ""
                  draw_line "${INFO_COLOR}" "=" 40
                  echo -e "${INFO_COLOR}     📊 FRPulse Server Logs${RESET}"
                  draw_line "${INFO_COLOR}" "=" 40
                  echo ""
                  echo -e "${INFO_COLOR}🔍 Searching for FRPulse servers...${RESET}"
                  mapfile -t services < <(systemctl list-units --type=service --all | grep 'frpulse-server-' | awk '{print $1}' | sed 's/.service$//')
                  if [ ${#services[@]} -eq 0 ]; then
                    echo -e "${ERROR_COLOR}❌ No FRPulse servers found.${RESET}"
                  else
                    echo -e "${INFO_COLOR}📋 Please select a service to view logs:${RESET}"
                    services+=("Back to Previous Menu")
                    select selected_service in "${services[@]}"; do
                      if [[ "$selected_service" == "Back to Previous Menu" ]]; then
                        echo -e "${PROMPT_COLOR}Returning to previous menu...${RESET}"
                        echo ""
                        break 2
                      elif [ -n "$selected_service" ]; then
                        show_service_logs "$selected_service"
                        break
                      else
                        echo -e "${ERROR_COLOR}⚠️ Invalid choice. Please enter a valid number.${RESET}"
                      fi
                    done
                  fi
                  echo ""
                  echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
                  read -p ""
                  ;;
                3)
                  clear
                  echo ""
                  draw_line "${INFO_COLOR}" "=" 40
                  echo -e "${INFO_COLOR}     🗑️ Delete FRPulse Server${RESET}"
                  draw_line "${INFO_COLOR}" "=" 40
                  echo ""
                  echo -e "${INFO_COLOR}🔍 Searching for FRPulse servers...${RESET}"
                  mapfile -t services < <(systemctl list-units --type=service --all | grep 'frpulse-server-' | awk '{print $1}' | sed 's/.service$//')
                  if [ ${#services[@]} -eq 0 ]; then
                    echo -e "${ERROR_COLOR}❌ No FRPulse servers found.${RESET}"
                  else
                    echo -e "${INFO_COLOR}📋 Please select a service to delete:${RESET}"
                    services+=("Back to Previous Menu")
                    select selected_service in "${services[@]}"; do
                      if [[ "$selected_service" == "Back to Previous Menu" ]]; then
                        echo -e "${PROMPT_COLOR}Returning to previous menu...${RESET}"
                        echo ""
                        break 2
                      elif [ -n "$selected_service" ]; then
                        service_file="/etc/systemd/system/${selected_service}.service"
                        config_file_to_delete="$(pwd)/frpulse/frps-$(echo "$selected_service" | sed 's/frpulse-server-//').toml" # Changed to .toml
                        
                        echo -e "${PROMPT_COLOR}🛑 Stopping $selected_service...${RESET}"
                        sudo systemctl stop "$selected_service" > /dev/null 2>&1
                        sudo systemctl disable "$selected_service" > /dev/null 2>&1
                        sudo rm -f "/etc/systemd/system/$service_file" > /dev/null 2>&1
                        sudo systemctl daemon-reload > /dev/null 2>&1
                        print_success "FRPulse server '$selected_service' deleted."
                        
                        # Remove the TOML configuration file
                        if [ -f "$config_file_to_delete" ]; then
                            echo "🗑️ Deleting configuration file: $config_file_to_delete..."
                            rm -f "$config_file_to_delete"
                            print_success "Configuration file deleted."
                        else
                            echo "⚠️ Configuration file not found: $config_file_to_delete. Skipping deletion."
                        fi

                        (sudo crontab -l 2>/dev/null | grep -v "# FRPulse automated restart for $selected_service$") | sudo crontab -
                        print_success "Cron jobs for '$selected_service' deleted."
                        break
                      else
                        echo -e "${ERROR_COLOR}⚠️ Invalid choice. Please enter a valid number.${RESET}"
                      fi
                    done
                  fi
                  echo ""
                  echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
                  read -p ""
                  ;;
                4) # Schedule FRPulse server restart
                  clear
                  echo ""
                  draw_line "${INFO_COLOR}" "=" 40
                  echo -e "${INFO_COLOR}     ⏰ Schedule FRPulse Server Restart${RESET}"
                  draw_line "${INFO_COLOR}" "=" 40
                  echo ""
                  echo -e "${INFO_COLOR}🔍 Searching for FRPulse servers...${RESET}"
                  mapfile -t services < <(systemctl list-units --type=service --all | grep 'frpulse-server-' | awk '{print $1}' | sed 's/.service$//')
                  if [ ${#services[@]} -eq 0 ]; then
                    echo -e "${ERROR_COLOR}❌ No FRPulse servers found to schedule. Please add a server first.${RESET}"
                    echo ""
                    echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
                    read -p ""
                  else
                    echo -e "${INFO_COLOR}📋 Please select the FRPulse server service to schedule restart:${RESET}"
                    services+=("Back to Previous Menu")
                    select selected_server_service in "${services[@]}"; do
                      if [[ "$selected_server_service" == "Back to Previous Menu" ]]; then
                        echo -e "${PROMPT_COLOR}Returning to previous menu...${RESET}"
                        echo ""
                        break 2
                      elif [ -n "$selected_server_service" ]; then
                        reset_timer "$selected_server_service"
                        break
                      else
                        echo -e "${ERROR_COLOR}⚠️ Invalid choice. Please enter a valid number.${RESET}"
                      fi
                    done
                  fi
                  ;;
                5)
                  delete_cron_job_action
                  ;;
                6)
                  echo -e "${PROMPT_COLOR}Returning to previous menu...${RESET}"
                  break # Break out of this while loop to return to FRPulse Tunnel Management
                  ;;
                *)
                  echo -e "${ERROR_COLOR}❌ Invalid option.${RESET}"
                  echo ""
                  echo -e "${PROMPT_COLOR}Press Enter to continue...${RESET}"
                  read -p ""
                  ;;
              esac
            done
            ;;
          2) # FRPulse Client Management
            while true; do
              clear
              echo ""
              draw_line "${INFO_COLOR}" "=" 40
              echo -e "${INFO_COLOR}     📡 FRPulse Client Management${RESET}"
              draw_line "${INFO_COLOR}" "=" 40
              echo ""
              echo -e "  ${SUB_MENU_OPTION_COLOR}1)${RESET} ${DEFAULT_TEXT_COLOR}Add New FRPulse Client${RESET}"
              echo -e "  ${SUB_MENU_OPTION_COLOR}2)${RESET} ${DEFAULT_TEXT_COLOR}View FRPulse Client Logs${RESET}"
              echo -e "  ${SUB_MENU_OPTION_COLOR}3)${RESET} ${DEFAULT_TEXT_COLOR}Delete an FRPulse Client${RESET}"
              echo -e "  ${SUB_MENU_OPTION_COLOR}4)${RESET} ${DEFAULT_TEXT_COLOR}Schedule FRPulse Client Restart${RESET}"
              echo -e "  ${SUB_MENU_OPTION_COLOR}5)${RESET} ${DEFAULT_TEXT_COLOR}Delete Scheduled Restart${RESET}"
              echo -e "  ${SUB_MENU_OPTION_COLOR}6)${RESET} ${DEFAULT_TEXT_COLOR}Back to Previous Menu${RESET}"
              echo ""
              draw_line "${INFO_COLOR}" "-" 40
              echo -e "👉 ${INFO_COLOR}Your choice:${RESET} "
              read -p "" frpulse_client_choice
              echo ""

              case $frpulse_client_choice in
                1)
                  add_new_frpulse_client_action
                  ;;
                2)
                  clear
                  echo ""
                  draw_line "${INFO_COLOR}" "=" 40
                  echo -e "${INFO_COLOR}     📊 FRPulse Client Logs${RESET}"
                  draw_line "${INFO_COLOR}" "=" 40
                  echo ""
                  echo -e "${INFO_COLOR}🔍 Searching for FRPulse clients...${RESET}"
                  mapfile -t services < <(systemctl list-units --type=service --all | grep 'frpulse-client-' | awk '{print $1}' | sed 's/.service$//')
                  if [ ${#services[@]} -eq 0 ]; then
                    echo -e "${ERROR_COLOR}❌ No FRPulse clients found.${RESET}"
                  else
                    echo -e "${INFO_COLOR}📋 Please select a service to view logs:${RESET}"
                    services+=("Back to Previous Menu")
                    select selected_service in "${services[@]}"; do
                      if [[ "$selected_service" == "Back to Previous Menu" ]]; then
                        echo -e "${PROMPT_COLOR}Returning to previous menu...${RESET}"
                        echo ""
                        break 2
                      elif [ -n "$selected_service" ]; then
                        show_service_logs "$selected_service"
                        break
                      else
                        echo -e "${ERROR_COLOR}⚠️ Invalid choice. Please enter a valid number.${RESET}"
                      fi
                    done
                  fi
                  echo ""
                  echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
                  read -p ""
                  ;;
                3)
                  clear
                  echo ""
                  draw_line "${INFO_COLOR}" "=" 40
                  echo -e "${INFO_COLOR}     🗑️ Delete FRPulse Client${RESET}"
                  draw_line "${INFO_COLOR}" "=" 40
                  echo ""
                  echo -e "${INFO_COLOR}🔍 Searching for FRPulse clients...${RESET}"
                  mapfile -t services < <(systemctl list-units --type=service --all | grep 'frpulse-client-' | awk '{print $1}' | sed 's/.service$//')
                  if [ ${#services[@]} -eq 0 ]; then
                    echo -e "${ERROR_COLOR}❌ No FRPulse clients found.${RESET}"
                  else
                    echo -e "${INFO_COLOR}📋 Please select a service to delete:${RESET}"
                    services+=("Back to Previous Menu")
                    select selected_service in "${services[@]}"; do
                      if [[ "$selected_service" == "Back to Previous Menu" ]]; then
                        echo -e "${PROMPT_COLOR}Returning to previous menu...${RESET}"
                        echo ""
                        break 2
                      elif [ -n "$selected_service" ]; then
                        service_file="/etc/systemd/system/${selected_service}.service"
                        config_file_to_delete="$(pwd)/frpulse/frpc-$(echo "$selected_service" | sed 's/frpulse-client-//').toml" # Changed to .toml

                        echo -e "${PROMPT_COLOR}🛑 Stopping $selected_service...${RESET}"
                        sudo systemctl stop "$selected_service" > /dev/null 2>&1
                        sudo systemctl disable "$selected_service" > /dev/null 2>&1
                        sudo rm -f "$service_file" > /dev/null 2>&1
                        sudo systemctl daemon-reload > /dev/null 2>&1
                        print_success "FRPulse client '$selected_service' deleted."
                        
                        # Remove the TOML configuration file
                        if [ -f "$config_file_to_delete" ]; then
                            echo "🗑️ Deleting configuration file: $config_file_to_delete..."
                            rm -f "$config_file_to_delete"
                            print_success "Configuration file deleted."
                        else
                            echo "⚠️ Configuration file not found: $config_file_to_delete. Skipping deletion."
                        fi

                        (sudo crontab -l 2>/dev/null | grep -v "# FRPulse automated restart for $selected_service$") | sudo crontab -
                        print_success "Cron jobs for '$selected_service' deleted."
                        break
                      else
                        echo -e "${ERROR_COLOR}⚠️ Invalid choice. Please enter a valid number.${RESET}"
                      fi
                    done
                  fi
                  echo ""
                  echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
                  read -p ""
                  ;;
                4) # Schedule FRPulse client restart (shifted from 4)
                  clear
                  echo ""
                  draw_line "${INFO_COLOR}" "=" 40
                  echo -e "${INFO_COLOR}     ⏰ Schedule FRPulse Client Restart${RESET}"
                  draw_line "${INFO_COLOR}" "=" 40
                  echo ""
                  echo -e "${INFO_COLOR}🔍 Searching for FRPulse clients...${RESET}"
                  mapfile -t services < <(systemctl list-units --type=service --all | grep 'frpulse-client-' | awk '{print $1}' | sed 's/.service$//')
                  if [ ${#services[@]} -eq 0 ]; then
                    echo -e "${ERROR_COLOR}❌ No FRPulse clients found to schedule. Please add a client first.${RESET}"
                    echo ""
                    echo -e "${PROMPT_COLOR}Press Enter to return to the previous menu...${RESET}"
                    read -p ""
                  else
                    echo -e "${INFO_COLOR}📋 Please select the FRPulse client service to schedule restart:${RESET}"
                    services+=("Back to Previous Menu")
                    select selected_client_service in "${services[@]}"; do
                      if [[ "$selected_client_service" == "Back to Previous Menu" ]]; then
                        echo -e "${PROMPT_COLOR}Returning to previous menu...${RESET}"
                        echo ""
                        break 2
                      elif [ -n "$selected_client_service" ]; then
                        reset_timer "$selected_client_service"
                        break
                      else
                        echo -e "${ERROR_COLOR}⚠️ Invalid choice. Please enter a valid number.${RESET}"
                      fi
                    done
                  fi
                  ;;
                5) # Delete Scheduled Restart (shifted from 5)
                  delete_cron_job_action
                  ;;
                6) # Back to previous menu (shifted from 6)
                  echo -e "${PROMPT_COLOR}Returning to previous menu...${RESET}"
                  break # Break out of this while loop to return to FRPulse Tunnel Management
                  ;;
                *)
                  echo -e "${ERROR_COLOR}❌ Invalid option.${RESET}"
                  echo ""
                  echo -e "${PROMPT_COLOR}Press Enter to continue...${RESET}"
                  read -p ""
                  ;;
              esac
            done
            ;;
          3)
            echo -e "${PROMPT_COLOR}Returning to main menu...${RESET}"
            break # Break out of this while loop to return to main menu
            ;;
          *)
            echo -e "${ERROR_COLOR}❌ Invalid option.${RESET}"
            echo ""
            echo -e "${PROMPT_COLOR}Press Enter to continue...${RESET}"
            read -p ""
            ;;
        esac
      done
      ;;
    3) # Certificate Management option
      certificate_management_menu
      ;;
    4) # Uninstall FRPulse and cleanup
      uninstall_frpulse_action
      ;;
    5) # Exit
      exit 0
      ;;
    *)
      echo -e "${ERROR_COLOR}❌ Invalid choice. Exiting.${RESET}"
      echo ""
      echo -e "${PROMPT_COLOR}Press Enter to continue...${RESET}"
      read -p ""
    ;;
  esac
  echo ""
done
