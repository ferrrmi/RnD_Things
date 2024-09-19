from flask import Flask, jsonify, request
import requests
import urllib3
import logging
from colorama import Fore, Style, init

# Initialize colorama for cross-platform colored output
init(autoreset=True)

# Suppress only the InsecureRequestWarning
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Configure logging
logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

def log_request(route, method, status_code, message):
    color = Fore.GREEN if status_code < 400 else Fore.RED
    logger.info(f"{color}[{method}] {route} - Status: {status_code} - {message}{Style.RESET_ALL}")

def log_response(response):
    logger.info(f"{Fore.CYAN}Raw Response:{Style.RESET_ALL}\n{response.text}")

@app.route('/newman/latest/url', methods=['GET'])
def get_newman_url():
    try:
        response = requests.get('https://10.70.6.217/newman/latest/url', verify=False)
        
        log_response(response)
        
        if response.status_code == 200:
            log_request('/newman/latest/url', 'GET', 200, 'Success')
            return jsonify(response.json()), 200
        else:
            log_request('/newman/latest/url', 'GET', 500, 'Failed to fetch URL')
            return jsonify({'error': 'Failed to fetch URL'}), 500
    except Exception as e:
        log_request('/newman/latest/url', 'GET', 500, f'Error: {str(e)}')
        return jsonify({'error': str(e)}), 500

@app.route('/location/properties/diamond/all', methods=['GET'])
def get_location_properties():
    try:
        response = requests.get('https://10.70.6.217/location/properties/diamond/all', verify=False)
        
        log_response(response)
        
        if response.status_code == 200:
            log_request('/location/properties/diamond/all', 'GET', 200, 'Success')
            return jsonify(response.json()), 200
        else:
            log_request('/location/properties/diamond/all', 'GET', 500, 'Failed to fetch location properties')
            return jsonify({'error': 'Failed to fetch location properties'}), 500
    except Exception as e:
        log_request('/location/properties/diamond/all', 'GET', 500, f'Error: {str(e)}')
        return jsonify({'error': str(e)}), 500

@app.route('/location/properties/add-location', methods=['POST'])
def add_location():
    try:
        data = request.json
        response = requests.post(
            'https://10.70.6.217/location/properties/add-location',
            json=data,
            verify=False
        )
        
        log_response(response)
        
        if response.status_code == 201:
            log_request('/location/properties/add-location', 'POST', 201, 'Success')
            return jsonify(response.json()), 201
        elif response.status_code == 400:
            log_request('/location/properties/add-location', 'POST', 400, 'Missing attribute or key in request body')
            return jsonify({'error': 'Missing attribute or key in request body'}), 400
        else:
            log_request('/location/properties/add-location', 'POST', response.status_code, 'Failed to add location')
            return jsonify({'error': 'Failed to add location'}), response.status_code
    except Exception as e:
        log_request('/location/properties/add-location', 'POST', 500, f'Error: {str(e)}')
        return jsonify({'error': str(e)}), 500

@app.route('/newman/add/url', methods=['POST'])
def add_newman_url():
    try:
        data = request.json
        response = requests.post(
            'https://10.70.6.217/newman/add/url',
            json=data,
            verify=False
        )
        
        log_response(response)
        
        if response.status_code == 201:
            log_request('/newman/add/url', 'POST', 201, 'Success')
            return jsonify(response.json()), 201
        elif response.status_code == 400:
            log_request('/newman/add/url', 'POST', 400, 'Missing attribute or key in request body')
            return jsonify({'error': 'Missing attribute or key in request body'}), 400
        else:
            log_request('/newman/add/url', 'POST', response.status_code, 'Failed to add URL')
            return jsonify({'error': 'Failed to add URL'}), response.status_code
    except Exception as e:
        log_request('/newman/add/url', 'POST', 500, f'Error: {str(e)}')
        return jsonify({'error': str(e)}), 500

@app.route('/newman/run/all', methods=['POST'])
def run_newman_all():
    try:
        response = requests.post('https://10.70.6.217/newman/run/all', verify=False)
        
        log_response(response)
        
        if response.status_code == 200:
            log_request('/newman/run/all', 'POST', 200, 'Success')
            return jsonify(response.json()), 200
        else:
            log_request('/newman/run/all', 'POST', response.status_code, 'Failed to run Newman')
            return jsonify({'error': 'Failed to run Newman'}), response.status_code
    except Exception as e:
        log_request('/newman/run/all', 'POST', 500, f'Error: {str(e)}')
        return jsonify({'error': str(e)}), 500

@app.route('/newman/bulk/status', methods=['GET'])
def get_newman_bulk_status():
    try:
        response = requests.get('https://10.70.6.217/newman/bulk/status', verify=False)
        
        log_response(response)
        
        if response.status_code == 200:
            log_request('/newman/bulk/status', 'GET', 200, 'Success')
            return jsonify(response.json()), 200
        else:
            log_request('/newman/bulk/status', 'GET', response.status_code, 'Failed to fetch Newman bulk status')
            return jsonify({'error': 'Failed to fetch Newman bulk status'}), response.status_code
    except Exception as e:
        log_request('/newman/bulk/status', 'GET', 500, f'Error: {str(e)}')
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    print(f"{Fore.CYAN}Starting Flask server on http://0.0.0.0:5000{Style.RESET_ALL}")
    app.run(host='0.0.0.0', port=5000)