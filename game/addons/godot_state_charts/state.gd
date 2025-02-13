@tool
## This class represents a state that can be either active or inactive.
class_name State
extends Node

## Called when the state is entered.
signal state_entered()

## Called when the state is exited.
signal state_exited()

## Called when the state receives an event. Only called if the state is active.
signal event_received(event:StringName)

## Called when the state is processing.
signal state_processing(delta:float)

## Called when the state is physics processing.
signal state_physics_processing(delta:float)

## Whether the current state is active.
var active:bool:
	get: return process_mode != Node.PROCESS_MODE_DISABLED

## The currently active pending transition.
var _pending_transition:Transition = null

## Remaining time in seconds until the pending transition is triggered.
var _pending_transition_time:float = 0

## The transitions of this state.
var _transitions:Array[Transition] = []

## Called when the state chart is built.
func _state_init():
	# disable state by default
	process_mode = Node.PROCESS_MODE_DISABLED
	# load transitions
	_transitions.clear()
	for child in get_children():
		if child is Transition:
			_transitions.append(child)
	
## Called when the state is entered.
func _state_enter():
	# print("state_enter: " + name)
	process_mode = Node.PROCESS_MODE_INHERIT
	# emit the signal
	state_entered.emit()
	# check all transitions which have no event
	for transition in _transitions:
		if not transition.has_event and transition.evaluate_guard():
			# first match wins
			_queue_transition(transition)
			

## Called when the state is exited.
func _state_exit():
	# print("state_exit: " + name)
	# cancel any pending transitions
	_pending_transition = null
	_pending_transition_time = 0
	# stop processing
	process_mode = Node.PROCESS_MODE_DISABLED
	# emit the signal
	state_exited.emit()

## Called when the state should be saved. The parameter is is the SavedState object
## of the parent state. The state is expected to add a child to the SavedState object
## under its own name. 
## 
## The child_levels parameter indicates how many levels of children should be saved.
## If set to -1 (default), all children should be saved. If set to 0, no children should be saved.
##
## This method will only be called if the state is active and should only be called on
## active children if children should be saved.
func _state_save(saved_state:SavedState, child_levels:int = -1):
	if not active:
		push_error("_state_save should only be called if the state is active.")
		return
	
	# create a new SavedState object for this state
	var our_saved_state := SavedState.new()
	our_saved_state.pending_transition_name = _pending_transition.name if _pending_transition != null else ""
	our_saved_state.pending_transition_time = _pending_transition_time
	# add it to the parent
	saved_state.add_substate(self, our_saved_state)

	if child_levels == 0:
		return

	# calculate the child levels for the children, -1 means all children
	var sub_child_levels = -1 if child_levels == -1 else child_levels - 1

	# save all children
	for child in get_children():
		if child is State and child.active:
			child._state_save(our_saved_state, sub_child_levels)


## Called when the state should be restored. The parameter is the SavedState object
## of the parent state. The state is expected to retrieve the SavedState object
## for itself from the parent and restore its state from it. 
##
## The child_levels parameter indicates how many levels of children should be restored.
## If set to -1 (default), all children should be restored. If set to 0, no children should be restored.
##
## If the state was not active when it was saved, this method still will be called
## but the given SavedState object will not contain any data for this state.
func _state_restore(saved_state:SavedState, child_levels:int = -1):
	print("restoring state " + name)
	var our_saved_state = saved_state.get_substate_or_null(self)
	if our_saved_state == null:
		# if we are currently active, deactivate the state
		if active:
			_state_exit()
		# otherwise we are already inactive, so we don't need to do anything
		return

	# otherwise if we are currently inactive, activate the state
	if not active:
		_state_enter()
	# and restore any pending transition
	_pending_transition = get_node_or_null(our_saved_state.pending_transition_name) as Transition
	_pending_transition_time = our_saved_state.pending_transition_time
	
	if _pending_transition != null:
		print("restored pending transition " + _pending_transition.name + " with time " + str(_pending_transition_time))
	else:
		print("no pending transition restored")

	if child_levels == 0:
		return

	# calculate the child levels for the children, -1 means all children
	var sub_child_levels = -1 if child_levels == -1 else child_levels - 1

	# restore all children
	for child in get_children():
		if child is State:
			child._state_restore(our_saved_state, sub_child_levels)


## Called while the state is active.
func _process(delta:float):
	if Engine.is_editor_hint():
		return
		
	# emit the processing signal
	state_processing.emit(delta)
	# check if there is a pending transition
	if _pending_transition != null:
		_pending_transition_time -= delta
		# if the transition is ready, trigger it
		# and clear it.
		if _pending_transition_time <= 0:
			var transition_to_send = _pending_transition
			_pending_transition = null
			_pending_transition_time = 0
			# print("requesting transition from " + name + " to " + transition_to_send.to.get_concatenated_names() + " now")
			_handle_transition(transition_to_send, self)


func _handle_transition(transition:Transition, source:State):
	push_error("State " + name + " cannot handle transitions.")
	

func _physics_process(delta:float):
	if Engine.is_editor_hint():
		return
	state_physics_processing.emit(delta)


## Handles the given event. Returns true if the event was consumed, false otherwise.
func _state_event(event:StringName) -> bool:
	if not active:
		return false

	# emit the event received signal
	event_received.emit(event)

	# check all transitions which have the event
	for transition in _transitions:
		if transition.event == event and transition.evaluate_guard():
			# print(name +  ": consuming event " + event)
			# first match wins
			_queue_transition(transition)
			return true
	return false

## Queues the transition to be triggered after the delay.
## Executes the transition immediately if the delay is 0.
func _queue_transition(transition:Transition):
	# print("transitioning from " + name + " to " + transition.to.get_concatenated_names() + " in " + str(transition.delay_seconds) + " seconds" )
	# queue the transition for the delay time (0 means next frame)
	_pending_transition = transition
	_pending_transition_time = transition.delay_seconds


func _get_configuration_warnings() -> PackedStringArray:
	var result = []
	# if not at least one of our ancestors is a StateChart add a warning
	var parent = get_parent()
	var found = false
	while is_instance_valid(parent):
		if parent is StateChart:
			found = true
			break
		parent = parent.get_parent()
	
	if not found:
		result.append("State is not a child of a StateChart. This will not work.")

	return result		
