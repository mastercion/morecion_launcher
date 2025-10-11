# In res://scripts/read_config_wii.py

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

# --- NEW: Function to set up logging ---
def setup_logging():
    """Configures logging to write to a file."""
    log_file_path = os.path.join(SCRIPT_DIR, 'python_scanner.log')
    logging.basicConfig(
        filename=log_file_path,
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        filemode='a' # Append mode
    )

# --- NEW: Copied function to get and save game artwork ---
def get_game_artwork(game_filename):
    """
    Searches SteamGridDB for a game's icon, downloads it, and returns the local path.
    """
    if not api_key or api_key == "YOUR_API_KEY_HERE":
        logging.warning("SteamGridDB API Key is not set. Skipping icon search.")
        return None

    clean_name = re.sub(r'\[.*?\]|\(.*?\)|\..*$', '', game_filename).strip()
    if not clean_name:
        return None

    logging.info(f"  -> Searching artwork for '{clean_name}'...")
    headers = {'Authorization': f'Bearer {api_key}'}
    
    try:
        search_res = requests.get(f"{STEAMGRIDDB_API_URL}/search/autocomplete/{clean_name}", headers=headers)
        search_res.raise_for_status()
        search_data = search_res.json()

        if search_data.get('success') and search_data.get('data'):
            game_id = search_data['data'][0]['id']
            
            icon_res = requests.get(f"{STEAMGRIDDB_API_URL}/icons/game/{game_id}", headers=headers)
            icon_res.raise_for_status()
            icon_data = icon_res.json()

            if icon_data.get('success') and icon_data.get('data'):
                icon_url = icon_data['data'][0]['url']
                
                image_res = requests.get(icon_url, stream=True)
                image_res.raise_for_status()

                base_game_name = os.path.splitext(game_filename)[0]
                safe_filename = re.sub(r'[<>:"/\\|?*]', '_', base_game_name)
                icon_filename = f"{safe_filename}.png"
                
                os.makedirs(ICON_SAVE_DIR, exist_ok=True)
                local_icon_path = os.path.join(ICON_SAVE_DIR, icon_filename)

                with open(local_icon_path, 'wb') as f:
                    for chunk in image_res.iter_content(chunk_size=8192):
                        f.write(chunk)
                
                logging.info(f"  -> Icon saved to: {local_icon_path}")
                return local_icon_path.replace('\\', '/')
    
    except requests.exceptions.RequestException as e:
        logging.error(f"  -> API request or download failed for '{clean_name}': {e}")
    except (IndexError, KeyError):
        logging.warning(f"  -> No results found in API for '{clean_name}'.")

    return None

def find_game_paths_from_config(directory, filename, output_filename):
    """
    Reads a Dolphin Emulator configuration file to find ISO paths.
    It lists the contents and saves game files to a JSON file.
    """
    config_path = os.path.join(directory, filename)

    if not os.path.isfile(config_path):
        logging.error(f"Error: The file '{filename}' was not found in the directory '{directory}'")
        return

    logging.info(f"Reading from: {config_path}\n")
    directory_contents = {}

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        for i in range(0, 10):
            key_to_find = f"ISOPath{i}"
            for line in lines:
                clean_line = line.strip()
                if clean_line.startswith(key_to_find + ' ' + '='):
                    value = clean_line.split('=', 1)[1].strip()
                    logging.info(f"Value for ISOPath{i}: {value}")

                    if os.path.isdir(value):
                        try:
                            contents = os.listdir(value)
                            filtered_contents = [item for item in contents if item.lower().endswith(('.iso', '.gcm', '.wbfs', '.rvz', '.wad', '.dol', '.elf'))]
                            
                            if filtered_contents:
                                normalized_path = value.replace('\\', '/')
                                # --- MODIFIED: Loop through games to find icons ---
                                game_list = []
                                for game_file in filtered_contents:
                                    local_icon_path = get_game_artwork(game_file)
                                    game_list.append({
                                        "filename": game_file, 
                                        "icon_path": local_icon_path
                                    })
                                directory_contents[normalized_path] = game_list
                                logging.info(f"  -> Storing {len(game_list)} matching items from '{value}'")
                            else:
                                logging.info(f"  -> No compatible game files found in '{value}'.")
                        except Exception as list_e:
                            logging.warning(f"  -> Could not list contents of '{value}': {list_e}")
                    else:
                        logging.warning(f"  -> Directory '{value}' does not exist or is not accessible.")
                    break

    except Exception as e:
        logging.error(f"An error occurred while reading the file: {e}")

    if directory_contents:
        output_dir = os.path.dirname(output_filename)
        os.makedirs(output_dir, exist_ok=True)
        
        logging.info(f"\nSaving found directory contents to '{output_filename}'...")
        with open(output_filename, 'w', encoding='utf-8') as f:
            json.dump(directory_contents, f, indent=4)
        logging.info("Save complete.")
    else:
        logging.info("\nNo directory contents were found to save.")


if __name__ == "__main__":
    setup_logging() # --- NEW ---
    logging.info("--- Starting Wii Scan Script ---")

    if len(sys.argv) > 2:
        target_directory = sys.argv[1]
        output_file = sys.argv[2]
    else:
        logging.error("Error: Required command-line arguments not provided (config directory and output file path).")
        sys.exit(1)

    config_file_name = "Dolphin.ini"
    find_game_paths_from_config(target_directory, config_file_name, output_file)
    logging.info("--- Wii Script Finished ---")