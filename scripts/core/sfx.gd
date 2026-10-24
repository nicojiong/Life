extends Node
## 程序化音效：没有素材，用正弦波 + 噪声合成几个短音。
## 顺带管总音量：- / = 调整，写进 user://settings.cfg。

signal volume_changed(db: float)

const SETTINGS_PATH := "user://settings.cfg"
const VOLUME_MIN := -36.0
const VOLUME_MAX := 0.0

var _players: Array = []
var _streams: Dictionary = {}
var _next := 0
var master_db := 0.0

## 每个音效额外的增益（分贝）。脚步要压得很低，不然一路响得像敲鼓。
const GAIN_DB := {
	"step": -16.0,
	"click": -4.0,
	"open": -2.0,
	"bell": 2.0,
}


func _ready() -> void:
	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)

	_streams["click"] = _tone(760.0, 0.075, 46.0, 0.34, 0.30)
	_streams["step"] = _tone(96.0, 0.070, 34.0, 0.075, 0.05)
	_streams["open"] = _tone(520.0, 0.16, 13.0, 0.26, 0.0)
	_streams["coin"] = _tone(1180.0, 0.20, 15.0, 0.30, 0.0)
	_streams["bell"] = _tone(294.0, 1.8, 1.9, 0.34, 0.0)
	_streams["fail"] = _tone(170.0, 0.24, 11.0, 0.28, 0.18)
	_streams["ok"] = _tone(660.0, 0.22, 9.0, 0.28, 0.0)
	_load_settings()
	print("[SFX] 生成 %d 个程序化音效，主音量 %.0f dB" % [_streams.size(), master_db])


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	if k == KEY_MINUS or k == KEY_KP_SUBTRACT:
		set_master(master_db - 3.0)
	elif k == KEY_EQUAL or k == KEY_KP_ADD:
		set_master(master_db + 3.0)


func set_master(db: float) -> void:
	master_db = clampf(db, VOLUME_MIN, VOLUME_MAX)
	AudioServer.set_bus_volume_db(0, master_db)
	_save_settings()
	volume_changed.emit(master_db)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		master_db = clampf(float(cfg.get_value("audio", "master_db", 0.0)), VOLUME_MIN, VOLUME_MAX)
	AudioServer.set_bus_volume_db(0, master_db)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_db", master_db)
	cfg.save(SETTINGS_PATH)


func play(sound: String) -> void:
	if not _streams.has(sound) or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next % _players.size()]
	_next += 1
	p.stream = _streams[sound]
	p.volume_db = -8.0 + float(GAIN_DB.get(sound, 0.0))
	p.play()


func _tone(freq: float, dur: float, decay: float, vol: float, noise: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * float(rate))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var tt := float(i) / float(rate)
		var env := exp(-tt * decay)
		var s := sin(TAU * freq * tt) * env * vol
		if noise > 0.0:
			s += (randf() * 2.0 - 1.0) * noise * env
		var v := int(clampf(s, -1.0, 1.0) * 32000.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	return st
