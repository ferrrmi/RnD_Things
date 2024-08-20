import subprocess
import re
import psycopg2
import json
import os
from datetime import datetime

def get_hdsentinel_output():
    cmd = ['sudo', './hdsentinel-019c-x64']
    cwd = '/opt/app/agent/'
    result = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding='utf-8')
    return result.stdout.strip()

def parse_hdsentinel_output(output):
    hdds = []
    hdd_blocks = output.split("HDD Device")

    for block in hdd_blocks[1:]:  # Skip the first split part as it contains the introductory lines
        device_match = re.search(r"^\s*\d+:\s+(\S+)", block)
        model_match = re.search(r"HDD Model ID\s+:\s+([^\n]+)", block)
        size_match = re.search(r"HDD Size\s+:\s+([^\n]+)", block)
        interface_match = re.search(r"Interface\s+:\s+([^\n]+)", block)
        high_temperature_match = re.search(r"Highest Temp.:\s+(\d+)\s+°C", block)
        health_match = re.search(r"Health\s+:\s+(\d+)\s+%", block)
        power_on_match = re.search(r"Power on time:\s+([^\n]+)", block)
        lifetime_match = re.search(r"Est\. lifetime:\s+([^\n]+)", block)

        if device_match and model_match and size_match and interface_match and high_temperature_match and health_match and power_on_match and lifetime_match:
            device = device_match.group(1)
            size_in_string = str(size_match.group(1))
            size, unit = size_in_string.split()
            size_in_gb = float(size) / 1024  # Convert MB to GB
            size_in_gb_formatted = f"{size_in_gb:.2f} GB"

            hdd_info = {
                "device": device,
                "model": model_match.group(1),
                "size": size_in_gb_formatted,
                "interface": interface_match.group(1),
                "high_temperature": high_temperature_match.group(1),
                "health": health_match.group(1),
                "power_on_time": power_on_match.group(1),
                "est_lifetime": lifetime_match.group(1)
            }
            hdds.append(hdd_info)

    return hdds

def get_system_storage_device():
    result = subprocess.run(['df', '/'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding='utf-8')
    output = result.stdout.strip()
    lines = output.split('\n')
    device_line = lines[1]  # The second line contains the device information
    device = device_line.split()[0]  # The first column is the device
    print(f"device: ", device)
    return device
    
def postgres_conn():
    # connection production
    conn = psycopg2.connect(
        database="{{ db_name }}",
        user="{{ db_username }}",
        password="{{ db_password }}",
        host="localhost",
        port="5432",
    )
    # test to 01h
    # conn = psycopg2.connect(
    #     database="agent_01h",
    #     user="agent",
    #     password="01h545115",
    #     host="localhost",
    #     port="5432",
    # )

    cur = conn.cursor()

    cur.execute(
        """
        SELECT * FROM (SELECT TRIM(REGEXP_REPLACE(REGEXP_REPLACE(UPPER(l.name), '\s+', ' '), '\)\s+', ') ')) AS loc_name FROM location l) AS subquery_alias, to_char((now() AT TIME ZONE 'Asia/Bangkok'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS last_sync
        """
    )

    query_result = cur.fetchone()
    return query_result

def last_sync():
    current_timestamp = postgres_conn()[1]
    return current_timestamp

def location_unique_code():
    location_unique_code = (
        os.popen(
            "cat /opt/app/agent/watersheep/application.properties | grep 'parkee.common.location-unique-code=' | head -n 1 | cut -d= -f2"
        )
        .read()
        .strip()
    )

    return location_unique_code

def save_hdd_info_to_json(hdd_info):
    current_timestamp_str = last_sync()

    result_dict = {
        "location_name": postgres_conn()[0],
        "location_code": location_unique_code(),
        "last_sync": current_timestamp_str,
        **hdd_info
    }

    result_json = json.dumps(result_dict, indent=4)
    with open('/tmp/storage_health_activity.json', 'w') as f:
        f.write(result_json)

    print(result_json)

# def main():
#     output = get_hdsentinel_output()
#     hdd_info_list = parse_hdsentinel_output(output)
#     system_device = get_system_storage_device()

#     system_device_prefix = re.match(r"^(/dev/[a-z]+)", system_device).group(1)

#     system_hdd_info = None
#     for hdd_info in hdd_info_list:
#         if hdd_info["device"].startswith(system_device_prefix):
#             system_hdd_info = hdd_info
#             break

#     if system_hdd_info:
#         save_hdd_info_to_json(system_hdd_info)
#     else:
#         print("Error: could not find system storage information")

def main():
    output = get_hdsentinel_output()
    hdd_info_list = parse_hdsentinel_output(output)
    system_device = get_system_storage_device()

    print(f"System device: {system_device}")

    # Modified matching logic
    system_hdd_info = None
    for hdd_info in hdd_info_list:
        if system_device in hdd_info["device"] or hdd_info["device"] in system_device:
            system_hdd_info = hdd_info
            print(f"Matched HDSentinel device: {hdd_info['device']}")
            break

    if system_hdd_info:
        save_hdd_info_to_json(system_hdd_info)
    else:
        print("Error: could not find system storage information")
        print("Available devices:")
        for hdd_info in hdd_info_list:
            print(f"- {hdd_info['device']}")

if __name__ == "__main__":
    main()