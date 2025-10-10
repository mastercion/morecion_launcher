import sys
import win32gui
import win32con
import logging
import os

# Get the directory where the script is located
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

def setup_logging():
    """Configures logging to write to a file."""
    log_file_path = os.path.join(SCRIPT_DIR, 'python_scanner.log')
    logging.basicConfig(
        filename=log_file_path,
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        filemode='w'
    )

def force_focus(partial_title):
    """Finds a window whose title starts with partial_title and focuses it."""
    logging.info(f"--- Searching for window starting with: '{partial_title}' ---")
    
    # --- START OF THE FIX ---
    # We will replace the exact search with a loop that finds a partial match.
    
    hwnd = None
    
    def callback(handle, extra):
        # This function is called for every open window.
        nonlocal hwnd
        if win32gui.IsWindowVisible(handle):
            window_text = win32gui.GetWindowText(handle)
            # Check if the window's title starts with the text we're looking for.
            if window_text.startswith(partial_title):
                hwnd = handle # If it matches, we've found our window.

    # Enumerate through all windows and run our callback function.
    win32gui.EnumWindows(callback, None)
    
    # --- END OF THE FIX ---

    try:
        if not hwnd:
            logging.error(f"Window starting with '{partial_title}' not found.")
            return

        logging.info(f"Found matching window: '{win32gui.GetWindowText(hwnd)}' ({hwnd})")
        
        win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
        win32gui.SetForegroundWindow(hwnd)
        
        if win32gui.GetForegroundWindow() == hwnd:
            logging.info(f"SUCCESS: Window is now the foreground window.")
        else:
            logging.warning(f"FAILURE: OS prevented the window from taking focus.")

    except Exception as e:
        logging.error(f"An unexpected error occurred", exc_info=True)

if __name__ == "__main__":
    setup_logging()
    logging.info("--- Focus Script Starting ---")
    
    if len(sys.argv) > 1:
        title = sys.argv[1]
        force_focus(title)
    else:
        print("Usage: python focus_window.py \"Partial Window Title\"")
        logging.warning("Script was called with no window title argument.")
    
    logging.info("--- Focus Script Finished ---")