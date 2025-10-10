extends Node

var is_combo_pressed: bool = false

func _ready() -> void:
	print("✅ Controller Hook script is active and listening.")
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	var a_down: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_X)
	var b_down: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_Y)
	var select_down: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_START)

	if a_down and b_down and select_down:
		if not is_combo_pressed:
			is_combo_pressed = true
			print("Controller hook activated! Calling external Python script...")

			# 1. Get the current window's title.
			var window_title = get_tree().root.title

			# --- START OF THE FIX ---
			# 2a. Define the Godot-specific path to your script.
			var godot_script_path = "res://scripts/focus_window.py"
			
			# 2b. Convert it to a full system path that the OS can understand.
			var absolute_script_path = ProjectSettings.globalize_path(godot_script_path)

			# 2c. Prepare the arguments for the Python script using the new absolute path.
			var args = [absolute_script_path, window_title]
			# --- END OF THE FIX ---
			
			# 3. Execute the script.
			OS.create_process("python", args)
	else:
		is_combo_pressed = false
