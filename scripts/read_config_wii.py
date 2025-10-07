import os
import sys
import json

def find_game_paths_from_config(directory, filename):
    """
    Reads a Dolphin Emulator configuration file to find ISO paths.
    It lists the contents and saves game files to a JSON file.

    Args:
        directory (str): The directory where the configuration file is located.
        filename (str): The name of the configuration file.
    """
    config_path = os.path.join(directory, filename)

    # Check if the configuration file actually exists
    if not os.path.isfile(config_path):
        print(f"Error: The file '{filename}' was not found in the directory '{directory}'")
        print("Please make sure the filename and directory are correct.")
        return

    print(f"Reading from: {config_path}\n")

    directory_contents = {}

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        # Loop through the game directory numbers from 0 to 9 (Dolphin supports up to 10)
        for i in range(0, 10):
            # This is the key we are searching for in each line for Dolphin.ini
            key_to_find = f"ISOPath{i}"
            
            path_found_for_id = False
            # Go through each line in the file
            for line in lines:
                # Remove any leading/trailing whitespace from the line
                clean_line = line.strip()

                # Check if the line starts with our key followed by an equals sign
                if clean_line.startswith(key_to_find + ' ' + '='):
                    # Split the line at the '=' to get the value
                    value = clean_line.split('=', 1)[1].strip()
                    
                    print(f"Value for ISOPath{i}: {value}")

                    # Check if the directory exists
                    if os.path.isdir(value):
                        try:
                            contents = os.listdir(value)
                            # Filter for common Dolphin game file extensions (case-insensitive)
                            filtered_contents = [item for item in contents if item.lower().endswith(('.iso', '.gcm', '.wbfs', '.rvz', '.wad', '.dol', '.elf'))]
                            
                            if filtered_contents:
                                # Normalize the path to use forward slashes for better consistency in the JSON file
                                normalized_path = value.replace('\\', '/')
                                directory_contents[normalized_path] = filtered_contents
                                print(f"  -> Storing {len(filtered_contents)} matching items from '{value}'")
                            else:
                                print(f"  -> No compatible game files found in '{value}'.")
                        except Exception as list_e:
                            print(f"  -> Could not list contents of '{value}': {list_e}")
                    else:
                        print(f"  -> Directory '{value}' does not exist or is not accessible.")

                    path_found_for_id = True
                    # Once found, we can stop searching for this ID and move to the next
                    break
            
            # We don't need to print "not found" for every possible path number
            # if not path_found_for_id:
            #     print(f"Path for ISOPath{i} was not found in the file.")

    except Exception as e:
        print(f"An error occurred while reading the file: {e}")

    # After checking all paths, save the collected contents to a JSON file
    if directory_contents:
        output_dir = "scripts/config"
        # Create the directory if it doesn't exist
        os.makedirs(output_dir, exist_ok=True)
        
        output_filename = os.path.join(output_dir, "gamedir_contents_wii.json")
        print(f"\nSaving found directory contents to '{output_filename}'...")
        with open(output_filename, 'w', encoding='utf-8') as f:
            json.dump(directory_contents, f, indent=4)
        print("Save complete.")
    else:
        print("\nNo directory contents were found to save.")


if __name__ == "__main__":
    # --- CONFIGURATION ---
    
    # Check if a directory path is provided as a command-line argument
    if len(sys.argv) > 1:
        # Use the directory path from the first argument
        target_directory = sys.argv[1]
        print(f"Using directory from command-line argument: {target_directory}")
    else:
        # If no argument is provided, use a default path
        target_directory = os.path.join(os.path.expanduser('~'), 'AppData', 'Roaming', 'Dolphin Emulator', 'Config')
        print(f"No directory argument provided. Using default: {target_directory}")


    # The configuration file for Dolphin Emulator
    config_file_name = "Dolphin.ini" 

    # --- SCRIPT EXECUTION ---
    find_game_paths_from_config(target_directory, config_file_name)

