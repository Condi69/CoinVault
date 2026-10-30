extends RefCounted
const RUN = preload("res://run_state.gd")
var directory := "user://saves"
var error_message := ""
var recovered := false

func _path(slot:int,suffix:String="") -> String:
	return directory+"/vault_%d.sav%s" % [slot,suffix]

func exists(slot:int) -> bool:
	return FileAccess.file_exists(_path(slot)) or FileAccess.file_exists(_path(slot,".bak"))

func _digest(bytes:PackedByteArray) -> String:
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(bytes)
	return hash_context.finish().hex_encode()

func _read(path:String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()<4 or file.get_length()>128000000:return {}
	var encoded_length := file.get_32()
	if encoded_length!=file.get_length()-4:return {}
	file.seek(0)
	var envelope=file.get_var(false)
	file.close()
	if not envelope is Dictionary or envelope.get("magic","")!="COINVAULT_RUN" or envelope.get("version",0)!=1:return {}
	var bytes=envelope.get("payload")
	if not bytes is PackedByteArray or _digest(bytes)!=envelope.get("sha256",""):return {}
	var data=bytes_to_var(bytes)
	if not data is Dictionary or not RUN.valid(data):return {}
	return data

func read_slot(slot:int) -> Dictionary:
	error_message=""
	recovered=false
	if slot<1 or slot>3:
		error_message="Invalid save slot."
		return {}
	var data := _read(_path(slot))
	if data.is_empty():
		data=_read(_path(slot,".bak"))
		recovered=not data.is_empty()
	if data.is_empty() and exists(slot):error_message="Slot %d could not be read. Its files have been kept." % slot
	return data

func summaries() -> Array:
	var result: Array=[]
	for slot in range(1,4):
		var data := read_slot(slot)
		result.append({"slot":slot,"exists":exists(slot),"valid":not data.is_empty(),"backup":recovered,"data":data,"error":error_message})
	return result

func latest_slot() -> int:
	var latest := 0
	var timestamp := -1.0
	for entry in summaries():
		if entry.valid and float(entry.data.saved_at)>timestamp:
			timestamp=float(entry.data.saved_at)
			latest=entry.slot
	return latest

func write_slot(slot:int,data:Dictionary) -> bool:
	error_message=""
	if slot<1 or slot>3 or not RUN.valid(data):
		error_message="Save data failed validation; the previous file was kept."
		return false
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:
		error_message="Cannot create the save folder."
		return false
	var bytes := var_to_bytes(data)
	var file := FileAccess.open(_path(slot,".tmp"),FileAccess.WRITE)
	if file==null:
		error_message="Cannot write the save file. Check free space and folder access."
		return false
	file.store_var({"magic":"COINVAULT_RUN","version":1,"payload":bytes,"sha256":_digest(bytes)},false)
	file.flush()
	var result := file.get_error()
	file.close()
	if result!=OK or _read(_path(slot,".tmp")).is_empty():
		error_message="The new save could not be verified. Your previous save was kept."
		return false
	var path := _path(slot)
	var backup := _path(slot,".bak")
	if FileAccess.file_exists(path):
		if not _read(path).is_empty():
			if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup)!=OK:
				error_message="Cannot rotate the save backup."
				return false
			if DirAccess.rename_absolute(path,backup)!=OK:
				error_message="Cannot back up the previous save."
				return false
		elif DirAccess.remove_absolute(path)!=OK:
			error_message="Cannot replace the damaged save."
			return false
	if DirAccess.rename_absolute(_path(slot,".tmp"),path)!=OK:
		if not FileAccess.file_exists(path) and FileAccess.file_exists(backup):DirAccess.copy_absolute(backup,path)
		error_message="Cannot finish saving. Your previous save is available in its backup."
		return false
	return true


