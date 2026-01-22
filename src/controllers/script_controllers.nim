import core
import ./script_controllers/worker

proc init*(T: type ScriptController): ScriptController =
  result = ScriptController()
  result.worker_thread = launch_worker(Ed.thread_ctx, state)
