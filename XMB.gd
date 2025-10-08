extends Control 
# XMB-like Menu for Godot 4 
# This script handles navigation, animation, and dynamic creation of menu items. 

# --- 1. SCRIPT VARIABLES --- 

# MENU_DATA is now a variable that will be loaded from a file 
var MENU_DATA = {} 

# Preload the background item template scene 
const BackgroundItemScene = preload("res://BackgroundItem.tscn") 
const ZOOM_INCREMENT = 0.2 
const EMULATOR_CONFIG_PATH = "user://emulator_paths.cfg"
const MENU_DATA_PATH = "res://menu_data.json"

enum { XMB, SETTINGS } 
var current_state = XMB 

# Layout & Animation Settings 
const HORIZONTAL_SPACING = 300 
const VERTICAL_SPACING = 170 
const ICON_SIZE = Vector2(100, 100) 
const LABEL_Y_OFFSET = 15 
var ANIM_SPEED = 0.2 

# State Variables 
var highlight_color = Color.GOLD
var custom_backgrounds = [] 
var background_fit_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED 
var manual_background_zoom = 1.0 
var is_animating = false
var glow_tween: Tween
var settings_history = [] 
var current_selection = Vector2i.ZERO 
var current_settings_selection_index = 0 
var emulator_paths = {}
var current_emulator_selection = ""
var last_launched_game_coords = Vector2i(-1, -1)
var default_shader_time_speed: float = 1.0
var needs_background_reset = false

# Node References 
@onready var camera_origin = $CameraOrigin 
@onready var selection_label = $SelectionInfo/CurrentSelectionLabel 
@onready var settings_panel = $SettingsPanel 
@onready var settings_title_label = $SettingsPanel/SettingsTitleLabel 
@onready var settings_list_container = $SettingsPanel/SettingsListContainer 
@onready var settings_grid_container = $SettingsPanel/SettingsGridContainer 
@onready var background_file_dialog = $BackgroundFileDialog 
@onready var emulator_dir_dialog = $EmulatorDirDialog
@onready var emulator_dir_dialog_exec = $EmulatorDirDialogExec
@onready var xmb_ui_elements = [$CameraOrigin, $SelectionInfo] 
@onready var background_particles = $Background 
@onready var background_container = $BackgroundContainer 
@onready var background_image = $BackgroundContainer/BackgroundImage
@onready var navigation_sound = $NavigationSound
@onready var background_shader_rect = $ColorRect

# --- NEW: References for the launch animation ---
@onready var launch_overlay = $LaunchAnimationOverlay
@onready var animated_icon = $LaunchAnimationOverlay/AnimatedIcon
@onready var animated_label = $LaunchAnimationOverlay/AnimatedLabel
@onready var loading_spinner = $LaunchAnimationOverlay/LoadingSpinner
@onready var dimbackground = $LaunchAnimationOverlay/DimBackground
@onready var process_check_timer = $ProcessCheckTimer

var category_container: Node2D 
var item_columns_container: Node2D 
var category_nodes = [] 
var item_columns = [] 
var categories = [] 
var main_settings_items = [] 

# --- 2. GODOT ENGINE CALLBACKS --- 

func _ready():
	# Load persistent data first
	load_menu_data() 
	load_emulator_paths()

	# Default Shader Behaivor
	default_shader_time_speed = background_shader_rect.material.get_shader_parameter("time_speed")
	
	settings_panel.visible = false 
	background_image.visible = false 
	
	# Create containers for menu items
	category_container = Node2D.new() 
	category_container.name = "CategoryContainer" 
	camera_origin.add_child(category_container) 
	
	item_columns_container = Node2D.new() 
	item_columns_container.name = "ItemColumnsContainer" 
	camera_origin.add_child(item_columns_container) 
	
	# Build the visual menu from the loaded data
	build_xmb_from_data()
	
	# Connect signals
	background_file_dialog.file_selected.connect(_on_background_file_selected) 
	emulator_dir_dialog.dir_selected.connect(_on_emulator_dir_selected)
	emulator_dir_dialog_exec.file_selected.connect(_on_emulator_dir_selected)
	Input.joy_connection_changed.connect(update_controller_display) 
	update_controller_display()
	
	# Add this line
	$PythonPathDialog.file_selected.connect(_on_python_path_selected)
	
	# --- NEW: Setup and start the process checker ---
	process_check_timer.wait_time = 3.0 # Check every 3 seconds
	process_check_timer.timeout.connect(_on_process_check_timeout)
	process_check_timer.start()

func _unhandled_input(event): 
	var dialogs_visible = background_file_dialog.visible or emulator_dir_dialog.visible or emulator_dir_dialog_exec.visible or $PythonPathDialog.visible
	if is_animating or dialogs_visible: 
		return 
	match current_state: 
		XMB: handle_xmb_input(event) 
		SETTINGS: handle_settings_input(event) 

func _on_process_check_timeout():
	# If no game has been launched, there's nothing to check.
	if last_launched_game_coords == Vector2i(-1, -1):
		return

	# 1. Get the category and executable path for the *specific game* that was launched.
	var category_index = last_launched_game_coords.x
	var category_name = categories[category_index]
	var exec_key = category_name + "_EXEC"

	# 2. If we don't have an emulator executable path for this category, we can't check it.
	if not emulator_paths.has(exec_key):
		return

	# 3. Get the emulator's .exe name (e.g., "yuzu.exe").
	var full_path = emulator_paths[exec_key]
	var exe_name = full_path.get_file()

	# 4. Check if that specific emulator process is still running.
	var is_running = is_process_running(exe_name)

	# 5. If the process is NOT running anymore, it means the user closed the game.
	if not is_running:
		# Reset the coordinates to their default "no game launched" state.
		last_launched_game_coords = Vector2i(-1, -1)
		# Call the existing update function, which will now hide the icon.
		update_play_icons()


# Helper function that checks if a process is running on Windows.
func is_process_running(exe_name: String) -> bool:
	var output = []
	var command = "tasklist"
	var args = ["/NH", "/FI", "IMAGENAME eq %s" % exe_name]
	
	# OS.execute runs the command and captures the output
	var exit_code = OS.execute(command, args, output, true)
	
	if exit_code == OK:
		# If the output contains the exe name, the process was found.
		return not output.is_empty() and output[0].contains(exe_name)
	
	return false

# --- 3. DATA LOADING & PERSISTENCE ---

func load_menu_data():
	var settings_data = {
		"icon_path": "res://src/icons/settings/icon_settings.svg",
		"items": {
			"Display": { "type": "submenu", "icon_path": "res://src/icons/settings/icon_display.svg", "options": ["Menu Speed", "Menu Color", "Background", "Effects"] },
			"Audio": { "type": "submenu", "icon_path": "res://src/icons/settings/icon_audio.svg", "options": ["Master Volume", "Music Volume", "SFX Volume"] },
			"Controller Settings": { "type": "submenu", "icon_path": "res://src/icons/settings/icon_controller.svg", "options": ["Vibration", "Button Mapping", "Deadzone"] },
			"Emulator": { "type": "submenu", "icon_path": "res://src/icons/settings/icon_emulator.svg", "options": ["Switch", "Switch_EXEC", "Wii", "Wii_EXEC", "Playstation 3"] },
			"System": { "type": "submenu", "icon_path": "res://src/icons/settings/icon_system.svg", "options": ["Set Python Path"] },
			"Set Python Path": { "type": "action", "icon_path": "res://src/icons/settings/icon_pythonset.svg" },
			"Exit": { "type": "action", "icon_path": "res://src/icons/settings/icon_exit.svg" },
			
			"Menu Speed": { "type": "list", "options": ["Slow", "Standard", "Fast"] },
			"Menu Color": { "type": "list", "options": ["Blue", "Green", "Yellow", "Red"] },
			"Background": { "type": "submenu", "options": ["Select Background", "Image Fit", "Manual Zoom"] },
			
			"Select Background": { "type": "grid" },
			"Image Fit": { "type": "list", "options": ["Stretch", "Zoom", "Center"] },
			"Manual Zoom": { "type": "list", "options": ["Zoom In (+)", "Zoom Out (-)"] }
		}
	}

	var game_data = {}
	if not FileAccess.file_exists(MENU_DATA_PATH):
		print("menu_data.json not found, creating a default one.")
		game_data = {
			"Switch": { "icon_path": "res://src/icons/platform/icon_switch.svg", "items": [] },
			"Wii": { "icon_path": "res://src/icons/platform/icon_wii.svg", "items": [] }
		}
		save_game_data_to_json(game_data)
	else:
		var file = FileAccess.open(MENU_DATA_PATH, FileAccess.READ)
		var content = file.get_as_text().strip_edges() # Read and trim whitespace
		
		# FIX: Check if the file content is empty before parsing
		if content.is_empty():
			print("Warning: menu_data.json is empty. Re-initializing.")
			game_data = {
				"Switch": { "icon_path": "res://src/icons/platform/icon_switch.svg", "items": [] },
				"Wii": { "icon_path": "res://src/icons/platform/icon_wii.svg", "items": [] }
			}
		else:
			var json = JSON.new()
			var error = json.parse(content)
			if error != OK:
				print("Error parsing menu_data.json: ", json.get_error_message(), " at line ", json.get_error_line())
			else:
				game_data = json.data
	
	MENU_DATA = game_data
	MENU_DATA["Settings"] = settings_data

func save_emulator_paths():
	var config = ConfigFile.new()
	for key in emulator_paths:
		config.set_value("paths", key, emulator_paths[key])
	config.save(EMULATOR_CONFIG_PATH)

func load_emulator_paths():
	var config = ConfigFile.new()
	var err = config.load(EMULATOR_CONFIG_PATH)
	if err != OK: return
	
	if not config.has_section("paths"): return
	var keys = config.get_section_keys("paths")
	for key in keys:
		emulator_paths[key] = config.get_value("paths", key)

# Saves the game list portion of MENU_DATA to the JSON file.
func save_game_data_to_json(data_to_save):
	var file = FileAccess.open(MENU_DATA_PATH, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(data_to_save, "\t")
		file.store_string(json_string)
	else:
		print("Error: Could not write to ", MENU_DATA_PATH)

# --- 4. INPUT & NAVIGATION --- 

func handle_xmb_input(event): 
	var direction = Vector2i.ZERO 
	if event.is_action_pressed("ui_right"): direction.x = 1 
	elif event.is_action_pressed("ui_left"): direction.x = -1 
	elif event.is_action_pressed("ui_down"): direction.y = 1 
	elif event.is_action_pressed("ui_up"): direction.y = -1 
	elif event.is_action_pressed("ui_accept"): handle_accept_action() 
	if direction != Vector2i.ZERO: move_selection(direction) 

func handle_settings_input(event): 
	if event.is_action_pressed("ui_cancel"): go_back_in_settings() 
	elif event.is_action_pressed("ui_down"): move_settings_selection(Vector2i(0, 1)) 
	elif event.is_action_pressed("ui_up"): move_settings_selection(Vector2i(0, -1)) 
	elif event.is_action_pressed("ui_right"): move_settings_selection(Vector2i(1, 0)) 
	elif event.is_action_pressed("ui_left"): move_settings_selection(Vector2i(-1, 0)) 
	elif event.is_action_pressed("ui_accept"): handle_settings_accept() 

func update_play_icons():
	# Loop through all category columns
	for x in range(item_columns.size()):
		var column = item_columns[x]
		# Loop through all game items in that column
		for y in range(column.get_child_count()):
			var item_node = column.get_child(y)
			if item_node.has_node("PlayIconOverlay"):
				var play_icon = item_node.get_node("PlayIconOverlay")
				
				# The coordinates for an item are (columnIndex, itemIndex + 1)
				var item_coords = Vector2i(x, y + 1)
				
				# Show the icon only if its coordinates match the one we launched
				play_icon.visible = (item_coords == last_launched_game_coords)

func move_selection(direction: Vector2i):
	var new_selection = current_selection + direction 
	new_selection.x = clamp(new_selection.x, 0, categories.size() - 1) 
	if direction.x != 0: new_selection.y = 0 
	
	var category_key = categories[new_selection.x] 
	var item_count = main_settings_items.size() if category_key == "Settings" else MENU_DATA[category_key]["items"].size() 
	new_selection.y = clamp(new_selection.y, 0, item_count) 
	
	if new_selection != current_selection:
		navigation_sound.play()
		current_selection = new_selection 
		animate_to_selection() 
		update_item_visibility() 
		update_selection_highlight() 

func move_settings_selection(direction: Vector2i): 
	var container 
	var menu_info = MENU_DATA["Settings"]["items"][settings_history.back()] 
	if menu_info.type == "grid": container = settings_grid_container 
	else: container = settings_list_container 

	var items = container.get_children() 
	if items.is_empty(): return 
	
	var old_index = current_settings_selection_index
	var new_index = current_settings_selection_index 
	if menu_info.type == "grid": 
		var columns = container.columns 
		new_index += direction.y * columns + direction.x 
	else: 
		new_index += direction.y 
	current_settings_selection_index = clamp(new_index, 0, items.size() - 1)
	
	if old_index != current_settings_selection_index:
		navigation_sound.play()

	update_settings_highlight() 

# --- 5. DRAG AND DROP --- 

func _can_drop_data(_pos, data): 
	if current_state == SETTINGS and not settings_history.is_empty() and settings_history.back() == "Select Background": 
		return typeof(data) == TYPE_DICTIONARY and data.has("files") 
	return false 

func _drop_data(_pos, data): 
	for file_path in data["files"]: 
		add_background_item(file_path) 

# --- 6. ACTION HANDLERS --- 

func handle_accept_action(): 
	var category_key = categories[current_selection.x] 
	if current_selection.y == 0: return 

	if category_key == "Settings":
		var item_index = current_selection.y - 1 
		var item_name = main_settings_items[item_index] 
		var item_info = MENU_DATA["Settings"]["items"][item_name]
		if item_info.get("type") == "action":
			if item_name == "Exit":
				get_tree().quit()
		else: # If it's not an action, it must be a submenu
			show_settings_panel(item_name)
	else: 
		# --- GAME LAUNCH LOGIC ---
		var selected_node = get_item_node(current_selection)
		if not selected_node or not selected_node.has_meta("game_path"):
			print("Error: Could not launch game because path metadata is missing.")
			return
		
		# Instead of launching directly, we now call our animation function.
		play_launch_animation_and_run_game(selected_node, category_key)

func handle_settings_accept(): 
	var current_menu_title = settings_history.back() 
	var menu_info = MENU_DATA["Settings"]["items"][current_menu_title] 
	var selected_option_text
	
	if menu_info.type == "grid": 
		var selected_button = settings_grid_container.get_children()[current_settings_selection_index] 
		if selected_button.has_meta("image_path"): selected_option_text = selected_button.get_meta("image_path") 
		elif selected_button.has_meta("option_text"): selected_option_text = selected_button.get_meta("option_text") 
		else: selected_option_text = "Unknown" 
	else: 
		selected_option_text = menu_info["options"][current_settings_selection_index] 
		
	var next_menu_info = MENU_DATA["Settings"]["items"].get(selected_option_text) 

	if next_menu_info and next_menu_info.get("type") == "action":
		if selected_option_text == "Set Python Path":
			$PythonPathDialog.popup_centered()
		elif selected_option_text == "Exit":
			get_tree().quit()
		return # Stop the function here

	# If it's a submenu or list, show the next panel.
	if next_menu_info and next_menu_info.has("type"): 
		show_settings_panel(selected_option_text) 
	else: 
		# This part now only handles final choices from a list, like "Slow" or "Fast".
		match current_menu_title: 
			"Menu Speed": 
				match selected_option_text: 
					"Slow": ANIM_SPEED = 0.3 
					"Standard": ANIM_SPEED = 0.2 
					"Fast": ANIM_SPEED = 0.1 
				go_back_in_settings() 
			"Menu Color": 
				match selected_option_text: 
					"Blue": highlight_color = Color.DODGER_BLUE 
					"Green": highlight_color = Color.LIME_GREEN 
					"Yellow": highlight_color = Color.GOLD 
					"Red": highlight_color = Color.CRIMSON 
				update_selection_highlight(); update_settings_highlight() 
				go_back_in_settings() 
			"Select Background": 
				if selected_option_text == "+ Add New": 
					background_file_dialog.popup_centered() 
				elif selected_option_text == "Built-in Effect": 
					background_particles.visible = true 
					background_image.visible = false 
					go_back_in_settings() 
				else: 
					apply_background_settings(selected_option_text) 
					go_back_in_settings() 
			"Image Fit": 
				match selected_option_text: 
					"Stretch": background_fit_mode = TextureRect.STRETCH_SCALE 
					"Zoom": background_fit_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED 
					"Center": background_fit_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED 
				apply_background_settings() 
				go_back_in_settings() 
			"Manual Zoom": 
				if selected_option_text == "Zoom In (+)": manual_background_zoom += ZOOM_INCREMENT 
				elif selected_option_text == "Zoom Out (-)": manual_background_zoom = max(0.1, manual_background_zoom - ZOOM_INCREMENT) 
				apply_background_settings() 
			"Emulator":
				current_emulator_selection = selected_option_text
				if selected_option_text.ends_with("EXEC"):
					emulator_dir_dialog_exec.popup_centered()
				else:
					emulator_dir_dialog.popup_centered()
# --- 7. UI & VISUALS --- 

func show_settings_panel(title: String): 
	if not settings_history.has(title): settings_history.push_back(title) 
	
	current_state = SETTINGS 
	settings_title_label.text = title 
	
	for child in settings_list_container.get_children(): child.queue_free() 
	for child in settings_grid_container.get_children(): child.queue_free() 
	
	var menu_info = MENU_DATA["Settings"]["items"].get(title) 
	if not menu_info: return 

	if menu_info.type == "grid": 
		settings_grid_container.visible = true 
		settings_list_container.visible = false 
		rebuild_background_grid() 
	else: 
		settings_grid_container.visible = false 
		settings_list_container.visible = true 
		for option_text in menu_info["options"]: 
			var button = Button.new() 
			button.text = option_text 
			button.custom_minimum_size.y = 40 
			
			if title == "Emulator" and emulator_paths.has(option_text):
				button.text = "%s [%s]" % [option_text, emulator_paths[option_text]]
			
			settings_list_container.add_child(button) 
		
	for element in xmb_ui_elements: element.visible = false 
	settings_panel.visible = true 
	current_settings_selection_index = 0 
	update_settings_highlight() 

func rebuild_background_grid(): 
	for child in settings_grid_container.get_children(): child.queue_free() 

	var builtin_btn = BackgroundItemScene.instantiate() 
	builtin_btn.get_node("Thumbnail").texture = load("res://icon.svg") 
	var label = Label.new(); label.text = "Built-in Effect"; label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.autowrap_mode = TextServer.AUTOWRAP_WORD;
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER) 
	builtin_btn.add_child(label) 
	builtin_btn.set_meta("option_text", "Built-in Effect") 
	settings_grid_container.add_child(builtin_btn) 
	
	for path in custom_backgrounds: 
		var item_btn = BackgroundItemScene.instantiate() 
		var thumbnail_rect = item_btn.get_node("Thumbnail") 
		var img = Image.load_from_file(path) 
		if not img.is_empty(): thumbnail_rect.texture = ImageTexture.create_from_image(img) 
		item_btn.set_meta("image_path", path) 
		settings_grid_container.add_child(item_btn) 

	var add_new_btn = BackgroundItemScene.instantiate() 
	var add_label = Label.new(); add_label.text = "+ Add New"; add_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; 
	add_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) 
	add_new_btn.add_child(add_label) 
	add_new_btn.set_meta("option_text", "+ Add New") 
	settings_grid_container.add_child(add_new_btn) 
	
	update_settings_highlight() 

func go_back_in_settings(): 
	settings_history.pop_back() 
	if settings_history.is_empty(): 
		current_state = XMB 
		for element in xmb_ui_elements: element.visible = true 
		settings_panel.visible = false 
	else: 
		show_settings_panel(settings_history.back()) 

func add_background_item(path: String): 
	if not (path.ends_with(".png") or path.ends_with(".jpg")): return 
	if not custom_backgrounds.has(path): 
		custom_backgrounds.append(path) 
		rebuild_background_grid() 

func _on_python_path_selected(path: String):
	emulator_paths["python_executable_path"] = path
	save_emulator_paths()
	print("Python executable path saved: ", path)

func apply_background_settings(image_path: String = ""): 
	if image_path: 
		var img = Image.load_from_file(image_path) 
		if not img.is_empty(): 
			background_image.texture = ImageTexture.create_from_image(img) 
			background_image.visible = true 
			background_particles.visible = false 
		else: 
			print("Error: Could not load background image from path: ", image_path) 
			return 

	background_image.stretch_mode = background_fit_mode 
	background_image.scale = Vector2.ONE * manual_background_zoom 
	background_image.pivot_offset = background_image.size / 2 
	background_image.position = background_container.size / 2 

func _on_background_file_selected(path: String): 
	add_background_item(path) 
	
func _on_emulator_dir_selected(path: String):
	# This function now handles paths from BOTH dialogs.
	# It always saves the selected path to the dictionary.
	print("Saving path for '%s': %s" % [current_emulator_selection, path])
	emulator_paths[current_emulator_selection] = path
	save_emulator_paths()
	
	# Refresh the settings panel to show the newly saved path.
	show_settings_panel(settings_history.back())

	# IMPORTANT: Only trigger the game scan for game directories, not executables.
	if current_emulator_selection == "Switch" or current_emulator_selection == "Wii":
		generate_game_list_for_emulator(current_emulator_selection, path)
	
func update_selection_highlight():
	# Stop and clear any existing glow animation to prevent conflicts
	if glow_tween:
		glow_tween.kill()

	# Reset all nodes to their default appearance
	for node in category_nodes:
		node.modulate = Color.WHITE
		node.scale = Vector2.ONE
	for column in item_columns:
		for item in column.get_children():
			item.modulate = Color.WHITE
			item.scale = Vector2.ONE

	var selected_node = get_item_node(current_selection) # [cite: 26]
	if selected_node:
		selected_node.scale = Vector2.ONE * 1.4 # [cite: 27]

		# Define the brighter color for the "peak" of the glow
		# Multiplying a color makes its RGB values exceed 1.0, creating an HDR/glow effect.
		var bright_color = highlight_color * 1.8

		# Create a new tween that will run indefinitely
		glow_tween = create_tween().set_loops()
		glow_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

		# Animate the color property ("modulate") to the bright color over 0.8 seconds
		glow_tween.tween_property(selected_node, "modulate", bright_color, 0.8)
		# Animate it back to the base highlight color over the next 0.8 seconds
		glow_tween.tween_property(selected_node, "modulate", highlight_color, 0.8)

func update_settings_highlight():
	# Stop and clear any existing glow animation
	if glow_tween:
		glow_tween.kill()

	var menu_info = MENU_DATA["Settings"]["items"].get(settings_history.back())
	if not menu_info: return

	var container = settings_grid_container if menu_info.type == "grid" else settings_list_container
	var buttons = container.get_children()

	# Reset all buttons that are NOT selected
	for i in range(buttons.size()):
		if i != current_settings_selection_index:
			buttons[i].modulate = Color.WHITE

	# Check if the selection index is valid
	if current_settings_selection_index >= 0 and current_settings_selection_index < buttons.size():
		var selected_button = buttons[current_settings_selection_index]
		
		# Define the bright color for the glow effect
		var bright_color = highlight_color * 1.8

		# Create and configure the looping tween for the settings item
		glow_tween = create_tween().set_loops()
		glow_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		
		# Animate the modulate property for the glowing pulse effect
		glow_tween.tween_property(selected_button, "modulate", bright_color, 0.8)
		glow_tween.tween_property(selected_button, "modulate", highlight_color, 0.8)

func update_item_visibility(): 
	for i in range(item_columns.size()): 
		var is_active = (i == current_selection.x) 
		for item in item_columns[i].get_children(): item.visible = is_active 

# --- 8. UI BUILDING & REBUILDING ---

# Clears and rebuilds the entire XMB menu from MENU_DATA.
func rebuild_xmb_menu():
	# Clear existing nodes
	for child in category_container.get_children(): child.queue_free()
	for child in item_columns_container.get_children(): child.queue_free()
	
	# Clear internal node arrays
	category_nodes.clear()
	item_columns.clear()
	
	# Re-run the build process
	build_xmb_from_data()

# Extracted the main menu building logic so it can be re-used.
func build_xmb_from_data():
	# Build the main XMB menu from the loaded MENU_DATA
	categories = MENU_DATA.keys() 
	for category_name in categories: 
		var category_data = MENU_DATA[category_name] 
		var items 
		if category_name == "Settings": 
			items = [] 
			for key in category_data["items"].keys(): 
				var item_data = category_data["items"][key] 
				if item_data.has("type") and (item_data.type == "submenu" or item_data.type == "action"):
					items.append(key) 
			main_settings_items = items 
		else: 
			items = category_data.get("items", []) # Use .get for safety
		
		var category_index = categories.find(category_name) 
		var icon = category_data.get("icon_path", "res://icon.svg")
		var category_node = create_menu_item(category_name, icon, true)
		category_node.position = Vector2(category_index * HORIZONTAL_SPACING, 0) 
		category_container.add_child(category_node) 
		category_nodes.push_back(category_node) 
		
		var column_node = Node2D.new() 
		column_node.position.x = category_node.position.x 
		item_columns_container.add_child(column_node) 
		item_columns.push_back(column_node) 
		
		for i in range(items.size()):
			var item_entry = items[i]
			var item_name = ""
			var icon_path = "res://icon.svg" # Default fallback
			var item_node: Control

			if category_name == "Settings":
				# For settings, the entry is a string (the menu item's name)
				item_name = item_entry
				var item_data = category_data["items"][item_name]
				if item_data.has("icon_path"):
					icon_path = item_data.icon_path
				item_node = create_menu_item(item_name, icon_path, false)

			else:
				# For games, the entry should be a dictionary { "name": ..., "path": ... }
				if typeof(item_entry) == TYPE_DICTIONARY:
					item_name = item_entry.get("name", "Unknown Game")
					item_node = create_menu_item(item_name, icon_path, false)
					# Store the full path as metadata in the node for later use (e.g., launching)
					item_node.set_meta("game_path", item_entry.get("path", ""))
				else:
					# Fallback for any old string-based data
					item_name = str(item_entry)
					item_node = create_menu_item(item_name, icon_path, false)

			item_node.position = Vector2(0, (i + 1) * VERTICAL_SPACING)
			column_node.add_child(item_node)
			
	update_item_visibility() 
	current_selection = Vector2i.ZERO
	update_selection_highlight() 
	
	var initial_pos_x = -get_category_position(current_selection.x) 
	category_container.position.x = initial_pos_x 
	item_columns_container.position.x = initial_pos_x 

func _execute_game_launch(category_key: String, game_path: String) -> int:
	match category_key:
		"Switch":
			var python_executable = emulator_paths.get("python_executable_path", "python")
			var emulator_exec_key = "Switch_EXEC"
			if not emulator_paths.has(emulator_exec_key):
				print("Error: Switch emulator executable path is not set in Settings.")
				return FAILED # Return an error code
			var emulator_exec_path = emulator_paths[emulator_exec_key]
			var launcher_script_path = ProjectSettings.globalize_path("res://scripts/launch_game.py")

			var command_to_run = '"%s" "%s" "%s" "%s"' % [
				python_executable, 
				launcher_script_path, 
				emulator_exec_path, 
				game_path
			]

			var cmd_args = ["/c", command_to_run]
			print("--- Godot: Calling Python Launcher via CMD ---")
			print("Executing: cmd.exe ", " ".join(cmd_args))

			var output = []
			var error = OS.execute("cmd.exe", cmd_args, output, true)
			if error != OK:
				print("Error: Failed to start the command process. Exit code: ", error)
				print("Output: ", "\n".join(output))
			
			return error # Return the result

		"Wii":
			print("Wii launch logic is not yet implemented.")
			return FAILED

		_:
			print("Cannot launch. No launch logic for category '%s'." % [category_key])
			return FAILED

	return FAILED

func _notification(what):
	# This function is called when the game window's state changes.
	# We check if the window just regained focus.
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		# If it did, and our flag is set, it's time to run the reset animation.
		if needs_background_reset:
			# Set the flag to false immediately so this animation doesn't run again.
			needs_background_reset = false
			
			# Create a new tween to animate the background back to its standard state.
			var reset_tween = create_tween().set_parallel()
			reset_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			
			# Animate the speed from 0 back to the default.
			reset_tween.tween_property(background_shader_rect.material, "shader_parameter/time_speed", default_shader_time_speed, 1.5)
			# Animate the color from dim gray back to white.
			reset_tween.tween_property(background_shader_rect, "modulate", Color.WHITE, 1.5)

func play_launch_animation_and_run_game(node: Control, category_key: String):
	# 1. Prevent player input and show overlays
	is_animating = true
	loading_spinner.visible = true
	dimbackground.visible = true

	# --- RESET STATE AND GO WILD ---
	background_shader_rect.modulate = Color.WHITE # <-- ADD THIS LINE
	background_shader_rect.material.set_shader_parameter("time_speed", 25.0)

	# 2. Get info from the selected item
	var original_icon: TextureRect = node.get_node("Icon")
	var original_label: Label = node.get_node("Label")
	var game_path = node.get_meta("game_path")

	# 3. Setup the animation overlay
	animated_icon.texture = original_icon.texture
	animated_label.text = original_label.text
	animated_label.add_theme_font_size_override("font_size", 30)

	# Get starting positions of the original item
	var start_pos = original_icon.get_global_transform_with_canvas().get_origin()
	var start_scale = original_icon.get_global_transform_with_canvas().get_scale()
	
	animated_icon.global_position = start_pos
	animated_icon.scale = start_scale
	animated_label.global_position = start_pos + Vector2(0, 120 * start_scale.y)

	# Pre-Animation Setup
	loading_spinner.modulate.a = 0.0
	launch_overlay.visible = true
	
	# 4. Create a SINGLE tween to handle all animations
	var tween = create_tween().set_parallel()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# ... (rest of the animation code is unchanged) ...
	var screen_size = get_viewport_rect().size
	var screen_center = screen_size / 2
	
	var icon_target_scale = Vector2.ONE * 3.0
	tween.tween_property(animated_icon, "global_position", screen_center - (animated_icon.size * icon_target_scale / 2), 0.6)
	tween.tween_property(animated_icon, "scale", icon_target_scale, 0.6)

	var font = animated_label.get_theme_font("font")
	var font_size = animated_label.get_theme_font_size("font_size")
	var text_size = font.get_string_size(animated_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

	var label_target_pos = Vector2(
		screen_center.x - (text_size.x / 2),
		screen_center.y + 150
	)
	tween.tween_property(animated_label, "global_position", label_target_pos, 0.6)
	
	var spinner_target_pos = Vector2(
		screen_center.x - (loading_spinner.size.x / 2),
		label_target_pos.y + text_size.y + 50
	)
	tween.tween_property(loading_spinner, "position", spinner_target_pos, 0.6)
	tween.tween_property(loading_spinner, "modulate:a", 1.0, 0.6)

	# 5. Wait for animations and delay
	await tween.finished
	
	# --- FREEZE AND DIM THE SHADER (NOW WITH SMOOTHING) ---
	var dissipate_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Animate the shader's speed down to 0 to freeze it
	dissipate_tween.tween_property(background_shader_rect.material, "shader_parameter/time_speed", 0.0, 1.0)
	# Animate the modulate color to a dim gray to darken it
	dissipate_tween.tween_property(background_shader_rect, "modulate", Color(0.3, 0.3, 0.3, 1.0), 1.0)
	await dissipate_tween.finished
	
	await get_tree().create_timer(3.0).timeout 
	
	# Remember which game we are about to launch.
	last_launched_game_coords = current_selection
	# Update the UI to show the play icon.
	update_play_icons()

	# 6. Execute the game launch
	var launch_result = _execute_game_launch(category_key, game_path)
	
	# 7. Minimize on success
	if launch_result == OK:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)

	needs_background_reset = true 

	# 8. Clean up animation overlay
	launch_overlay.visible = false
	is_animating = false
	loading_spinner.visible = false
	dimbackground.visible = false

func create_menu_item(text: String, icon_path: String, is_category: bool) -> Control: 
	var control = Control.new(); control.set_meta("is_category", is_category)
	var icon = TextureRect.new()
	icon.name = "Icon"
	if ResourceLoader.exists(icon_path): icon.texture = load(icon_path) 
	else: print("Warning: Icon not found: ", icon_path); icon.texture = load("res://icon.svg") 
	icon.custom_minimum_size = ICON_SIZE; icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.position = -ICON_SIZE / 2 
	var label = Label.new(); label.name = "Label"; label.text = text; label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; label.position = Vector2(-200,50) 
	label.custom_minimum_size = Vector2(400, 50); control.add_child(icon); control.add_child(label) 
	if not is_category:
		var play_icon = TextureRect.new()
		play_icon.name = "PlayIconOverlay"
		play_icon.texture = load("res://src/icons/settings/icon_playing.svg") # Your icon path
		play_icon.custom_minimum_size = Vector2(48, 48) # Adjust size as needed
		play_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		play_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		# Position it at the bottom-right of the main icon
		play_icon.position = (ICON_SIZE / 2) - play_icon.custom_minimum_size - Vector2(5, 5)
		
		play_icon.visible = false # Hide it by default
		control.add_child(play_icon)
	if is_category: 
		var theme_override = Theme.new(); theme_override.set_font_size("font_size", "Label", 30)
		label.theme = theme_override 
	return control 

# --- 9. ANIMATION & HELPERS ---

func animate_to_selection(): 
	is_animating = true 
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) 
	var target_pos_x = -get_category_position(current_selection.x) 
	tween.tween_property(category_container, "position:x", target_pos_x, ANIM_SPEED) 
	tween.parallel().tween_property(item_columns_container, "position:x", target_pos_x, ANIM_SPEED) 
	for i in range(item_columns.size()): 
		var target_pos_y = 0 
		if i == current_selection.x and current_selection.y > 0: target_pos_y = -(current_selection.y * VERTICAL_SPACING) 
		tween.parallel().tween_property(item_columns[i], "position:y", target_pos_y, ANIM_SPEED) 
		tween.parallel().tween_property(category_nodes[i], "position:y", target_pos_y, ANIM_SPEED) 
	await tween.finished 
	is_animating = false 

func get_category_position(coord_x: int) -> float: return coord_x * HORIZONTAL_SPACING 

func get_item_node(coords: Vector2i) -> Control: 
	if coords.x < 0 or coords.x >= category_nodes.size(): return null 
	if coords.y == 0: return category_nodes[coords.x] 
	var column = item_columns[coords.x]; var item_index = coords.y - 1
	if item_index < 0 or item_index >= column.get_child_count(): return null 
	return column.get_child(item_index) 

func update_controller_display(): 
	var joypads = Input.get_connected_joypads() 
	selection_label.text = Input.get_joy_name(joypads[0]) if not joypads.is_empty() else "Keyboard & Mouse" 


# Main function to execute external Python scripts for game scanning.
func generate_game_list_for_emulator(emulator_name: String, emu_path: String):
	print("Executing Python scan script for ", emulator_name)
	
	var python_executable = emulator_paths.get("python_executable_path", "python")
	var script_res_path = ""
	var output_json_name = ""
	
	match emulator_name:
		"Switch":
			script_res_path = "res://scripts/read_config_switch.py"
			output_json_name = "gamedir_contents_switch.json"
		"Wii":
			script_res_path = "res://scripts/read_config_wii.py"
			output_json_name = "gamedir_contents_wii.json"
		_:
			print("No Python script configured for ", emulator_name)
			return
			
	var script_abs_path = ProjectSettings.globalize_path(script_res_path)

	if not FileAccess.file_exists(script_abs_path):
		print("Error: Python script not found at %s" % script_abs_path)
		return

	var output_json_abs_path = ProjectSettings.globalize_path("res://scripts/config/").path_join(output_json_name)
	var command_to_run = '"%s" "%s" "%s" "%s"' % [python_executable, script_abs_path, emu_path, output_json_abs_path]
	var cmd_args = ["/c", command_to_run]
	
	var output = []
	var exit_code = OS.execute("cmd.exe", cmd_args, output, true)
	
	if exit_code != 0:
		print("Error: Python script for %s failed with exit code %s." % [emulator_name, exit_code])
		print("Executed command: ", command_to_run)
		print("Python output: ", "\n".join(output))
		return
	
	print("Python script executed successfully.")

	#var output_json_abs_path = ProjectSettings.globalize_path("res://scripts/config/").path_join(output_json_name)
	
	if not FileAccess.file_exists(output_json_abs_path):
		print("Error: Python script finished, but the output JSON was not found at %s" % output_json_abs_path)
		return
		
	var file = FileAccess.open(output_json_abs_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	
	# DirAccess.remove_absolute(output_json_abs_path)
	
	var json = JSON.new()
	var error = json.parse(content)
	
	if error != OK:
		print("Error: Could not parse the JSON file created by the Python script.")
		return
		
	# --- NEW FIX: Handle the dictionary structure from Python ---
	var json_data = json.data
	var game_items = [] # This will now store dictionaries, not just names

	if typeof(json_data) == TYPE_DICTIONARY:
		# Iterate through the keys (the base paths) of the dictionary
		for base_path in json_data.keys():
			var file_list = json_data[base_path]
			if typeof(file_list) == TYPE_ARRAY:
				# For each filename, create a dictionary with the name and full path
				for filename in file_list:
					var full_path = base_path.path_join(filename)
					game_items.append({
						"name": filename,
						"path": full_path
					})
	else:
		print("Error: The JSON from the Python script is not a dictionary as expected.")
		return
	# --- END NEW LOGIC ---

	print("Found %d games for %s from script output." % [game_items.size(), emulator_name])
	
	var game_data = {}
	if FileAccess.file_exists(MENU_DATA_PATH):
		var game_file = FileAccess.open(MENU_DATA_PATH, FileAccess.READ)
		var game_content = game_file.get_as_text().strip_edges()
		if not game_content.is_empty():
			var game_json = JSON.new()
			if game_json.parse(game_content) == OK:
				game_data = game_json.data
	
	var icon = "res://icon.svg"
	if emulator_name == "Switch":
		icon = "res://icons/switch_icon.svg"
	elif emulator_name == "Wii":
		icon = "res://icons/wii_icon.svg"
		
	game_data[emulator_name] = {
		"icon_path": icon,
		"items": game_items
	}
	save_game_data_to_json(game_data)
	
	load_menu_data()
	rebuild_xmb_menu()
