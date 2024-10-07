#!/bin/bash
# pawdog_restore_server.sh
# Version: 3.0.0
# Last Modified: 2024-10-07

# configuration
UUID_EXTERNAL_STORAGE=""
PC_USERNAME=""
LOG_FILE="/var/log/agent/pawdog_restore_server.log"
BOT_TOKEN="5931041111:AAF7aAfq0taY22mLoEw-TvcrGfX30oOaWRM"
API_ENDPOINT="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

# chat id production
CHAT_ID="-1002123325894"

# chat id staging
# CHAT_ID="-1002004613421"

# Function to log messages with INFO level
function log_message() {
    local message=$1
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] $message"
}

function add_hashtag_to_kafka_service() {
    local file="/etc/systemd/system/kafka.service"
    local search_pattern='Environment="KAFKA_OPTS=-javaagent:/etc/kafka/libs/jmx_prometheus_javaagent.jar=[0-9]+:/etc/kafka/config/jmx_exporter.yml"'

    # Check if the file exists
    if [ ! -f "$file" ]; then
        echo "Error: $file does not exist."
        return 1
    else
        echo "File found: $file"
    fi

    # Find the matching line
    local found_line=$(grep -E "$search_pattern" "$file")
    if [ -z "$found_line" ]; then
        echo "Error: Pattern not found in $file"
        return 1
    else
        echo "Pattern found: $found_line"
    fi

    # Add hashtag in front of "Environment"
    if sed -i.bak 's/^Environment/#Environment/' "$file" 2>/dev/null; then
        echo "Sed command executed successfully."
    else
        echo "Error: Sed command failed. Trying alternative method."
        # Alternative method using temp file
        sed 's/^Environment/#Environment/' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    fi

    # Check if the replacement was successful
    if grep -q "^#Environment" "$file"; then
        echo "Hashtag added successfully. Updated line:"
        grep "^#Environment" "$file"
        return 0
    else
        echo "Error: Failed to add hashtag to the Environment line in $file"
        return 1
    fi
}

function logrotate_handler() {
    local OLD_STORAGE_PATH="/media/$PC_USERNAME/$UUID_EXTERNAL_STORAGE"
    local OLD_STORAGE_ETC_LOGROTATE_PATH="$OLD_STORAGE_PATH/etc/logrotate.d"
    local NEW_STORAGE_ETC_LOGROTATE_PATH="/etc/logrotate.d"

    # Define the list of logrotate configurations to sync
    local configs=(
        "pg_wal_archive"
        "rsyslog"
        "postgresql-common"
    )

    # Sync logrotate configurations
    log_message "Syncing specific logrotate configurations."

    # Loop through each configuration and rsync
    for config in "${configs[@]}"; do
        local old_config_path="$OLD_STORAGE_ETC_LOGROTATE_PATH/$config"
        local new_config_path="$NEW_STORAGE_ETC_LOGROTATE_PATH/$config"

        # Check if the configuration file exists in the old storage
        if [ -f "$old_config_path" ]; then
            sudo rsync -avh --progress "$old_config_path" "$NEW_STORAGE_ETC_LOGROTATE_PATH/"
            if [ $? -eq 0 ]; then
                log_message "Synced $config successfully."
            else
                log_message "Failed to sync $config."
            fi
        else
            log_message "$config not found in old storage."
        fi
    done
}

function etc_systemd_handler() {
    local OLD_STORAGE_PATH="/media/$PC_USERNAME/$UUID_EXTERNAL_STORAGE"
    local OLD_STORAGE_ETC_SYSTEMD_PATH="$OLD_STORAGE_PATH/etc/systemd/system"
    local NEW_STORAGE_ETC_SYSTEMD_PATH="/etc/systemd/system"

    # Define the list of services to sync
    local services=(
        "watersheep.service"
        "fisherman.service"
        "kafka.service"
        "agent-kafka.service"
        "agent-ws.service"
        "agent-ssh.service"
        "agent-db.service"
        "agent-checker.service"
        "agent-checker.timer"
        "zookeeper.service"
        "redis.service"
        "redis-server.service"
        "postgresql.service"
        "postgresql@12-main.service"
        "minio.service"
        "minio-old.service"
        "idle_cleanup.timer"
        "idle_cleanup.service"
    )

    rsync_systemd_spesific_files() {
        # Loop through each service and rsync
        for service in "${services[@]}"; do
            local old_service_path="$OLD_STORAGE_ETC_SYSTEMD_PATH/$service"
            local new_service_path="$NEW_STORAGE_ETC_SYSTEMD_PATH/$service"

            # Check if the service file exists in the old storage
            if [ -f "$old_service_path" ]; then
                sudo rsync -avh --progress "$old_service_path" "$new_service_path"
                if [ $? -eq 0 ]; then
                    log_message "Synced $service successfully."
                else
                    log_message "Failed to sync $service."
                fi
            else
                log_message "$service not found in old storage."
            fi
        done
    }

    # Check old storage Ubuntu version
    if [ -f "$OLD_STORAGE_PATH/etc/os-release" ]; then
        old_storage_ubuntu_version=$(grep 'VERSION_ID=' "$OLD_STORAGE_PATH/etc/os-release" | cut -d'=' -f2 | tr -d '"' | cut -d'.' -f1)
        log_message "old_storage_ubuntu_version: $old_storage_ubuntu_version"
    else
        log_message "Old storage os-release file not found."
        return 1
    fi

    # Check new storage Ubuntu version
    if [ -f "/etc/os-release" ]; then
        new_storage_ubuntu_version=$(grep 'VERSION_ID=' "/etc/os-release" | cut -d'=' -f2 | tr -d '"' | cut -d'.' -f1)
        log_message "new_storage_ubuntu_version: $new_storage_ubuntu_version"
    else
        log_message "New storage os-release file not found."
        return 2
    fi

    # Compare versions and rsync if they match
    if [ "$old_storage_ubuntu_version" -eq "$new_storage_ubuntu_version" ]; then
        log_message "Ubuntu versions match. Syncing systemd unit files."

        if [ "$old_storage_ubuntu_version" -eq 18 ] && [ "$new_storage_ubuntu_version" -eq 18 ]; then
            sudo rsync -avh --progress "$OLD_STORAGE_ETC_SYSTEMD_PATH/" "$NEW_STORAGE_ETC_SYSTEMD_PATH/"
            if [ $? -eq 0 ]; then
                log_message "Synced all services successfully."
            else
                log_message "Failed to sync all services."
            fi
        else
            log_message "Ubuntu versions do not match 18. Syncing specific systemd unit files."
            rsync_systemd_spesific_files
        fi
    else
        log_message "Ubuntu versions do not match. Syncing specific systemd unit files."
        rsync_systemd_spesific_files
    fi
}

function minio_app_handler() {

    local MINIO_OLD_SOURCE_PATH="/media/$PC_USERNAME/$UUID_EXTERNAL_STORAGE"

    # Function to rsync the minio app
    rsync_minio_app() {

        if [ $1 -eq 0 ]; then
            log_message "Rsyncing minio app from mounted device to /opt/app/agent/minio..."
            sudo rsync -avh --progress "$MINIO_OLD_SOURCE_PATH/opt/app/agent/minio/minio" "/opt/app/agent/minio/minio"
        elif [ $1 -eq 1 ]; then
            log_message "Rsyncing minio app from /usr/local/bin to /opt/app/agent/minio..."
            sudo rsync -avh --progress /usr/local/bin/minio "/opt/app/agent/minio/minio"
        else
            log_message "No valid minio command found, skipping rsync."
        fi

    }

    # Function to check which minio command is used in the script
    check_minio_command() {

        if grep -q '/opt/app/agent/minio/minio' "$MINIO_OLD_SOURCE_PATH/opt/app/agent/minio/minio.sh"; then
            log_message "Using /opt/app/agent/minio/minio command."
            return 0
        elif grep -q 'minio' "$MINIO_OLD_SOURCE_PATH/opt/app/agent/minio/minio.sh"; then
            log_message "Using minio command from /usr/local/bin/minio."
            return 1
        else
            log_message "Minio command not found in the script."
            return 2
        fi

    }

    bak_minio_sh() {

        log_message "Backing up the current minio.sh file"
        local current_date=$(date +%Y%m%d%H%M%S)
        cp /opt/app/agent/minio/minio.sh /opt/app/agent/minio/minio.sh.bak.$current_date
        if [ $? -eq 0 ]; then
            log_message "Backup successful: /opt/app/agent/minio/minio.sh.bak.$current_date"
        else
            log_message "Backup failed."
        fi

    }

    rsync_minio_sh() {

        if [ $1 -eq 0 ]; then

            bak_minio_sh

            log_message "Rsyncing minio.sh from mounted device to /opt/app/agent/minio..."
            sudo rsync -avh --progress "$MINIO_OLD_SOURCE_PATH/opt/app/agent/minio/minio.sh" "/opt/app/agent/minio/minio.sh"

        elif [ $1 -eq 1 ]; then

            bak_minio_sh

            # Truncate the minio.sh file to zero size
            log_message "truncate minio.sh"
            truncate -s 0 /opt/app/agent/minio/minio.sh

            # Write the content to minio.sh using echo -e in a one-liner
            log_message "fill custom value for minio.sh"
            echo -e "#!/bin/bash\nif [ -d "/opt/app/agent/minio/data" ]; then\n    echo "Directory data exists";\nelse\n    sudo mkdir /opt/app/agent/minio/data;\n    echo "Directory created";\n    sudo chown $PC_USERNAME /opt/app/agent/minio/data && sudo chmod u+rw /opt/app/agent/minio/data;\nfi\n/opt/app/agent/minio/minio server /opt/app/agent/minio/data --address :9000 --console-address :9001" > /opt/app/agent/minio/minio.sh

        else
            log_message "No valid minio.sh found, skipping rsync."
        fi

    }

    log_message "state_run: check_minio_command()"
    check_minio_command
    local command_status=$?
    log_message "command_status: $command_status"
    log_message "state_run: rsync_minio_app($command_status)"
    rsync_minio_app $command_status
    log_message "state_run: rsync_minio_sh($command_status)"
    rsync_minio_sh $command_status

}

function restart_services() {

    local services=(
        "watersheep.service"
        "fisherman.service"
        "kafka.service"
        "agent-kafka.service"
        "agent-ws.service"
        "agent-ssh.service"
        "agent-db.service"
        "agent-checker.service"
        "agent-checker.timer"
        "zookeeper.service"
        "redis.service"
        "redis-server.service"
        "postgresql.service"
        "postgresql@12-main.service"
        "minio.service"
        "minio-old.service"
        "idle_cleanup.timer"
        "idle_cleanup.service"
    )

    log_message "Re enabling and restarting services"

    for service in "${services[@]}"; do
        log_message "Re enabling $service"
        sudo systemctl enable "$service"

        log_message "Restarting $service"
        sudo systemctl restart "$service"
    done

    log_message "Daemon reload"
    sudo systemctl daemon-reload

    # Save the current date and time as the end date
    first_end_date=$(date +'%Y-%m-%d %H:%M:%S')

}

function stop_services() {

    local services=(
        "watersheep.service"
        "fisherman.service"
        "kafka.service"
        "agent-kafka.service"
        "agent-ws.service"
        "agent-ssh.service"
        "agent-db.service"
        "agent-checker.service"
        "agent-checker.timer"
        "zookeeper.service"
        "redis.service"
        "redis-server.service"
        "postgresql.service"
        "postgresql@12-main.service"
        "minio.service"
        "minio-old.service"
        "idle_cleanup.timer"
        "idle_cleanup.service"
        "parkee-settlement.service"
    )

    log_message "Stopping and disabling services"

    for service in "${services[@]}"; do
        log_message "Stopping $service"
        sudo systemctl stop "$service"

        log_message "Disabling $service"
        sudo systemctl disable "$service"
    done
}

function hello() {

    # Save the current date and time as the start date
    first_start_date=$(date +'%Y-%m-%d %H:%M:%S')

    echo "# ======================= START ========================================================= #"
    log_message "Welcome to pawdog restore server! gowk gowk gowk! script started!"

}

function bye_bye() {

    log_message "Yey, fully restoring server done! see you again later! bye-bye!"
    echo "# ======================= END ============================================================ #"

    # exit program
    exit 0

}

function parkee_settlement_handler() {
    local parkee_settlement_path="/opt/app/agent/parkee-settlement"
    
    # Remove systemd service
    sudo rm /etc/systemd/system/parkee-settlement.service
    
    # Remove all files inside parkee_settlement_path folder
    if [ -d "$parkee_settlement_path" ]; then
        sudo rm -rf "${parkee_settlement_path:?}"/*
    else
        log_message "Warning: $parkee_settlement_path does not exist or is not a directory."
    fi
    
    # Remove folder parkee_settlement_path
    if [ -d "$parkee_settlement_path" ]; then
        sudo rm -rf "$parkee_settlement_path"
        log_message "Removed $parkee_settlement_path"
    else
        log_message "Warning: $parkee_settlement_path does not exist or is not a directory."
    fi
    
    log_message "Settlement jar cleanup completed."
}

function run_rsync_all_services() {

    local SOURCE_PATH="/media/$PC_USERNAME/$UUID_EXTERNAL_STORAGE"

    rsync_opt_folders_exclude_minio() {
        local SOURCE=$1
        local DEST=$2

        log_message "rsync_opt_folders_exclude_minio $SOURCE $DEST started!"
        sudo rsync -avh --progress --exclude='fisherman/' --exclude='watersheep/' --exclude='minio/' --exclude='minio-old/' "$SOURCE" "$DEST"

        # Check the exit status of rsync_opt_folders_exclude_minio
        if [ $? -eq 0 ]; then
            log_message "rsync_opt_folders_exclude_minio successful"
        else
            log_message "Error occurred for rsync_opt_folders_exclude_minio"
        fi

    }

    rsync_minio_exclude_imagesdirectory() {

        local SOURCE=$1
        local DEST=$2

        log_message "rsync_minio_exclude_imagesdirectory $SOURCE $DEST started!"
        sudo rsync -avh --progress --exclude='imagesdirectory/' "$SOURCE" "$DEST"

        # Check the exit status of rsync_opt_folders_exclude_minio
        if [ $? -eq 0 ]; then
            log_message "rsync_minio_exclude_imagesdirectory successful"
        else
            log_message "Error occurred for rsync_minio_exclude_imagesdirectory"
        fi

    }

    create_minio_folders () {
        folders=("imagesdirectory" "imagesdirectory/location" "imagesdirectory/PP" "imagesdirectory/coupon")

        for folder in "${folders[@]}"; do
            # create folder
            log_message "Create /opt/app/agent/minio/data/$folder folder"
            sudo mkdir -p "/opt/app/agent/minio/data/$folder"
            sudo mkdir -p "$SOURCE_PATH/opt/app/agent/minio/data/$folder"
        done

        # change permissions for parent folder
        log_message "Change permission /opt/app/agent/minio/data/imagesdirectory"
        sudo chmod +x "/opt/app/agent/minio/data/imagesdirectory"
    }

    rsync_minio_spesific_folders() {

        rsync_minio_imagesdirectories() {
            local source_folder="$1"
            local destination_folder="$2"
            local folder_name="$3"

            log_message "Rsync $source_folder folders"
            sudo rsync -avh --progress "$source_folder" "$destination_folder"
            if [ $? -eq 0 ]; then
                log_message "Rsync for $folder_name successful"
            else
                echo "$(date +"%Y-%m-%d %H:%M:%S") [ERROR] Rsync for $folder_name failed"
            fi
        }

        # Call function for create folders in minio
        create_minio_folders

        # Rsync each folder
        rsync_minio_imagesdirectories "$SOURCE_PATH/opt/app/agent/minio/data/imagesdirectory/location" "/opt/app/agent/minio/data/imagesdirectory/" "imagesdirectory/location"
        rsync_minio_imagesdirectories "$SOURCE_PATH/opt/app/agent/minio/data/imagesdirectory/PP" "/opt/app/agent/minio/data/imagesdirectory/" "imagesdirectory/PP"
        rsync_minio_imagesdirectories "$SOURCE_PATH/opt/app/agent/minio/data/imagesdirectory/coupon" "/opt/app/agent/minio/data/imagesdirectory/" "imagesdirectory/coupon"

    }

    rysnc_general_services() {

        local SOURCE=$1
        local DEST=$2

        log_message "rysnc_general_services $SOURCE $DEST started!"
        sudo rsync -avh --progress "$SOURCE" "$DEST"

        # Check the exit status of rysnc_general_services
        if [ $? -eq 0 ]; then
            log_message "rysnc_general_services $SOURCE $DEST successful"
        else
            log_message "Error occurred for rysnc_general_services $SOURCE $DEST"
        fi

    }

    cp_etc_postgres_12_main(){

        log_message "state cp_etc_postgres_12_main start"

        sudo cp -r $SOURCE_PATH/etc/postgresql/12/main /etc/postgresql/12/

        if [ $? -eq 0 ]; then
            log_message "cp_etc_postgres_12_main successful"
        else
            log_message "Error occurred for cp_etc_postgres_12_main"
        fi

    }

    comment_archive_mode() {

        log_message "state: comment_archive_mode()"

        # Define the path to the postgresql.config file
        local PG_CONFIG_FILE="/etc/postgresql/12/main/postgresql.conf"

        echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] run: comment_archive_mode()"

        # Comment out specific lines
        sudo sed -i 's/^\(archive_mode = on\)/# \1/' "$PG_CONFIG_FILE"
        sudo sed -i 's/^\(archive_command = .*\)/# \1/' "$PG_CONFIG_FILE"
        sudo sed -i 's/^\(archive_timeout = 5\)/# \1/' "$PG_CONFIG_FILE"

    }

    comment_pg_timeout_settings() {
        log_message "state: comment_pg_timeout_settings()"

        # Define the path to the postgresql.config file
        local PG_CONFIG_FILE="/etc/postgresql/12/main/postgresql.conf"

        echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] run: comment_pg_timeout_settings()"

        # Comment out specific lines
        sudo sed -i 's/^\(idle_in_transaction_session_timeout = 120000ms\)/# \1/' "$PG_CONFIG_FILE"
        sudo sed -i 's/^\(lock_timeout = 120000ms\)/# \1/' "$PG_CONFIG_FILE"
        sudo sed -i 's/^\(deadlock_timeout = 10s\)/# \1/' "$PG_CONFIG_FILE"
        sudo sed -i 's/^\(statement_timeout = 600000ms\)/# \1/' "$PG_CONFIG_FILE"

        # Verify the changes
        echo "Verifying changes:"
        grep -E "^#\s*(idle_in_transaction_session_timeout|lock_timeout|deadlock_timeout|statement_timeout)" "$PG_CONFIG_FILE"
    }

    cp_var_lib_postgres() {

        log_message "state cp_var_lib_postgres start"

        sudo cp -r $SOURCE_PATH/var/lib/postgresql/12/main /var/lib/postgresql/12/

        if [ $? -eq 0 ]; then
            log_message "cp_var_lib_postgres successful"
        else
            log_message "Error occurred for cp_var_lib_postgres"
        fi

    }

    cleanup_var_lib_postgres() {

        log_message "state cleanup_var_lib_postgres start"

        sudo rm -r /var/lib/postgresql/12/main/

        if [ $? -eq 0 ]; then
            log_message "cleanup_var_lib_postgres successful"
        else
            log_message "Error occurred for cleanup_var_lib_postgres"
        fi

    }

    chown_chmod_var_lib_postgres() {

        log_message "state chown_chmod_var_lib_postgres start"

        sudo chown -R postgres:postgres /var/lib/postgresql/12/main

        sudo chmod 700 /var/lib/postgresql/12/main

    }

    replace_default_runner_fs_ws() {

        log_message "state replace_default_runner_fs_ws start"

        # for ws
        truncate -s 0 /opt/app/agent/watersheep/watersheep.sh
        echo -e '#!/bin/bash\ncd /opt/app/agent/watersheep\njava -jar mini-agent.jar;' > /opt/app/agent/watersheep/watersheep.sh

        # for fs
        truncate -s 0 /opt/app/agent/fisherman/fisherman.sh
        echo -e '#!/bin/bash\ncd /opt/app/agent/fisherman\njava -jar fisherman.jar;' > /opt/app/agent/fisherman/fisherman.sh

    }

    redis_config_permissions() {
        sudo chmod 640 /etc/redis/redis.conf
        sudo chown redis:redis /etc/redis/redis.conf
    }

    check_fisherman_properties() {
        local source_path="$1"
        local properties_file="$source_path/opt/app/agent/fisherman/application.properties"
        
        # Check if properties file exists
        if [ ! -f "$properties_file" ]; then
            echo "Fisherman application.properties not found at: $properties_file"
            return 1
        fi
        
        # Check for the specific dialect property
        if grep -q "agent.jpa.properties.hibernate.dialect=app.parkee.fisherman.common.dialect.PostgreSQL12Dialect" "$properties_file"; then
            echo "PostgreSQL12Dialect found in application.properties. Proceeding with installation..."
            return 0
        else
            echo "PostgreSQL12Dialect not found in application.properties. Skipping installation."
            return 1
        fi
    }

    rsync_and_install_java21() {
        local source_path="$1"
        local dest_path="$2"
        local file_pattern="bellsoft-jdk21*.deb"
        local java_source_path="$source_path/mnt/shared"

        # Check fisherman properties first using the main source path
        if ! check_fisherman_properties "$source_path"; then
            echo "Skipping Java 21 installation due to fisherman properties check."
            return 0
        fi

        # Check if Java source path exists
        if [ ! -d "$java_source_path" ]; then
            echo "Error: Java source path '$java_source_path' does not exist."
            return 1
        fi

        # Check if destination path exists
        if [ ! -d "$dest_path" ]; then
            echo "Error: Destination path '$dest_path' does not exist."
            return 1
        fi

        echo "Starting rsync operation..."
        echo "Source: $java_source_path"
        echo "Destination: $dest_path"
        echo "File pattern: $file_pattern"

        # Perform rsync
        rsync -av --progress "$java_source_path/$file_pattern" "$dest_path"

        # Check rsync exit status
        if [ $? -eq 0 ]; then
            echo "Rsync completed successfully."
        else
            echo "Error: Rsync operation failed."
            return 1
        fi

        # List synced files
        echo "Synced files in destination:"
        ls -l "$dest_path/$file_pattern"

        # Find the most recent Java 21 .deb file
        local java_deb=$(ls -t "$dest_path/$file_pattern" | head -n1)
        if [ -z "$java_deb" ]; then
            echo "Error: No Java 21 .deb file found in $dest_path"
            return 1
        fi

        echo "Installing Java 21 from $java_deb"
        # Install the .deb package
        if sudo dpkg -i "$java_deb"; then
            echo "Java 21 installed successfully."
        else
            echo "Error occurred during Java 21 installation. Attempting to fix..."
            if sudo apt-get install -f; then
                echo "Dependencies resolved. Java 21 should now be installed."
            else
                echo "Error: Failed to install Java 21. Please check the package and try again."
                return 1
            fi
        fi

        # Verify Java installation
        if java -version 2>&1 | grep -q "21"; then
            echo "Java 21 installation verified."
        else
            echo "Warning: Java 21 installation could not be verified. Please check manually."
        fi
    }

    update_pgdg_source_list() {
        local sources_dir="/etc/apt/sources.list.d"
        local pgdg_file="pgdg.list"
        local pgdg_save_file="pgdg.list.save"
        local ubuntu_release=$(lsb_release -cs)

        # Check if running with sudo privileges
        if [ "$(id -u)" -ne 0 ]; then
            echo "This function needs to be run with sudo privileges."
            return 1
        fi

        # Remove pgdg.list.save if it exists
        if [ -f "$sources_dir/$pgdg_save_file" ]; then
            echo "Removing $pgdg_save_file..."
            rm "$sources_dir/$pgdg_save_file"
            if [ $? -eq 0 ]; then
                echo "$pgdg_save_file removed successfully."
            else
                echo "Error: Failed to remove $pgdg_save_file."
                return 1
            fi
        else
            echo "$pgdg_save_file not found. Skipping removal."
        fi

        # Create new pgdg.list file
        echo "Creating new $pgdg_file..."
        echo "deb http://apt-archive.postgresql.org/pub/repos/apt $ubuntu_release-pgdg main" > "$sources_dir/$pgdg_file"
        
        if [ $? -eq 0 ]; then
            echo "$pgdg_file created successfully with the following content:"
            cat "$sources_dir/$pgdg_file"
        else
            echo "Error: Failed to create $pgdg_file."
            return 1
        fi

        echo "PGDG source list update completed."
    }

    check_and_install_pg_extensions() {
        local PG_CONFIG_FILE="/etc/postgresql/12/main/postgresql.conf"
        local SHARED_PRELOAD_LINE="shared_preload_libraries = 'pg_cron'"
        local CRON_DATABASE_PATTERN="cron\.database_name\s*=\s*'agent_[^']*'"

        echo "Checking PostgreSQL configuration..."

        # Check if the configuration file exists
        if [ ! -f "$PG_CONFIG_FILE" ]; then
            echo "Error: PostgreSQL configuration file not found at $PG_CONFIG_FILE"
            return 1
        fi

        local install_cron=false

        # Check for shared_preload_libraries line
        if grep -q "^#.*$SHARED_PRELOAD_LINE" "$PG_CONFIG_FILE"; then
            echo "Warning: $SHARED_PRELOAD_LINE is commented out. Skipping pg_cron installation."
        elif grep -q "$SHARED_PRELOAD_LINE" "$PG_CONFIG_FILE"; then
            echo "Found: $SHARED_PRELOAD_LINE"
            install_cron=true
        else
            echo "Not found: $SHARED_PRELOAD_LINE"
        fi

        # Check for cron.database_name line with regex pattern
        if grep -qE "^#.*$CRON_DATABASE_PATTERN" "$PG_CONFIG_FILE"; then
            echo "Warning: cron.database_name is commented out. Skipping pg_cron installation."
        elif grep -qE "$CRON_DATABASE_PATTERN" "$PG_CONFIG_FILE"; then
            echo "Found: cron.database_name matching pattern 'agent_*'"
            grep -E "$CRON_DATABASE_PATTERN" "$PG_CONFIG_FILE"
            install_cron=true
        else
            echo "Not found: cron.database_name matching pattern 'agent_*'"
        fi

        # Install pg_cron if needed
        if [ "$install_cron" = true ]; then
            install_pg_cron
            # Install postgresql-12-partman right after pg_cron
            install_pg_partman
        else
            echo "Skipping pg_cron and postgresql-12-partman installation due to missing or commented configuration."
        fi

        # Print the lines if they exist
        echo "Current configuration:"
        grep -E "(shared_preload_libraries|cron\.database_name)" "$PG_CONFIG_FILE" || echo "No matching lines found in the configuration file."

        echo "Check complete."
    }

    install_pg_cron() {
        # Check if pg_cron is installed
        if dpkg -l | grep -q pg-cron; then
            echo "pg_cron is already installed."
        else
            echo "pg_cron is not installed. Attempting to install..."
            
            # Attempt to install pg_cron
            if sudo apt-get update && sudo apt-get install -y postgresql-12-cron; then
                echo "pg_cron installed successfully."
            else
                echo "Error: Failed to install pg_cron. Please check your system and try again."
                return 1
            fi
        fi
    }

    install_pg_partman() {
        # Check if postgresql-12-partman is installed
        if dpkg -l | grep -q postgresql-12-partman; then
            echo "postgresql-12-partman is already installed."
        else
            echo "postgresql-12-partman is not installed. Attempting to install..."
            
            # Attempt to install postgresql-12-partman
            if sudo apt-get update && sudo apt-get install -y postgresql-12-partman; then
                echo "postgresql-12-partman installed successfully."
            else
                echo "Error: Failed to install postgresql-12-partman. Please check your system and try again."
                return 1
            fi
        fi
    }

    log_message "Starting rsync process..."

    # Call function rsync_opt_folders_exclude_minio for /opt/app/agent/
    rsync_opt_folders_exclude_minio "$SOURCE_PATH/opt/app/agent/" "/opt/app/agent/"

    # rsync minio app
    minio_app_handler

    # Call function rsync_minio_exclude_imagesdirectory for /opt/app/agent/
    rsync_minio_exclude_imagesdirectory "$SOURCE_PATH/opt/app/agent/minio/data" "/opt/app/agent/minio/"

    # Call function rsync_minio_spesific_folders for /opt/app/agent/
    rsync_minio_spesific_folders

    # clean up var lib pg
    cleanup_var_lib_postgres

    # Call cp var lib pg
    cp_var_lib_postgres

    # Call etc postgres 12 main
    cp_etc_postgres_12_main

    # rsync mnt share for getting java 21 deb
    rsync_and_install_java21 "$SOURCE_PATH" "/mnt/shared"

    # update_pgdg_source_list
    update_pgdg_source_list

    # comment archive mode
    comment_archive_mode

    # comment_pg_timeout_settings
    comment_pg_timeout_settings

    # chown pg and chmod 700 var lib pg
    chown_chmod_var_lib_postgres

    # check_and_install_pg_extensions
    check_and_install_pg_extensions

    # crontab
    rysnc_general_services "$SOURCE_PATH/var/spool/cron/crontabs/root" "/var/spool/cron/crontabs/root"
    rysnc_general_services "$SOURCE_PATH/var/spool/cron/crontabs/$PC_USERNAME" "/var/spool/cron/crontabs/$PC_USERNAME"

    # fs
    rysnc_general_services "$SOURCE_PATH/opt/app/agent/fisherman/application.properties" "/opt/app/agent/fisherman/application.properties"
    rysnc_general_services "$SOURCE_PATH/opt/app/agent/fisherman/fisherman.jar" "/opt/app/agent/fisherman/fisherman.jar"
    rysnc_general_services "$SOURCE_PATH/opt/app/agent/fisherman/backup" "/opt/app/agent/fisherman/"

    # ws
    rysnc_general_services "$SOURCE_PATH/opt/app/agent/watersheep/application.properties" "/opt/app/agent/watersheep/application.properties"
    rysnc_general_services "$SOURCE_PATH/opt/app/agent/watersheep/mini-agent.jar" "/opt/app/agent/watersheep/mini-agent.jar"
    rysnc_general_services "$SOURCE_PATH/opt/app/agent/watersheep/backup" "/opt/app/agent/watersheep/"

    # zsh, mnt, systemd
    rysnc_general_services "$SOURCE_PATH/home/$PC_USERNAME/.zshrc" "/home/$PC_USERNAME/.zshrc"
    rysnc_general_services "$SOURCE_PATH/home/$PC_USERNAME/.zsh_history" "/home/$PC_USERNAME/.zsh_history"
    rysnc_general_services "$SOURCE_PATH/mnt/shared" "/mnt/"
    rysnc_general_services "$SOURCE_PATH/etc/redis/redis.conf" "/etc/redis/redis.conf"

    # handling permission on redis conf
    redis_config_permissions

    # handle rsync etc systemd
    etc_systemd_handler

    # handle rsync log rotate
    logrotate_handler

    # parkee_settlement_handler
    parkee_settlement_handler

    # add_hashtag_to_kafka_service
    add_hashtag_to_kafka_service

    # replace default runner
    replace_default_runner_fs_ws

}

function rsync_rest_minio_folders() {

    local SOURCE_PATH="/media/$PC_USERNAME/$UUID_EXTERNAL_STORAGE"

    rsyncRestMinioFolders() {

        local SOURCE=$1
        local DEST=$2

        log_message "rsyncRestMinioFolders $SOURCE $DEST started!"
        sudo rsync -avh --progress "$SOURCE" "$DEST"

        # Check the exit status of rysnc_general_services
        if [ $? -eq 0 ]; then
            log_message "rsyncRestMinioFolders $SOURCE $DEST successful"
        else
            log_message "Error occurred for rsyncRestMinioFolders $SOURCE $DEST"
        fi

    }

    # Save the current date and time as the start date
    second_start_date=$(date +'%Y-%m-%d %H:%M:%S')

    rsyncRestMinioFolders "$SOURCE_PATH/opt/app/agent/minio/data/imagesdirectory" "/opt/app/agent/minio/data/"

    # Save the current date and time as the end date
    second_end_date=$(date +'%Y-%m-%d %H:%M:%S')

}

function second_telegram_notify() {

    local SOURCE_PATH="/media/$PC_USERNAME/$UUID_EXTERNAL_STORAGE"
    local chat_id=$1
    local api_endpoint=$2
    local second_final_duration=$3
    local hostname=$(hostname)
    local ip_address=$(hostname -I)
    local date_time=$(date +"%Y-%m-%d %H:%M:%S")
    local new_storage_os_version=$(grep 'PRETTY_NAME=' "/etc/os-release" | cut -d'=' -f2 | tr -d '"')
    local old_storage_os_version=$(grep 'PRETTY_NAME=' "$SOURCE_PATH/etc/os-release" | cut -d'=' -f2 | tr -d '"')
    local messages="🐶 Pawdog Restore Server Alert 🐶

    Notify Count: [2]
    Hostname: $hostname
    Datetime: $date_time
    IP Address: $ip_address
    New Storage OS Version: $new_storage_os_version
    Old Storage OS Version: $old_storage_os_version

    Restore Minio Duration: $second_final_duration

    Details:
    $hostname remaining Minio folders restore is complete. The current restore status is fully restored. Bye-bye!"

    log_message "State: second_telegram_notify, msg: Notifying final steps to Telegram pawdog monitoring alert."

    send_telegram_message "$chat_id" "$api_endpoint" "$messages"

}

function first_telegram_notify() {

    local SOURCE_PATH="/media/$PC_USERNAME/$UUID_EXTERNAL_STORAGE"
    local chat_id=$1
    local api_endpoint=$2
    local first_final_duration=$3
    local hostname=$(hostname)
    local ip_address=$(hostname -I)
    local date_time=$(date +"%Y-%m-%d %H:%M:%S")
    local new_storage_os_version=$(grep 'PRETTY_NAME=' "/etc/os-release" | cut -d'=' -f2 | tr -d '"')
    local old_storage_os_version=$(grep 'PRETTY_NAME=' "$SOURCE_PATH/etc/os-release" | cut -d'=' -f2 | tr -d '"')
    local messages="🐶 Pawdog Restore Server Alert 🐶

    Notify Count: [1]
    Hostname: $hostname
    Datetime: $date_time
    IP Address: $ip_address
    New Storage OS Version: $new_storage_os_version
    Old Storage OS Version: $old_storage_os_version

    Restore Server Duration: $first_final_duration

    Details:
    $hostname server restore has been completed successfully. You can now test transactions, export reports, and ensure everything runs smoothly. I will continue to rsync the remaining Minio data folders.

    Note: Please ensure the server location's IP address matches the IP address on the datasite."

    log_message "State: first_telegram_notify, msg: Notifying steps to Telegram pawdog monitoring alert."

    send_telegram_message "$chat_id" "$api_endpoint" "$messages"

}

function send_telegram_message() {
    local chat_id=$1
    local api_endpoint=$2
    local message=$3
    local max_attempts=3
    local attempt=1
    local success=false

    while [ $attempt -le $max_attempts ] && [ "$success" = false ]; do
        local response=$(curl -s -X POST "$api_endpoint" -d "chat_id=$chat_id" -d "text=$message")
        local exit_status=$?

        if [ $exit_status -eq 0 ]; then
            log_message "Message sent successfully on attempt $attempt!"
            log_message "Response: $response"
            success=true
        else
            log_message "Error occurred on attempt $attempt. HTTP status code: $exit_status"
            log_message "Response: $response"
            if [ $attempt -lt $max_attempts ]; then
                log_message "Retrying in 5 seconds..."
                sleep 5
            fi
            ((attempt++))
        fi
    done

    if [ "$success" = false ]; then
        log_message "Failed to send message after $max_attempts attempts."
    fi
}

# Function to calculate duration
function calculate_first_duration() {

    # Convert dates to Unix timestamps
    first_start_timestamp=$(date -d "$first_start_date" +%s)
    first_end_timestamp=$(date -d "$first_end_date" +%s)

    # Calculate duration in seconds
    first_duration=$((first_end_timestamp - first_start_timestamp))

    # Convert duration to human-readable format
    first_duration_formatted=$(date -u -d @"$first_duration" +'%H hours %M minutes %S seconds')

}

# Function to calculate duration
function calculate_second_duration() {

    # Convert dates to Unix timestamps
    second_start_timestamp=$(date -d "$second_start_date" +%s)
    second_end_timestamp=$(date -d "$second_end_date" +%s)

    # Calculate duration in seconds
    second_duration=$((second_end_timestamp - second_start_timestamp))

    # Convert duration to human-readable format
    second_duration_formatted=$(date -u -d @"$second_duration" +'%H hours %M minutes %S seconds')

}

function main() {

    # call funtion hello
    hello

    # call function to stop services
    stop_services

    # call function to rsync all agent services
    run_rsync_all_services

    # call function to restart services
    restart_services

    # calculate duration
    calculate_first_duration

    # call telegram notify
    first_telegram_notify "$CHAT_ID" "$API_ENDPOINT" "$first_duration_formatted"

    # contiune rsync remaining minio folders
    rsync_rest_minio_folders

    # calculate duration
    calculate_second_duration

    # call final telegram notify
    second_telegram_notify "$CHAT_ID" "$API_ENDPOINT" "$second_duration_formatted"

    # call function bye bye
    bye_bye

}

(

    # function main
    main &> "$LOG_FILE"

)