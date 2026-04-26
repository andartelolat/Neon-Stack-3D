extends Node3D

const BOARD_WIDTH := 10
const BOARD_HEIGHT := 20
const CELL_SIZE := 1.0
const DROP_START := 0.72
const LEVEL_SCORE_STEP := 650
const MUSIC_PATH := "res://assets/music/voltaic_kevin_macleod_cc_by_3.mp3"

const SHAPES := {
	"I": [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
	"J": [Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)],
	"L": [Vector2i(1, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)],
	"O": [Vector2i(0, -1), Vector2i(1, -1), Vector2i(0, 0), Vector2i(1, 0)],
	"S": [Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(0, 0)],
	"T": [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)],
	"Z": [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(0, 0), Vector2i(1, 0)],
}

const COLORS := {
	"I": Color(0.0, 0.9, 1.0),
	"J": Color(0.2, 0.35, 1.0),
	"L": Color(1.0, 0.55, 0.08),
	"O": Color(1.0, 0.88, 0.12),
	"S": Color(0.05, 1.0, 0.46),
	"T": Color(0.78, 0.2, 1.0),
	"Z": Color(1.0, 0.12, 0.25),
}

var board: Dictionary = {}
var active_kind := ""
var active_blocks: Array = []
var active_pos := Vector2i(int(BOARD_WIDTH / 2), 1)
var next_kind := ""
var score := 0
var lines := 0
var level := 1
var next_level_score := LEVEL_SCORE_STEP
var drop_timer := 0.0
var game_over := false
var paused := false

var block_mesh := BoxMesh.new()
var board_root: Node3D
var active_root: Node3D
var ghost_root: Node3D
var fx_root: Node3D
var next_root: Node3D
var scenery_root: Node3D
var camera_pivot: Node3D
var camera: Camera3D
var score_label: Label
var lines_label: Label
var level_label: Label
var status_label: Label
var next_label: Label
var hint_label: Label
var title_label: Label
var creator_label: Label
var pause_overlay: Control
var rng := RandomNumberGenerator.new()
var particle_tex: Texture2D
var spark_tex: Texture2D
var camera_yaw := 0.0
var camera_pitch := -0.42
var camera_distance := 20.0
var camera_preset := 0
var camera_shake := 0.0
var camera_target := Vector3(0.0, 0.0, 0.0)
var neon_root: Node3D
var current_scenery := -1
var scenery_layers: Array[Node3D] = []
var move_sound: AudioStreamPlayer
var rotate_sound: AudioStreamPlayer
var drop_sound: AudioStreamPlayer
var clear_sound: AudioStreamPlayer
var level_sound: AudioStreamPlayer
var music_player: AudioStreamPlayer


func _ready() -> void:
	rng.randomize()
	particle_tex = _make_radial_texture(96, Color(0.6, 0.2, 1.0, 1.0))
	spark_tex = _make_radial_texture(64, Color(0.25, 0.95, 1.0, 1.0))
	block_mesh.size = Vector3(0.92, 0.92, 0.92)
	_build_world()
	_build_hud()
	_build_audio()
	_restart()


func _process(delta: float) -> void:
	_update_camera(delta)
	_update_scenery(delta)
	if game_over or paused:
		return

	drop_timer += delta
	var interval: float = _drop_interval()
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		interval *= 0.08
	if drop_timer >= interval:
		drop_timer = 0.0
		if not _try_move(Vector2i(0, 1)):
			_lock_piece()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			camera_yaw -= motion.relative.x * 0.006
			camera_pitch = clampf(camera_pitch - motion.relative.y * 0.004, -0.98, -0.12)
		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(12.0, camera_distance - 1.0)
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(30.0, camera_distance + 1.0)
		return

	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not event.is_pressed() or event.is_echo():
		return

	match key_event.keycode:
		KEY_R:
			_restart()
		KEY_P, KEY_ESCAPE:
			_set_paused(not paused)
		KEY_Q:
			camera_yaw += 0.18
		KEY_E:
			camera_yaw -= 0.18
		KEY_C:
			_cycle_camera_preset()
		KEY_A, KEY_LEFT:
			if _can_play():
				_try_move(Vector2i(-1, 0))
		KEY_D, KEY_RIGHT:
			if _can_play():
				_try_move(Vector2i(1, 0))
		KEY_W, KEY_UP:
			if _can_play():
				_try_rotate()
		KEY_SPACE:
			if _can_play():
				_hard_drop()


func _build_world() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.012, 0.025)
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_strength = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)

	camera_pivot = Node3D.new()
	add_child(camera_pivot)

	camera = Camera3D.new()
	camera.fov = 48.0
	camera.current = true
	camera_pivot.add_child(camera)
	_update_camera(0.0)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-5.0, 4.0, 7.0)
	fill.light_color = Color(0.1, 0.8, 1.0)
	fill.light_energy = 2.1
	add_child(fill)

	var magenta := OmniLight3D.new()
	magenta.position = Vector3(6.0, 12.0, 4.0)
	magenta.light_color = Color(1.0, 0.1, 0.75)
	magenta.light_energy = 1.7
	add_child(magenta)

	board_root = Node3D.new()
	active_root = Node3D.new()
	ghost_root = Node3D.new()
	fx_root = Node3D.new()
	neon_root = Node3D.new()
	scenery_root = Node3D.new()
	next_root = Node3D.new()
	add_child(board_root)
	add_child(ghost_root)
	add_child(active_root)
	add_child(next_root)
	add_child(scenery_root)
	add_child(fx_root)
	add_child(neon_root)

	scenery_root.position.z = -7.5
	next_root.position = Vector3(7.3, 4.4, 0.0)
	_create_grid()
	_create_starfield()
	_create_neon_ribbons()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var hud_panel := _make_panel(Vector2(28, 24), Vector2(258, 178), Color(0.02, 0.06, 0.11, 0.68), Color(0.0, 0.9, 1.0, 0.75))
	layer.add_child(hud_panel)

	var brand := Label.new()
	brand.position = Vector2(44, 34)
	brand.text = "NEON STACK"
	brand.add_theme_font_size_override("font_size", 18)
	brand.add_theme_color_override("font_color", Color(0.38, 1.0, 0.95))
	layer.add_child(brand)

	title_label = Label.new()
	title_label.position = Vector2(44, 58)
	title_label.add_theme_font_size_override("font_size", 34)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.24, 0.88))
	title_label.text = "HYPERDROP"
	layer.add_child(title_label)

	creator_label = Label.new()
	creator_label.position = Vector2(44, 86)
	creator_label.text = "created by iben"
	creator_label.add_theme_font_size_override("font_size", 15)
	creator_label.add_theme_color_override("font_color", Color(0.72, 0.92, 1.0))
	layer.add_child(creator_label)

	score_label = Label.new()
	score_label.position = Vector2(44, 112)
	score_label.add_theme_font_size_override("font_size", 30)
	score_label.add_theme_color_override("font_color", Color(0.85, 0.97, 1.0))
	layer.add_child(score_label)

	lines_label = _make_stat_label(Vector2(44, 144), "LINES 0")
	layer.add_child(lines_label)

	level_label = _make_stat_label(Vector2(158, 144), "LVL 1")
	layer.add_child(level_label)

	var next_panel := _make_panel(Vector2(998, 24), Vector2(238, 158), Color(0.035, 0.02, 0.09, 0.68), Color(1.0, 0.25, 0.9, 0.72))
	layer.add_child(next_panel)

	next_label = Label.new()
	next_label.position = Vector2(1022, 42)
	next_label.add_theme_font_size_override("font_size", 26)
	next_label.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0))
	next_label.text = "NEXT DROP"
	layer.add_child(next_label)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.position = Vector2(390, 22)
	status_label.size = Vector2(500, 38)
	status_label.add_theme_font_size_override("font_size", 22)
	status_label.add_theme_color_override("font_color", Color(0.96, 1.0, 0.72))
	layer.add_child(status_label)

	hint_label = Label.new()
	hint_label.position = Vector2(28, 668)
	hint_label.size = Vector2(1224, 28)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 16)
	hint_label.add_theme_color_override("font_color", Color(0.72, 0.88, 0.96))
	hint_label.text = "A/D MOVE   W ROTATE   SPACE SLAM   Q/E CAMERA   RMB ORBIT   WHEEL ZOOM   C VIEW   P PAUSE"
	layer.add_child(hint_label)

	_build_pause_menu(layer)


func _restart() -> void:
	board.clear()
	_clear_children(board_root)
	_clear_children(active_root)
	_clear_children(ghost_root)
	score = 0
	lines = 0
	level = 1
	next_level_score = _score_needed_for_level(2)
	drop_timer = 0.0
	game_over = false
	_set_paused(false)
	next_kind = _random_kind()
	_set_scenery(0)
	_spawn_piece()
	_update_hud()


func _spawn_piece() -> void:
	active_kind = next_kind
	next_kind = _random_kind()
	active_blocks = SHAPES[active_kind].duplicate()
	active_pos = Vector2i(int(BOARD_WIDTH / 2), 1)
	if not _is_valid(active_blocks, active_pos):
		game_over = true
		_burst(Vector3(0, 7, 0), COLORS[active_kind], 90, 2.4)
	_update_active_visuals()
	_update_hud()


func _try_move(offset: Vector2i) -> bool:
	var next_pos := active_pos + offset
	if not _is_valid(active_blocks, next_pos):
		return false
	if offset.y > 0:
		_trail_piece(active_pos, active_blocks, active_kind)
	active_pos = next_pos
	_update_active_visuals()
	if offset.x != 0:
		_play(move_sound)
	return true


func _try_rotate() -> void:
	if active_kind == "O":
		return
	var rotated: Array[Vector2i] = []
	for b in active_blocks:
		rotated.append(Vector2i(-b.y, b.x))

	for kick in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, -1)]:
		if _is_valid(rotated, active_pos + kick):
			active_blocks = rotated
			active_pos += kick
			_update_active_visuals()
			_burst(_board_to_world(active_pos), COLORS[active_kind], 10, 0.55)
			_shockwave(_board_to_world(active_pos), COLORS[active_kind], 0.65)
			_play(rotate_sound)
			return


func _hard_drop() -> void:
	var dist := 0
	while _try_move(Vector2i(0, 1)):
		dist += 1
	score += dist * 2
	_apply_score_rewards()
	_lock_piece()
	_play(drop_sound)


func _lock_piece() -> void:
	for b in active_blocks:
		var block := b as Vector2i
		var cell: Vector2i = active_pos + block
		board[_key(cell)] = active_kind
		_add_board_block(cell, active_kind)
	_burst(_board_to_world(active_pos), COLORS[active_kind], 22, 0.9)
	_shockwave(_board_to_world(active_pos), COLORS[active_kind], 1.15)
	_clear_children(active_root)
	_clear_children(ghost_root)
	_clear_lines()
	_spawn_piece()


func _clear_lines() -> void:
	var cleared: Array[int] = []
	for y in range(BOARD_HEIGHT):
		var full := true
		for x in range(BOARD_WIDTH):
			if not board.has(_key(Vector2i(x, y))):
				full = false
				break
		if full:
			cleared.append(y)

	if cleared.is_empty():
		return

	for y in cleared:
		_burst(_board_to_world(Vector2i(int(BOARD_WIDTH / 2), y)), Color(0.55, 1.0, 0.95), 70, 1.8)
		_line_flash(y)

	var new_board: Dictionary = {}
	for y in range(BOARD_HEIGHT - 1, -1, -1):
		if cleared.has(y):
			continue
		var shift := 0
		for line_y in cleared:
			if y < line_y:
				shift += 1
		for x in range(BOARD_WIDTH):
			var cell := Vector2i(x, y)
			if board.has(_key(cell)):
				new_board[_key(Vector2i(x, y + shift))] = board[_key(cell)]
	board = new_board

	_clear_children(board_root)
	for key in board.keys():
		var parts := str(key).split(",")
		_add_board_block(Vector2i(int(parts[0]), int(parts[1])), board[key])

	var count := cleared.size()
	lines += count
	score += [0, 100, 300, 500, 800][count] * level
	_update_hud()
	_shake_camera(0.18 + count * 0.05)
	_play(clear_sound)
	_apply_score_rewards()


func _update_active_visuals() -> void:
	_clear_children(active_root)
	_clear_children(ghost_root)
	for b in active_blocks:
		var block := b as Vector2i
		var cell: Vector2i = active_pos + block
		active_root.add_child(_make_block(cell, active_kind, 1.0))

	var ghost_pos := active_pos
	while _is_valid(active_blocks, ghost_pos + Vector2i(0, 1)):
		ghost_pos.y += 1
	for b in active_blocks:
		var block := b as Vector2i
		ghost_root.add_child(_make_block(ghost_pos + block, active_kind, 0.22))
	_update_next_preview()


func _add_board_block(cell: Vector2i, kind: String) -> void:
	board_root.add_child(_make_block(cell, kind, 0.92))


func _update_next_preview() -> void:
	_clear_children(next_root)
	if not SHAPES.has(next_kind):
		return
	var color: Color = COLORS[next_kind]
	for b in SHAPES[next_kind]:
		var block := b as Vector2i
		var preview := MeshInstance3D.new()
		preview.mesh = block_mesh
		preview.position = Vector3(float(block.x) * 0.62, -float(block.y) * 0.62, 0.0)
		preview.scale = Vector3.ONE * 0.58
		preview.material_override = _make_material(color, 0.96)
		next_root.add_child(preview)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.25
	light.omni_range = 4.0
	light.position = Vector3(0, 0, 2.0)
	next_root.add_child(light)


func _make_block(cell: Vector2i, kind: String, alpha: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = block_mesh
	mesh.position = _board_to_world(cell)
	mesh.material_override = _make_material(COLORS[kind], alpha)
	if alpha > 0.5:
		mesh.scale = Vector3.ONE * 0.01
		var tween := create_tween()
		tween.tween_property(mesh, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_pulse_block(mesh)
	return mesh


func _make_material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.7 if alpha > 0.5 else 0.28
	mat.metallic = 0.18
	mat.roughness = 0.22
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.no_depth_test = alpha < 0.3
	return mat


func _drop_interval() -> float:
	var speedup: float = pow(0.86, float(level - 1))
	return maxf(0.055, DROP_START * speedup)


func _score_needed_for_level(target_level: int) -> int:
	var progress: int = maxi(target_level - 1, 1)
	return int(float(LEVEL_SCORE_STEP) * pow(float(progress), 1.35))


func _apply_score_rewards() -> void:
	var leveled_up := false
	while score >= next_level_score:
		level += 1
		next_level_score = _score_needed_for_level(level + 1)
		leveled_up = true

	if leveled_up:
		_set_scenery(level - 1)
		_background_flash(Color(0.95, 0.24, 1.0))
		_burst(Vector3(0.0, 0.0, 0.85), Color(1.0, 0.4, 0.95), 120, 2.1)
		_shake_camera(0.36)
		_play(level_sound)
	_update_hud()


func _make_radial_texture(size: int, color: Color) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var distance := Vector2(x, y).distance_to(center) / radius
			var alpha := clampf(1.0 - distance, 0.0, 1.0)
			alpha = pow(alpha, 2.6)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
	return ImageTexture.create_from_image(image)


func _make_panel(pos: Vector2, size: Vector2, fill: Color, stroke: Color) -> Control:
	var root := Control.new()
	root.position = pos
	root.size = size

	var bg := ColorRect.new()
	bg.size = size
	bg.color = fill
	root.add_child(bg)

	var top := ColorRect.new()
	top.size = Vector2(size.x, 2)
	top.color = stroke
	root.add_child(top)

	var bottom := ColorRect.new()
	bottom.position = Vector2(0, size.y - 2)
	bottom.size = Vector2(size.x, 2)
	bottom.color = Color(stroke.r, stroke.g, stroke.b, 0.42)
	root.add_child(bottom)

	var left := ColorRect.new()
	left.size = Vector2(2, size.y)
	left.color = Color(stroke.r, stroke.g, stroke.b, 0.55)
	root.add_child(left)

	var right := ColorRect.new()
	right.position = Vector2(size.x - 2, 0)
	right.size = Vector2(2, size.y)
	right.color = Color(stroke.r, stroke.g, stroke.b, 0.55)
	root.add_child(right)
	return root


func _make_stat_label(pos: Vector2, text: String) -> Label:
	var label := Label.new()
	label.position = pos
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.62, 0.9, 1.0))
	return label


func _build_pause_menu(layer: CanvasLayer) -> void:
	pause_overlay = Control.new()
	pause_overlay.visible = false
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(pause_overlay)

	var shade := ColorRect.new()
	shade.color = Color(0.005, 0.008, 0.018, 0.76)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(shade)

	var panel := _make_panel(Vector2(440, 138), Vector2(400, 418), Color(0.025, 0.035, 0.07, 0.9), Color(0.0, 0.95, 1.0, 0.95))
	pause_overlay.add_child(panel)

	var header := Label.new()
	header.position = Vector2(472, 174)
	header.size = Vector2(336, 52)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.text = "PAUSED"
	header.add_theme_font_size_override("font_size", 46)
	header.add_theme_color_override("font_color", Color(1.0, 0.28, 0.9))
	pause_overlay.add_child(header)

	var sub := Label.new()
	sub.position = Vector2(486, 232)
	sub.size = Vector2(308, 48)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.text = "created by iben - drop the beat"
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(0.76, 0.94, 1.0))
	pause_overlay.add_child(sub)

	var resume := _make_menu_button("RESUME", Vector2(506, 300))
	resume.pressed.connect(_resume_game)
	pause_overlay.add_child(resume)

	var restart := _make_menu_button("RESTART RUN", Vector2(506, 360))
	restart.pressed.connect(_restart_from_menu)
	pause_overlay.add_child(restart)

	var quit := _make_menu_button("QUIT", Vector2(506, 420))
	quit.pressed.connect(_quit_game)
	pause_overlay.add_child(quit)


func _make_menu_button(text: String, pos: Vector2) -> Button:
	var button := Button.new()
	button.position = pos
	button.size = Vector2(268, 44)
	button.text = text
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color(0.92, 1.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.36, 0.92))
	return button


func _set_paused(value: bool) -> void:
	paused = value
	if pause_overlay != null:
		pause_overlay.visible = paused
	if music_player != null:
		music_player.volume_db = -22.0 if paused else -14.0
	_update_hud()


func _resume_game() -> void:
	_set_paused(false)


func _restart_from_menu() -> void:
	_restart()


func _quit_game() -> void:
	get_tree().quit()


func _build_audio() -> void:
	move_sound = _make_audio_player(_make_tone(520.0, 0.055, 0.18, 0.35))
	rotate_sound = _make_audio_player(_make_tone(780.0, 0.075, 0.16, 0.48))
	drop_sound = _make_audio_player(_make_tone(120.0, 0.12, 0.24, 0.62))
	clear_sound = _make_audio_player(_make_tone(960.0, 0.28, 0.34, 0.8))
	level_sound = _make_audio_player(_make_tone(420.0, 0.42, 0.26, 0.95, true))
	var music_stream := _load_music_stream()
	music_player = _make_audio_player(music_stream)
	music_player.volume_db = -14.0 if music_stream is AudioStreamMP3 else -17.0
	music_player.play()


func _make_audio_player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -8.0
	add_child(player)
	return player


func _load_music_stream() -> AudioStream:
	if FileAccess.file_exists(MUSIC_PATH):
		var bytes := FileAccess.get_file_as_bytes(MUSIC_PATH)
		if not bytes.is_empty():
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			mp3.loop = true
			return mp3
	return _make_edm_loop()


func _make_tone(freq: float, seconds: float, decay: float, volume: float, sweep: bool = false) -> AudioStreamWAV:
	var rate := 44100
	var frames := int(float(rate) * seconds)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / float(rate)
		var progress := float(i) / float(maxi(frames - 1, 1))
		var active_freq := freq + progress * 520.0 if sweep else freq
		var envelope := pow(1.0 - progress, decay * 6.0)
		var tone := sin(TAU * active_freq * t)
		var shimmer := sin(TAU * active_freq * 2.01 * t) * 0.22
		var sample := int(clampf((tone + shimmer) * envelope * volume, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream


func _make_edm_loop() -> AudioStreamWAV:
	var rate := 44100
	var bpm := 128.0
	var seconds := 7.5
	var frames := int(float(rate) * seconds)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var beat_len := 60.0 / bpm
	var bass_notes := [55.0, 55.0, 65.41, 49.0, 73.42, 65.41, 55.0, 82.41]
	var lead_notes := [440.0, 493.88, 659.25, 587.33, 523.25, 659.25, 739.99, 587.33]

	for i in range(frames):
		var t := float(i) / float(rate)
		var beat := fmod(t / beat_len, 8.0)
		var step := int(floor(beat * 2.0)) % 16
		var note_index := int(floor(beat)) % bass_notes.size()
		var kick_phase := fmod(t, beat_len) / beat_len
		var kick: float = sin(TAU * (48.0 + 90.0 * pow(1.0 - kick_phase, 2.0)) * t) * pow(1.0 - kick_phase, 8.0)
		var bass_freq: float = bass_notes[note_index]
		var bass_gate: float = 0.82 if step % 2 == 0 else 0.38
		var bass: float = sign(sin(TAU * bass_freq * t)) * 0.12 * bass_gate
		var lead_freq: float = lead_notes[(step + 2) % lead_notes.size()]
		var lead_gate: float = 0.0 if step % 4 == 3 else 1.0
		var lead: float = (sin(TAU * lead_freq * t) + sin(TAU * lead_freq * 2.0 * t) * 0.18) * 0.06 * lead_gate
		var hat_phase: float = fmod(t, beat_len * 0.5) / (beat_len * 0.5)
		var hat_noise: float = sin(TAU * 8800.0 * t) * sin(TAU * 1234.0 * t)
		var hat: float = hat_noise * pow(1.0 - hat_phase, 18.0) * 0.045
		var sidechain: float = 0.45 + 0.55 * clampf(kick_phase * 2.6, 0.0, 1.0)
		var sample := int(clampf(kick * 0.44 + (bass + lead + hat) * sidechain, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	stream.data = data
	return stream


func _play(player: AudioStreamPlayer) -> void:
	if player == null:
		return
	player.stop()
	player.play()


func _update_camera(delta: float) -> void:
	if camera == null:
		return

	var horizontal := cos(camera_pitch) * camera_distance
	var base_position := Vector3(
		sin(camera_yaw) * horizontal,
		sin(-camera_pitch) * camera_distance + 1.4,
		cos(camera_yaw) * horizontal
	)
	var shake_offset := Vector3.ZERO
	if camera_shake > 0.001:
		shake_offset = Vector3(
			rng.randf_range(-camera_shake, camera_shake),
			rng.randf_range(-camera_shake, camera_shake),
			rng.randf_range(-camera_shake, camera_shake)
		)
		camera_shake = maxf(0.0, camera_shake - delta * 2.4)

	camera.position = base_position + shake_offset
	camera.look_at(camera_target, Vector3.UP)


func _cycle_camera_preset() -> void:
	camera_preset = (camera_preset + 1) % 4
	match camera_preset:
		0:
			camera_yaw = 0.0
			camera_pitch = -0.42
			camera_distance = 20.0
		1:
			camera_yaw = 0.55
			camera_pitch = -0.36
			camera_distance = 17.5
		2:
			camera_yaw = -0.65
			camera_pitch = -0.55
			camera_distance = 22.0
		3:
			camera_yaw = 3.14
			camera_pitch = -0.34
			camera_distance = 19.0
	_update_camera(0.0)


func _set_scenery(index: int) -> void:
	var scenery_index := index % 5
	if scenery_index == current_scenery:
		return
	current_scenery = scenery_index
	scenery_layers.clear()
	_clear_children(scenery_root)

	var themes := [
		{
			"sky_top": Color(0.02, 0.09, 0.18),
			"sky_bottom": Color(0.15, 0.45, 0.54),
			"far": Color(0.05, 0.22, 0.26, 0.72),
			"mid": Color(0.03, 0.34, 0.31, 0.84),
			"near": Color(0.02, 0.16, 0.12, 0.96),
			"accent": Color(0.1, 1.0, 0.75),
			"shape": "hills",
		},
		{
			"sky_top": Color(0.07, 0.03, 0.17),
			"sky_bottom": Color(0.58, 0.18, 0.36),
			"far": Color(0.17, 0.08, 0.25, 0.78),
			"mid": Color(0.34, 0.09, 0.27, 0.86),
			"near": Color(0.16, 0.05, 0.16, 0.98),
			"accent": Color(1.0, 0.32, 0.74),
			"shape": "mountains",
		},
		{
			"sky_top": Color(0.01, 0.04, 0.12),
			"sky_bottom": Color(0.03, 0.22, 0.34),
			"far": Color(0.05, 0.2, 0.42, 0.78),
			"mid": Color(0.03, 0.31, 0.55, 0.86),
			"near": Color(0.02, 0.12, 0.24, 0.98),
			"accent": Color(0.0, 0.72, 1.0),
			"shape": "coast",
		},
		{
			"sky_top": Color(0.05, 0.06, 0.1),
			"sky_bottom": Color(0.35, 0.34, 0.22),
			"far": Color(0.19, 0.17, 0.13, 0.78),
			"mid": Color(0.36, 0.27, 0.13, 0.86),
			"near": Color(0.17, 0.11, 0.07, 0.98),
			"accent": Color(1.0, 0.72, 0.18),
			"shape": "desert",
		},
		{
			"sky_top": Color(0.01, 0.01, 0.045),
			"sky_bottom": Color(0.06, 0.02, 0.11),
			"far": Color(0.06, 0.06, 0.18, 0.78),
			"mid": Color(0.11, 0.06, 0.23, 0.86),
			"near": Color(0.03, 0.025, 0.08, 0.98),
			"accent": Color(0.75, 0.25, 1.0),
			"shape": "city",
		},
	]
	var theme: Dictionary = themes[scenery_index]
	_make_sky_band(theme.sky_top, Vector3(0, 6.8, -0.9), Vector2(48, 18))
	_make_sky_band(theme.sky_bottom, Vector3(0, -6.4, -0.8), Vector2(48, 14))
	_make_silhouette_layer(theme.far, -4.5, 0.75, theme.shape, 0.18)
	_make_silhouette_layer(theme.mid, -6.2, 1.15, theme.shape, 0.34)
	_make_silhouette_layer(theme.near, -8.2, 1.65, theme.shape, 0.52)
	_make_moon_or_sun(theme.accent, scenery_index)
	_background_flash(theme.accent)


func _make_sky_band(color: Color, pos: Vector3, size: Vector2) -> void:
	var plane := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	plane.mesh = mesh
	plane.position = pos
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.55
	plane.material_override = mat
	scenery_root.add_child(plane)
	scenery_layers.append(plane)


func _make_silhouette_layer(color: Color, bottom: float, height: float, shape: String, depth: float) -> void:
	var layer := MeshInstance3D.new()
	layer.mesh = _make_landscape_mesh(bottom, height, shape)
	layer.set_meta("parallax", depth)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b, 1.0)
	mat.emission_energy_multiplier = 0.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	layer.material_override = mat
	scenery_root.add_child(layer)
	scenery_layers.append(layer)


func _make_landscape_mesh(bottom: float, height: float, shape: String) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var width := 42.0
	var segments := 18
	for i in range(segments):
		var x1 := -width * 0.5 + width * float(i) / float(segments)
		var x2 := -width * 0.5 + width * float(i + 1) / float(segments)
		var y1 := _landscape_height(i, height, shape)
		var y2 := _landscape_height(i + 1, height, shape)
		mesh.surface_add_vertex(Vector3(x1, bottom, 0.0))
		mesh.surface_add_vertex(Vector3(x1, bottom + y1, 0.0))
		mesh.surface_add_vertex(Vector3(x2, bottom + y2, 0.0))
		mesh.surface_add_vertex(Vector3(x1, bottom, 0.0))
		mesh.surface_add_vertex(Vector3(x2, bottom + y2, 0.0))
		mesh.surface_add_vertex(Vector3(x2, bottom, 0.0))
	mesh.surface_end()
	return mesh


func _landscape_height(i: int, height: float, shape: String) -> float:
	match shape:
		"mountains":
			return height * (1.2 + abs(sin(float(i) * 1.7)) * 2.3)
		"coast":
			return height * (0.8 + sin(float(i) * 0.9) * 0.35 + abs(sin(float(i) * 0.32)) * 1.1)
		"desert":
			return height * (0.9 + sin(float(i) * 0.55) * 0.45 + sin(float(i) * 1.15) * 0.12)
		"city":
			return height * (0.8 + float((i * 37) % 5) * 0.55)
		_:
			return height * (0.9 + sin(float(i) * 0.68) * 0.3 + abs(sin(float(i) * 0.37)) * 0.8)


func _make_moon_or_sun(color: Color, index: int) -> void:
	var orb := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.9 + float(index % 2) * 0.25
	mesh.height = mesh.radius * 2.0
	orb.mesh = mesh
	orb.position = Vector3(-7.5 + float(index) * 3.2, 5.2 - float(index % 3) * 0.5, 0.15)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.72)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.7
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	orb.material_override = mat
	scenery_root.add_child(orb)
	scenery_layers.append(orb)


func _update_scenery(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for layer in scenery_layers:
		if layer == null:
			continue
		var depth := float(layer.get_meta("parallax", 0.08))
		layer.position.x = sin(t * (0.18 + depth) + depth * 9.0) * depth * 1.4 - camera_yaw * depth * 1.8
		layer.position.y += sin(t * 0.5 + depth) * depth * delta * 0.06


func _background_flash(color: Color) -> void:
	if fx_root == null:
		return
	var flash := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(44, 26)
	flash.mesh = mesh
	flash.position = Vector3(0, 0, -6.6)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.18)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.9
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash.material_override = mat
	fx_root.add_child(flash)

	var tween := flash.create_tween()
	tween.tween_property(mat, "albedo_color", Color(color.r, color.g, color.b, 0.0), 0.55)
	tween.tween_callback(flash.queue_free)


func _pulse_block(mesh: MeshInstance3D) -> void:
	var tween := mesh.create_tween()
	tween.set_loops()
	tween.tween_interval(rng.randf_range(0.18, 0.72))
	tween.tween_property(mesh, "scale", Vector3.ONE * 1.035, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(mesh, "scale", Vector3.ONE, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _trail_piece(piece_pos: Vector2i, blocks: Array, kind: String) -> void:
	for b in blocks:
		var block := b as Vector2i
		var trail := _make_block(piece_pos + block, kind, 0.14)
		trail.scale = Vector3.ONE * 0.82
		trail.position.z -= 0.22
		fx_root.add_child(trail)
		var tween := trail.create_tween()
		tween.tween_property(trail, "scale", Vector3.ONE * 0.2, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(trail, "position:z", -0.9, 0.22)
		tween.tween_callback(trail.queue_free)


func _line_flash(line_y: int) -> void:
	var flash := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(BOARD_WIDTH + 1.4, 0.18, 0.18)
	flash.mesh = mesh
	flash.position = _board_to_world(Vector2i(int(BOARD_WIDTH / 2), line_y))
	flash.position.x = 0.0
	flash.position.z = 0.56
	flash.scale.x = 0.05

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 1.0, 0.96, 0.74)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 1.0, 0.95)
	mat.emission_energy_multiplier = 2.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash.material_override = mat
	fx_root.add_child(flash)

	var tween := flash.create_tween()
	tween.tween_property(flash, "scale:x", 1.0, 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash, "scale:y", 0.02, 0.16)
	tween.parallel().tween_property(mat, "albedo_color", Color(0.75, 1.0, 0.96, 0.0), 0.16)
	tween.tween_callback(flash.queue_free)


func _shockwave(pos: Vector3, color: Color, size: float) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = _make_ring_mesh(1.0)
	ring.position = pos
	ring.position.z = 0.72
	ring.scale = Vector3.ONE * 0.15

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.72)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring.material_override = mat
	fx_root.add_child(ring)

	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3.ONE * size, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color", Color(color.r, color.g, color.b, 0.0), 0.32)
	tween.tween_callback(ring.queue_free)


func _make_ring_mesh(radius: float) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var segments := 64
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		var b := TAU * float(i + 1) / float(segments)
		mesh.surface_add_vertex(Vector3(cos(a) * radius, sin(a) * radius, 0.0))
		mesh.surface_add_vertex(Vector3(cos(b) * radius, sin(b) * radius, 0.0))
	mesh.surface_end()
	return mesh


func _create_grid() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var grid_color := Color(0.2, 0.95, 1.0, 0.34)
	mesh.surface_set_color(grid_color)
	for x in range(BOARD_WIDTH + 1):
		var wx := (float(x) - BOARD_WIDTH * 0.5) * CELL_SIZE
		mesh.surface_add_vertex(Vector3(wx, 0.0, 0.15))
		mesh.surface_add_vertex(Vector3(wx, BOARD_HEIGHT * CELL_SIZE, 0.15))
	for y in range(BOARD_HEIGHT + 1):
		var wy := y * CELL_SIZE
		mesh.surface_add_vertex(Vector3(-BOARD_WIDTH * 0.5, wy, 0.15))
		mesh.surface_add_vertex(Vector3(BOARD_WIDTH * 0.5, wy, 0.15))
	mesh.surface_end()

	var grid := MeshInstance3D.new()
	grid.mesh = mesh
	grid.position.y = -BOARD_HEIGHT * 0.5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = grid_color
	mat.emission_enabled = true
	mat.emission = grid_color
	mat.emission_energy_multiplier = 0.9
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid.material_override = mat
	add_child(grid)

	var back := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(BOARD_WIDTH + 2.8, BOARD_HEIGHT + 2.8)
	back.mesh = plane
	back.position = Vector3(0, 0, -0.62)
	back.rotation_degrees.x = 90.0
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.02, 0.035, 0.07, 0.78)
	back_mat.emission_enabled = true
	back_mat.emission = Color(0.01, 0.08, 0.16)
	back_mat.emission_energy_multiplier = 0.5
	back.material_override = back_mat
	add_child(back)


func _create_starfield() -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 180
	particles.lifetime = 8.0
	particles.preprocess = 8.0
	particles.position = Vector3(0, 1.2, -8.0)
	particles.visibility_aabb = AABB(Vector3(-30, -22, -8), Vector3(60, 52, 18))

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(16, 18, 2)
	process.direction = Vector3(0, 1, 0)
	process.spread = 180
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.18
	process.scale_min = 0.025
	process.scale_max = 0.08
	process.color = Color(0.45, 0.95, 1.0, 0.7)
	particles.process_material = process

	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = spark_tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	particles.draw_pass_1 = quad
	add_child(particles)


func _create_neon_ribbons() -> void:
	for i in range(5):
		var ribbon := MeshInstance3D.new()
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var y_base := -7.8 + float(i) * 3.9
		var z_base := -3.6 - float(i % 2) * 0.7
		for s in range(34):
			var x1 := -11.0 + float(s) * 0.66
			var x2 := -11.0 + float(s + 1) * 0.66
			var y1 := y_base + sin(float(s) * 0.72 + float(i)) * 0.18
			var y2 := y_base + sin(float(s + 1) * 0.72 + float(i)) * 0.18
			mesh.surface_add_vertex(Vector3(x1, y1, z_base))
			mesh.surface_add_vertex(Vector3(x2, y2, z_base))
		mesh.surface_end()
		ribbon.mesh = mesh

		var hue := float(i) / 5.0
		var color := Color.from_hsv(hue, 0.7, 1.0, 0.38)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.8
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		ribbon.material_override = mat
		neon_root.add_child(ribbon)

		var tween := ribbon.create_tween()
		tween.set_loops()
		tween.tween_property(ribbon, "position:x", 1.15, 2.2 + float(i) * 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(ribbon, "position:x", -1.15, 2.2 + float(i) * 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _burst(pos: Vector3, color: Color, amount: int, speed: float) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.one_shot = true
	particles.explosiveness = 0.86
	particles.lifetime = 0.72
	particles.position = pos
	particles.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	fx_root.add_child(particles)

	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 1, 0)
	process.spread = 180
	process.initial_velocity_min = speed
	process.initial_velocity_max = speed * 2.2
	process.gravity = Vector3(0, -2.4, 0)
	process.scale_min = 0.12
	process.scale_max = 0.42
	process.color = color
	particles.process_material = process

	var quad := QuadMesh.new()
	quad.size = Vector2(0.72, 0.72)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = particle_tex
	mat.albedo_color = Color(color.r, color.g, color.b, 0.86)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	particles.draw_pass_1 = quad
	particles.emitting = true

	await get_tree().create_timer(1.1).timeout
	if is_instance_valid(particles):
		particles.queue_free()


func _shake_camera(strength: float) -> void:
	camera_shake = maxf(camera_shake, strength)


func _is_valid(blocks: Array, pos: Vector2i) -> bool:
	for b in blocks:
		var block := b as Vector2i
		var cell: Vector2i = pos + block
		if cell.x < 0 or cell.x >= BOARD_WIDTH or cell.y >= BOARD_HEIGHT:
			return false
		if cell.y >= 0 and board.has(_key(cell)):
			return false
	return true


func _board_to_world(cell: Vector2i) -> Vector3:
	return Vector3(
		(float(cell.x) - float(BOARD_WIDTH - 1) * 0.5) * CELL_SIZE,
		(float(BOARD_HEIGHT - 1) * 0.5 - float(cell.y)) * CELL_SIZE,
		0.0
	)


func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _random_kind() -> String:
	var keys := SHAPES.keys()
	return str(keys[rng.randi_range(0, keys.size() - 1)])


func _can_play() -> bool:
	return not game_over and not paused


func _update_hud() -> void:
	if score_label == null:
		return
	score_label.text = "%06d" % score
	if lines_label != null:
		lines_label.text = "LINES %02d" % lines
	if level_label != null:
		level_label.text = "LVL %02d  NEXT %d" % [level, next_level_score]
	if next_label != null:
		next_label.text = "NEXT %s" % next_kind
	if status_label == null:
		return
	if paused:
		status_label.text = "SYSTEM HOLD"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.9))
	elif game_over:
		status_label.text = "STACK CRASH - PRESS R"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.18, 0.22))
	else:
		status_label.text = "DROP THE BEAT"
		status_label.add_theme_color_override("font_color", Color(0.92, 1.0, 0.72))


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.free()
