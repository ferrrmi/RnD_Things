from robot.api.deco import library, keyword
import subprocess
import binascii

@library(scope='GLOBAL')
@keyword(name='Send Tap Wuzz')
def send_tap_member_wuzz(smart_tag_number):
    file_path = '/opt/app/agent/parkee-agent/fake_port.txt'

    def get_robot_prop_value(file_path):
        with open(file_path, 'r') as file:
            for line in file:
                if line.startswith('robot_additional_prop_2:'):
                    return line.split(':')[1].strip()
        return None

    # Get the robot_prop value
    robot_prop_value = get_robot_prop_value(file_path)

    if robot_prop_value:
        # Change ownership and permissions of the file
        try:
            subprocess.run(['sudo', 'chown', 'root:root', robot_prop_value], check=True)
            subprocess.run(['sudo', 'chmod', '666', robot_prop_value], check=True)
        except subprocess.CalledProcessError as e:
            print(f"An error occurred while changing file permissions: {e}")
            return

        smart_tag_number_hex = " ".join([smart_tag_number[i:i+2] for i in range(0, len(smart_tag_number), 2)])
        input_hex = f"AA AA FF 18 C1 01 00 C7 30 00 {smart_tag_number_hex} 8F 52 00"
        input_bytes = bytes.fromhex(input_hex.replace(" ", ""))
        crc = binascii.crc_hqx(input_bytes, 0xFFFF)
        checksum_hex = f"{crc:04X}"
        checksum_hex = checksum_hex[:2] + " " + checksum_hex[2:]
        output_hex = input_hex + " " + checksum_hex
        print(f"output_hex: ", output_hex)
        output_hex_list = [int(x, 16) for x in input_hex.split()]
        print(f"output_hex_list: ", output_hex_list)
        output_hex_bytes = bytes(output_hex_list)
        print(f"output_hex_bytes: ", output_hex_bytes)

        try:
            with open(robot_prop_value, 'wb') as f:
                f.write(output_hex_bytes)
            print("Command executed successfully.")
        except Exception as e:
            print(f"An error occurred: {e}")
    else:
        print("robot_prop value not found.")
        
# smart_tag_number = "E2004EC83B8798CA3021478B"
# send_tap_member_wuzz(smart_tag_number)