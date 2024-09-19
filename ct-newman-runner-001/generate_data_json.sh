#!/bin/bash

# Configuration
BOT_TOKEN="5931041111:AAF7aAfq0taY22mLoEw-TvcrGfX30oOaWRM"
API_ENDPOINT="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
CHAT_ID="-1002004613421"
DIR="/home/server-qaa/Codes/docker_files/PAA/index/postman"
OUTPUT_FILE="$DIR/data.json"
ERROR_LOG="$DIR/error.log"
SCRIPT_LOG="$DIR/generate_data_json.log"

# Function to log errors
log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error in file $1: $2" >> "$ERROR_LOG"
}

# Function to send Telegram message
send_telegram_message() {
    local message="$1"
    local response

    if [[ -z "$API_ENDPOINT" || -z "$CHAT_ID" ]]; then
        echo "Error: API endpoint or chat ID is not set."
        return 1
    fi

    # Print the message before sending
    echo "Sending the following message to Telegram:"
    echo -e "$message"
    echo "----------------------------------------"

    response=$(curl -s -X POST "$API_ENDPOINT" \
        -d "chat_id=$CHAT_ID" \
        -d "text=$message" \
        -d "parse_mode=HTML")

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to send Telegram message. Curl error: $?"
        return 1
    fi

    if echo "$response" | jq -e '.ok == false' > /dev/null; then
        echo "Error: Telegram API returned an error. Response: $response"
        return 1
    fi

    echo "Message sent successfully to Telegram."
    return 0
}

# Function to process a single HTML file
process_html_file() {
    local file="$1"
    local fileName=$(basename "$file")
    local filePath="/postman/html/$fileName"
    local dateTime=$(stat -c %y "$file" | cut -d'.' -f1)
    local fileDate=$(date -d "$dateTime" +%Y-%m-%d)
    local currentDate=$(date +%Y-%m-%d)

    local failedTests=$(grep -A1 "Total Failed Tests" "$file" | grep "display" | sed -E 's/<[^>]+>//g' | tr -d '[:space:]')
    
    if [[ ! "$failedTests" =~ ^[0-9]+$ ]]; then
        log_error "$fileName" "Failed to extract number of failed tests"
        failedTests=0
    fi
    
    local testRunStatus=$([[ "$failedTests" -eq 0 ]] && echo "PASSED" || echo "FAILED")
    
    # Append to JSON file
    echo "{" >> "$OUTPUT_FILE"
    cat << EOF >> "$OUTPUT_FILE"
        "fileName": "$fileName",
        "filePath": "$filePath",
        "dateTime": "$dateTime",
        "failedTests": $failedTests,
        "testRunStatus": "$testRunStatus"
EOF
    echo "}" >> "$OUTPUT_FILE"

    # Return status if this is for today
    if [[ "$fileDate" == "$currentDate" ]]; then
        [[ "$testRunStatus" == "PASSED" ]] && return 0 || return 2
    else
        return 1  # Not today's file
    fi
}

# Function to process all HTML files
process_html_files() {
    local total_runs=0
    local passed_runs=0
    local failed_runs=0
    local first_entry=true

    # Start JSON array
    echo "[" > "$OUTPUT_FILE"

    for file in "$DIR"/html/*report*.html; do
        if [[ -f "$file" ]]; then  # Check if file exists and is a regular file
            # Avoid adding a comma before the first entry
            if ! $first_entry; then
                echo "," >> "$OUTPUT_FILE"
            else
                first_entry=false
            fi

            process_html_file "$file"
            case $? in
                0) ((passed_runs++)); ((total_runs++)) ;;
                2) ((failed_runs++)); ((total_runs++)) ;;
            esac
        fi
    done

    # Close JSON array
    echo "]" >> "$OUTPUT_FILE"

    if [[ $total_runs -gt 0 ]]; then
        notification_message="<b>-- Newman Bulk Test Notify --</b>

<b>Date:</b> $(date +%Y-%m-%d)
<b>Total Test Runs Passed:</b> $passed_runs
<b>Total Test Runs Failed:</b> $failed_runs"
        return 0
    else
        echo "No test run files found for today's date ($(date +%Y-%m-%d))"
        return 1
    fi
}


# Main function
main() {
    echo "Error log for script run on $(date '+%Y-%m-%d %H:%M:%S')" > "$ERROR_LOG"

    if process_html_files; then
        echo "JSON data generated and saved to $OUTPUT_FILE"
        echo "Error log saved to $ERROR_LOG"
        send_telegram_message "$notification_message"
    else
        echo "No data to process. JSON file contains empty array."
    fi
}

# Run the main function and redirect all output to the log file
{
    truncate -s 0 "$SCRIPT_LOG"
    main &> "$SCRIPT_LOG"
}
