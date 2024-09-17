#!/bin/bash

# Function to convert sizes to MB
convert_to_mb() {
    local size=$1
    local unit=${size: -1}
    local value=${size::-1}
    case $unit in
        G|g) echo $((value * 1024)) ;;
        M|m) echo $value ;;
        K|k) echo $((value / 1024)) ;;
        *) echo $size ;;
    esac
}

# Function to get CPU info
get_cpu_info() {
    cpuModel=$(lscpu | grep "Model name" | cut -d':' -f2 | sed 's/^[ \t]*//')
    totalCores=$(nproc)
    realCores=$(lscpu | grep "Core(s) per socket" | awk '{print $4}')
    sockets=$(lscpu | grep "Socket(s)" | awk '{print $2}')
    realCores=$((realCores * sockets))
    threadsPerCore=$((totalCores / realCores))
    echo "{\"model\":\"$cpuModel\",\"totalCores\":$totalCores,\"realCores\":$realCores,\"threadsPerCore\":$threadsPerCore}"
}

# Function to get memory info
get_memory_info() {
    totalMem=$(free -m | awk '/Mem:/ {print $2}')
    slotMemory=$(dmidecode -t memory | grep -c "Size:")
    usedSlot=$(dmidecode -t memory | grep -c "Size: [0-9]")
    ddrVersion=$(dmidecode -t memory | grep "Type:" | awk '{print $2}' | head -n1)
    
    echo "{\"total\":$totalMem,\"slotMemory\":$slotMemory,\"usedSlot\":$usedSlot,\"ddrVersion\":\"$ddrVersion\"}"
}

# Function to get disk info
get_disk_info() {
    total=$(df -BM / | awk 'NR==2 {gsub("M", "", $2); print $2}')
    used=$(df -BM / | awk 'NR==2 {gsub("M", "", $3); print $3}')
    available=$(df -BM / | awk 'NR==2 {gsub("M", "", $4); print $4}')
    
    diskModel=$(lsblk -no MODEL | awk 'NF' | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Determine if the disk is SSD or HDD
    rota=$(lsblk -ndo ROTA /dev/$(lsblk -ndo NAME | head -n1) | awk '{print $1}')
    if [ "$rota" == "0" ]; then
        diskType="SSD"
    else
        diskType="HDD"
    fi
    
    echo "{\"usage\":{\"total\":$total,\"used\":$used,\"available\":$available},\"model\":\"$diskModel\",\"type\":\"$diskType\"}"
}

# Function to get network info
get_network_info() {
    primaryInterface=$(ip route | awk '/default/ {print $5}' | head -n1)
    ipAddress=$(ip -4 addr show $primaryInterface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    echo "{\"interface\":\"$primaryInterface\",\"ipAddress\":\"$ipAddress\"}"
}

# Function to get OS info
get_os_info() {
    osInfo=$(lsb_release -a 2>/dev/null | awk -F':' '
    {
        gsub(/^[ \t]+|[ \t]+$/, "", $2);
        key = tolower($1);
        gsub(/ /, "", key);
        if (key == "distributorid") key = "distributorId";
        if (key == "description") $2 = substr($0, index($0, $2)); # Keep the entire description, including colons
        printf "\"%s\":\"%s\",", key, $2
    }' | sed 's/,$//')
    echo "{$osInfo}"
}

# Function to get location code
get_location_code() {
    locationCode=$(/opt/app/agent/parkee-agent/server.properties | grep 'db=' | cut -d'=' -f2- | sed 's/agent_//' | awk '{print toupper($0)}')
    echo "\"$locationCode\""
}

# Function to get motherboard info
get_motherboard_info() {
    manufacturer=$(dmidecode -s baseboard-manufacturer)
    product=$(dmidecode -s baseboard-product-name)
    echo "{\"manufacturer\":\"$manufacturer\",\"model\":\"$product\"}"
}

# Main function to collect all info and create JSON
collect_info() {
    cpuInfo=$(get_cpu_info)
    memoryInfo=$(get_memory_info)
    diskInfo=$(get_disk_info)
    networkInfo=$(get_network_info)
    osInfo=$(get_os_info)
    locationCode=$(get_location_code)
    motherboardInfo=$(get_motherboard_info)

    jsonOutput=$(cat << EOF
{
    "cpu": $cpuInfo,
    "memory": $memoryInfo,
    "disk": $diskInfo,
    "network": $networkInfo,
    "os": $osInfo,
    "locationCode": $locationCode,
    "motherboard": $motherboardInfo
}
EOF
)

    echo "$jsonOutput" | jq '.' > /tmp/client_specification.json
}

# Run the main function
collect_info

echo "Hardware specification collected and saved to /tmp/client_specification.json"