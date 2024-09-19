#!/bin/bash

# Path to the lock file
PIDFILE="/tmp/newman_bash_script.pid"

# Function to check for an existing lock file
function ensure_single_instance() {
    if [[ -e "$PIDFILE" ]]; then
        if kill -0 $(cat "$PIDFILE") > /dev/null 2>&1; then
            echo "Another instance is already running. Exiting."
            exit 1
        else
            # Stale PID file, remove it
            rm -f "$PIDFILE"
        fi
    fi

    # Create a new lock file with the current PID
    echo $$ > "$PIDFILE"
}

# Function to clean up the lock file on exit
function cleanup {
    rm -f "$PIDFILE"
}

# Register the cleanup function to be called on script exit
trap cleanup EXIT

# The main script logic
function main() {
    # Record the start time
    start_time=$(date +%s)

    # Activate the virtual environment
    source /root/.venv/bin/activate

    # Navigate to the 'newman' directory if needed
    cd /opt/app/agent/newman

    # Run the Python script
    python3 newman.py

    # Deactivate the virtual environment after running the script (optional)
    deactivate

    # Record the end time
    end_time=$(date +%s)

    # Calculate the duration in seconds
    duration=$((end_time - start_time))

    # Output the duration
    echo "Duration: ${duration} seconds"
}

function truncate_log() {
    cd /opt/app/agent/newman
    truncate -s 0 run_newman.log
    truncate -s 0 newman-py.log
}

# Ensure only a single instance runs
ensure_single_instance

(
    truncate_log
    main &> /opt/app/agent/newman/run_newman.log
)
