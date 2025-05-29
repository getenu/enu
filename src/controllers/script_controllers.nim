import core
import ./script_controllers/worker
import ./script_controllers/thinker

proc init*(T: type ScriptController): ScriptController =
  result = ScriptController()
  result.worker_thread = launch_worker(state)
  result.thinker_thread = launch_thinker(state)
