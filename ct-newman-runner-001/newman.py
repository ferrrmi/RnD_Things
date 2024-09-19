import os
import json
import asyncio
import subprocess
import requests
import shutil
import logging
from datetime import datetime
import psycopg2
from psycopg2 import Error
import fcntl
import sys

# Configure logging
logging.basicConfig(
    filename='./newman-py.log',
    filemode='a',  # Append to the log file
    format='%(asctime)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

def print_styled(message, style="info"):
    styles = {
        "info": "\033[94m[INFO]\033[0m",
        "success": "\033[92m[SUCCESS]\033[0m",
        "warning": "\033[93m[WARNING]\033[0m",
        "error": "\033[91m[ERROR]\033[0m"
    }
    # Print to console
    print(f"{styles.get(style, styles['info'])} {message}")
    # Log to file based on style
    if style == "success":
        logging.info(message)
    elif style == "warning":
        logging.warning(message)
    elif style == "error":
        logging.error(message)
    else:
        logging.info(message)

# Ensure single instance of the script is running
def ensure_single_instance():
    pid_file = '/tmp/newman_script.pid'
    try:
        fp = open(pid_file, 'w')
        fcntl.lockf(fp, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except IOError:
        print_styled("Another instance is already running. Exiting.", "warning")
        sys.exit(0)
    return fp  # Keep the file open to maintain the lock

# New function to clean the log file
def clean_log_file(log_file_path):
    print_styled(f"Cleaning log file: {log_file_path}", "info")
    try:
        open(log_file_path, 'w').close()  # Clear the content of the log file
        print_styled(f"Log file {log_file_path} cleaned successfully", "success")
    except Exception as e:
        print_styled(f"Failed to clean log file {log_file_path}. Reason: {e}", "error")

# Step 1: Fetch result of the curl command
def fetch_locations(url):
    try:
        print_styled("Fetching location data...", "info")
        response = requests.get(url)
        response.raise_for_status()
        print_styled("Location data fetched successfully!", "success")
        return response.json()
    except requests.RequestException as e:
        print_styled(f"Error fetching data: {e}", "error")
        return []

# Step 2: Fetch the latest Newman URL from the API
def fetch_latest_newman_info():
    try:
        print_styled("Fetching latest Newman URL and iteration...", "info")
        response = requests.get("http://localhost:8080/newman/latest/url")
        response.raise_for_status()
        data = response.json()
        print_styled(f"Latest Newman URL fetched: {data['url']}", "success")
        print_styled(f"Iteration: {data['iteration']}", "success")
        return data
    except requests.RequestException as e:
        print_styled(f"Error fetching latest Newman info: {e}", "error")
        return None

def generate_env_files(locations, base_env_path, env_dir):
    print_styled("Generating environment files...", "info")
    if not os.path.exists(env_dir):
        os.makedirs(env_dir)

    with open(base_env_path, 'r') as base_file:
        base_data = json.load(base_file)

    for location in locations:
        file_name = f"{location['location_unique_code']}_env.json"
        file_path = os.path.join(env_dir, file_name)

        # Modify base data inside the "values" field
        for item in base_data['values']:
            if item['key'] == 'hostname':
                item['value'] = location['location_zerotier_ip_address']
            elif item['key'] == 'cutoff':
                # Connect to the database and fetch the cutoff value
                try:
                    connection = psycopg2.connect(
                        user="agent",
                        password=f"{location['location_unique_code']}545115",
                        host=location['location_zerotier_ip_address'],
                        database=f"agent_{location['location_unique_code']}"
                    )
                    cursor = connection.cursor()
                    cursor.execute("SELECT cutoff FROM location_setting WHERE id = 1")
                    cutoff_location = cursor.fetchone()[0]
                    item['value'] = cutoff_location
                    print_styled(f"Cutoff value fetched for {location['location_name']}: {cutoff_location}", "success")
                except (Exception, Error) as error:
                    print_styled(f"Error while connecting to PostgreSQL for {location['location_name']}: {error}", "error")
                    item['value'] = "CUTOFF_07"  # Default value if database connection fails
                finally:
                    if connection:
                        cursor.close()
                        connection.close()

        # Write the new file
        with open(file_path, 'w') as env_file:
            json.dump(base_data, env_file, indent=4)

        print_styled(f"Environment file created for {location['location_name']}: {file_path}", "success")

# Step 4: Check reachability of each IP address
def is_reachable(ip_address):
    print_styled(f"Checking reachability for {ip_address}...", "info")
    result = subprocess.run(["ping", "-c", "1", ip_address], stdout=subprocess.DEVNULL)
    return result.returncode == 0

def check_location_connectivity(locations, result_dir):
    print_styled("Checking IP reachability for all locations...", "info")
    if not os.path.exists(result_dir):
        os.makedirs(result_dir)

    timeout_locations = []
    connected_locations = []

    for location in locations:
        if is_reachable(location["location_zerotier_ip_address"]):
            print_styled(f"{location['location_name']} is reachable!", "success")
            connected_locations.append(location)
        else:
            print_styled(f"{location['location_name']} is not reachable!", "warning")
            timeout_locations.append(location)

    # Write timeout locations to JSON file
    timeout_file = os.path.join(result_dir, "timeout_location.json")
    with open(timeout_file, 'w') as tf:
        json.dump(timeout_locations, tf, indent=4)

    print_styled("Timeout locations saved to timeout_location.json", "warning")
    return connected_locations

async def run_newman(semaphore, location, newman_url, iteration):
    async with semaphore:
        print_styled(f"Running newman.sh for {location['location_name']} with iteration {iteration}...", "info")
        process = await asyncio.create_subprocess_shell(
            f"./newman.sh {location['location_unique_code']} {newman_url} {iteration}",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await process.communicate()
        print_styled(f"Completed newman.sh for {location['location_name']}", "success")
        return location, process.returncode

async def run_newman_async(connected_locations, newman_url, iteration, max_workers=10):
    print_styled(f"Starting asynchronous execution of newman.sh for {len(connected_locations)} locations...", "info")
    semaphore = asyncio.Semaphore(max_workers)
    tasks = set()

    async def worker():
        while True:
            if not connected_locations:
                break
            location = connected_locations.pop(0)
            task = asyncio.create_task(run_newman(semaphore, location, newman_url, iteration))
            tasks.add(task)
            task.add_done_callback(tasks.discard)

            done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)

            for task in done:
                location, result = await task
                print_styled(f"Task for {location['location_name']} completed with exit code: {result}", "info")

    await asyncio.gather(*(worker() for _ in range(max_workers)))

    # Wait for any remaining tasks to complete
    if tasks:
        await asyncio.wait(tasks)

    print_styled("Asynchronous execution completed!", "success")

def scp_files(source_dir, destination, file_suffix):
    print_styled(f"Copying files from {source_dir} to {destination}...", "info")
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    copied_files = []
    
    for filename in os.listdir(source_dir):
        if filename.endswith(file_suffix):
            new_filename = f"{os.path.splitext(filename)[0]}_{timestamp}{os.path.splitext(filename)[1]}"
            source_path = os.path.join(source_dir, filename)
            dest_path = f"{destination}/{new_filename}"
            
            try:
                subprocess.run(["scp", source_path, dest_path], check=True)
                copied_files.append(new_filename)
            except subprocess.CalledProcessError:
                print_styled(f"Failed to copy file: {filename}", "error")
    
    if copied_files:
        print_styled(f"Files copied successfully to {destination}", "success")
        print_styled("List of copied files:", "info")
        for file in copied_files:
            print_styled(f"- {file}", "info")
    else:
        print_styled("No files were copied.", "warning")

def clean_directory(directory, exclude_file=None):
    print_styled(f"Cleaning directory: {directory}", "info")
    for filename in os.listdir(directory):
        file_path = os.path.join(directory, filename)
        if exclude_file and os.path.abspath(file_path) == os.path.abspath(exclude_file):
            continue
        try:
            if os.path.isfile(file_path):
                os.unlink(file_path)
            elif os.path.isdir(file_path):
                shutil.rmtree(file_path)
        except Exception as e:
            print_styled(f"Failed to delete {file_path}. Reason: {e}", "error")
    print_styled(f"Directory {directory} cleaned successfully", "success")

def set_newman_status(status):
    url = f"http://localhost:8080/newman/bulk/status/{'start' if status == 1 else 'stop'}"
    try:
        response = requests.post(url)
        response.raise_for_status()
        print_styled(f"Newman status set to {'running' if status == 1 else 'stopped'}", "success")
    except requests.RequestException as e:
        print_styled(f"Error setting Newman status: {e}", "error")

def main():
    # Ensure only one instance of the script is running
    ensure_single_instance()
    
    url = "http://localhost:8080/location/properties/diamond/all"
    base_env_path = "./env/based_env.json"
    env_dir = "./env/"
    result_dir = "./connection_result/"
    
    # Clean directories
    clean_directory("./results")
    clean_directory("./log")

    # Clean the ./env/ folder, excluding based_env.json
    clean_directory(env_dir, exclude_file="./env/based_env.json")

    # Clean the log file
    # clean_log_file('./newman-py.log')

    # Fetch locations
    locations = fetch_locations(url)

    # Check location connectivity and get connected locations
    connected_locations = check_location_connectivity(locations, result_dir)

    # Generate environment files only for connected locations
    generate_env_files(connected_locations, base_env_path, env_dir)

    # Fetch the latest Newman URL and iteration
    newman_info = fetch_latest_newman_info()

    if newman_info:
        # Set Newman status to start (1)
        set_newman_status(1)

        # Run newman.sh for connected locations asynchronously
        asyncio.run(run_newman_async(connected_locations, newman_info['url'], newman_info['iteration']))

        # SCP results files
        scp_files("./results", "server-qaa@172.16.18.210:/home/server-qaa/Codes/docker_files/PAA/index/postman/html/", ".html")

        # SCP log files
        scp_files("./log", "server-qaa@172.16.18.210:/home/server-qaa/Codes/docker_files/PAA/index/postman/log/", ".log")

        # Run remote script
        print_styled("Running remote script...", "info")
        subprocess.run(["ssh", "server-qaa@172.16.18.210", "/home/server-qaa/Codes/docker_files/PAA/index/postman/generate_data_json.sh"])
        subprocess.run(["ssh", "server-qaa@172.16.18.210", "/home/server-qaa/Codes/docker_files/PAA/index/postman/generate_log_json.sh"])
        print_styled("Remote script execution completed", "success")

        # Set Newman status to stop (0)
        set_newman_status(0)

if __name__ == "__main__":
    main()