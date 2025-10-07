import os
import sys
import json
import logging

def setup_logging():
    """Configures logging to write to a file."""
    # The log file will be created in the same directory as this script.
    log_file_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'python_scanner.log')
    
    logging.basicConfig(
        filename=log_file_path,
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        filemode='w'  # 'w' overwrites the log file on each run, use 'a' to append
    )

def find_game_paths_from_config(directory, filename):
    """
    Reads a configuration file to find specific game directory paths.
    If a path is a directory, it lists its contents and saves them to a JSON file.

    Args:
        directory (str): The directory where the configuration file is located.
        filename (str): The name of the configuration file.
    """
    config_path = os.path.join(directory, filename)

    # Check if the configuration file actually exists
    if not os.path.isfile(config_path):
        logging.error(f"The file '{filename}' was not found in the directory '{directory}'")
        logging.error("Please make sure the filename and directory are correct.")
        return

    logging.info(f"Reading from: {config_path}")

    directory_contents = {}

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        # Loop through the game directory numbers from 1 to 5
        for i in range(1, 6):
            # This is the key we are searching for in each line
            # Note: We use double backslashes '\\' because a single backslash is an escape character.
            key_to_find = f"Paths\\gamedirs\\{i}\\path="
            
            path_found_for_id = False
            # Go through each line in the file
            for line in lines:
                # Remove any leading/trailing whitespace from the line
                clean_line = line.strip()

                # Check if the line starts with our key
                if clean_line.startswith(key_to_find):
                    # Split the line at the '=' to get the value
                    # The '1' ensures we only split on the first '=', in case the path has an '='
                    value = clean_line.split('=', 1)[1]
                    
                    logging.info(f"Value for gamedir {i}: {value}")

                    # Check if the value looks like a drive path (e.g., "E:/")
                    if len(value) >= 2 and value[0].isalpha() and value[1] == ':':
                        # Check if the directory exists
                        if os.path.isdir(value):
                            try:
                                contents = os.listdir(value)
                                # Filter the list for files ending with .nsp or .xci (case-insensitive)
                                filtered_contents = [item for item in contents if item.lower().endswith(('.nsp', '.xci'))]
                                
                                if filtered_contents:
                                    directory_contents[value] = filtered_contents
                                    logging.info(f"  -> Storing {len(filtered_contents)} matching items from '{value}'")
                                else:
                                    logging.info(f"  -> No .nsp or .xci files found in '{value}'.")
                            except Exception as list_e:
                                logging.warning(f"  -> Could not list contents of '{value}': {list_e}")
                        else:
                            logging.warning(f"  -> Directory '{value}' does not exist or is not accessible.")

                    path_found_for_id = True
                    # Once found, we can stop searching for this ID and move to the next
                    break
            
            if not path_found_for_id:
                logging.info(f"Path for gamedir {i} was not found in the file.")

    except Exception as e:
        logging.error(f"An error occurred while reading the file: {e}")

    # After checking all paths, save the collected contents to a JSON file
    if directory_contents:
        # Check if the output path argument was provided by Godot
        if len(sys.argv) > 2:
            output_filename = sys.argv[2]  # Use the full path from the 3rd argument (index 2)
            
            # Get the directory part of the path and create it if it doesn't exist
            output_dir = os.path.dirname(output_filename)
            os.makedirs(output_dir, exist_ok=True)
    
            logging.info(f"Saving found directory contents to '{output_filename}'...")
            with open(output_filename, 'w', encoding='utf-8') as f:
                json.dump(directory_contents, f, indent=4)
            logging.info("Save complete.")
        else:
            logging.error("Output file path was not provided to the script.")


if __name__ == "__main__":
    # --- SCRIPT SETUP ---
    setup_logging()
    
    # --- CONFIGURATION ---
    logging.info("--- Starting Python Scan Script ---")
    
    # Check if a directory path is provided as a command-line argument
    if len(sys.argv) > 1:
        # Use the directory path from the first argument
        target_directory = sys.argv[1]
        logging.info(f"Using directory from command-line argument: {target_directory}")
    else:
        # If no argument is provided, use the default path
        target_directory = os.path.join(os.path.expanduser('~'), 'AppData', 'Roaming', 'eden', 'config')
        logging.info(f"No directory argument provided. Using default: {target_directory}")


    # !!! IMPORTANT !!!
    # You need to specify the name of the file that contains the path information.
    # I have used 'settings.ini' as a placeholder.
    config_file_name = "qt-config.ini" 

    # --- SCRIPT EXECUTION ---
    find_game_paths_from_config(target_directory, config_file_name)
    logging.info("--- Python Script Finished ---")
