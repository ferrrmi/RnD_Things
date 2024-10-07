#!/bin/bash

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

# rsync mnt share for getting java 21 deb
rsync_and_install_java21 "$SOURCE_PATH" "/mnt/shared"