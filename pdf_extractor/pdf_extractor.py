import os
import PyPDF2
import re
import json
from datetime import datetime
import pytz
from robot.api.deco import library, keyword

def extract_pdf_text(pdf_path):
    with open(pdf_path, 'rb') as file:
        pdf_reader = PyPDF2.PdfReader(file)
        text = ""
        for page in pdf_reader.pages:
            text += page.extract_text() + "\n"
    return text

def get_last_10_lines_after_total(text):
    lines = text.split('\n')
    total_index = next((i for i, line in enumerate(lines) if "TOTAL" in line), -1)
    if total_index != -1:
        return lines[total_index:][-10:]
    return []

def find_negative_numbers(text):
    pattern = r'-\d{1,3}(?:,\d{3})*(?:\.\d+)?'
    return re.findall(pattern, text)

def process_pdf_directory(directory):
    results = []
    for filename in os.listdir(directory):
        if filename.endswith(".pdf"):
            pdf_path = os.path.join(directory, filename)
            print(f"\nProcessing: {filename}")

            full_text = extract_pdf_text(pdf_path)
            last_10_lines = get_last_10_lines_after_total(full_text)

            if last_10_lines:
                print("Last 10 lines after TOTAL:")
                minus_data = {}
                for i, line in enumerate(last_10_lines, 1):
                    print(line)
                    negative_numbers = find_negative_numbers(line)
                    if negative_numbers:
                        minus_data[f"lineOf{i}"] = negative_numbers

                if minus_data:
                    print("Negative numbers found:")
                    for line, numbers in minus_data.items():
                        print(f"{line}: {', '.join(numbers)}")

                    results.append({
                        "reportName": filename,
                        "checkTime": datetime.now(pytz.utc).isoformat(),
                        "minusData": minus_data
                    })
                else:
                    print("No negative numbers found in the specified format.")
            else:
                print("No 'TOTAL' line found in the document.")

    return results

def save_to_json(data, output_filename):
    with open(output_filename, 'w') as json_file:
        json.dump(data, json_file, indent=2)
    print(f"\nOutput saved to {output_filename}")

def get_latest_json_file(directory):
    json_files = [f for f in os.listdir(directory) if f.startswith('parkee_report_minus_digit') and f.endswith('.json')]
    if not json_files:
        return None, None
    latest_file = max(json_files, key=lambda f: os.path.getmtime(os.path.join(directory, f)))
    latest_file_path = os.path.join(directory, latest_file)
    
    # Read the content of the latest file
    with open(latest_file_path, 'r') as file:
        file_content = json.load(file)
    
    return latest_file, file_content

@library(scope='GLOBAL')
@keyword(name='Check Minus Digit')
def main(pdf_directory):
    # Process all PDF files in the directory
    output_data = process_pdf_directory(pdf_directory)

    # Generate output JSON file
    output_filename = f"{pdf_directory}/parkee_report_minus_digit_{datetime.now().strftime('%y-%m-%d_%H:%M:%S')}.json"
    save_to_json(output_data, output_filename)

    # Return the name and content of the latest JSON file
    latest_file_name, latest_file_content = get_latest_json_file(pdf_directory)
    return latest_file_name, latest_file_content

# Disable the direct call so Robot Framework can use the main function instead.
# if __name__ == "__main__":
#     main("/opt/app/agent/parkee-agent/reportsSaver/")
