# In res://scripts/read_config_ps3.py

import os
import sys
import json
import re
import requests
from dotenv import load_dotenv
import logging

# --- NEW: Load environment variables and set up API access ---
load_dotenv()
api_key = os.getenv("STEAMGRIDDB_API_KEY")
STEAMGRIDDB_API_URL = "https://www.steamgriddb.com/api/v2"

if api_key:
    print("API key loaded successfully!")
else:
    print("Warning: Could not load SteamGridDB API key. Make sure it's set in your .env file.")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ICON_SAVE_DIR = os.path.join(SCRIPT_DIR, 'media', 'icon')
# --- END NEW ---


# This script requires the PyYAML library.
# You can install it by running: pip install PyYAML
try:
    import yaml
except ImportError:
    print("Error: The PyYAML library is required. Please install it using 'pip install PyYAML'")
    sys.exit(1)

# --- NEW: Function to set up logging ---
def setup_logging():
    """Configures logging to write to a file."""
    log_file_path = os.path.join(SCRIPT_DIR, 'python_scanner.log')
    logging.basicConfig(
        filename=log_file_path,
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        filemode='a' # Append mode, so logs from different scripts add to the same file
    )

# --- NEW: Copied function to get and save game artwork ---
def get_game_artwork(game_filename):
    """
    Searches SteamGridDB for a game's icon, downloads it, and returns the local path.
    """
    if not api_key or api_key == "YOUR_API_KEY_HERE":
        logging.warning("SteamGridDB API Key is not set. Skipping icon search.")
        return None

    # 1. Clean filename to get a good search term
    clean_name = re.sub(r'\[.*?\]|\(.*?\)|\..*$', '', game_filename).strip()
    if not clean_name:
        return None

    logging.info(f"  -> Searching artwork for '{clean_name}'...")
    headers = {'Authorization': f'Bearer {api_key}'}
    
    try:
        # 2. Search for the game to get its ID
        search_res = requests.get(f"{STEAMGRIDDB_API_URL}/search/autocomplete/{clean_name}", headers=headers)
        search_res.raise_for_status()
        search_data = search_res.json()

        if search_data.get('success') and search_data.get('data'):
            game_id = search_data['data'][0]['id']
            
            # 3. Get icons for that game ID
            icon_res = requests.get(f"{STEAMGRIDDB_API_URL}/icons/game/{game_id}", headers=headers)
            icon_res.raise_for_status()
            icon_data = icon_res.json()

            if icon_data.get('success') and icon_data.get('data'):
                icon_url = icon_data['data'][0]['url']
                
                # 4. Download the icon
                image_res = requests.get(icon_url, stream=True)
                image_res.raise_for_status()

                # 5. Save the icon locally
                safe_filename = re.sub(r'[<>:"/\\|?*]', '_', clean_name)
                icon_filename = f"{safe_filename}.png"
                
                os.makedirs(ICON_SAVE_DIR, exist_ok=True)
                local_icon_path = os.path.join(ICON_SAVE_DIR, icon_filename)

                with open(local_icon_path, 'wb') as f:
                    for chunk in image_res.iter_content(chunk_size=8192):
                        f.write(chunk)
                
                logging.info(f"  -> Icon saved to: {local_icon_path}")
                # Return the path with forward slashes for Godot
                return local_icon_path.replace('\\', '/')
    
    except requests.exceptions.RequestException as e:
        logging.error(f"  -> API request or download failed for '{clean_name}': {e}")
    except (IndexError, KeyError):
        logging.warning(f"  -> No results found in API for '{clean_name}'.")

    return None

def find_games_from_yml(directory, filename, output_filename):
    """
    Reads a RPCS3 games.yml file to find game paths, extracts game info,
    and saves it to a JSON file for Godot.
    """
    config_path = os.path.join(directory, filename)

    if not os.path.isfile(config_path):
        logging.error(f"Error: The file '{filename}' was not found in the directory '{directory}'")
        return

    logging.info(f"Reading from: {config_path}\n")
    
    game_list = []

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            yaml_data = yaml.safe_load(f)

        if not isinstance(yaml_data, dict):
            logging.error("Error: The YAML file does not contain a valid dictionary structure.")
            return

        for game_id, game_path in yaml_data.items():
            if not os.path.isdir(game_path):
                logging.warning(f"  -> Path for {game_id} does not exist: {game_path}")
                continue

            base_name = os.path.basename(os.path.normpath(game_path))
            clean_name = re.sub(r'\[.*?\]', '', base_name).strip()
            normalized_path = game_path.replace('\\', '/')

            # --- MODIFIED: Get icon path ---
            local_icon_path = get_game_artwork(clean_name)

            game_object = {
                "name": clean_name,
                "path": normalized_path,
                "id": game_id,
                "icon_path": local_icon_path # Use the downloaded icon path
            }
            game_list.append(game_object)
            logging.info(f"  -> Found '{clean_name}'")

    except yaml.YAMLError as e:
        logging.error(f"An error occurred while parsing the YAML file: {e}")
    except Exception as e:
        logging.error(f"An unexpected error occurred: {e}")

    output_data = { directory.replace('\\', '/'): game_list }

    if game_list:
        output_dir = os.path.dirname(output_filename)
        os.makedirs(output_dir, exist_ok=True)
        
        logging.info(f"\nSaving {len(game_list)} found games to '{output_filename}'...")
        with open(output_filename, 'w', encoding='utf-8') as f:
            json.dump(output_data, f, indent=4)
        logging.info("Save complete.")
    else:
        logging.info("\nNo valid game paths were found to save.")


if __name__ == "__main__":
    setup_logging() # --- NEW ---
    logging.info("--- Starting PS3 Scan Script ---")

    if len(sys.argv) > 2:
        target_directory = sys.argv[1]
        output_file = sys.argv[2]
    else:
        logging.error("Error: Required arguments were not provided (config directory and output file path).")
        sys.exit(1)

    config_file_name = "games.yml"
    find_games_from_yml(target_directory, config_file_name, output_file)
    logging.info("--- PS3 Script Finished ---")