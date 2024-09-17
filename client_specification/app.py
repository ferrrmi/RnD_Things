import os
import json
import psycopg2


def get_system_info():
    system_info = {}

    def postgres_conn():
        """Connect to PostgreSQL and fetch location name and last sync time."""
        # Fetch unique code, database name, password, and host from the properties file
        try:
            with open("/opt/app/agent/parkee-agent/server.properties", "r") as file:
                properties = file.readlines()

            unique_code = ""
            db_host = ""

            for line in properties:
                if line.startswith("db="):
                    unique_code = line.split('=')[1].strip().replace('agent_', '')
                if line.startswith("dbHost="):
                    db_host = line.split('=')[1].strip()

            database_name = f"agent_{unique_code}"
            database_password = f"{unique_code}545115"

        except Exception as e:
            print(f"Error reading properties file: {e}")
            return None

        # Connect to PostgreSQL
        try:
            conn = psycopg2.connect(
                database=database_name,
                user="agent",
                password=database_password,
                host=db_host,
                port="5432",
            )
            cur = conn.cursor()
            cur.execute(
                """
                SELECT * FROM (
                    SELECT 
                        TRIM(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(UPPER(l.name), '\s+', ' '), 
                                '\)\s+', ') '
                            )
                        ) AS loc_name 
                    FROM location l
                ) AS subquery_alias, 
                to_char(
                    (now() AT TIME ZONE 'Asia/Bangkok'), 
                    'YYYY-MM-DD"T"HH24:MI:SS"Z"'
                ) AS last_sync
                """
            )
            query_result = cur.fetchone()
            cur.close()
            conn.close()
            return query_result
        except Exception as e:
            print(f"Error in postgres_conn: {e}")
            return None

    def get_location_unique_code():
        """Get the location unique code from the application properties file."""
        try:
            result = os.popen(
                "cat /opt/app/agent/parkee-agent/server.properties | grep 'db=' | cut -d'=' -f2- | sed 's/agent_//' | awk '{print toupper($0)}'"
            ).read().strip()
            return result
        except Exception as e:
            print(f"Error in get_location_unique_code: {e}")
            return None

    def get_processor_info():
        """Fetch processor information."""
        processor_info = {}
        try:
            processor_info["processor_name"] = (
                os.popen('lscpu | grep "Model name:" | cut -d: -f2').read().strip()
            )
            processor_info["real_core"] = (
                os.popen('lscpu | grep "Core(s) per socket:" | cut -d: -f2').read().strip()
            ) or "0"  # Handle empty real_core

            processor_info["thread_per_core"] = (
                os.popen('lscpu | grep "Thread(s) per core:" | cut -d: -f2').read().strip()
            )
        except Exception as e:
            print(f"Error in processor_info retrieval: {e}")
        return processor_info

    def get_memory_info():
        """Fetch memory information including total memory and DDR version."""
        memory_info = {}
        try:
            with open("/proc/meminfo", "r") as meminfo_file:
                for line in meminfo_file:
                    if line.startswith("MemTotal"):
                        total_memory_kb = int(line.split()[1])
                        total_memory_gb = total_memory_kb / (1024 ** 2)
                        memory_info["total_memory"] = f"{total_memory_gb:.1f} GB"
            memory_info["slot_memory"] = (
                os.popen('dmidecode -t memory | grep "Number Of Devices" | cut -d: -f2')
                .read().strip()
            ) or "0"  # Handle empty slot_memory
            memory_info["used_slot"] = (
                os.popen('dmidecode -t memory | grep "DDR" | wc -l').read().strip()
            )

            # Get DDR version
            with os.popen("dmidecode -t memory") as dmidecode_output:
                for line in dmidecode_output:
                    if "DDR" in line:
                        memory_info["ddr_version"] = line.split(":")[-1].strip()
                        break
        except Exception as e:
            print(f"Error in memory_info retrieval: {e}")
        return memory_info

    def get_storage_info():
        """Fetch storage information including model and type (SSD/HDD)."""
        storage_info = {}
        try:
            storage_model_command = (
                "lsblk -no MODEL '/dev/$(df -h / | awk 'NR>1 {print $1}' | sed 's/\/dev\/\(.*\)/\\1/' | sed 's/[0-9]*$//')' | awk 'NR==1'"
            )
            storage_info["storage_model"] = os.popen(storage_model_command).read().strip()
            storage_info["total_storage"] = (
                os.popen('lsblk -d -o size | grep -v "SIZE" | tail -n 1').read().strip()
            )
            rota_value = os.popen('lsblk -d -o rota | grep -v "ROTA" | head -n 1').read().strip()
            storage_info["rota_storage"] = "SSD" if rota_value == "0" else "HDD"
        except Exception as e:
            print(f"Error in storage_info retrieval: {e}")
        return storage_info

    try:
        # Fetch system info
        system_info["location_name"], system_info["last_sync"] = postgres_conn() or ("Unknown", "Unknown")
        system_info["location_code"] = get_location_unique_code() or "Unknown"
        system_info["location_processor"] = get_processor_info()
        system_info["location_memory"] = get_memory_info()
        system_info["location_storage"] = get_storage_info()

        # Fetch motherboard info
        system_info["location_motherboard"] = (
            os.popen('dmidecode -t baseboard | grep "Product Name:" | cut -d: -f2')
            .read().strip()
        )

    except Exception as e:
        print(f"Error in system information retrieval: {e}")
        raise

    return system_info


if __name__ == "__main__":
    try:
        system_info = get_system_info()

        json_data = json.dumps(system_info, indent=2)

        with open("/tmp/client_specification_activity.json", "w") as f:
            f.write(json_data)

        print(json_data)
    except Exception as e:
        print(f"Error in main execution: {e}")
