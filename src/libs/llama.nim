when defined(generate_llama_binding):
  import std/os
  import pkg/futhark

  proc rename_symbol(
      n: string, k: SymbolKind, p: string, overloading: var bool
  ): string =
    result = n
    if k in [Typedef, Enum, Struct, Anon]:
      result = n.split("_").map_it(it.capitalize_ascii()).join("")

  const
    base_dir =
      current_source_path.parent_dir / ".." / ".." / "vendor" / "llama.cpp"
    include_dir = base_dir / "include"
    ggml_include_dir = base_dir / "ggml" / "include"
    sys_path =
      "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/"
    output_path =
      current_source_path.parent_dir / "generated" / "llama_binding.nim"

  importc:
    # futhark symbols must be camelCase
    renameCallback rename_symbol
    sysPath sys_path
    path include_dir
    path ggml_include_dir
    outputPath output_path
    "llama.h"
else:
  import generated/llama_binding

type
  LLM* = object
    ctx: ptr StructLlamaContext
    vocab: ptr StructLlamaVocab
    sampler: ptr StructLlamaSampler
    model: ptr StructLlamaModel
    messages: seq[LlamaChatMessage]
    msg_strings: seq[string]
    formatted: string
    prev_len: int

  LlamaError* = object of CatchableError

proc `=destroy`(self: LLM) =
  llama_sampler_free(self.sampler)
  llama_free(self.ctx)
  llama_model_free(self.model)
  llama_backend_free()

const
  ngl = 99
  n_ctx = 128000

proc init*(_: type LLM, model_path = "gemma-3-4b-it-q4_0.gguf"): LLM =
  ggml_backend_load_all()

  llama_log_set(
    proc(level: EnumGgmlLogLevel, text: cstring, _: pointer) {.cdecl.} =
      if level >= GGML_LOG_LEVEL_ERROR:
        stdout.write text
    ,
    nil,
  )

  var model_params = llama_model_default_params()
  model_params.n_gpu_layers = ngl

  let model = llama_model_load_from_file(model_path, model_params)
  if model.is_nil:
    raise LlamaError.new_exception("failed to load model")

  let vocab = llama_model_get_vocab(model)

  var ctx_params = llama_context_default_params()
  ctx_params.n_ctx = n_ctx
  ctx_params.n_batch = n_ctx

  let ctx = llama_init_from_model(model, ctx_params)
  if ctx.is_nil:
    raise LlamaError.new_exception("failed to create context")

  var sparams = llama_sampler_chain_default_params()
  sparams.no_perf = false
  var sampler = llama_sampler_chain_init(sparams)

  llama_sampler_chain_add(sampler, llama_sampler_init_min_p(0.05, 1))
  llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.8))
  llama_sampler_chain_add(
    sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED.uint32)
  )

  let ctx_size = llama_n_ctx(ctx)

  result = LLM(
    ctx: ctx,
    vocab: vocab,
    sampler: sampler,
    model: model,
    formatted: new_string(ctx_size),
    prev_len: 0,
  )

iterator generate*(self: var LLM, input: string): string =
  self.msg_strings.add input
  let tmpl = llama_model_chat_template(self.model, nil)
  self.messages.add LlamaChatMessage(role: "user", content: self.msg_strings[^1].cstring)

  var new_len = llama_chat_apply_template(
    tmpl,
    cast[ptr StructLlamaChatMessage](self.messages[0].addr),
    cast[csize_t](self.messages.len),
    true,
    self.formatted.cstring,
    self.formatted.len.int32,
  )

  if new_len >= self.formatted.len:
    self.formatted.set_len(new_len)
    new_len = llama_chat_apply_template(
      tmpl,
      cast[ptr StructLlamaChatMessage](self.messages[0].addr),
      cast[csize_t](self.messages.len),
      true,
      self.formatted.cstring,
      self.formatted.len.int32,
    )
  if new_len < 0:
    raise LlamaError.new_exception("failed to apply the chat template")

  let prompt = self.formatted[self.prev_len ..< new_len]

  let is_first = llama_kv_self_used_cells(self.ctx) == 0

  var response = ""

  let n_prompt_tokens =
    -llama_tokenize(
      self.vocab, prompt.cstring, prompt.len.int32, nil, 0, is_first, true
    )
  var prompt_tokens =
    cast[ptr LlamaToken](alloc(n_prompt_tokens * sizeof(LlamaToken)))
  defer:
    dealloc(prompt_tokens)

  if llama_tokenize(
    self.vocab, prompt.cstring, prompt.len.int32, prompt_tokens,
    n_prompt_tokens, is_first, true,
  ) < 0:
    raise LlamaError.new_exception("failed to tokenize the prompt")

  var batch = llama_batch_get_one(prompt_tokens, n_prompt_tokens)
  var new_token_id: LlamaToken

  while true:
    let n_ctx = llama_n_ctx(self.ctx).int32
    let n_ctx_used = llama_kv_self_used_cells(self.ctx)
    if n_ctx_used + batch.n_tokens > n_ctx:
      raise LlamaError.new_exception("context size exceeded")

    if (llama_decode(self.ctx, batch) != 0):
      raise LlamaError.new_exception("failed to decode")

    new_token_id = llama_sampler_sample(self.sampler, self.ctx, -1)
    if llama_vocab_is_eog(self.vocab, new_token_id):
      break

    var buf = new_string(256)
    let n = llama_token_to_piece(
      self.vocab, new_token_id, buf.cstring, sizeof(buf).int32, 0, true
    )
    if n < 0:
      raise LlamaError.new_exception("failed to convert token to piece")

    buf.set_len(buf.cstring.len)
    yield buf
    response.add buf

    batch = llama_batch_get_one(new_token_id.addr, 1)

  self.msg_strings.add response
  self.messages.add LlamaChatMessage(role: "assistant", content: self.msg_strings[^1].cstring)

  self.prev_len = llama_chat_apply_template(
    tmpl,
    cast[ptr StructLlamaChatMessage](self.messages[0].addr),
    cast[csize_t](self.messages.len),
    false,
    nil,
    0,
  )

  if self.prev_len < 0:
    raise LlamaError.new_exception("failed to apply the chat template")

when is_main_module:
  try:
    var llm = LLM.init
    while true:
      stdout.write "\n\n\e[32m> \e[0m"
      let input = stdin.read_line
      if input == "":
        break
      stdout.write "\n"

      stdout.write("\e[33m");

      for msg in llm.generate(input):
        stdout.write(msg)
        stdout.flush_file()

      stdout.write("\n\e[0m");
  except Defect as e:
    echo e.msg
    echo e.get_stack_trace
