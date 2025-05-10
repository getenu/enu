import pkg/futhark
import core

proc rename_symbol(
    n: string, k: SymbolKind, p: string, overloading: var bool
): string =
  result = n
  if k in [Typedef, Enum, Struct, Anon]:
    result = n.split("_").map_it(it.capitalize_ascii()).join("")

importc:
  renameCallback rename_symbol
  sysPath "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/"
  path "/Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/src/include"
  path "/Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/src/ggml/include"
  retype StructLlamaBatch.token, ptr UncheckedArray[LlamaToken]
  retype StructLlamaBatch.pos, ptr UncheckedArray[LlamaPos]
  retype StructLlamaBatch.lama_seq_id, ptr UncheckedArray[ptr LlamaSeqId]
  "llama.h"

type
  LLM* = object
    ctx: ptr StructLlamaContext
    vocab: ptr StructLlamaVocab
    sampler: ptr StructLlamaSampler
    messages: seq[LlamaChatMessage]
    ctx_size: uint32
    formatted: string
    tmpl: cstring
    prev_len: int

  LlamaError* = object of CatchableError

const
  ngl = 99
  n_ctx = 2048
  n_predict = 32

proc init*(_: type LLM, model_path = "gemma-3-4b-it-q4_0.gguf"): LLM =
  ggml_backend_load_all()

  llama_log_set(
    proc(level: EnumGgmlLogLevel, text: cstring, _: pointer) {.cdecl.} =
      if level >= GGML_LOG_LEVEL_ERROR and text.len > 1:
        echo text
    ,
    nil,
  )

  var model_params = llama_model_default_params()
  model_params.n_gpu_layers = ngl

  let model = llama_model_load_from_file(model_path, model_params)
  let vocab = llama_model_get_vocab(model)

  var ctx_params = llama_context_default_params()
  ctx_params.n_ctx = n_ctx
  ctx_params.n_batch = n_ctx
  ctx_params.no_perf = false

  let ctx = llama_init_from_model(model, ctx_params)

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
    tmpl: llama_model_chat_template(model, nil),
    ctx_size: ctx_size,
    formatted: new_string(ctx_size),
    prev_len: 0,
  )

iterator generate*(self: var LLM, input: string): string =
  self.messages.add LlamaChatMessage(role: "user", content: input)
  var new_len = llama_chat_apply_template(
    self.tmpl,
    cast[ptr StructLlamaChatMessage](self.messages[0].addr),
    cast[csize_t](self.messages.len),
    true,
    self.formatted.cstring,
    self.ctx_size.int32,
  )

  if new_len > self.formatted.len:
    self.formatted.set_len(new_len)
    new_len = llama_chat_apply_template(
      self.tmpl,
      cast[ptr StructLlamaChatMessage](self.messages[0].addr),
      cast[csize_t](self.messages.len),
      true,
      self.formatted.cstring,
      self.ctx_size.int32,
    )
  if new_len < 0:
    raise LlamaError.init("failed to apply the chat template")

  let prompt = self.formatted[self.prev_len .. new_len]
  var response = ""

  let is_first = llama_kv_self_used_cells(self.ctx) == 0

  let n_prompt_tokens =
    -llama_tokenize(
      self.vocab, prompt.cstring, prompt.len.int32, nil, 0, is_first, true
    )
  var prompt_tokens =
    cast[ptr LlamaToken](alloc(n_prompt_tokens * sizeof(LlamaToken)))

  if llama_tokenize(
    self.vocab, prompt.cstring, prompt.len.int32, prompt_tokens,
    n_prompt_tokens, is_first, true,
  ) < 0:
    raise LlamaError.init("failed to tokenize the prompt")

  var batch = llama_batch_get_one(prompt_tokens, n_prompt_tokens)
  var new_token_id: LlamaToken

  while true:
    let n_ctx = llama_n_ctx(self.ctx).int32
    let n_ctx_used = llama_kv_self_used_cells(self.ctx)
    if n_ctx_used + batch.n_tokens > n_ctx:
      raise LlamaError.init("context size exceeded")

    if (llama_decode(self.ctx, batch) != 0):
      raise LlamaError.init("failed to decode")

    new_token_id = llama_sampler_sample(self.sampler, self.ctx, -1)
    if llama_vocab_is_eog(self.vocab, new_token_id):
      break

    var buf = new_string(256)
    let n = llama_token_to_piece(
      self.vocab, new_token_id, buf.cstring, sizeof(buf).int32, 0, true
    )
    if n < 0:
      raise LlamaError.init("failed to convert token to piece")

    yield buf

    batch = llama_batch_get_one(new_token_id.addr, 1)

  self.messages.add LlamaChatMessage(role: "assistant", content: response)

  self.prev_len = llama_chat_apply_template(
    self.tmpl,
    cast[ptr StructLlamaChatMessage](self.messages[0].addr),
    cast[csize_t](self.messages.len),
    false,
    nil,
    0,
  )
  if self.prev_len < 0:
    raise LlamaError.init("failed to apply the chat template")

when is_main_module:
  var llm = LLM.init
  while true:
    stdout.write "\n\n> "
    let input = stdin.read_line

    for msg in llm.generate(input):
      stdout.write(msg)
