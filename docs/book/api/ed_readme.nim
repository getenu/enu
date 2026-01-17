## Ed README
## Ed README page with Ed-specific sidebar.

import nimib, nimibook
import ../../enuib
import ../../api_docs

# Load README at compile time
const readme_md = static_read("../../../../model_citizen/README.md")

# Load JSON documentation files for sidebar
const
  types_json = static_read("../../../../model_citizen/docs/json/ed/types.json")
  initializers_json = static_read("../../../../model_citizen/docs/json/ed/zens/initializers.json")
  operations_json = static_read("../../../../model_citizen/docs/json/ed/zens/operations.json")
  contexts_json = static_read("../../../../model_citizen/docs/json/ed/zens/contexts.json")
  validations_json = static_read("../../../../model_citizen/docs/json/ed/zens/validations.json")

const modules: seq[ModuleConfig] = @[
  ("ed/types", types_json),
  ("ed/zens/initializers", initializers_json),
  ("ed/zens/operations", operations_json),
  ("ed/zens/contexts", contexts_json),
  ("ed/zens/validations", validations_json),
]

nb_init(theme = use_ed_readme)

# Set API context for sidebar
let data = collect_symbols(modules)
nb.context["api"] = data.to_api_json()

nb_text(readme_md)
nb_save
