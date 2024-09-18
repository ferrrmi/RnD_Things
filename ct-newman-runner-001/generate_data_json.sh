#!/bin/bash

# Telegram credentials
BOT_TOKEN="5931041111:AAF7aAfq0taY22mLoEw-TvcrGfX30oOaWRM"
API_ENDPOINT="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
CHAT_ID="-1002123325894"

# Define the directory containing the HTML files
DIR="/home/server-qaa/Codes/docker_files/PAA/index/postman"
# Define the output JSON file
OUTPUT_FILE="$DIR/data.json"
# Define the error log file
ERROR_LOG="$DIR/error.log"

# Function to log errors
log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error in file $1: $2" >> "$ERROR_LOG"
}

# Function to send Telegram message
send_telegram_message() {
    local message="$1"
    curl -s -X POST "$API_ENDPOINT" -d chat_id="$CHAT_ID" -d text="$message" -d "parse_mode=HTML"
}

# Initialize the JSON structure
echo "[" > "$OUTPUT_FILE"

# Initialize error log
echo "Error log for script run on $(date '+%Y-%m-%d %H:%M:%S')" > "$ERROR_LOG"

# Initialize variables for notification
notification_message="<b>-- Newman Bulk Test Notify --</b>\n\n"
current_date=$(date '+%Y-%m-%d')

# Iterate over each HTML file in the directory that matches the 'report' pattern
first=1
for file in "$DIR"/html/*report*.html; do
    # Check if the file exists to avoid processing non-matching patterns
    if [ -e "$file" ]; then
        # Get the file name
        fileName=$(basename "$file")
        
        # Get the relative file path
        filePath="/postman/html/$fileName"
        
        # Get the last modification time in a readable format
        dateTime=$(stat -c %y "$file" | cut -d'.' -f1)  # Remove milliseconds

        # Extract the number of failed tests
        failedTests=$(grep -A1 "Total Failed Tests" "$file" | grep "display" | sed 's/<[^>]*>//g' | tr -d '\n ')

        # Check if failedTests is empty or not a number
        if [ -z "$failedTests" ] || ! [[ "$failedTests" =~ ^[0-9]+$ ]]; then
            log_error "$fileName" "Failed to extract number of failed tests"
            failedTests=0  # Set a default value
        fi

        # Determine test run status
        if [ "$failedTests" -gt 0 ]; then
            testRunStatus="FAILED"
        else
            testRunStatus="PASSED"
        fi
        
        # Append file information to the JSON file
        if [ $first -eq 1 ]; then
            first=0
        else
            echo "," >> "$OUTPUT_FILE"
        fi
        
        echo "    {" >> "$OUTPUT_FILE"
        echo "        \"fileName\": \"$fileName\"," >> "$OUTPUT_FILE"
        echo "        \"filePath\": \"$filePath\"," >> "$OUTPUT_FILE"
        echo "        \"dateTime\": \"$dateTime\"," >> "$OUTPUT_FILE"
        echo "        \"failedTests\": $failedTests," >> "$OUTPUT_FILE"
        echo "        \"testRunStatus\": \"$testRunStatus\"" >> "$OUTPUT_FILE"
        echo "    }" >> "$OUTPUT_FILE"

        # Append to notification message
        notification_message+="<b>Date:</b> $dateTime\n"
        notification_message+="<b>Filename:</b> $fileName\n"
        notification_message+="<b>Status:</b> $testRunStatus\n"
        notification_message+="<b>Total Failed Tests:</b> $failedTests\n\n"
    fi
done

# Close the JSON array
echo "]" >> "$OUTPUT_FILE"

# Print completion message
echo "JSON data generated and saved to $OUTPUT_FILE"
echo "Error log saved to $ERROR_LOG"

# Send Telegram notification
send_telegram_message "$notification_message"
echo "Telegram notification sent for all processed files."