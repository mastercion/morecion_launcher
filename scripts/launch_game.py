import sys
import subprocess

def main():
    # Check if we have the correct number of command-line arguments
    # sys.argv[0] is the script name itself
    # sys.argv[1] should be the emulator path
    # sys.argv[2] should be the game path
    if len(sys.argv) != 3:
        print("Usage: python launch_game.py <emulator_path> <game_path>")
        sys.exit(1)

    emulator_path = sys.argv[1]
    game_path = sys.argv[2]

    # This is the command structure for your Switch emulator
    command_args = [
        emulator_path,
        "-f",
        "-g",
        game_path
    ]

    print(f"--- Python Launcher ---")
    print(f"Executing command: {' '.join(command_args)}")

    try:
        # Use subprocess.Popen for non-blocking execution.
        # This starts the process and immediately returns,
        # allowing Godot to continue without freezing.
        subprocess.Popen(command_args)
        print("Process started successfully.")
    except Exception as e:
        print(f"Error starting process: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()