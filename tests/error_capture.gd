class_name ErrorCapture
extends Logger
## Records engine and script errors so the test runner can fail a test that
## hit one. A runtime script error (null deref, bad cast, missing method)
## aborts the test method silently from the caller's point of view: call()
## just returns, and no assert ever records a failure. Warnings are ignored.
##
## Loggers can be called from any thread, hence the mutex.

var _mutex: Mutex = Mutex.new()
var _errors: PackedStringArray = PackedStringArray()


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: Logger.ErrorType, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	# Engine ERR_*_MSG errors carry the condition in `code` and the message in
	# `rationale`; keep both. Script errors and push_error use only `code`.
	var what: String = code if rationale.is_empty() else "%s [%s]" % [rationale, code]
	_mutex.lock()
	_errors.append("%s (%s:%d in %s)" % [what, file, line, function])
	_mutex.unlock()


## Returns everything logged since the last take() and clears it.
func take() -> PackedStringArray:
	_mutex.lock()
	var out: PackedStringArray = _errors
	_errors = PackedStringArray()
	_mutex.unlock()
	return out
