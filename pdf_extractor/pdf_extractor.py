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

@library(scope='GLOBAL')
@keyword(name='Minus Report Checker')
def main(pdf_directory):
    # Process all PDF files in the directory
    output_data = process_pdf_directory(pdf_directory)

    # Generate output JSON file
    output_filename = f"{pdf_directory}/parkee_report_minus_digit_{datetime.now().strftime('%y-%m-%d_%H:%M:%S')}.json"
    save_to_json(output_data, output_filename)
    return pdf_directory

# Disable the direct call so Robot Framework can use the main function instead.
# if __name__ == "__main__":
#     main("/opt/app/agent/parkee-agent/reportsSaver/")
