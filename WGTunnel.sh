#!/bin/bash

# Define colors for better terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
RESET='\033[0m' # No Color
BOLD_GREEN='\033[1;32m' # Bold Green for menu title

# --- Global Paths and Markers ---
# Use readlink -f to get the canonical path of the script, resolving symlinks and /dev/fd/ issues
TRUST_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$TRUST_SCRIPT_PATH")"
SETUP_MARKER_FILE="/var/lib/wgtunnel/.setup_complete"

# --- Script Version ---
SCRIPT_VERSION="1.0.0" # Initial release for WGTunnel

# --- OS Detection ---
check_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
      echo -e "\033[0;31m❌ Error: This script only supports Ubuntu and Debian.\033[0m"
      echo -e "\033[0;33mDetected OS: $PRETTY_NAME\033[0m"
      exit 1
    fi
  else
    echo -e "\033[0;31m❌ Error: Cannot detect operating system. /etc/os-release not found.\033[0m"
    exit 1
  fi
}

# Run OS check immediately
check_os

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
  echo -e "\033[0;32m✅ $message\033[0m" # Green color for success messages
}

# Function to print error messages in red
print_error() {
  local message="$1"
  echo -e "\033[0;31m❌ $message\033[0m" # Red color for error messages
}

# Function to show service logs and return to a "menu"
show_service_logs() {
  local service_name="$1"
  clear # Clear the screen before showing logs
  echo -e "\033[0;34m--- Displaying logs for $service_name ---\033[0m" # Blue color for header

  # Display the last 50 lines of logs for the specified service
  # --no-pager ensures the output is direct to the terminal without opening 'less'
  sudo journalctl -u "$service_name" -n 50 --no-pager

  echo ""
  echo -e "\033[1;33mPress any key to return to the previous menu...\033[0m" # Yellow color for prompt
  read -n 1 -s -r # Read a single character, silent, raw input

  clear
}

# Function to draw a green line (used for main menu border)
draw_green_line() {
  echo -e "${GREEN}+--------------------------------------------------------+${RESET}"
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
  # This regex is a balance between strictness and covering common valid IPv6 formats.
  # It does not cover all extremely complex valid IPv6 cases (e.g., IPv4-mapped IPv6),
  # but should be sufficient for typical user input.
  local ipv6_regex="^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){1,7}:(\b[0-9a-fA-F]{1,4}\b){1,7}$|^([0-9a-fA-F]{1,4}:){1,6}(:[0-9a-fA-F]{1,4}){1,2}$|^([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,3}$|^([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,4}$|^([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,5}$|^([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,6}$|^[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,7}|:)$|^::((:[0-9a-fA-F]{1,4}){1,7}|[0-9a-fA-F]{1,4})$|^[0-9a-fA-F]{1,4}::([0-9a-fA-F]{1,4}:){0,5}[0-9a-fA-F]{1,4}$|^::([0-9a-fA-F]{1,4}:){0,6}[0-9a-fA-F]{1,4}$"
  # Regex for domain name
  local domain_regex="^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,6}$"

  if [[ "$host" =~ $ipv4_regex ]] || [[ "$host" =~ $ipv6_regex ]] || [[ "$host" =~ $domain_regex ]]; then
    return 0 # Valid
  else
    return 1 # Invalid
  fi
}

# Function to validate IP:Port format
validate_ip_port() {
  local input="$1"
  local host_part=""
  local port_part=""

  # Check for IPv6 with brackets
  if [[ "$input" =~ ^\[(.*)\]:([0-9]+)$ ]]; then
    host_part="${BASH_REMATCH[1]}"
    port_part="${BASH_REMATCH[2]}"
  elif [[ "$input" =~ ^([^:]+):([0-9]+)$ ]]; then
    host_part="${BASH_REMATCH[1]}"
    port_part="${BASH_REMATCH[2]}"
  else
    return 1 # Does not match IP:Port pattern
  fi

  if validate_host "$host_part" && validate_port "$port_part"; then
    return 0 # Valid
  else
    return 1 # Invalid host or port
  fi
}


# Update cron job logic to include Hysteria
reset_timer() {
  local service_to_restart="$1" # Optional: service name passed as argument

  clear
  echo ""
  draw_line "$CYAN" "=" 40
  echo -e "${CYAN}     ⏰ Schedule Service Restart${RESET}"
  draw_line "$CYAN" "=" 40
  echo ""

  if [[ -z "$service_to_restart" ]]; then
    echo -e "👉 ${WHITE}Which service do you want to restart (e.g., 'nginx', 'hysteria-server-myname', 'frpulse')? ${RESET}"
    read -p "" service_to_restart
    echo ""
  fi

  if [[ -z "$service_to_restart" ]]; then
    print_error "Service name cannot be empty. Aborting scheduling."
    echo ""
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return 1
  fi

  if [ ! -f "/etc/systemd/system/${service_to_restart}.service" ]; then
    print_error "Service '$service_to_restart' does not exist on this system. Cannot schedule restart."
    echo ""
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return 1
  fi

  echo -e "${CYAN}Scheduling restart for service: ${WHITE}$service_to_restart${RESET}"
  echo ""
  echo "Please select a time interval for the service to restart RECURRINGLY:"
  echo -e "  ${YELLOW}1)${RESET} ${WHITE}Every 30 minutes${RESET}"
  echo -e "  ${YELLOW}2)${RESET} ${WHITE}Every 1 hour${RESET}"
  echo -e "  ${YELLOW}3)${RESET} ${WHITE}Every 2 hours${RESET}"
  echo -e "  ${YELLOW}4)${RESET} ${WHITE}Every 4 hours${RESET}"
  echo -e "  ${YELLOW}5)${RESET} ${WHITE}Every 6 hours${RESET}"
  echo -e "  ${YELLOW}6)${RESET} ${WHITE}Every 12 hours${RESET}"
  echo -e "  ${YELLOW}7)${RESET} ${WHITE}Every 24 hours${RESET}"
  echo ""
  read -p "👉 Enter your choice (1-7): " choice
  echo ""

  local cron_minute=""
  local cron_hour=""
  local cron_day_of_month="*"
  local cron_month="*"
  local cron_day_of_week="*"
  local description=""
  local cron_tag=""

  if [[ "$service_to_restart" == hysteria-* ]]; then
      cron_tag="Hysteria"
  else
      cron_tag="FRPulse" # Keep this for existing FRPulse cron jobs cleanup
  fi


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
      echo -e "${RED}❌ Invalid choice. No cron job will be scheduled.${RESET}"
      echo ""
      echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
      read -p ""
      return 1
      ;;
  esac

  echo -e "${CYAN}Scheduling '$service_to_restart' to restart $description...${RESET}"
  echo ""
  
  local cron_command="/usr/bin/systemctl restart $service_to_restart >> /var/log/${cron_tag}_cron.log 2>&1"
  local cron_job_entry="$cron_minute $cron_hour $cron_day_of_month $cron_month $cron_day_of_week $cron_command # ${cron_tag} automated restart for $service_to_restart"

  local temp_cron_file=$(mktemp)
  if ! sudo crontab -l &> /dev/null; then
      echo "" | sudo crontab -
  fi
  sudo crontab -l > "$temp_cron_file"

  # Remove existing cron jobs for both FRPulse and Hysteria for this service
  sed -i "/# FRPulse automated restart for $service_to_restart$/d" "$temp_cron_file"
  sed -i "/# Hysteria automated restart for $service_to_restart$/d" "$temp_cron_file"

  echo "$cron_job_entry" >> "$temp_cron_file"

  if sudo crontab "$temp_cron_file"; then
    print_success "Successfully scheduled a restart for '$service_to_restart' $description."
    echo -e "${CYAN}   The cron job entry looks like this:${RESET}"
    echo -e "${WHITE}   $cron_job_entry${RESET}"
    echo -e "${CYAN}   Logs will be written to: ${WHITE}/var/log/${cron_tag}_cron.log${RESET}"
  else
    print_error "Failed to schedule the cron job. Check permissions or cron service status.${RESET}"
  fi

  rm -f "$temp_cron_file"

  echo ""
  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
  read -p ""
}

delete_cron_job_action() {
  clear
  echo ""
  draw_line "$RED" "=" 40
  echo -e "${RED}     🗑️ Delete Scheduled Restart (Cron)${RESET}"
  draw_line "$RED" "=" 40
  echo ""

  echo -e "${CYAN}🔍 Searching for Hysteria related services with scheduled restarts...${RESET}" # Updated message

  # Only search for Hysteria cron jobs, but keep the FRPulse grep for existing ones
  mapfile -t services_with_cron < <(sudo crontab -l 2>/dev/null | grep -E "# (FRPulse|Hysteria) automated restart for" | awk '{print $NF}' | sort -u)

  local service_names=()
  for service_comment in "${services_with_cron[@]}"; do
    local extracted_name=$(echo "$service_comment" | sed -E 's/# (FRPulse|Hysteria) automated restart for //')
    service_names+=("$extracted_name")
  done

  if [ ${#service_names[@]} -eq 0 ]; then
    print_error "No Hysteria or legacy FRPulse services with scheduled cron jobs found." # Updated message
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return 1
  fi

  echo -e "${CYAN}📋 Please select a service to delete its scheduled restart:${RESET}"
  service_names+=("Back to previous menu")
  select selected_service_name in "${service_names[@]}"; do
    if [[ "$selected_service_name" == "Back to previous menu" ]]; then
      echo -e "${YELLOW}Returning to previous menu...${RESET}"
      echo ""
      return 0
    elif [ -n "$selected_service_name" ]; then
      break
    else
      print_error "Invalid selection. Please enter a valid number."
    fi
  done
  echo ""

  if [[ -z "$selected_service_name" ]]; then
    print_error "No service selected. Aborting."
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return 1
  fi

  echo -e "${CYAN}Attempting to delete cron job for '$selected_service_name'...${RESET}"

  local temp_cron_file=$(mktemp)
  if ! sudo crontab -l &> /dev/null; then
      print_error "Crontab is empty or not accessible. Nothing to delete."
      rm -f "$temp_cron_file"
      echo ""
      echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
      read -p ""
      return 1
  fi
  sudo crontab -l > "$temp_cron_file"

  # Remove existing cron jobs for both FRPulse and Hysteria for this service
  sed -i "/# FRPulse automated restart for $selected_service_name$/d" "$temp_cron_file"
  sed -i "/# Hysteria automated restart for $selected_service_name$/d" "$temp_cron_file"

  echo "$cron_job_entry" >> "$temp_cron_file"

  if sudo crontab "$temp_cron_file"; then
    print_success "Successfully removed scheduled restart for '$selected_service_name'."
    echo -e "${WHITE}You can verify with: ${YELLOW}sudo crontab -l${RESET}"
  else
    print_error "Failed to delete cron job. It might not exist or there's a permission issue.${RESET}"
  fi

  rm -f "$temp_cron_file"

  echo ""
  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
  read -p ""
}

# Uninstall Backhaul Action
uninstall_backhaul_action() {
  clear
  echo ""
  echo -e "${RED}⚠️ Are you sure you want to uninstall Backhaul and remove all associated files and services? (y/N): ${RESET}"
  read -p "" confirm
  echo ""

  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "🧹 Uninstalling Backhaul and cleaning up..."

    # Stop and remove services
    echo "Searching for Backhaul services to remove..."
    # Only target services created by this script (backhaul-server-* and backhaul-client-*)
    mapfile -t backhaul_services < <(sudo systemctl list-unit-files --full --no-pager | grep -E '^backhaul-(server|client)-.*\.service' | awk '{print $1}')

    if [ ${#backhaul_services[@]} -gt 0 ]; then
      echo "🛑 Stopping and disabling Backhaul services..."
      for service_file in "${backhaul_services[@]}"; do
        local service_name=$(basename "$service_file")
        echo "  - Processing $service_name..."
        sudo systemctl stop "$service_name" > /dev/null 2>&1
        sudo systemctl disable "$service_name" > /dev/null 2>&1
        sudo rm -f "/etc/systemd/system/$service_name" > /dev/null 2>&1
      done
      print_success "Backhaul services have been stopped, disabled, and removed."
    else
      echo "⚠️ No Backhaul services found to remove."
    fi

    sudo systemctl daemon-reload

    # Remove binary
    if [ -f "/usr/local/bin/backhaul" ]; then
      echo "🗑️ Removing Backhaul binary..."
      sudo rm -f "/usr/local/bin/backhaul"
      print_success "Backhaul binary removed."
    fi

    # Remove config folder
    if [ -d "$(pwd)/backhaul" ]; then
      echo "🗑️ Removing 'backhaul' config folder..."
      rm -rf "$(pwd)/backhaul"
      print_success "'backhaul' config folder removed successfully."
    fi

    # Remove cron jobs
    echo -e "${CYAN}🧹 Removing any associated Backhaul cron jobs...${RESET}"
    (sudo crontab -l 2>/dev/null | grep -v "# Backhaul automated restart for") | sudo crontab -
    print_success "Associated cron jobs removed."

    # Remove setup marker file
    if [ -f "$SETUP_MARKER_FILE" ]; then
      echo "🗑️ Removing setup marker file..."
      sudo rm -f "$SETUP_MARKER_FILE"
      print_success "Setup marker file removed."
    fi

    print_success "Backhaul uninstallation and cleanup complete."
  else
    echo -e "${YELLOW}❌ Uninstall cancelled.${RESET}"
  fi
  echo ""
  echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
  read -p ""
}

# Install Backhaul Action
install_backhaul_action() {
  clear
  echo ""
  draw_line "$CYAN" "=" 40
  echo -e "${CYAN}     📥 Installing Backhaul${RESET}"
  draw_line "$CYAN" "=" 40
  echo ""

  echo -e "${CYAN}Detecting system architecture...${RESET}"
  local arch=$(uname -m)
  local backhaul_arch=""
  if [[ "$arch" == "x86_64" ]]; then
    backhaul_arch="amd64"
  elif [[ "$arch" == "aarch64" ]]; then
    backhaul_arch="arm64"
  else
    print_error "Unsupported architecture: $arch"
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -p ""
    return 1
  fi
  print_success "Architecture detected: $backhaul_arch"

  echo -e "${CYAN}Fetching latest Backhaul release version...${RESET}"
  local latest_version=$(curl -s https://api.github.com/repos/Musixal/Backhaul/releases/latest | grep "tag_name" | cut -d '"' -f 4)
  if [[ -z "$latest_version" ]]; then
    print_error "Failed to fetch latest version. Please check your internet connection."
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -p ""
    return 1
  fi
  print_success "Latest version: $latest_version"

  local download_url="https://github.com/Musixal/Backhaul/releases/download/${latest_version}/backhaul_linux_${backhaul_arch}.tar.gz"
  echo -e "${CYAN}Downloading Backhaul from: ${WHITE}$download_url${RESET}"
  
  if curl -L -o backhaul.tar.gz "$download_url"; then
    print_success "Download complete."
  else
    print_error "Download failed."
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -p ""
    return 1
  fi

  echo -e "${CYAN}Extracting and installing...${RESET}"
  tar -xzf backhaul.tar.gz
  if [ -f "backhaul" ]; then
    sudo mv backhaul /usr/local/bin/backhaul
    sudo chmod +x /usr/local/bin/backhaul
    rm -f backhaul.tar.gz
    print_success "Backhaul installed successfully to /usr/local/bin/backhaul"
  else
    print_error "Extraction failed or binary not found."
    rm -f backhaul.tar.gz
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -p ""
    return 1
  fi

  echo ""
  echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
  read -p ""
}

# New function for Port Hopping Configuration


# --- Initial Setup Function ---
# This function performs one-time setup tasks like installing dependencies
# and creating the 'trust' command symlink.
perform_initial_setup() {
  # Check if initial setup has already been performed
  if [ -f "$SETUP_MARKER_FILE" ]; then
    echo -e "${YELLOW}Initial setup already performed. Skipping prerequisites installation.${RESET}"
    return 0 # Exit successfully
  fi

  echo -e "${CYAN}Performing initial setup (installing dependencies)...${RESET}"

  # Install required tools
  echo -e "${CYAN}Updating package lists and installing dependencies...${RESET}"
  sudo apt update
  # Removed rustc and cargo from apt install list
  sudo apt install -y build-essential curl pkg-config libssl-dev git figlet certbot cron

  # Removed Rust-specific checks and installations
  # The script now assumes Hysteria's own installation handles its dependencies.

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
  draw_line "$CYAN" "=" 40
  echo -e "${CYAN}     ➕ Get New SSL Certificate${RESET}"
  draw_line "$CYAN" "=" 40
  echo ""

  echo -e "${CYAN}🌐 Domain and Email for SSL Certificate:${RESET}"
  echo -e "  (e.g., yourdomain.com)"
  
  local domain
  while true; do
    echo -e "👉 ${WHITE}Please enter your domain:${RESET} "
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
    echo -e "👉 ${WHITE}Please enter your email:${RESET} "
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
    echo -e "${CYAN}🔐 Requesting SSL certificate with Certbot...${RESET}"
    echo -e "${YELLOW}Ensure port 80 is open and not in use by another service.${RESET}"
    if sudo certbot certonly --standalone -d "$domain" --non-interactive --agree-tos -m "$email"; then
      print_success "SSL certificate obtained successfully for $domain."
    else
      print_error "❌ Failed to obtain SSL certificate for $domain. Check Certbot logs for details."
      print_error "   Ensure your domain points to this server and port 80 is open."
    fi
  fi
  echo ""
  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
  read -p ""
}

# --- New: Function to delete existing SSL certificates ---
delete_certificates_action() {
  clear
  echo ""
  draw_line "$RED" "=" 40
  echo -e "${RED}     🗑️ Delete SSL Certificates${RESET}"
  draw_line "$RED" "=" 40
  echo ""

  echo -e "${CYAN}🔍 Searching for existing SSL certificates...${RESET}"
  # Find directories under /etc/letsencrypt/live/ that are not 'README'
  mapfile -t cert_domains < <(sudo find /etc/letsencrypt/live -maxdepth 1 -mindepth 1 -type d ! -name "README" -exec basename {} \;)

  if [ ${#cert_domains[@]} -eq 0 ]; then
    print_error "No SSL certificates found to delete."
    echo ""
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return 0
  fi

  echo -e "${CYAN}📋 Please select a certificate to delete:${RESET}"
  # Add a "Back to previous menu" option
  cert_domains+=("Back to previous menu")
  select selected_domain in "${cert_domains[@]}"; do
    if [[ "$selected_domain" == "Back to previous menu" ]]; then
      echo -e "${YELLOW}Returning to previous menu...${RESET}"
      echo ""
      return 0
    elif [ -n "$selected_domain" ]; then
      break
    else
      print_error "Invalid selection. Please enter a valid number."
    fi
  done
  echo ""

  if [[ -z "$selected_domain" ]]; then
    print_error "No certificate selected. Aborting deletion."
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return 0
  fi

  echo -e "${RED}⚠️ Are you sure you want to delete the certificate for '$selected_domain'? (y/N): ${RESET}"
  read -p "" confirm_delete
  echo ""

  if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
    echo -e "${CYAN}🗑️ Deleting certificate for '$selected_domain' using Certbot...${RESET}"
    if sudo certbot delete --cert-name "$selected_domain"; then
      print_success "Certificate for '$selected_domain' deleted successfully."
    else
      print_error "❌ Failed to delete certificate for '$selected_domain'. Check Certbot logs."
    fi
  else
    echo -e "${YELLOW}Deletion cancelled for '$selected_domain'.${RESET}"
  fi

  echo ""
  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
  read -p ""
}

# Function to generate a self-signed certificate
generate_self_signed_cert_action() {
  clear
  echo ""
  draw_line "$CYAN" "=" 40
  echo -e "${CYAN}     📝 Generate Self-Signed Certificate${RESET}"
  draw_line "$CYAN" "=" 40
  echo ""
  
  echo -e "${YELLOW}⚠️  WARNING: Self-signed certificates only work with SNI Mode!${RESET}"
  echo -e "${YELLOW}    Do not use this for Strict Mode.${RESET}"
  echo ""

  local cert_name
  while true; do
    echo -e "👉 ${WHITE}Enter a name for this certificate (e.g., my-self-signed):${RESET} "
    read -p "" cert_name
    # Sanitize input
    cert_name=$(echo "$cert_name" | tr -cd '[:alnum:]_-')
    if [[ -n "$cert_name" ]]; then
      break
    else
      print_error "Certificate name cannot be empty."
    fi
  done
  echo ""

  local cert_dir="$(pwd)/hysteria/certs/selfsigned/$cert_name"
  if [ -d "$cert_dir" ]; then
    print_error "A certificate with this name already exists."
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return
  fi

  mkdir -p "$cert_dir"

  echo -e "${CYAN}Generating self-signed certificate...${RESET}"
  
  # Generate key and cert
  # using the name as CN
  if openssl req -x509 -newkey rsa:2048 -keyout "$cert_dir/privkey.pem" -out "$cert_dir/fullchain.pem" -sha256 -days 3650 -nodes -subj "/CN=$cert_name" 2>/dev/null; then
    print_success "Self-signed certificate generated successfully."
    echo -e "   Path: ${WHITE}$cert_dir${RESET}"
  else
    print_error "Failed to generate certificate. Please check if openssl is installed."
    rm -rf "$cert_dir" # Cleanup
  fi

  echo ""
  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
  read -p ""
}

# Function to delete self-signed certificates
delete_self_signed_cert_action() {
  clear
  echo ""
  draw_line "$RED" "=" 40
  echo -e "${RED}     🗑️ Delete Self-Signed Certificate${RESET}"
  draw_line "$RED" "=" 40
  echo ""

  local cert_base_dir="$(pwd)/hysteria/certs/selfsigned"
  
  if [ ! -d "$cert_base_dir" ]; then
     print_error "No self-signed certificates found."
     echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
     read -p ""
     return
  fi

  mapfile -t cert_names < <(find "$cert_base_dir" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)

  if [ ${#cert_names[@]} -eq 0 ]; then
    print_error "No self-signed certificates found."
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return
  fi

  echo -e "${CYAN}📋 Please select a certificate to delete:${RESET}"
  cert_names+=("Back to previous menu")
  select selected_cert in "${cert_names[@]}"; do
    if [[ "$selected_cert" == "Back to previous menu" ]]; then
      return
    elif [ -n "$selected_cert" ]; then
      break
    else
      print_error "Invalid selection."
    fi
  done

  echo -e "${RED}⚠️ Are you sure you want to delete '$selected_cert'? (y/N): ${RESET}"
  read -p "" confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
      rm -rf "$cert_base_dir/$selected_cert"
      print_success "Certificate deleted."
  else
      echo -e "${YELLOW}Cancelled.${RESET}"
  fi
  
  echo ""
  echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
  read -p ""
}

# Self-signed certificate menu
self_signed_certificate_menu() {
  while true; do
    clear
    echo ""
    draw_line "$CYAN" "=" 40
    echo -e "${CYAN}     📝 Self-Signed Certificates${RESET}"
    draw_line "$CYAN" "=" 40
    echo ""
    echo -e "  ${YELLOW}1)${RESET} ${WHITE}Generate new certificate${RESET}"
    echo -e "  ${YELLOW}2)${RESET} ${WHITE}Delete certificate${RESET}"
    echo -e "  ${YELLOW}3)${RESET} ${WHITE}Back to previous menu${RESET}"
    echo ""
    read -p "👉 Your choice: " choice
    case $choice in
      1) generate_self_signed_cert_action ;;
      2) delete_self_signed_cert_action ;;
      3) break ;;
      *) print_error "Invalid option." ;;
    esac
  done
}

# --- New: Certificate Management Menu Function ---
certificate_management_menu() {
  while true; do
    clear
    echo ""
    draw_line "$YELLOW" "=" 40
    echo -e "${CYAN}     🔐 Certificate Management${RESET}"
    draw_line "$YELLOW" "=" 40
    echo ""
    echo -e "  ${YELLOW}1)${RESET} ${WHITE}Get new certificate${RESET}"
    echo -e "  ${YELLOW}2)${RESET} ${WHITE}Delete certificates${RESET}"
    echo -e "  ${YELLOW}3)${RESET} ${WHITE}Self signed certificate${RESET}"
    echo -e "  ${YELLOW}4)${RESET} ${WHITE}Back to main menu${RESET}"
    echo ""
    draw_line "$YELLOW" "-" 40
    echo -e "👉 ${CYAN}Your choice:${RESET} "
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
        self_signed_certificate_menu
        ;;
      4)
        echo -e "${YELLOW}Returning to main menu...${RESET}"
        break # Break out of this while loop to return to main menu
        ;;
      *)
        echo -e "${RED}❌ Invalid option.${RESET}"
        echo ""
        echo -e "${YELLOW}Press Enter to continue...${RESET}"
        read -p ""
        ;;
    esac
  done
}

# --- New function to check Backhaul installation status ---
check_backhaul_installation_status() {
  if command -v backhaul &> /dev/null; then
    echo -e "${GREEN}Installed ✅${RESET}"
  else
    echo -e "${RED}Not Installed ❌${RESET}"
  fi
}

# --- Main Script Execution ---
set -e # Exit immediately if a command exits with a non-zero status

# Perform initial setup (will run only once)
perform_initial_setup || { echo "Initial setup failed. Exiting."; exit 1; }

# Removed Rust readiness check as it's no longer installed by this script's initial setup.
# The Hysteria installation script is responsible for its own dependencies.

while true; do
  # Clear terminal and show logo
  clear
  echo -e "${CYAN}"
  figlet -f slant "WGTunnel"
  echo -e "${CYAN}"
  draw_line "$CYAN" "=" 80 # Decorative line
  echo ""
  echo -e "Developed by ErfanXRay => ${BOLD_GREEN}https://github.com/Erfan-XRay/HPulse${RESET}"
  echo -e "Telegram Channel => ${BOLD_GREEN}@Erfan_XRay${RESET}"
  echo -e "Tunnel script for ${CYAN}WireGuard & OpenVPN${RESET} (Backhaul UDP)"
  echo ""
  # Get server IP addresses
  SERVER_IPV4=$(hostname -I | awk '{print $1}')
  # SERVER_IPV6=$(hostname -I | awk '{print $2}') # This might be empty if no IPv6


  draw_line "$CYAN" "=" 40 # Decorative line
  echo -e "${CYAN}     🌐 Server Information${RESET}"
  draw_line "$CYAN" "=" 40 # Decorative line
  echo -e "  ${WHITE}IPv4 Address: ${YELLOW}$SERVER_IPV4${RESET}"
  echo -e "  ${WHITE}Backhaul Status: $(check_backhaul_installation_status)${RESET}"
  echo -e "  ${WHITE}Script Version: ${YELLOW}$SCRIPT_VERSION${RESET}"
  draw_line "$CYAN" "=" 40 # Decorative line
  echo "" # Added for spacing

  # Menu
  echo "Select an option:"
  echo ""
  echo -e "${MAGENTA}1) Install Backhaul (UDP Tunnel)${RESET}"
  echo -e "${CYAN}2) Backhaul tunnel management${RESET}"
  echo -e "${RED}3) Uninstall WGTunnel and cleanup${RESET}"
  echo -e "${WHITE}4) Exit${RESET}"
  echo ""
  read -p "👉 Your choice: " choice

  case $choice in
    1)
      install_backhaul_action
      ;;
    2) # Backhaul tunnel management
      while true; do
        clear
        echo ""
        draw_line "$CYAN" "=" 40
        echo -e "${CYAN}     🌐 Backhaul Tunnel Management${RESET}"
        draw_line "$CYAN" "=" 40
        echo ""
        echo -e "  ${YELLOW}1)${RESET} ${MAGENTA}Add Backhaul Server${RESET}"
        echo -e "  ${YELLOW}2)${RESET} ${BLUE}Add Backhaul Client${RESET}"
        echo -e "  ${YELLOW}3)${RESET} ${WHITE}Return to main menu${RESET}"
        echo ""
        draw_line "$CYAN" "-" 40
        echo -e "👉 ${CYAN}Your choice:${RESET} "
        read -p "" backhaul_tunnel_choice
        echo ""

        case $backhaul_tunnel_choice in
          1)
            add_new_backhaul_server_action
            ;;
          2)
            add_new_backhaul_client_action
            ;;
          3)
            echo -e "${YELLOW}Returning to main menu...${RESET}"
            break
            ;;
          *)
            echo -e "${RED}❌ Invalid option.${RESET}"
            echo ""
            echo -e "${YELLOW}Press Enter to continue...${RESET}"
            read -p ""
            ;;
        esac
      done
      ;;
    3) # Uninstall WGTunnel and cleanup
      uninstall_backhaul_action
      ;;
    4) # Exit
      exit 0
      ;;
    *)
      echo -e "${RED}❌ Invalid choice. Exiting.${RESET}"
      echo ""
      echo -e "${YELLOW}Press Enter to continue...${RESET}"
      read -p ""
    ;;
  esac
  echo ""
done

# New function for adding a Backhaul server
add_new_backhaul_server_action() {
  clear
  echo ""
  draw_line "$CYAN" "=" 40
  echo -e "${CYAN}     ➕ Add New Backhaul Server${RESET}"
  draw_line "$CYAN" "=" 40
  echo ""

  # Check for backhaul executable
  if ! command -v backhaul &> /dev/null; then
    echo -e "${RED}❗ Backhaul executable (backhaul) not found.${RESET}"
    echo -e "${YELLOW}Please run 'Install Backhaul' option from the main menu first.${RESET}"
    echo ""
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -p ""
    return
  fi

  local server_name
  while true; do
    echo -e "👉 ${CYAN}Enter server name (e.g., myserver, only alphanumeric, hyphens, underscores allowed):${RESET} "
    read -p "" server_name_input
    server_name=$(echo "$server_name_input" | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')
    if [[ -n "$server_name" ]]; then
      break
    else
      print_error "Server name cannot be empty!"
    fi
  done
  echo ""

  local service_name="backhaul-server-$server_name"
  local config_dir="$(pwd)/backhaul"
  local config_file_path="$config_dir/backhaul-server-$server_name.toml"
  local service_file="/etc/systemd/system/${service_name}.service"

  if [ -f "$service_file" ]; then
    echo -e "${RED}❌ Service with this name already exists: $service_name.${RESET}"
    echo ""
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return
  fi

  mkdir -p "$config_dir"

  echo -e "${CYAN}⚙️ Server Configuration:${RESET}"

  local listen_port
  while true; do
    echo -e "👉 ${WHITE}Enter tunnel listen port (1-65535, e.g., 3000):${RESET} "
    read -p "" listen_port_input
    listen_port=${listen_port_input:-3000}
    if validate_port "$listen_port"; then
      break
    else
      print_error "Invalid port number."
    fi
  done
  echo ""

  local token
  while true; do
    echo -e "👉 ${WHITE}Enter token (password) for the tunnel:${RESET} "
    read -p "" token
    if [[ -n "$token" ]]; then
      break
    else
      print_error "Token cannot be empty!"
    fi
  done
  echo ""

  # Create the Backhaul server config file (TOML)
  echo -e "${CYAN}📝 Creating backhaul-server-${server_name}.toml configuration file...${RESET}"
  cat <<EOF > "$config_file_path"
[server]
bind_addr = "0.0.0.0:$listen_port"
transport = "tcp"
token = "$token"
heartbeat = 40
EOF
  print_success "backhaul-server-${server_name}.toml created successfully at $config_file_path"

  # Create the systemd service file
  echo -e "${CYAN}🔧 Creating systemd service file for Backhaul server '$server_name'...${RESET}"
  cat <<EOF | sudo tee "$service_file" > /dev/null
[Unit]
Description=Backhaul Server - $server_name
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/backhaul -c "$config_file_path"
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

  echo -e "${CYAN}🔧 Reloading systemd daemon...${RESET}"
  sudo systemctl daemon-reload

  echo -e "${CYAN}🚀 Enabling and starting Backhaul service '$service_name'...${RESET}"
  sudo systemctl enable "$service_name" > /dev/null 2>&1
  sudo systemctl start "$service_name" > /dev/null 2>&1

  print_success "Backhaul server '$server_name' started as $service_name"

  echo ""
  echo -e "${YELLOW}Do you want to view the logs for $service_name now? (y/N): ${RESET}"
  read -p "" view_logs_choice
  echo ""

  if [[ "$view_logs_choice" =~ ^[Yy]$ ]]; then
    show_service_logs "$service_name"
  fi

  echo ""
  echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
  read -p ""
}

# New function for adding a Backhaul client
add_new_backhaul_client_action() {
  clear
  echo ""
  draw_line "$CYAN" "=" 40
  echo -e "${CYAN}     ➕ Add New Backhaul Client${RESET}"
  draw_line "$CYAN" "=" 40
  echo ""

  # Check for backhaul executable
  if ! command -v backhaul &> /dev/null; then
    echo -e "${RED}❗ Backhaul executable (backhaul) not found.${RESET}"
    echo -e "${YELLOW}Please run 'Install Backhaul' option from the main menu first.${RESET}"
    echo ""
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -p ""
    return
  fi

  local client_name
  while true; do
    echo -e "👉 ${CYAN}Enter client name (e.g., myclient, alphanumeric, hyphens, underscores only):${RESET} "
    read -p "" client_name_input
    client_name=$(echo "$client_name_input" | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')
    if [[ -n "$client_name" ]]; then
      break
    else
      print_error "Client name cannot be empty!"
    fi
  done
  echo ""

  local service_name="backhaul-client-$client_name"
  local config_dir="$(pwd)/backhaul"
  local config_file_path="$config_dir/backhaul-client-$client_name.toml"
  local service_file="/etc/systemd/system/${service_name}.service"

  if [ -f "$service_file" ]; then
    echo -e "${RED}❌ Service with this name already exists: $service_name.${RESET}"
    echo ""
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -p ""
    return
  fi

  mkdir -p "$config_dir"

  echo -e "${CYAN}⚙️ Client Configuration:${RESET}"

  local server_address
  while true; do
    echo -e "👉 ${WHITE}Enter server IP address:${RESET} "
    read -p "" server_address
    if validate_host "$server_address"; then
      break
    else
      print_error "Invalid IP address."
    fi
  done
  echo ""

  local server_port
  while true; do
    echo -e "👉 ${WHITE}Enter server tunnel port (e.g., 3000):${RESET} "
    read -p "" server_port
    if validate_port "$server_port"; then
      break
    else
      print_error "Invalid port."
    fi
  done
  echo ""

  local token
  while true; do
    echo -e "👉 ${WHITE}Enter token (password):${RESET} "
    read -p "" token
    if [[ -n "$token" ]]; then
      break
    else
      print_error "Token cannot be empty!"
    fi
  done
  echo ""

  echo -e "${CYAN}Configure Tunnel Service (WireGuard/OpenVPN):${RESET}"
  local svc_name
  while true; do
    echo -e "👉 ${WHITE}Enter service name (e.g., wg0):${RESET} "
    read -p "" svc_name
    if [[ -n "$svc_name" ]]; then
      break
    else
      print_error "Service name cannot be empty!"
    fi
  done
  echo ""

  local local_port
  while true; do
    echo -e "👉 ${WHITE}Enter Local Port (Iran) to listen on (e.g., 51820):${RESET} "
    read -p "" local_port
    if validate_port "$local_port"; then
      break
    else
      print_error "Invalid port."
    fi
  done
  echo ""

  local remote_port
  while true; do
    echo -e "👉 ${WHITE}Enter Remote Port (Kharej) to forward to (e.g., 51820):${RESET} "
    read -p "" remote_port
    if validate_port "$remote_port"; then
      break
    else
      print_error "Invalid port."
    fi
  done
  echo ""

  # Create the Backhaul client config file (TOML)
  echo -e "${CYAN}📝 Creating backhaul-client-${client_name}.toml configuration file...${RESET}"
  cat <<EOF > "$config_file_path"
[client]
remote_addr = "$server_address:$server_port"
transport = "tcp"
token = "$token"
connection_pool = 8

[[services]]
name = "$svc_name"
local_addr = "0.0.0.0:$local_port"
remote_addr = "127.0.0.1:$remote_port"
type = "udp"
EOF
  print_success "backhaul-client-${client_name}.toml created successfully at $config_file_path"

  # Create the systemd service file
  echo -e "${CYAN}🔧 Creating systemd service file for Backhaul client '$client_name'...${RESET}"
  cat <<EOF | sudo tee "$service_file" > /dev/null
[Unit]
Description=Backhaul Client - $client_name
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/backhaul -c "$config_file_path"
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

  echo -e "${CYAN}🔧 Reloading systemd daemon...${RESET}"
  sudo systemctl daemon-reload

  echo -e "${CYAN}🚀 Enabling and starting Backhaul service '$service_name'...${RESET}"
  sudo systemctl enable "$service_name" > /dev/null 2>&1
  sudo systemctl start "$service_name" > /dev/null 2>&1

  print_success "Backhaul client '$client_name' started as $service_name"

  echo ""
  echo -e "${YELLOW}Do you want to view the logs for $service_name now? (y/N): ${RESET}"
  read -p "" view_logs_choice
  echo ""

  if [[ "$view_logs_choice" =~ ^[Yy]$ ]]; then
    show_service_logs "$service_name"
  fi

  echo ""
  echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
  read -p ""
}
