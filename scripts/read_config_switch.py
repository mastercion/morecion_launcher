import os
import sys
import json
import logging
import re
import requests
from dotenv import load_dotenv

load_dotenv()
api_key = os.getenv("STEAMGRIDDB_API_KEY")
STEAMGRIDDB_API_URL = "https://www.steamgriddb.com/api/v2"

if api_key:
    print("API key loaded successfully!")
    # Check for API Key, for easier debugging later
else:
    print("Error: Could not load API key. Make sure it's set in your .env file.")

# Get the directory where the script is located
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# Define the directory to save icons, relative to the script's location
ICON_SAVE_DIR = os.path.join(SCRIPT_DIR, 'media', 'icon')

def setup_logging():
    """Configures logging to write to a file."""
    log_file_path = os.path.join(SCRIPT_DIR, 'python_scanner.log')
    
    logging.basicConfig(
        filename=log_file_path,
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        filemode='w'
    )

# --- ADDED: Function to get and save game artwork ---
def get_game_artwork(game_filename):
    """
    Searches SteamGridDB for a game's icon, downloads it, and returns the local path.
    """
    if not STEAMGRIDDB_API_KEY or STEAMGRIDDB_API_KEY == "YOUR_API_KEY_HERE":
        logging.warning("SteamGridDB API Key is not set. Skipping icon search.")
        return None

    # 1. Clean filename to get a good search term
    clean_name = re.sub(r'\[.*?\]|\(.*?\)|\..*$', '', game_filename).strip()
    if not clean_name:
        return None

    logging.info(f"  -> Searching artwork for '{clean_name}'...")
    headers = {'Authorization': f'Bearer {STEAMGRIDDB_API_KEY}'}
    
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
                # Create a valid filename from the original game name (without extension)
                base_game_name = os.path.splitext(game_filename)[0]
                # Sanitize the name to remove characters invalid for filenames
                safe_filename = re.sub(r'[<>:"/\\|?*]', '_', base_game_name)
                icon_filename = f"{safe_filename}.png"
                
                # Create the media/icon directory if it doesn't exist
                os.makedirs(ICON_SAVE_DIR, exist_ok=True)
                local_icon_path = os.path.join(ICON_SAVE_DIR, icon_filename)

                with open(local_icon_path, 'wb') as f:
                    for chunk in image_res.iter_content(chunk_size=8192):
                        f.write(chunk)
                
                logging.info(f"  -> Icon saved to: {local_icon_path}")
                return local_icon_path
    
    except requests.exceptions.RequestException as e:
        logging.error(f"  -> API request or download failed for '{clean_name}': {e}")
    except (IndexError, KeyError):
        logging.warning(f"  -> No results found in API for '{clean_name}'.")

    return None


def find_game_paths_from_config(directory, filename):
    config_path = os.path.join(directory, filename)

    if not os.path.isfile(config_path):
        logging.error(f"The file '{filename}' was not found in the directory '{directory}'")
        return

    logging.info(f"Reading from: {config_path}")
    directory_contents = {}

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        for i in range(1, 6):
            key_to_find = f"Paths\\gamedirs\\{i}\\path="
            path_found_for_id = False
            for line in lines:
                clean_line = line.strip()
                if clean_line.startswith(key_to_find):
                    value = clean_line.split('=', 1)[1]
                    logging.info(f"Value for gamedir {i}: {value}")

                    if len(value) >= 2 and value[0].isalpha() and value[1] == ':':
                        if os.path.isdir(value):
                            try:
                                contents = os.listdir(value)
                                filtered_contents = [item for item in contents if item.lower().endswith(('.nsp', '.xci'))]
                                
                                # --- MODIFIED: Process each game to get icon ---
                                if filtered_contents:
                                    game_list = []
                                    for game_file in filtered_contents:
                                        # Call the function to get and save the icon
                                        local_icon_path = get_game_artwork(game_file)
                                        # Add game object to the list
                                        game_list.append({
                                            "filename": game_file,
                                            "icon_path": local_icon_path
                                        })
                                    
                                    directory_contents[value] = game_list
                                    logging.info(f"  -> Storing {len(game_list)} items from '{value}'")
                                else:
                                    logging.info(f"  -> No .nsp or .xci files found in '{value}'.")
                            except Exception as list_e:
                                logging.warning(f"  -> Could not list contents of '{value}': {list_e}")
                        else:
                            logging.warning(f"  -> Directory '{value}' does not exist or is not accessible.")
                    path_found_for_id = True
                    break
            
            if not path_found_for_id:
                logging.info(f"Path for gamedir {i} was not found in the file.")

    except Exception as e:
        logging.error(f"An error occurred while reading the file: {e}")

    if directory_contents:
        if len(sys.argv) > 2:
            output_filename = sys.argv[2]
            output_dir = os.path.dirname(output_filename)
            os.makedirs(output_dir, exist_ok=True)
    
            logging.info(f"Saving found directory contents to '{output_filename}'...")
            with open(output_filename, 'w', encoding='utf-8') as f:
                json.dump(directory_contents, f, indent=4)
            logging.info("Save complete.")
        else:
            logging.error("Output file path was not provided to the script.")


if __name__ == "__main__":
    setup_logging()
    logging.info("--- Starting Python Scan Script ---")
    
    if len(sys.argv) > 1:
        target_directory = sys.argv[1]
        logging.info(f"Using directory from command-line argument: {target_directory}")
    else:
        target_directory = os.path.join(os.path.expanduser('~'), 'AppData', 'Roaming', 'eden', 'config')
        logging.info(f"No directory argument provided. Using default: {target_directory}")

    config_file_name = "qt-config.ini" 
    find_game_paths_from_config(target_directory, config_file_name)
    logging.info("--- Python Script Finished ---")