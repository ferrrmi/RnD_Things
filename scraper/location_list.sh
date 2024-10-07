#!/bin/bash

# Define file paths
# hosts_file="/home/parkee/deployment/parkee-deployment/ansible/inventory/hosts"
# output_file="/home/parkee/deployment/parkee-deployment/ansible/files/data_collection/location_list.txt"

hosts_file="./hosts"
output_file="./location_list.txt"

# Function to log info messages with a timestamp
log_info() {
    local message=$1
    echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] $message"
}

# Function to scrape and sync server codes
scrape_and_sync() {
    log_info "Starting the scraping and syncing process."

    # Get start time and date
    start_time=$(date +%s)
    start_date=$(date +"%Y-%m-%d %H:%M:%S")

    # Empty the output file
    > "$output_file"
    log_info "Emptied the file: $output_file"

    # Find the line numbers for the range
    start_line=$(awk '/\[servers:children\]/{print NR; exit}' "$hosts_file")
    end_line=$(awk '/###endserverhosts###/{print NR; exit}' "$hosts_file")

    log_info "Extracting lines between [servers:children] (line $start_line) and ###endserverhosts### (line $end_line)."

    # Extract lines between [servers:children] and ###endserverhosts###
    extracted_lines=$(awk "NR>=$start_line && NR<=$end_line" "$hosts_file")

    # Show extracted lines
    log_info "Extracted lines:"
    echo "$extracted_lines"
    echo

    # Extract unique server codes and save to the output file
    unique_codes=$(echo "$extracted_lines" | grep -oP '_\K[0-9a-z]{3}(?=_server)' | sort | uniq)
    echo "$unique_codes" > "$output_file"

    # Show total unique codes synced
    total_unique=$(echo "$unique_codes" | wc -l)
    log_info "Total unique codes synced to $output_file: $total_unique"

    # Get end time and date
    end_time=$(date +%s)
    end_date=$(date +"%Y-%m-%d %H:%M:%S")

    # Calculate the duration
    duration=$((end_time - start_time))

    # Display the information
    log_info "Line start at: $start_line"
    log_info "Line end at: $end_line"
    log_info "Start date at: $start_date"
    log_info "End date at: $end_date"
    log_info "Duration: ${duration}s"

    log_info "Scraping and syncing process completed."
}

# Call the function
scrape_and_sync
