# Metrics HTTP server module - isolated from gdobj to avoid chronos/godot conflicts
when defined(metrics):
  import pkg/metrics/chronos_httpserver
  import std/net

  proc start_metrics_server*(host: string, port: int) =
    {.cast(gcsafe).}:
      start_metrics_http_server(host, Port(port))
