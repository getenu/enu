# --define:"chronicles_log_level=DEBUG"
# --define:"chronicles_sinks=textlines[dynamic],json[file]"
# --define:"chronicles_disabled_topics=verbose"
# --define:"chronicles_line_numbers"
# --define:"metrics"

# --define:"ed_trace"
# --define:"dump_ed_objects"

# Release mode options that may need to be enabled for debugging:
# --define:"chronicles_colors=None"
# --assertions:off
# --define:"ed_lax_free"

# Sequential ids and no timestamps for better log diffs.
# Sequential ids can only be enabled for a single client.
# --define:"ed_sequential_ids"
# --define:"chronicles_timestamps=None"
