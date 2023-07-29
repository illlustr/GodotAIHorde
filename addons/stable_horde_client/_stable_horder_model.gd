# warning-ignore-all: RETURN_VALUE_DISCARDED
# warning-ignore-all: UNUSED_SIGNAL

## simplify version of "stable_horde_models" class
## will only update once a day.
## it may missing somting, also strip alot of things

## model group by style, to get model data, call `get_ref` method
## EX from `get_ref`
## {"count": int, "style": string, "desc": string, "img": array, "page": string, "nsfw": bool}


extends Node
class_name RefStableHordeModel

signal failed
signal success(model)

enum STATE {
	GET_STATUS,
	GET_REFRENCE
}
const PATH_URL := [
	"https://aihorde.net/api/v2/status/models",
	"https://raw.githubusercontent.com/db0/AI-Horde-image-model-reference/main/stable_diffusion.json"
]
const PATH_SAVE := [
	"user://model",
	"user://model_date",
]

var state: int = STATE.GET_STATUS
var _date: String
var _new := false
var _err := 0

var model: Dictionary
var refrence: Dictionary

var http: HTTPRequest


func _init() -> void:
	_date = Time.get_date_string_from_system()


func _request_completed(result: int, _c: int, _h: PoolStringArray, body: PoolByteArray) -> void:
	if result != 0:
		_err += 1
		if _err > 10:
			emit_signal("failed")
			return
		
		http.call_deferred("request_raw", PATH_URL[state])
		return
	
	var format = str2var(body.get_string_from_utf8())
	match state:
		STATE.GET_STATUS:
			if format is Array and !format.empty():
				call_deferred("_create_status", format)
			
		STATE.GET_REFRENCE:
			if format is Dictionary and !format.empty():
				call_deferred("_create_refrences", format)
				return
			
			http.call_deferred("request_raw", PATH_URL[state])


## Create status for every model
func _create_status(data: Array) -> void:
	for info in data:
		# exclude model that has only 1 worker
		if !info.has("count") or info["count"] < 2:
			continue
		
		refrence[info["name"]] = {
			"count": info["count"]
		}
	
	state = STATE.GET_REFRENCE
	http.call_deferred("request_raw", PATH_URL[state])


## add detail
func _create_refrences(data: Dictionary) -> void:
	for key in data:
		if !refrence.has(key): continue
		
		# Minifying
		var current_model :Dictionary = refrence[key]
		
		current_model["style"] = data[key].get("style")
		current_model["desc"] = data[key].get("description")
		current_model["img"] = data[key].get("showcases")
		current_model["page"] = data[key].get("homepage")
		current_model["nsfw"] = data[key].get("nsfw")
		
		refrence[key] = current_model
	
	if _new:
		http.queue_free()
		call_deferred("_save_file")
	
	call_deferred("_group_style")


## group the models to its specifict style
func _group_style() -> void:
	for key in refrence:
		if refrence[key].size() < 4: continue
		
		var style: String = refrence[key].get("style")
		if refrence[key].get("style") == null: continue
		
		if model.has(style):
			var last_data: Array = model.get(style)
			last_data.append(key)
			model[style] = last_data
		else:
			model[style] = [key]
	
	emit_signal("success", model)


func _save_file() -> void:
	var file := File.new()
	file.open(PATH_SAVE[0], File.WRITE)
	file.store_var(refrence)
	file.close()
	
	file.open(PATH_SAVE[1], File.WRITE)
	file.store_var(_date)
	file.close()


func _load_file() -> void:
	var file = File.new()
	file.open(PATH_SAVE[1], File.READ)
	var filevar = file.get_var()
	file.close()
	
	if _date != filevar:
		call_deferred("_initialize")
		return
	
	file.open(PATH_SAVE[0], File.READ)
	refrence = file.get_var()
	file.close()
	
	call_deferred("_group_style")


func _initialize() -> void:
	_new = true
	state = STATE.GET_STATUS
	http = HTTPRequest.new()
	http.use_threads = true
	http.connect("request_completed", self, "_request_completed")
	
	call_deferred("add_child", http)
	http.call_deferred("request_raw", PATH_URL[state])


func get_ref(model_name: String) -> Dictionary:
	return refrence.get(model_name)


func initialize() -> void:
	call_deferred("_load_file")
