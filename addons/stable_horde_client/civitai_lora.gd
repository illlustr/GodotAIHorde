# warning-ignore-all: RETURN_VALUE_DISCARDED
extends Node
class_name RefCivitAILoRA

signal failed(msg) # string
signal complete(type) # int

enum COMPLETE {
	RATED,
	USER,
	FULL
}
enum {
	CIVIT_RATED,
	CIVIT_USERS
}
const PATH_SAVE := [
	"user://LoRA_date",
	"user://LoRA_highest_rated",
	"user://LoRA_user_favorite"
]
const HTML_TO_BBCODE := {
	"<p>": '',
	"</p>": '\n',
	"</b>": '[/b]',
	"<b>": '[b]',
	"</strong>": '[/b]',
	"<strong>": '[b]',
	"</em>": '[/i]',
	"<em>": '[i]',
	"</i>": '[/i]',
	"<i>": '[i]',
	"<br />": '\n',
	"<br/>": '\n',
	"<br>": '\n',
	"<h1>": '[b][color=yellow]',
	"</h1>": '[/color][/b]\n',
	"<h2>": '[b]',
	"<h2 id=": '[b]',
	"</h2>": '[/b]\n',
	"<h3>": '',
	"<h3 id=": '',
	"</h3>": '',
	"<u>": '[u]',
	"</u>": '[/u]',
	"<code>": '[code]',
	"</code>": '[/code]',
	"<ul>": '[ul]',
	"</ul>": '[/ul]',
	"<ol>": '[ol]',
	"</ol>": '[/ol]',
	"<li>": '',
	"</li>": '\n',
	"&lt;": '<',
	"&gt;": '>',
	"<a target=": "[url=",
	'">': "]",
	"</a>": "[/url]",
	'<span style="color:': "[b][color=",
	"</span>": "[/color]",
	"<img src=": " ",
	"/>": " ",
	"<a rel=": " ",
	"href=": " "
	
}
var _REQ_URL := [
	# Maximum allowed is 100 ..
	#"https://civitai.com/api/v1/models?types=LORA&sort=Most%20Downloaded&primaryFileOnly=true&limit=100",
	"https://civitai.com/api/v1/models?types=LORA&sort=Highest%20Rated&primaryFileOnly=true&limit=100",
	"https://civitai.com/api/v1/models",
]

const _ERR_MAX := 16
const _CRI_MAX := 4

var _state: int = CIVIT_RATED

# Hacky workaround, just in case it called multiple time.
var _process: bool = false

var _err: int = 0
var _critical: int = 0
var _format

var lora_date: String
var lora_users: Array

var _raw_lora_rated: Dictionary
var _raw_lora_users: Dictionary

var lora_ref_rated: Dictionary
var lora_ref_users: Dictionary

var lora_model_rated: Dictionary
var lora_model_users: Dictionary

var _request: HTTPRequest


func _init() -> void:
	lora_date = Time.get_date_string_from_system()


func _request_completed(result: int, _c: int, _h: PoolStringArray, body: PoolByteArray) -> void:
	if result != 0:
		_err += 1
		if _err > _ERR_MAX:
			emit_signal("failed", "Request Failed : " + _REQ_URL[_state])
			print_debug("Request Failed : ", _REQ_URL[_state], " - ", _c)
			return
		
		_request.call_deferred("request", _REQ_URL[_state])
		return
	
	_format = str2var(body.get_string_from_utf8())
	match _state:
		CIVIT_RATED:
			if _format is Dictionary and !_format.empty():
				_raw_lora_rated = _format
				call_deferred("_file_save")
				call_deferred(
						"_parse_lora",
						"_raw_lora_rated",
						"lora_ref_rated",
						"lora_model_rated",
						COMPLETE.RATED
				)
				
				if !lora_users.empty():
					call_deferred("request_favorite")
			
			else:
				_request.call_deferred("request", _REQ_URL[_state])
				_critical += 1
		
		CIVIT_USERS:
			if _format is Dictionary and !_format.empty():
				_raw_lora_users = _format
				call_deferred("_file_save")
				call_deferred(
						"_parse_lora",
						"_raw_lora_users",
						"lora_ref_users",
						"lora_model_users",
						COMPLETE.USER
				)
			
			else:
				_request.call_deferred("request", _REQ_URL[_state])
				_critical += 1
		
	if _critical > _CRI_MAX:
		_request.cancel_request()
		emit_signal("failed", "Critical Error : " + _REQ_URL[_state] + " | " + str(_format))
		print_debug("Critical Error : ", _REQ_URL[_state], " | ", _format)


func _parse_lora(raw_data: String, group_refrences: String, group_model: String, sign_complete: int) -> void:
	var current_entry: Dictionary = get(raw_data)
	var current_group: Dictionary = get(group_refrences)
	var current_model: Dictionary = get(group_model)
	
	if !current_entry.has("items"):
		emit_signal("failed", "refrences doesnt have items : " + str(current_entry))
		print_debug("refrences doesnt have items : ", current_entry)
		return
	
	for item in current_entry.get("items"):
		var _lora = {
			"id": int(item["id"]),
			"desc": item["description"],
			"nsfw": item["nsfw"],
		}
		
		var versions = item.get("modelVersions", {})
		if versions.size() == 0: continue
		
		for file in versions[0]["files"]:
			if not file.get("name", "").ends_with(".safetensors"):
				continue
			if round(file["sizeKB"] / 1024) > 150:
				continue
			if file.get("hashes", {}).get("SHA256") == null:
				continue
			if !file.has("downloadUrl"):
				continue
		
		_lora["tgr"] = versions[0]["trainedWords"]
		_lora["ver"] = versions[0]["name"]
		_lora["model"] = versions[0]["baseModel"]
		_lora["img"] = []
		for img in versions[0]["images"]:
			_lora["img"].append(img["url"])
		
		if _lora["desc"] != null:
			for key in HTML_TO_BBCODE:
				_lora["desc"] = _lora["desc"].replace(key, HTML_TO_BBCODE[key])
			
			if _lora["desc"].length() > 500:
				_lora["desc"] = _lora["desc"].left(500) + ' [...]'
		
		current_group[item["name"]] = _lora
		
		var model: String = _lora["model"]
		if current_model.has(model):
			var _data = current_model.get(model)
			_data.append(item["name"])
			current_model[model] = _data
		else:
			current_model[model] = [item["name"]]
	
	var _group: Dictionary = get(group_refrences)
	var _model: Dictionary = get(group_model)
	
	_group.merge(current_group)
	_model.merge(current_model)
	
	set(group_refrences, _group)
	set(group_model, _model)
	
	emit_signal("complete", sign_complete)
	
	# This is trully hacky, i dont event think it will work.
	# i only call this class once, its here for : just in case.
	_process = false


func _file_save() -> void:
	var file := File.new()
	file.open(PATH_SAVE[0], File.WRITE)
	file.store_var(lora_date)
	file.close()
	
	file.open(PATH_SAVE[1], File.WRITE)
	file.store_var(_raw_lora_rated)
	file.close()
	
	file.open(PATH_SAVE[2], File.WRITE)
	file.store_var(_raw_lora_users)
	file.close()


func _file_load() -> void:
	var file := File.new()
	
	for path in PATH_SAVE:
		if !file.file_exists(path):
			call_deferred("request_rated")
			return
	
	file.open(PATH_SAVE[0], File.READ_WRITE)
	lora_date = file.get_var()
	file.close()
	
	file.open(PATH_SAVE[1], File.READ_WRITE)
	_raw_lora_rated = file.get_var()
	file.close()
	
	file.open(PATH_SAVE[2], File.READ_WRITE)
	_raw_lora_users = file.get_var()
	file.close()
	
	call_deferred(
			"_parse_lora",
			"_raw_lora_rated",
			"lora_ref_rated",
			"lora_model_rated",
			COMPLETE.RATED
	)
	if !lora_users.empty():
		call_deferred(
				"_parse_lora",
				"_raw_lora_users",
				"lora_ref_users",
				"lora_model_users",
				COMPLETE.USER
		)
	_process = false


func request_favorite() -> void:
	_state = CIVIT_USERS
	var join = '&ids='.join(lora_users)
	_REQ_URL[CIVIT_USERS] = _REQ_URL[CIVIT_USERS] + join
	_request.call_deferred("request", _REQ_URL[_state])


func request_rated() -> void:
	_request = HTTPRequest.new()
	add_child(_request)
	_state = CIVIT_RATED
	_request.connect("request_completed", self, "_request_completed")
	_request.call_deferred("request", _REQ_URL[_state])


func initialize() -> void:
	if _process: return
	_process = true
	call_deferred("_file_load")
