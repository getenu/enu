import std/strformat

when defined(generate_llama_binding):
  import std/[os, strutils, sequtils]
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
  LLM* = ref object
    vocab: ptr StructLlamaVocab
    model: ptr StructLlamaModel
    tmpl: string
    ctx: ptr StructLlamaContext
    next_sequence_id: LlamaSeqId

  Conversation* = ref object
    llm: LLM
    messages: seq[LlamaChatMessage]
    msg_strings: seq[string]
    formatted: string
    prev_len: int
    sampler: ptr StructLlamaSampler
    sequence_id: LlamaSeqId
    current_token_pos: LlamaPos

  LlamaError* = object of CatchableError

proc `=destroy`(self: type LLM()[]) =
  if not self.ctx.is_nil:
    llama_free(self.ctx)
  if not self.model.is_nil:
    llama_model_free(self.model)

proc `=destroy`(self: type Conversation()[]) =
  if not self.sampler.is_nil:
    llama_sampler_free(self.sampler)

  if not self.llm.ctx.is_nil and self.llm.ctx != nil:
    discard llama_kv_cache_seq_rm(self.llm.ctx, self.sequence_id, 0, -1)

const
  ngl = 99
  n_ctx = 128000

template init*(_: type LlamaError, msg: string): ref LlamaError =
  LlamaError.new_exception(msg)

proc init_backend*(_: type LLM) =
  ggml_backend_load_all()

proc free_backend*(_: type LLM) =
  llama_backend_free()

proc init*(_: type LLM, model_path = "gemma-3-4b-it-q4_0.gguf"): LLM =
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
    raise LlamaError.init("failed to load model")

  var ctx_params = llama_context_default_params()
  ctx_params.n_ctx = n_ctx
  ctx_params.n_batch = n_ctx

  let ctx = llama_init_from_model(model, ctx_params)
  if ctx.is_nil:
    raise LlamaError.init("failed to create context for LLM")

  let vocab = llama_model_get_vocab(model)

  result = LLM(
    vocab: vocab,
    model: model,
    tmpl: $llama_model_chat_template(model, nil),
    ctx: ctx,
    next_sequence_id: 0,
  )

proc init*(_: type Conversation, llm: var LLM): Conversation =
  var sampler = llama_sampler_chain_init llama_sampler_chain_default_params()

  llama_sampler_chain_add(sampler, llama_sampler_init_min_p(0.05, 1))
  llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.8))
  llama_sampler_chain_add(
    sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED.uint32)
  )

  let sequence_id = llm.next_sequence_id
  llm.next_sequence_id += 1
  result = Conversation(
    llm: llm, sampler: sampler, sequence_id: sequence_id, current_token_pos: 0
  )

iterator generate*(self: var Conversation, input: string): string =
  self.msg_strings.add input

  self.messages.add LlamaChatMessage(
    role: "user", content: self.msg_strings[^1].cstring
  )

  var new_len = llama_chat_apply_template(
    self.llm.tmpl.cstring,
    cast[ptr StructLlamaChatMessage](self.messages[0].addr),
    cast[csize_t](self.messages.len),
    true,
    self.formatted.cstring,
    self.formatted.len.int32,
  )

  if new_len >= self.formatted.len:
    self.formatted.set_len(new_len)
    new_len = llama_chat_apply_template(
      self.llm.tmpl.cstring,
      cast[ptr StructLlamaChatMessage](self.messages[0].addr),
      cast[csize_t](self.messages.len),
      true,
      self.formatted.cstring,
      self.formatted.len.int32,
    )
  if new_len < 0:
    raise LlamaError.init("failed to apply the chat template")

  let prompt = self.formatted[self.prev_len ..< new_len]
  let is_first = llama_kv_self_used_cells(self.llm.ctx) == 0
  var response = ""

  let n_prompt_tokens_cint =
    -llama_tokenize(
      self.llm.vocab, prompt.cstring, prompt.len.int32, nil, 0, is_first, true
    )
  if n_prompt_tokens_cint <= 0:
    raise LlamaError.init("failed to get prompt token count for tokenization")

  var temp_prompt_tokens = new_seq[LlamaToken](n_prompt_tokens_cint.int)
  let actual_n_tokens = llama_tokenize(
    self.llm.vocab,
    prompt.cstring,
    prompt.len.int32,
    temp_prompt_tokens[0].addr,
    n_prompt_tokens_cint,
    is_first,
    true,
  )
  if actual_n_tokens < 0:
    raise LlamaError.init("failed to tokenize the prompt")

  var current_batch = llama_batch_init(512, 0, 1)
  var new_token_id: LlamaToken

  try:
    current_batch.n_tokens = 0
    for i in 0 ..< actual_n_tokens:
      let token_idx = current_batch.n_tokens
      current_batch.token[token_idx.int] = temp_prompt_tokens[i]
      current_batch.pos[token_idx.int] = self.currentTokenPos + i.LlamaPos

      let n_seq_id_ua = cast[ptr UncheckedArray[int32]](current_batch.n_seq_id)
      n_seq_id_ua[token_idx.int] = 1

      let seq_id_outer_ua =
        cast[ptr UncheckedArray[ptr LlamaSeqId]](current_batch.seq_id)
      let inner_seq_id_ptr = seq_id_outer_ua[token_idx.int]
      let inner_seq_id_ua =
        cast[ptr UncheckedArray[LlamaSeqId]](inner_seq_id_ptr)
      inner_seq_id_ua[0] = self.sequence_id # Use self.sequence_id

      current_batch.logits[token_idx.int] = char(0)
      current_batch.n_tokens += 1

    if current_batch.n_tokens > 0:
      current_batch.logits[current_batch.n_tokens.int - 1] = char(1)

    self.currentTokenPos += actual_n_tokens

    while self.current_token_pos < n_ctx:
      if current_batch.n_tokens > 0:
        let n_ctx_val = llama_n_ctx(self.llm.ctx).int32
        let n_kv_cached = llama_kv_self_used_cells(self.llm.ctx)
        if n_kv_cached + current_batch.n_tokens > n_ctx_val:
          raise LlamaError.init(
            fmt"context size exceeded before decode: used {n_kv_cached}, batch {current_batch.n_tokens}, total_ctx {n_ctx_val}"
          )

        if llama_decode(self.llm.ctx, current_batch) != 0:
          raise LlamaError.init("failed to decode")

      new_token_id = llama_sampler_sample(self.sampler, self.llm.ctx, -1)
      self.current_token_pos += 1

      if llama_vocab_is_eog(self.llm.vocab, new_token_id):
        break

      var piece_buf = new_string(256)
      let piece_len = llama_token_to_piece(
        self.llm.vocab, new_token_id, piece_buf.cstring, piece_buf.len.int32, 0,
        true,
      )
      if piece_len < 0:
        raise LlamaError.init("failed to convert token to piece")

      piece_buf.set_len(piece_len.int)
      yield piece_buf
      response.add piece_buf

      current_batch.n_tokens = 0
      current_batch.token[0] = new_token_id
      current_batch.pos[0] = self.current_token_pos - 1

      let n_seq_id_next_ua =
        cast[ptr UncheckedArray[int32]](current_batch.n_seq_id)
      n_seq_id_next_ua[0] = 1

      let seq_id_outer_next_ua =
        cast[ptr UncheckedArray[ptr LlamaSeqId]](current_batch.seq_id)
      let inner_seq_id_next_ptr = seq_id_outer_next_ua[0]
      let inner_seq_id_next_ua =
        cast[ptr UncheckedArray[LlamaSeqId]](inner_seq_id_next_ptr)
      inner_seq_id_next_ua[0] = self.sequence_id

      current_batch.logits[0] = char(1)
      current_batch.n_tokens = 1
  finally:
    llama_batch_free(current_batch)

  self.msg_strings.add response
  self.messages.add LlamaChatMessage(
    role: "assistant", content: self.msg_strings[^1].cstring
  )

  self.prev_len = llama_chat_apply_template(
    self.llm.tmpl.cstring,
    cast[ptr StructLlamaChatMessage](self.messages[0].addr),
    cast[csize_t](self.messages.len),
    false,
    nil,
    0,
  )

  if self.prev_len < 0:
    raise LlamaError.init("failed to apply the chat template")

when is_main_module:
  try:
    ggml_backend_load_all()
    defer:
      llama_backend_free()
    var llm = LLM.init
    var conv = Conversation.init(llm = llm)

    while true:
      stdout.write "\n\n\e[32m> \e[0m"
      let input = stdin.read_line
      if input == "":
        break
      stdout.write "\n"

      stdout.write("\e[33m")

      for msg in conv.generate(input):
        stdout.write(msg)
        stdout.flush_file()

      stdout.write("\n\e[0m")
  except Defect as e:
    echo e.msg
    echo e.get_stack_trace
