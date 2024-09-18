import json
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def fix_json_file(data, is_client_spec):
    """Fix the JSON structure for 'client_specification_activity'."""
    if is_client_spec and 'network' in data and 'ipAddress' in data['network']:
        ip_addresses = data['network']['ipAddress'].split()
        data['network']['ipAddress'] = ip_addresses[0]  # Keep only the first IP address
        logging.info(f"Fixed IP address in 'network': {ip_addresses[0]}")
    return data

def merge_json_files(input_dir, output_file, is_client_spec):
    """Merge JSON files and apply fix if in 'client_specification_activity'."""
    merged_data = []

    # List all JSON files in the directory
    for filename in os.listdir(input_dir):
        if filename.endswith('.json'):
            file_path = os.path.join(input_dir, filename)
            try:
                with open(file_path, 'r') as f:
                    data = json.load(f)
                    logging.info(f"Loaded {filename}")
                    # Apply fix if necessary
                    fixed_data = fix_json_file(data, is_client_spec)
                    merged_data.append(fixed_data)
            except json.JSONDecodeError as e:
                logging.error(f"Error reading {filename}: {str(e)}")

    # Write merged data to the output file
    with open(output_file, 'w') as f:
        json.dump(merged_data, f, indent=4)
    logging.info(f"Merged data saved to {output_file}")

    # Print the merged data
    print(json.dumps(merged_data, indent=4))

# Directory containing JSON files
input_directory = '/home/parkee/server-backups/{{ modul_type }}'

# Output file
output_file = '/home/parkee/server-backups/{{ modul_type }}/data.json'

# Determine if the directory is 'client_specification_activity'
is_client_spec = 'client_specification_activity' in input_directory

merge_json_files(input_directory, output_file, is_client_spec)
