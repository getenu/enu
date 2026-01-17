## Ed API Reference
## Generates API documentation page for Ed reactive data framework.

import nimib, nimibook
import ../../enuib
import ../../api_docs

# Load JSON documentation files at compile time
const
  types_json = static_read("../../../../model_citizen/docs/json/ed/types.json")
  initializers_json = static_read("../../../../model_citizen/docs/json/ed/zens/initializers.json")
  operations_json = static_read("../../../../model_citizen/docs/json/ed/zens/operations.json")
  contexts_json = static_read("../../../../model_citizen/docs/json/ed/zens/contexts.json")
  validations_json = static_read("../../../../model_citizen/docs/json/ed/zens/validations.json")

# Configure modules with their JSON content
const modules: seq[ModuleConfig] = @[
  ("ed/types", types_json),
  ("ed/zens/initializers", initializers_json),
  ("ed/zens/operations", operations_json),
  ("ed/zens/contexts", contexts_json),
  ("ed/zens/validations", validations_json),
]

# Initialize nimib with API docs theme
nb_init(theme = use_api_docs)

# Collect symbols and convert to JSON for Mustache
let data = collect_symbols(modules)
let api_json = data.to_api_json()

# Set API context for template
nb.context["api"] = api_json

nb_save
