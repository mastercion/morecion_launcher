import os
import sys
import json

def find_game_paths_from_config(directory, filename, output_filename):
    """
    Reads a Dolphin Emulator configuration file to find ISO paths.
    It lists the contents and saves game files to a JSON file.

    Args:
        directory (str): The directory where the configuration file is located.
        filename (str): The name of the configuration file.
        output_filename (str): The full path to save the output JSON file.
    """
    config_path = os.path.join(directory, filename)

    if not os.path.isfile(config_path):
        print(f"Error: The file '{filename}' was not found in the directory '{directory}'")
        return

    print(f"Reading from: {config_path}\n")
    directory_contents = {}

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        for i in range(0, 10):
            key_to_find = f"ISOPath{i}"
            path_found_for_id = False
            for line in lines:
                clean_line = line.strip()
                if clean_line.startswith(key_to_find + ' ' + '='):
                    value = clean_line.split('=', 1)[1].strip()
                    print(f"Value for ISOPath{i}: {value}")

                    if os.path.isdir(value):
                        try:
                            contents = os.listdir(value)
                            filtered_contents = [item for item in contents if item.lower().endswith(('.iso', '.gcm', '.wbfs', '.rvz', '.wad', '.dol', '.elf'))]
                            
                            if filtered_contents:
                                normalized_path = value.replace('\\', '/')
                                # MODIFIED: Create a list of game objects, not just filenames
                                game_list = [{"filename": game_file, "icon_path": None} for game_file in filtered_contents]
                                directory_contents[normalized_path] = game_list
                                print(f"  -> Storing {len(game_list)} matching items from '{value}'")
                            else:
                                print(f"  -> No compatible game files found in '{value}'.")
                        except Exception as list_e:
                            print(f"  -> Could not list contents of '{value}': {list_e}")
                    else:
                        print(f"  -> Directory '{value}' does not exist or is not accessible.")

                    path_found_for_id = True
                    break

    except Exception as e:
        print(f"An error occurred while reading the file: {e}")

    if directory_contents:
        # MODIFIED: Create the output directory if it doesn't exist
        output_dir = os.path.dirname(output_filename)
        os.makedirs(output_dir, exist_ok=True)
        
        print(f"\nSaving found directory contents to '{output_filename}'...")
        with open(output_filename, 'w', encoding='utf-8') as f:
            json.dump(directory_contents, f, indent=4)
        print("Save complete.")
    else:
        print("\nNo directory contents were found to save.")


if __name__ == "__main__":
    target_directory = ""
    output_file = ""

    # MODIFIED: Check for both command-line arguments
    if len(sys.argv) > 2:
        target_directory = sys.argv[1]
        output_file = sys.argv[2]
        print(f"Using directory from command-line argument: {target_directory}")
        print(f"Using output file from command-line argument: {output_file}")
    elif len(sys.argv) > 1:
        # Fallback for manual testing (like you did)
        target_directory = sys.argv[1]
        output_file = os.path.join("scripts", "config", "gamedir_contents_wii.json")
        print(f"Using directory from command-line argument: {target_directory}")
        print(f"Warning: Output file not provided. Using default: {output_file}")
    else:
        print("Error: Required command-line arguments not provided.")
        sys.exit(1) # Exit with an error code

    config_file_name = "Dolphin.ini"
    find_game_paths_from_config(target_directory, config_file_name, output_file)