#!/bin/bash

# Define file paths and directories
BASE_DIR="/home/parkee/deployment/parkee-deployment/ansible"
hosts_file="$BASE_DIR/inventory/hosts"
location_list="$BASE_DIR/files/data_collection/location_list.txt"
dir_to_remove="/home/parkee/server-backups/client_specification_activity"
BASE_DIR_LOG="/home/parkee/Documents/ansible-log"
LOG_FILE="$BASE_DIR_LOG/SPA_client_specification_activity_$(date +'%Y-%m-%d_%H-%M-%S').log"

# ANSI color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to log info messages with a timestamp
log_info() {
    local message=$1
    echo -e "${BLUE}$(date +"%Y-%m-%d %H:%M:%S") [INFO]${NC} $message"
}

# Function to print boxed information
print_box() {
    local title="$1"
    local content="$2"
    local border_char="="
    local border=$(printf "%0.s$border_char" {1..50})
    
    echo -e "\n${YELLOW}$border"
    echo -e ":: $title ::"
    echo -e "$border${NC}"
    echo -e "$content"
    echo -e "${YELLOW}$border${NC}\n"
}

# Function to calculate duration
calculate_duration() {
    local start_time=$1
    local end_time=$2
    local duration=$((end_time - start_time))
    local hours=$((duration / 3600))
    local minutes=$(( (duration % 3600) / 60 ))
    local seconds=$((duration % 60))
    printf "%02d:%02d:%02d" $hours $minutes $seconds
}

# Function to remove old files inside a directory but keep the directory
remove_old_files() {
    log_info "Starting removal of files inside $dir_to_remove"

    if [ -d "$dir_to_remove" ]; then
        rm -rf "$dir_to_remove"/*
        if [ $? -eq 0 ]; then
            log_info "Successfully removed files inside: $dir_to_remove"
        else
            log_info "Failed to remove files inside: $dir_to_remove"
        fi
    else
        log_info "Directory does not exist: $dir_to_remove"
    fi
}

# Function to scrape and sync server codes
scrape_and_sync() {
    log_info "Starting the scraping and syncing process."

    local start_time=$(date +%s)
    local start_date=$(date +"%Y-%m-%d %H:%M:%S")

    > "$location_list"
    log_info "Emptied the file: $location_list"

    local start_line=$(awk '/\[servers:children\]/{print NR; exit}' "$hosts_file")
    local end_line=$(awk '/###endserverhosts###/{print NR; exit}' "$hosts_file")

    log_info "Extracting lines between [servers:children] (line $start_line) and ###endserverhosts### (line $end_line)."

    local extracted_lines=$(awk "NR>=$start_line && NR<=$end_line" "$hosts_file")
    local unique_codes=$(echo "$extracted_lines" | grep -oP '_\K[0-9a-z]{3}(?=_server)' | sort | uniq)
    echo "$unique_codes" > "$location_list"

    local total_unique=$(echo "$unique_codes" | wc -l)
    local end_time=$(date +%s)
    local end_date=$(date +"%Y-%m-%d %H:%M:%S")
    local duration=$(calculate_duration $start_time $end_time)

    local info_content="Start Date: $start_date
End Date: $end_date
Duration: $duration
Total unique codes: $total_unique"

    print_box "Sync Process Information" "$info_content"
}

# Function to run ansible-playbooks with location codes from location_list.txt
run_playbooks() {
    cd "$BASE_DIR" || exit
    log_info "Changed directory to $BASE_DIR"

    local script_start_time=$(date +%s)
    local script_start_date=$(date +"%Y-%m-%d %H:%M:%S")

    while read -r loc_code; do
        if [[ -n "$loc_code" ]]; then
            local playbook_start_time=$(date +%s)
            local playbook_start_date=$(date +"%Y-%m-%d %H:%M:%S")
            
            log_info "Running ansible-playbook for location code: $loc_code"
            ansible-playbook SPA_client_specification_activity.yml -e "loc_code=$loc_code" -vv
            
            local playbook_end_time=$(date +%s)
            local playbook_end_date=$(date +"%Y-%m-%d %H:%M:%S")
            local playbook_duration=$(calculate_duration $playbook_start_time $playbook_end_time)
            
            local location_info="Location Code: $loc_code
Start Date: $playbook_start_date
End Date: $playbook_end_date
Duration: $playbook_duration"
            
            print_box "Location Run Information" "$location_info"
        fi
    done < "$location_list"

    log_info "All location codes processed. Running the SPA_sender.yml playbook."
    ansible-playbook SPA_sender.yml -v -e "modul_type=client_specification_activity"

    local script_end_time=$(date +%s)
    local script_end_date=$(date +"%Y-%m-%d %H:%M:%S")
    local script_duration=$(calculate_duration $script_start_time $script_end_time)

    local script_info="Start Script: $script_start_date
End Script: $script_end_date
Total Duration: $script_duration"

    print_box "Script Information Detail" "$script_info"
}

# Main execution
{
    remove_old_files
    scrape_and_sync
    run_playbooks
} &> >(tee -a "$LOG_FILE")