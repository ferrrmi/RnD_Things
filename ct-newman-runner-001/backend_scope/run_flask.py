import os
import logging
from logging.handlers import RotatingFileHandler
import subprocess
from flask import Flask, jsonify, request
from flask_cors import CORS
from apscheduler.schedulers.background import BackgroundScheduler
import psycopg2
from psycopg2.extras import RealDictCursor
from contextlib import contextmanager

# Configuration
DEBUG = True
HOST = '0.0.0.0'
PORT = 8080
LOG_FILE = '/var/log/newman_app.log'
PID_FILE = '/tmp/newman_bash_script.pid'
NEWMAN_SCRIPT = '/opt/app/agent/newman/run_newman.sh'

# Database connection parameters
DB_PARAMS = {
    'dbname': 'agent_dev',
    'user': 'agent',
    'password': 'dev545115',
    'host': 'localhost',
    'port': '5432'
}

# Set up logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG if DEBUG else logging.INFO)
handler = RotatingFileHandler(LOG_FILE, maxBytes=10000000, backupCount=5)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)

app = Flask(__name__)
CORS(app)

@contextmanager
def get_db_connection():
    """Context manager for database connections."""
    conn = None
    try:
        conn = psycopg2.connect(**DB_PARAMS)
        yield conn
    except Exception as e:
        logger.error(f"Database connection error: {e}")
        raise
    finally:
        if conn:
            conn.close()

def check_pid_file():
    """Check if the PID file exists and if the process is running."""
    if os.path.exists(PID_FILE):
        with open(PID_FILE, 'r') as f:
            pid = f.read().strip()
        try:
            os.kill(int(pid), 0)
            return True
        except OSError:
            os.remove(PID_FILE)
    return False

def run_newman_script():
    """Run the Newman script and manage the PID file."""
    if check_pid_file():
        logger.warning("Newman script is already running.")
        return False

    try:
        process = subprocess.Popen([NEWMAN_SCRIPT], 
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE,
                                   text=True)
        
        with open(PID_FILE, 'w') as f:
            f.write(str(process.pid))
        
        logger.info("Newman script execution started.")
        return True
    except Exception as e:
        logger.error(f"Error running Newman script: {e}")
        return False

def start_scheduler():
    """Set up and start the APScheduler."""
    scheduler = BackgroundScheduler()
    scheduler.add_job(run_newman_script, 'cron', hour=0, minute=0)
    scheduler.start()
    logger.info("Scheduler started.")

@app.route('/newman/run/all', methods=['POST'])
def run_newman_script_route():
    """Route to run the Newman script asynchronously."""
    if run_newman_script():
        return jsonify({"message": "Newman script execution started"}), 202
    else:
        return jsonify({"error": "Failed to start Newman script"}), 500

@app.route('/location/properties/diamond/all')
def diamond_locations():
    """Fetch all Diamond locations."""
    try:
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("""
                    SELECT location_name, location_unique_code, location_zerotier_ip_address
                    FROM location
                    WHERE deleted_at IS NULL AND location_tier = 'Diamond';
                """)
                locations = cur.fetchall()
        return jsonify(locations)
    except Exception as e:
        logger.error(f"Error fetching Diamond locations: {e}")
        return jsonify({"error": "Unable to fetch locations"}), 500

@app.route('/newman/latest/url')
def latest_newman_url():
    """Fetch the latest Newman URL."""
    try:
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("""
                    SELECT url, iteration, uuid
                    FROM newman
                    ORDER BY updated_at DESC
                    LIMIT 1;
                """)
                latest_url = cur.fetchone()
        return jsonify(latest_url)
    except Exception as e:
        logger.error(f"Error fetching latest Newman URL: {e}")
        return jsonify({"error": "Unable to fetch the latest Newman URL"}), 500

@app.route('/location/properties/add-location', methods=['POST'])
def add_new_location():
    """Add a new location."""
    data = request.json
    required_fields = ['location_name', 'location_unique_code', 'location_tier', 'location_zerotier_ip_address']
    
    if not all(field in data for field in required_fields):
        return jsonify({"error": "Missing required fields"}), 400

    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO location (location_name, location_unique_code, location_tier, location_zerotier_ip_address)
                    VALUES (%s, %s, %s, %s);
                """, (data['location_name'], data['location_unique_code'], data['location_tier'], data['location_zerotier_ip_address']))
                conn.commit()
        return jsonify({"message": "Location added successfully!"}), 201
    except Exception as e:
        logger.error(f"Error adding new location: {e}")
        return jsonify({"error": "Failed to add location"}), 500

@app.route('/newman/add/url', methods=['POST'])
def add_new_newman_url():
    """Add a new Newman URL with iteration."""
    data = request.json
    if 'url' not in data or 'iteration' not in data:
        return jsonify({"error": "URL and iteration are required"}), 400

    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO newman (url, iteration)
                    VALUES (%s, %s);
                """, (data['url'], data['iteration']))
                conn.commit()
        return jsonify({"message": "Newman URL added successfully!"}), 201
    except Exception as e:
        logger.error(f"Error adding new Newman URL: {e}")
        return jsonify({"error": "Failed to add Newman URL"}), 500

@app.route('/newman/bulk/status', methods=['GET'])
def bulk_newman_status():
    """Check bulk Newman status."""
    try:
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("""
                    SELECT start_date, end_date, status, uuid
                    FROM bulk_newman_status
                    WHERE id = 1;
                """)
                status = cur.fetchone()
        return jsonify(status)
    except Exception as e:
        logger.error(f"Error fetching bulk Newman status: {e}")
        return jsonify({"error": "Unable to fetch bulk Newman status"}), 500

@app.route('/newman/bulk/status/start', methods=['POST'])
def start_bulk_newman_route():
    """Set bulk Newman status to active."""
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE bulk_newman_status
                    SET status = 1, start_date = now()
                    WHERE id = 1;
                """)
                conn.commit()
        return jsonify({"message": "Bulk Newman status set to active"}), 200
    except Exception as e:
        logger.error(f"Error setting bulk Newman status to active: {e}")
        return jsonify({"error": "Failed to set bulk Newman status to active"}), 500

@app.route('/newman/bulk/status/stop', methods=['POST'])
def stop_bulk_newman_route():
    """Set bulk Newman status to inactive."""
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE bulk_newman_status
                    SET status = 0, end_date = now()
                    WHERE id = 1;
                """)
                conn.commit()
        return jsonify({"message": "Bulk Newman status set to inactive"}), 200
    except Exception as e:
        logger.error(f"Error setting bulk Newman status to inactive: {e}")
        return jsonify({"error": "Failed to set bulk Newman status to inactive"}), 500

if __name__ == '__main__':
    start_scheduler()
    app.run(host=HOST, port=PORT, debug=DEBUG)