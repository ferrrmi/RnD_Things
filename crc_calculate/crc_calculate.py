import binascii

smart_tag_number = "E2004EC83B82B94A3021340D"
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