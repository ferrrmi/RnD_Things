import asyncio
import aiohttp
import pandas as pd
from ping3 import ping

# Function to check if an IP can be pinged
def check_ip(ip):
    try:
        response = ping(ip, timeout=2)
        if response is not None:
            print(f"Ping successful for {ip}")
            return True
        else:
            print(f"Ping failed for {ip}")
            return False
    except Exception as e:
        print(f"Cannot ping {ip}: {e}")
        return False

# Function to fetch IP addresses from the API
async def fetch_location_data(api_url):
    async with aiohttp.ClientSession() as session:
        async with session.get(api_url) as response:
            if response.status == 200:
                return await response.json()
            else:
                print(f"Failed to fetch data: {response.status}")
                return []

# Function to check all IP addresses
async def check_all_ips(locations):
    loop = asyncio.get_event_loop()
    tasks = [loop.run_in_executor(None, check_ip, loc['location_zerotier_ip_address']) for loc in locations]
    results = await asyncio.gather(*tasks)
    return results

# Main function to run the process
async def main():
    api_url = "http://172.16.18.207:8080/location/properties/diamond/all"
    
    # Step 1: Fetch location data from API
    locations = await fetch_location_data(api_url)
    
    if not locations:
        return

    # Step 2: Check all ZeroTier IPs asynchronously
    check_results = await check_all_ips(locations)

    # Step 3: Prepare and display results with pandas
    df = pd.DataFrame(locations)
    df['connection_status'] = check_results
    print(df)

# Run the main function
if __name__ == "__main__":
    asyncio.run(main())
