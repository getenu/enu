
type
  EnumGgmlStatus* {.size: sizeof(cint).} = enum
    GGML_STATUS_ALLOC_FAILED = -2, GGML_STATUS_FAILED = -1,
    GGML_STATUS_SUCCESS = 0, GGML_STATUS_ABORTED = 1
type
  EnumGgmlType* {.size: sizeof(cuint).} = enum
    GGML_TYPE_F32 = 0, GGML_TYPE_F16 = 1, GGML_TYPE_Q4_0 = 2,
    GGML_TYPE_Q4_1 = 3, GGML_TYPE_Q5_0 = 6, GGML_TYPE_Q5_1 = 7,
    GGML_TYPE_Q8_0 = 8, GGML_TYPE_Q8_1 = 9, GGML_TYPE_Q2_K = 10,
    GGML_TYPE_Q3_K = 11, GGML_TYPE_Q4_K = 12, GGML_TYPE_Q5_K = 13,
    GGML_TYPE_Q6_K = 14, GGML_TYPE_Q8_K = 15, GGML_TYPE_IQ2_XXS = 16,
    GGML_TYPE_IQ2_XS = 17, GGML_TYPE_IQ3_XXS = 18, GGML_TYPE_IQ1_S = 19,
    GGML_TYPE_IQ4_NL = 20, GGML_TYPE_IQ3_S = 21, GGML_TYPE_IQ2_S = 22,
    GGML_TYPE_IQ4_XS = 23, GGML_TYPE_I8 = 24, GGML_TYPE_I16 = 25,
    GGML_TYPE_I32 = 26, GGML_TYPE_I64 = 27, GGML_TYPE_F64 = 28,
    GGML_TYPE_IQ1_M = 29, GGML_TYPE_BF16 = 30, GGML_TYPE_TQ1_0 = 34,
    GGML_TYPE_TQ2_0 = 35, GGML_TYPE_COUNT = 39
type
  EnumGgmlPrec* {.size: sizeof(cuint).} = enum
    GGML_PREC_DEFAULT = 0, GGML_PREC_F32 = 10
type
  EnumGgmlFtype* {.size: sizeof(cint).} = enum
    GGML_FTYPE_UNKNOWN = -1, GGML_FTYPE_ALL_F32 = 0, GGML_FTYPE_MOSTLY_F16 = 1,
    GGML_FTYPE_MOSTLY_Q4_0 = 2, GGML_FTYPE_MOSTLY_Q4_1 = 3,
    GGML_FTYPE_MOSTLY_Q4_1_SOME_F16 = 4, GGML_FTYPE_MOSTLY_Q8_0 = 7,
    GGML_FTYPE_MOSTLY_Q5_0 = 8, GGML_FTYPE_MOSTLY_Q5_1 = 9,
    GGML_FTYPE_MOSTLY_Q2_K = 10, GGML_FTYPE_MOSTLY_Q3_K = 11,
    GGML_FTYPE_MOSTLY_Q4_K = 12, GGML_FTYPE_MOSTLY_Q5_K = 13,
    GGML_FTYPE_MOSTLY_Q6_K = 14, GGML_FTYPE_MOSTLY_IQ2_XXS = 15,
    GGML_FTYPE_MOSTLY_IQ2_XS = 16, GGML_FTYPE_MOSTLY_IQ3_XXS = 17,
    GGML_FTYPE_MOSTLY_IQ1_S = 18, GGML_FTYPE_MOSTLY_IQ4_NL = 19,
    GGML_FTYPE_MOSTLY_IQ3_S = 20, GGML_FTYPE_MOSTLY_IQ2_S = 21,
    GGML_FTYPE_MOSTLY_IQ4_XS = 22, GGML_FTYPE_MOSTLY_IQ1_M = 23,
    GGML_FTYPE_MOSTLY_BF16 = 24
type
  EnumGgmlOp* {.size: sizeof(cuint).} = enum
    GGML_OP_NONE = 0, GGML_OP_DUP = 1, GGML_OP_ADD = 2, GGML_OP_ADD1 = 3,
    GGML_OP_ACC = 4, GGML_OP_SUB = 5, GGML_OP_MUL = 6, GGML_OP_DIV = 7,
    GGML_OP_SQR = 8, GGML_OP_SQRT = 9, GGML_OP_LOG = 10, GGML_OP_SIN = 11,
    GGML_OP_COS = 12, GGML_OP_SUM = 13, GGML_OP_SUM_ROWS = 14,
    GGML_OP_MEAN = 15, GGML_OP_ARGMAX = 16, GGML_OP_COUNT_EQUAL = 17,
    GGML_OP_REPEAT = 18, GGML_OP_REPEAT_BACK = 19, GGML_OP_CONCAT = 20,
    GGML_OP_SILU_BACK = 21, GGML_OP_NORM = 22, GGML_OP_RMS_NORM = 23,
    GGML_OP_RMS_NORM_BACK = 24, GGML_OP_GROUP_NORM = 25, GGML_OP_L2_NORM = 26,
    GGML_OP_MUL_MAT = 27, GGML_OP_MUL_MAT_ID = 28, GGML_OP_OUT_PROD = 29,
    GGML_OP_SCALE = 30, GGML_OP_SET = 31, GGML_OP_CPY = 32, GGML_OP_CONT = 33,
    GGML_OP_RESHAPE = 34, GGML_OP_VIEW = 35, GGML_OP_PERMUTE = 36,
    GGML_OP_TRANSPOSE = 37, GGML_OP_GET_ROWS = 38, GGML_OP_GET_ROWS_BACK = 39,
    GGML_OP_DIAG = 40, GGML_OP_DIAG_MASK_INF = 41, GGML_OP_DIAG_MASK_ZERO = 42,
    GGML_OP_SOFT_MAX = 43, GGML_OP_SOFT_MAX_BACK = 44, GGML_OP_ROPE = 45,
    GGML_OP_ROPE_BACK = 46, GGML_OP_CLAMP = 47, GGML_OP_CONV_TRANSPOSE_1D = 48,
    GGML_OP_IM2COL = 49, GGML_OP_IM2COL_BACK = 50, GGML_OP_CONV_2D_DW = 51,
    GGML_OP_CONV_TRANSPOSE_2D = 52, GGML_OP_POOL_1D = 53, GGML_OP_POOL_2D = 54,
    GGML_OP_POOL_2D_BACK = 55, GGML_OP_UPSCALE = 56, GGML_OP_PAD = 57,
    GGML_OP_PAD_REFLECT_1D = 58, GGML_OP_ARANGE = 59,
    GGML_OP_TIMESTEP_EMBEDDING = 60, GGML_OP_ARGSORT = 61,
    GGML_OP_LEAKY_RELU = 62, GGML_OP_FLASH_ATTN_EXT = 63,
    GGML_OP_FLASH_ATTN_BACK = 64, GGML_OP_SSM_CONV = 65, GGML_OP_SSM_SCAN = 66,
    GGML_OP_WIN_PART = 67, GGML_OP_WIN_UNPART = 68, GGML_OP_GET_REL_POS = 69,
    GGML_OP_ADD_REL_POS = 70, GGML_OP_RWKV_WKV6 = 71,
    GGML_OP_GATED_LINEAR_ATTN = 72, GGML_OP_RWKV_WKV7 = 73, GGML_OP_UNARY = 74,
    GGML_OP_MAP_CUSTOM1 = 75, GGML_OP_MAP_CUSTOM2 = 76,
    GGML_OP_MAP_CUSTOM3 = 77, GGML_OP_CUSTOM = 78,
    GGML_OP_CROSS_ENTROPY_LOSS = 79, GGML_OP_CROSS_ENTROPY_LOSS_BACK = 80,
    GGML_OP_OPT_STEP_ADAMW = 81, GGML_OP_COUNT = 82
type
  EnumGgmlUnaryOp* {.size: sizeof(cuint).} = enum
    GGML_UNARY_OP_ABS = 0, GGML_UNARY_OP_SGN = 1, GGML_UNARY_OP_NEG = 2,
    GGML_UNARY_OP_STEP = 3, GGML_UNARY_OP_TANH = 4, GGML_UNARY_OP_ELU = 5,
    GGML_UNARY_OP_RELU = 6, GGML_UNARY_OP_SIGMOID = 7, GGML_UNARY_OP_GELU = 8,
    GGML_UNARY_OP_GELU_QUICK = 9, GGML_UNARY_OP_SILU = 10,
    GGML_UNARY_OP_HARDSWISH = 11, GGML_UNARY_OP_HARDSIGMOID = 12,
    GGML_UNARY_OP_EXP = 13, GGML_UNARY_OP_COUNT = 14
type
  EnumGgmlObjectType* {.size: sizeof(cuint).} = enum
    GGML_OBJECT_TYPE_TENSOR = 0, GGML_OBJECT_TYPE_GRAPH = 1,
    GGML_OBJECT_TYPE_WORK_BUFFER = 2
type
  EnumGgmlLogLevel* {.size: sizeof(cuint).} = enum
    GGML_LOG_LEVEL_NONE = 0, GGML_LOG_LEVEL_DEBUG = 1, GGML_LOG_LEVEL_INFO = 2,
    GGML_LOG_LEVEL_WARN = 3, GGML_LOG_LEVEL_ERROR = 4, GGML_LOG_LEVEL_CONT = 5
type
  EnumGgmlTensorFlag* {.size: sizeof(cuint).} = enum
    GGML_TENSOR_FLAG_INPUT = 1, GGML_TENSOR_FLAG_OUTPUT = 2,
    GGML_TENSOR_FLAG_PARAM = 4, GGML_TENSOR_FLAG_LOSS = 8
type
  EnumGgmlOpPool* {.size: sizeof(cuint).} = enum
    GGML_OP_POOL_MAX = 0, GGML_OP_POOL_AVG = 1, GGML_OP_POOL_COUNT = 2
type
  EnumGgmlScaleMode* {.size: sizeof(cuint).} = enum
    GGML_SCALE_MODE_NEAREST = 0, GGML_SCALE_MODE_BILINEAR = 1
type
  EnumGgmlSortOrder* {.size: sizeof(cuint).} = enum
    GGML_SORT_ORDER_ASC = 0, GGML_SORT_ORDER_DESC = 1
type
  EnumGgmlSchedPriority* {.size: sizeof(cuint).} = enum
    GGML_SCHED_PRIO_NORMAL = 0, GGML_SCHED_PRIO_MEDIUM = 1,
    GGML_SCHED_PRIO_HIGH = 2, GGML_SCHED_PRIO_REALTIME = 3
type
  EnumGgmlBackendBufferUsage* {.size: sizeof(cuint).} = enum
    GGML_BACKEND_BUFFER_USAGE_ANY = 0, GGML_BACKEND_BUFFER_USAGE_WEIGHTS = 1,
    GGML_BACKEND_BUFFER_USAGE_COMPUTE = 2
type
  EnumGgmlBackendDevType* {.size: sizeof(cuint).} = enum
    GGML_BACKEND_DEVICE_TYPE_CPU = 0, GGML_BACKEND_DEVICE_TYPE_GPU = 1,
    GGML_BACKEND_DEVICE_TYPE_ACCEL = 2
type
  EnumGgmlNumaStrategy* {.size: sizeof(cuint).} = enum
    GGML_NUMA_STRATEGY_DISABLED = 0, GGML_NUMA_STRATEGY_DISTRIBUTE = 1,
    GGML_NUMA_STRATEGY_ISOLATE = 2, GGML_NUMA_STRATEGY_NUMACTL = 3,
    GGML_NUMA_STRATEGY_MIRROR = 4, GGML_NUMA_STRATEGY_COUNT = 5
type
  EnumGgmlOptLossType* {.size: sizeof(cuint).} = enum
    GGML_OPT_LOSS_TYPE_MEAN = 0, GGML_OPT_LOSS_TYPE_SUM = 1,
    GGML_OPT_LOSS_TYPE_CROSS_ENTROPY = 2,
    GGML_OPT_LOSS_TYPE_MEAN_SQUARED_ERROR = 3
type
  EnumGgmlOptBuildType* {.size: sizeof(cuint).} = enum
    GGML_OPT_BUILD_TYPE_FORWARD = 10, GGML_OPT_BUILD_TYPE_GRAD = 20,
    GGML_OPT_BUILD_TYPE_OPT = 30
type
  EnumLlamaVocabType* {.size: sizeof(cuint).} = enum
    LLAMA_VOCAB_TYPE_NONE = 0, LLAMA_VOCAB_TYPE_SPM = 1,
    LLAMA_VOCAB_TYPE_BPE = 2, LLAMA_VOCAB_TYPE_WPM = 3,
    LLAMA_VOCAB_TYPE_UGM = 4, LLAMA_VOCAB_TYPE_RWKV = 5
type
  EnumLlamaVocabPreType* {.size: sizeof(cuint).} = enum
    LLAMA_VOCAB_PRE_TYPE_DEFAULT = 0, LLAMA_VOCAB_PRE_TYPE_LLAMA3 = 1,
    LLAMA_VOCAB_PRE_TYPE_DEEPSEEK_LLM = 2,
    LLAMA_VOCAB_PRE_TYPE_DEEPSEEK_CODER = 3, LLAMA_VOCAB_PRE_TYPE_FALCON = 4,
    LLAMA_VOCAB_PRE_TYPE_MPT = 5, LLAMA_VOCAB_PRE_TYPE_STARCODER = 6,
    LLAMA_VOCAB_PRE_TYPE_GPT2 = 7, LLAMA_VOCAB_PRE_TYPE_REFACT = 8,
    LLAMA_VOCAB_PRE_TYPE_COMMAND_R = 9, LLAMA_VOCAB_PRE_TYPE_STABLELM2 = 10,
    LLAMA_VOCAB_PRE_TYPE_QWEN2 = 11, LLAMA_VOCAB_PRE_TYPE_OLMO = 12,
    LLAMA_VOCAB_PRE_TYPE_DBRX = 13, LLAMA_VOCAB_PRE_TYPE_SMAUG = 14,
    LLAMA_VOCAB_PRE_TYPE_PORO = 15, LLAMA_VOCAB_PRE_TYPE_CHATGLM3 = 16,
    LLAMA_VOCAB_PRE_TYPE_CHATGLM4 = 17, LLAMA_VOCAB_PRE_TYPE_VIKING = 18,
    LLAMA_VOCAB_PRE_TYPE_JAIS = 19, LLAMA_VOCAB_PRE_TYPE_TEKKEN = 20,
    LLAMA_VOCAB_PRE_TYPE_SMOLLM = 21, LLAMA_VOCAB_PRE_TYPE_CODESHELL = 22,
    LLAMA_VOCAB_PRE_TYPE_BLOOM = 23, LLAMA_VOCAB_PRE_TYPE_GPT3_FINNISH = 24,
    LLAMA_VOCAB_PRE_TYPE_EXAONE = 25, LLAMA_VOCAB_PRE_TYPE_CHAMELEON = 26,
    LLAMA_VOCAB_PRE_TYPE_MINERVA = 27, LLAMA_VOCAB_PRE_TYPE_DEEPSEEK3_LLM = 28,
    LLAMA_VOCAB_PRE_TYPE_GPT4O = 29, LLAMA_VOCAB_PRE_TYPE_SUPERBPE = 30,
    LLAMA_VOCAB_PRE_TYPE_TRILLION = 31, LLAMA_VOCAB_PRE_TYPE_BAILINGMOE = 32,
    LLAMA_VOCAB_PRE_TYPE_LLAMA4 = 33, LLAMA_VOCAB_PRE_TYPE_PIXTRAL = 34,
    LLAMA_VOCAB_PRE_TYPE_SEED_CODER = 35
type
  EnumLlamaRopeType* {.size: sizeof(cint).} = enum
    LLAMA_ROPE_TYPE_NONE = -1, LLAMA_ROPE_TYPE_NORM = 0,
    LLAMA_ROPE_TYPE_NEOX = 2, LLAMA_ROPE_TYPE_MROPE = 8,
    LLAMA_ROPE_TYPE_VISION = 24
type
  EnumLlamaTokenType* {.size: sizeof(cuint).} = enum
    LLAMA_TOKEN_TYPE_UNDEFINED = 0, LLAMA_TOKEN_TYPE_NORMAL = 1,
    LLAMA_TOKEN_TYPE_UNKNOWN = 2, LLAMA_TOKEN_TYPE_CONTROL = 3,
    LLAMA_TOKEN_TYPE_USER_DEFINED = 4, LLAMA_TOKEN_TYPE_UNUSED = 5,
    LLAMA_TOKEN_TYPE_BYTE = 6
type
  EnumLlamaTokenAttr* {.size: sizeof(cuint).} = enum
    LLAMA_TOKEN_ATTR_UNDEFINED = 0, LLAMA_TOKEN_ATTR_UNKNOWN = 1,
    LLAMA_TOKEN_ATTR_UNUSED = 2, LLAMA_TOKEN_ATTR_NORMAL = 4,
    LLAMA_TOKEN_ATTR_CONTROL = 8, LLAMA_TOKEN_ATTR_USER_DEFINED = 16,
    LLAMA_TOKEN_ATTR_BYTE = 32, LLAMA_TOKEN_ATTR_NORMALIZED = 64,
    LLAMA_TOKEN_ATTR_LSTRIP = 128, LLAMA_TOKEN_ATTR_RSTRIP = 256,
    LLAMA_TOKEN_ATTR_SINGLE_WORD = 512
type
  EnumLlamaFtype* {.size: sizeof(cuint).} = enum
    LLAMA_FTYPE_ALL_F32 = 0, LLAMA_FTYPE_MOSTLY_F16 = 1,
    LLAMA_FTYPE_MOSTLY_Q4_0 = 2, LLAMA_FTYPE_MOSTLY_Q4_1 = 3,
    LLAMA_FTYPE_MOSTLY_Q8_0 = 7, LLAMA_FTYPE_MOSTLY_Q5_0 = 8,
    LLAMA_FTYPE_MOSTLY_Q5_1 = 9, LLAMA_FTYPE_MOSTLY_Q2_K = 10,
    LLAMA_FTYPE_MOSTLY_Q3_K_S = 11, LLAMA_FTYPE_MOSTLY_Q3_K_M = 12,
    LLAMA_FTYPE_MOSTLY_Q3_K_L = 13, LLAMA_FTYPE_MOSTLY_Q4_K_S = 14,
    LLAMA_FTYPE_MOSTLY_Q4_K_M = 15, LLAMA_FTYPE_MOSTLY_Q5_K_S = 16,
    LLAMA_FTYPE_MOSTLY_Q5_K_M = 17, LLAMA_FTYPE_MOSTLY_Q6_K = 18,
    LLAMA_FTYPE_MOSTLY_IQ2_XXS = 19, LLAMA_FTYPE_MOSTLY_IQ2_XS = 20,
    LLAMA_FTYPE_MOSTLY_Q2_K_S = 21, LLAMA_FTYPE_MOSTLY_IQ3_XS = 22,
    LLAMA_FTYPE_MOSTLY_IQ3_XXS = 23, LLAMA_FTYPE_MOSTLY_IQ1_S = 24,
    LLAMA_FTYPE_MOSTLY_IQ4_NL = 25, LLAMA_FTYPE_MOSTLY_IQ3_S = 26,
    LLAMA_FTYPE_MOSTLY_IQ3_M = 27, LLAMA_FTYPE_MOSTLY_IQ2_S = 28,
    LLAMA_FTYPE_MOSTLY_IQ2_M = 29, LLAMA_FTYPE_MOSTLY_IQ4_XS = 30,
    LLAMA_FTYPE_MOSTLY_IQ1_M = 31, LLAMA_FTYPE_MOSTLY_BF16 = 32,
    LLAMA_FTYPE_MOSTLY_TQ1_0 = 36, LLAMA_FTYPE_MOSTLY_TQ2_0 = 37,
    LLAMA_FTYPE_GUESSED = 1024
type
  EnumLlamaRopeScalingType* {.size: sizeof(cint).} = enum
    LLAMA_ROPE_SCALING_TYPE_UNSPECIFIED = -1, LLAMA_ROPE_SCALING_TYPE_NONE = 0,
    LLAMA_ROPE_SCALING_TYPE_LINEAR = 1, LLAMA_ROPE_SCALING_TYPE_YARN = 2,
    LLAMA_ROPE_SCALING_TYPE_LONGROPE = 3
const
  LLAMA_ROPE_SCALING_TYPE_MAX_VALUE* = EnumLlamaRopeScalingType.LLAMA_ROPE_SCALING_TYPE_LONGROPE
type
  EnumLlamaPoolingType* {.size: sizeof(cint).} = enum
    LLAMA_POOLING_TYPE_UNSPECIFIED = -1, LLAMA_POOLING_TYPE_NONE = 0,
    LLAMA_POOLING_TYPE_MEAN = 1, LLAMA_POOLING_TYPE_CLS = 2,
    LLAMA_POOLING_TYPE_LAST = 3, LLAMA_POOLING_TYPE_RANK = 4
type
  EnumLlamaAttentionType* {.size: sizeof(cint).} = enum
    LLAMA_ATTENTION_TYPE_UNSPECIFIED = -1, LLAMA_ATTENTION_TYPE_CAUSAL = 0,
    LLAMA_ATTENTION_TYPE_NON_CAUSAL = 1
type
  EnumLlamaSplitMode* {.size: sizeof(cuint).} = enum
    LLAMA_SPLIT_MODE_NONE = 0, LLAMA_SPLIT_MODE_LAYER = 1,
    LLAMA_SPLIT_MODE_ROW = 2
type
  EnumLlamaModelKvOverrideType* {.size: sizeof(cuint).} = enum
    LLAMA_KV_OVERRIDE_TYPE_INT = 0, LLAMA_KV_OVERRIDE_TYPE_FLOAT = 1,
    LLAMA_KV_OVERRIDE_TYPE_BOOL = 2, LLAMA_KV_OVERRIDE_TYPE_STR = 3
type
  Extern* = object
type
  StructGgmlBackend* = object
type
  StructLlamaContext* = object
type
  StructGgmlOptDataset* = object
type
  StructGgmlBackendEvent* = object
type
  StructGgmlOptResult* = object
type
  StructLlamaVocab* = object
type
  StructGgmlObject* = object
type
  StructSFILEX* = object
type
  StructGgmlBackendBufferType* = object
type
  StructGgmlBackendDevice* = object
type
  StructGgmlContext* = object
type
  StructGgmlBackendSched* = object
type
  StructGgmlCgraph* = object
type
  Restrict* = object
type
  StructGgmlOptContext* = object
type
  StructGgmlBackendReg* = object
type
  Noreturn* = object
type
  StructGgmlBackendBuffer* = object
type
  StructLlamaModel* = object
type
  StructLlamaAdapterLora* = object
type
  StructLlamaKvCache* = object
type
  StructGgmlThreadpool* = object
type
  StructGgmlGallocr* = object
type
  GgmlFp16T* = uint16        ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:332:22
  StructGgmlBf16T* {.pure, inheritable, bycopy.} = object
    bits*: uint16            ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:339:13
  GgmlBf16T* = StructGgmlBf16T ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:339:39
  StructGgmlInitParams* {.pure, inheritable, bycopy.} = object
    mem_size*: csize_t       ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:566:12
    mem_buffer*: pointer
    no_alloc*: bool
  StructGgmlTensor* {.pure, inheritable, bycopy.} = object
    type_field*: EnumGgmlType ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:574:12
    buffer*: ptr StructGgmlBackendBuffer
    ne*: array[4'i64, int64]
    nb*: array[4'i64, csize_t]
    op*: EnumGgmlOp
    op_params*: array[16'i64, int32]
    flags*: int32
    src*: array[10'i64, ptr StructGgmlTensor]
    view_src*: ptr StructGgmlTensor
    view_offs*: csize_t
    data*: pointer
    name*: array[64'i64, cschar]
    extra*: pointer
    padding*: array[8'i64, cschar]
  GgmlAbortCallback* = proc (a0: pointer): bool {.cdecl.} ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:613:20
  GgmlGuid* = array[16'i64, uint8] ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:621:21
  GgmlGuidT* = ptr GgmlGuid  ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:622:25
  FILE* = StructSFILE        ## Generated based on /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/_stdio.h:159:3
  GgmlCustom1OpT* = proc (a0: ptr StructGgmlTensor; a1: ptr StructGgmlTensor;
                          a2: cint; a3: cint; a4: pointer): void {.cdecl.} ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:1943:20
  GgmlCustom2OpT* = proc (a0: ptr StructGgmlTensor; a1: ptr StructGgmlTensor;
                          a2: ptr StructGgmlTensor; a3: cint; a4: cint;
                          a5: pointer): void {.cdecl.} ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:1944:20
  GgmlCustom3OpT* = proc (a0: ptr StructGgmlTensor; a1: ptr StructGgmlTensor;
                          a2: ptr StructGgmlTensor; a3: ptr StructGgmlTensor;
                          a4: cint; a5: cint; a6: pointer): void {.cdecl.} ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:1945:20
  GgmlCustomOpT* = proc (a0: ptr StructGgmlTensor; a1: cint; a2: cint;
                         a3: pointer): void {.cdecl.} ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:1998:20
  GgmlLogCallback* = proc (a0: EnumGgmlLogLevel; a1: cstring; a2: pointer): void {.
      cdecl.}                ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:2088:20
  GgmlToFloatT* = proc (a0: pointer; a1: ptr cfloat; a2: int64): void {.cdecl.} ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:2143:20
  GgmlFromFloatT* = proc (a0: ptr cfloat; a1: pointer; a2: int64): void {.cdecl.} ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:2144:20
  StructGgmlTypeTraits* {.pure, inheritable, bycopy.} = object
    type_name*: cstring      ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:2146:12
    blck_size*: int64
    blck_size_interleave*: int64
    type_size*: csize_t
    is_quantized*: bool
    to_float*: GgmlToFloatT
    from_float_ref*: GgmlFromFloatT
  StructGgmlThreadpoolParams* {.pure, inheritable, bycopy.} = object
    cpumask*: array[512'i64, bool] ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:2172:12
    n_threads*: cint
    prio*: EnumGgmlSchedPriority
    poll*: uint32
    strict_cpu*: bool
    paused*: bool
  GgmlThreadpoolT* = ptr StructGgmlThreadpool ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:2183:38
  GgmlBackendBufferTypeT* = ptr StructGgmlBackendBufferType ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:24:47
  GgmlBackendBufferT* = ptr StructGgmlBackendBuffer ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:25:42
  GgmlBackendT* = ptr StructGgmlBackend ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:27:35
  StructGgmlTallocr* {.pure, inheritable, bycopy.} = object
    buffer*: GgmlBackendBufferT ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-alloc.h:14:8
    base*: pointer
    alignment*: csize_t
    offset*: csize_t
  GgmlGallocrT* = ptr StructGgmlGallocr ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-alloc.h:46:31
  GgmlBackendEventT* = ptr StructGgmlBackendEvent ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:26:41
  GgmlBackendGraphPlanT* = pointer ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:28:20
  GgmlBackendRegT* = ptr StructGgmlBackendReg ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:29:39
  GgmlBackendDevT* = ptr StructGgmlBackendDevice ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:30:42
  StructGgmlBackendDevCaps* {.pure, inheritable, bycopy.} = object
    async*: bool             ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:140:12
    host_buffer*: bool
    buffer_from_host_ptr*: bool
    events*: bool
  StructGgmlBackendDevProps* {.pure, inheritable, bycopy.} = object
    name*: cstring           ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:152:12
    description*: cstring
    memory_free*: csize_t
    memory_total*: csize_t
    type_field*: EnumGgmlBackendDevType
    caps*: StructGgmlBackendDevCaps
  GgmlBackendSplitBufferTypeT* = proc (a0: cint; a1: ptr cfloat): GgmlBackendBufferTypeT {.
      cdecl.}                ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:188:44
  GgmlBackendSetNThreadsT* = proc (a0: GgmlBackendT; a1: cint): void {.cdecl.} ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:190:44
  GgmlBackendDevGetExtraBuftsT* = proc (a0: GgmlBackendDevT): ptr GgmlBackendBufferTypeT {.
      cdecl.}                ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:192:44
  GgmlBackendSetAbortCallbackT* = proc (a0: GgmlBackendT; a1: GgmlAbortCallback;
                                        a2: pointer): void {.cdecl.} ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:194:44
  StructGgmlBackendFeature* {.pure, inheritable, bycopy.} = object
    name*: cstring           ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:196:12
    value*: cstring
  GgmlBackendGetFeaturesT* = proc (a0: GgmlBackendRegT): ptr StructGgmlBackendFeature {.
      cdecl.}                ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:200:45
  GgmlBackendSchedT* = ptr StructGgmlBackendSched ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:280:41
  GgmlBackendSchedEvalCallback* = proc (a0: ptr StructGgmlTensor; a1: bool;
                                        a2: pointer): bool {.cdecl.} ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:289:20
  StructGgmlBackendGraphCopy* {.pure, inheritable, bycopy.} = object
    buffer*: GgmlBackendBufferT ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:328:12
    ctx_allocated*: ptr StructGgmlContext
    ctx_unallocated*: ptr StructGgmlContext
    graph*: ptr StructGgmlCgraph
  GgmlBackendEvalCallback* = proc (a0: cint; a1: ptr StructGgmlTensor;
                                   a2: ptr StructGgmlTensor; a3: pointer): bool {.
      cdecl.}                ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-backend.h:339:20
  StructGgmlCplan* {.pure, inheritable, bycopy.} = object
    work_size*: csize_t      ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-cpu.h:12:12
    work_data*: ptr uint8
    n_threads*: cint
    threadpool*: ptr StructGgmlThreadpool
    abort_callback*: GgmlAbortCallback
    abort_callback_data*: pointer
  GgmlVecDotT* = proc (a0: cint; a1: ptr cfloat; a2: csize_t; a3: pointer;
                       a4: csize_t; a5: pointer; a6: csize_t; a7: cint): void {.
      cdecl.}                ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-cpu.h:109:20
  StructGgmlTypeTraitsCpu* {.pure, inheritable, bycopy.} = object
    from_float*: GgmlFromFloatT ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-cpu.h:112:12
    vec_dot*: GgmlVecDotT
    vec_dot_type*: EnumGgmlType
    nrows*: int64
  GgmlOptDatasetT* = ptr StructGgmlOptDataset ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-opt.h:22:39
  GgmlOptContextT* = ptr StructGgmlOptContext ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-opt.h:23:39
  GgmlOptResultT* = ptr StructGgmlOptResult ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-opt.h:24:39
  StructGgmlOptOptimizerParams_adamw_t* {.pure, inheritable, bycopy.} = object
    alpha*: cfloat
    beta1*: cfloat
    beta2*: cfloat
    eps*: cfloat
    wd*: cfloat
  StructGgmlOptOptimizerParams* {.pure, inheritable, bycopy.} = object
    adamw*: StructGgmlOptOptimizerParams_adamw_t ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-opt.h:78:12
  GgmlOptGetOptimizerParams* = proc (a0: pointer): StructGgmlOptOptimizerParams {.
      cdecl.}                ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-opt.h:91:48
  StructGgmlOptParams* {.pure, inheritable, bycopy.} = object
    backend_sched*: GgmlBackendSchedT ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-opt.h:101:12
    ctx_compute*: ptr StructGgmlContext
    inputs*: ptr StructGgmlTensor
    outputs*: ptr StructGgmlTensor
    loss_type*: EnumGgmlOptLossType
    build_type*: EnumGgmlOptBuildType
    opt_period*: int32
    get_opt_pars*: GgmlOptGetOptimizerParams
    get_opt_pars_ud*: pointer
  GgmlOptEpochCallback* = proc (a0: bool; a1: GgmlOptContextT;
                                a2: GgmlOptDatasetT; a3: GgmlOptResultT;
                                a4: int64; a5: int64; a6: int64): void {.cdecl.} ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml-opt.h:190:20
  LlamaPos* = int32          ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:66:21
  LlamaToken* = int32        ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:67:21
  LlamaSeqId* = int32        ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:68:21
  StructLlamaTokenData* {.pure, inheritable, bycopy.} = object
    id*: LlamaToken          ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:226:20
    logit*: cfloat
    p*: cfloat
  LlamaTokenData* = StructLlamaTokenData ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:230:7
  StructLlamaTokenDataArray* {.pure, inheritable, bycopy.} = object
    data*: ptr LlamaTokenData ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:232:20
    size*: csize_t
    selected*: int64
    sorted*: bool
  LlamaTokenDataArray* = StructLlamaTokenDataArray ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:239:7
  LlamaProgressCallback* = proc (a0: cfloat; a1: pointer): bool {.cdecl.} ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:241:20
  StructLlamaBatch* {.pure, inheritable, bycopy.} = object
    n_tokens*: int32         ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:256:20
    token*: ptr UncheckedArray[LlamaToken]
    embd*: ptr cfloat
    pos*: ptr UncheckedArray[LlamaPos]
    n_seq_id*: ptr int32
    seq_id*: ptr ptr LlamaSeqId
    logits*: cstring
  LlamaBatch* = StructLlamaBatch ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:265:7
  StructLlamaModelKvOverride_anon0_t* {.union, bycopy.} = object
    val_i64*: int64
    val_f64*: cdouble
    val_bool*: bool
    val_str*: array[128'i64, cschar]
  StructLlamaModelKvOverride* {.pure, inheritable, bycopy.} = object
    tag*: EnumLlamaModelKvOverrideType ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:274:12
    key*: array[128'i64, cschar]
    anon0*: StructLlamaModelKvOverride_anon0_t
  StructLlamaModelTensorBuftOverride* {.pure, inheritable, bycopy.} = object
    pattern*: cstring        ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:287:12
    buft*: GgmlBackendBufferTypeT
  StructLlamaModelParams* {.pure, inheritable, bycopy.} = object
    devices*: ptr GgmlBackendDevT ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:292:12
    tensor_buft_overrides*: ptr StructLlamaModelTensorBuftOverride
    n_gpu_layers*: int32
    split_mode*: EnumLlamaSplitMode
    main_gpu*: int32
    tensor_split*: ptr cfloat
    progress_callback*: LlamaProgressCallback
    progress_callback_user_data*: pointer
    kv_overrides*: ptr StructLlamaModelKvOverride
    vocab_only*: bool
    use_mmap*: bool
    use_mlock*: bool
    check_tensors*: bool
  StructLlamaContextParams* {.pure, inheritable, bycopy.} = object
    n_ctx*: uint32           ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:328:12
    n_batch*: uint32
    n_ubatch*: uint32
    n_seq_max*: uint32
    n_threads*: int32
    n_threads_batch*: int32
    rope_scaling_type*: EnumLlamaRopeScalingType
    pooling_type*: EnumLlamaPoolingType
    attention_type*: EnumLlamaAttentionType
    rope_freq_base*: cfloat
    rope_freq_scale*: cfloat
    yarn_ext_factor*: cfloat
    yarn_attn_factor*: cfloat
    yarn_beta_fast*: cfloat
    yarn_beta_slow*: cfloat
    yarn_orig_ctx*: uint32
    defrag_thold*: cfloat
    cb_eval*: GgmlBackendSchedEvalCallback
    cb_eval_user_data*: pointer
    type_k*: EnumGgmlType
    type_v*: EnumGgmlType
    abort_callback*: GgmlAbortCallback
    abort_callback_data*: pointer
    embeddings*: bool
    offload_kqv*: bool
    flash_attn*: bool
    no_perf*: bool
    op_offload*: bool
  StructLlamaModelQuantizeParams* {.pure, inheritable, bycopy.} = object
    nthread*: int32          ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:371:20
    ftype*: EnumLlamaFtype
    output_tensor_type*: EnumGgmlType
    token_embedding_type*: EnumGgmlType
    allow_requantize*: bool
    quantize_output_tensor*: bool
    only_copy*: bool
    pure*: bool
    keep_split*: bool
    imatrix*: pointer
    kv_overrides*: pointer
    tensor_types*: pointer
  LlamaModelQuantizeParams* = StructLlamaModelQuantizeParams ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:384:7
  StructLlamaLogitBias* {.pure, inheritable, bycopy.} = object
    token*: LlamaToken       ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:386:20
    bias*: cfloat
  LlamaLogitBias* = StructLlamaLogitBias ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:389:7
  StructLlamaSamplerChainParams* {.pure, inheritable, bycopy.} = object
    no_perf*: bool           ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:391:20
  LlamaSamplerChainParams* = StructLlamaSamplerChainParams ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:393:7
  StructLlamaChatMessage* {.pure, inheritable, bycopy.} = object
    role*: cstring           ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:396:20
    content*: cstring
  LlamaChatMessage* = StructLlamaChatMessage ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:399:7
  StructLlamaKvCacheViewCell* {.pure, inheritable, bycopy.} = object
    pos*: LlamaPos           ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:613:12
  StructLlamaKvCacheView* {.pure, inheritable, bycopy.} = object
    n_cells*: int32          ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:620:12
    n_seq_max*: int32
    token_count*: int32
    used_cells*: int32
    max_contiguous*: int32
    max_contiguous_idx*: int32
    cells*: ptr StructLlamaKvCacheViewCell
    cells_sequences*: ptr LlamaSeqId
  LlamaSamplerContextT* = pointer ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:1191:20
  StructLlamaSamplerI* {.pure, inheritable, bycopy.} = object
    name*: proc (a0: ptr StructLlamaSampler): cstring {.cdecl.} ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:1194:12
    accept*: proc (a0: ptr StructLlamaSampler; a1: LlamaToken): void {.cdecl.}
    apply*: proc (a0: ptr StructLlamaSampler; a1: ptr LlamaTokenDataArray): void {.
        cdecl.}
    reset*: proc (a0: ptr StructLlamaSampler): void {.cdecl.}
    clone*: proc (a0: ptr StructLlamaSampler): ptr StructLlamaSampler {.cdecl.}
    free*: proc (a0: ptr StructLlamaSampler): void {.cdecl.}
  StructLlamaSampler* {.pure, inheritable, bycopy.} = object
    iface*: ptr StructLlamaSamplerI ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:1206:12
    ctx*: LlamaSamplerContextT
  StructLlamaPerfContextData* {.pure, inheritable, bycopy.} = object
    t_start_ms*: cdouble     ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:1416:12
    t_load_ms*: cdouble
    t_p_eval_ms*: cdouble
    t_eval_ms*: cdouble
    n_p_eval*: int32
    n_eval*: int32
  StructLlamaPerfSamplerData* {.pure, inheritable, bycopy.} = object
    t_sample_ms*: cdouble    ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:1426:12
    n_sample*: int32
  LlamaOptParamFilter* = proc (a0: ptr StructGgmlTensor; a1: pointer): bool {.
      cdecl.}                ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:1446:20
  StructLlamaOptParams* {.pure, inheritable, bycopy.} = object
    n_ctx_train*: uint32     ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:1451:12
    param_filter*: LlamaOptParamFilter
    param_filter_ud*: pointer
    get_opt_pars*: GgmlOptGetOptimizerParams
    get_opt_pars_ud*: pointer
  StructSFILE* {.pure, inheritable, bycopy.} = object
    internal_p*: ptr uint8   ## Generated based on /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/_stdio.h:128:16
    internal_r*: cint
    internal_w*: cint
    internal_flags*: cshort
    internal_file*: cshort
    internal_bf*: StructSbuf
    internal_lbfsize*: cint
    internal_cookie*: pointer
    internal_close*: proc (a0: pointer): cint {.cdecl.}
    internal_read*: proc (a0: pointer; a1: cstring; a2: cint): cint {.cdecl.}
    internal_seek*: proc (a0: pointer; a1: FposT; a2: cint): FposT {.cdecl.}
    internal_write*: proc (a0: pointer; a1: cstring; a2: cint): cint {.cdecl.}
    internal_ub*: StructSbuf
    internal_extra*: ptr StructSFILEX
    internal_ur*: cint
    internal_ubuf*: array[3'i64, uint8]
    internal_nbuf*: array[1'i64, uint8]
    internal_lb*: StructSbuf
    internal_blksize*: cint
    internal_offset*: FposT
  StructSbuf* {.pure, inheritable, bycopy.} = object
    internal_base*: ptr uint8 ## Generated based on /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/_stdio.h:94:8
    internal_size*: cint
  FposT* = DarwinOffT        ## Generated based on /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/_stdio.h:83:25
  DarwinOffT* = Int64T       ## Generated based on /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/sys/_types.h:83:25
  Int64T* = clonglong        ## Generated based on /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/arm/_types.h:37:33
when 1734831468 is static:
  const
    GGML_FILE_MAGIC* = 1734831468 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:212:9
else:
  let GGML_FILE_MAGIC* = 1734831468 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:212:9
when 2 is static:
  const
    GGML_FILE_VERSION* = 2   ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:213:9
else:
  let GGML_FILE_VERSION* = 2 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:213:9
when 2 is static:
  const
    GGML_QNT_VERSION* = 2    ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:215:9
else:
  let GGML_QNT_VERSION* = 2  ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:215:9
when 1000 is static:
  const
    GGML_QNT_VERSION_FACTOR* = 1000 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:216:9
else:
  let GGML_QNT_VERSION_FACTOR* = 1000 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:216:9
when 4 is static:
  const
    GGML_MAX_DIMS* = 4       ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:218:9
else:
  let GGML_MAX_DIMS* = 4     ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:218:9
when 2048 is static:
  const
    GGML_MAX_PARAMS* = 2048  ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:219:9
else:
  let GGML_MAX_PARAMS* = 2048 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:219:9
when 10 is static:
  const
    GGML_MAX_SRC* = 10       ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:220:9
else:
  let GGML_MAX_SRC* = 10     ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:220:9
when 512 is static:
  const
    GGML_MAX_N_THREADS* = 512 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:221:9
else:
  let GGML_MAX_N_THREADS* = 512 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:221:9
when 64 is static:
  const
    GGML_MAX_OP_PARAMS* = 64 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:222:9
else:
  let GGML_MAX_OP_PARAMS* = 64 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:222:9
when 64 is static:
  const
    GGML_MAX_NAME* = 64      ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:225:12
else:
  let GGML_MAX_NAME* = 64    ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:225:12
when 4 is static:
  const
    GGML_DEFAULT_N_THREADS* = 4 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:228:9
else:
  let GGML_DEFAULT_N_THREADS* = 4 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:228:9
when 2048 is static:
  const
    GGML_DEFAULT_GRAPH_SIZE* = 2048 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:229:9
else:
  let GGML_DEFAULT_GRAPH_SIZE* = 2048 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:229:9
when 16 is static:
  const
    GGML_MEM_ALIGN* = 16     ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:234:13
else:
  let GGML_MEM_ALIGN* = 16   ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:234:13
when 0 is static:
  const
    GGML_EXIT_SUCCESS* = 0   ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:237:9
else:
  let GGML_EXIT_SUCCESS* = 0 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:237:9
when 1 is static:
  const
    GGML_EXIT_ABORTED* = 1   ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:238:9
else:
  let GGML_EXIT_ABORTED* = 1 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:238:9
when 2 is static:
  const
    GGML_ROPE_TYPE_NEOX* = 2 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:240:9
else:
  let GGML_ROPE_TYPE_NEOX* = 2 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:240:9
when 8 is static:
  const
    GGML_ROPE_TYPE_MROPE* = 8 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:241:9
else:
  let GGML_ROPE_TYPE_MROPE* = 8 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:241:9
when 24 is static:
  const
    GGML_ROPE_TYPE_VISION* = 24 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:242:9
else:
  let GGML_ROPE_TYPE_VISION* = 24 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:242:9
when 64 is static:
  const
    GGML_KQ_MASK_PAD* = 64   ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:1816:9
else:
  let GGML_KQ_MASK_PAD* = 64 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:1816:9
when -1 is static:
  const
    GGML_N_TASKS_MAX* = -1   ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:1947:9
else:
  let GGML_N_TASKS_MAX* = -1 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/ggml/include/ggml.h:1947:9
when 4294967295 is static:
  const
    LLAMA_DEFAULT_SEED* = 4294967295'i64 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:36:9
else:
  let LLAMA_DEFAULT_SEED* = 4294967295'i64 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:36:9
when -1 is static:
  const
    LLAMA_TOKEN_NULL* = -1   ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:38:9
else:
  let LLAMA_TOKEN_NULL* = -1 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:38:9
when cast[cuint](1734831201'i64) is static:
  const
    LLAMA_FILE_MAGIC_GGLA* = cast[cuint](1734831201'i64) ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:40:9
else:
  let LLAMA_FILE_MAGIC_GGLA* = cast[cuint](1734831201'i64) ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:40:9
when cast[cuint](1734833006'i64) is static:
  const
    LLAMA_FILE_MAGIC_GGSN* = cast[cuint](1734833006'i64) ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:41:9
else:
  let LLAMA_FILE_MAGIC_GGSN* = cast[cuint](1734833006'i64) ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:41:9
when cast[cuint](1734833009'i64) is static:
  const
    LLAMA_FILE_MAGIC_GGSQ* = cast[cuint](1734833009'i64) ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:42:9
else:
  let LLAMA_FILE_MAGIC_GGSQ* = cast[cuint](1734833009'i64) ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:42:9
when LLAMA_FILE_MAGIC_GGSN is typedesc:
  type
    LLAMA_SESSION_MAGIC* = LLAMA_FILE_MAGIC_GGSN ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:44:9
else:
  when LLAMA_FILE_MAGIC_GGSN is static:
    const
      LLAMA_SESSION_MAGIC* = LLAMA_FILE_MAGIC_GGSN ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:44:9
  else:
    let LLAMA_SESSION_MAGIC* = LLAMA_FILE_MAGIC_GGSN ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:44:9
when 9 is static:
  const
    LLAMA_SESSION_VERSION* = 9 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:45:9
else:
  let LLAMA_SESSION_VERSION* = 9 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:45:9
when LLAMA_FILE_MAGIC_GGSQ is typedesc:
  type
    LLAMA_STATE_SEQ_MAGIC* = LLAMA_FILE_MAGIC_GGSQ ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:47:9
else:
  when LLAMA_FILE_MAGIC_GGSQ is static:
    const
      LLAMA_STATE_SEQ_MAGIC* = LLAMA_FILE_MAGIC_GGSQ ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:47:9
  else:
    let LLAMA_STATE_SEQ_MAGIC* = LLAMA_FILE_MAGIC_GGSQ ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:47:9
when 2 is static:
  const
    LLAMA_STATE_SEQ_VERSION* = 2 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:48:9
else:
  let LLAMA_STATE_SEQ_VERSION* = 2 ## Generated based on /Users/scott/src/github.com/dsrw/enu/vendor/llama.cpp/include/llama.h:48:9
proc ggml_abort*(file: cstring; line: cint; fmt: cstring): void {.cdecl,
    varargs, importc: "ggml_abort".}
proc ggml_status_to_string*(status: EnumGgmlStatus): cstring {.cdecl,
    importc: "ggml_status_to_string".}
proc ggml_fp16_to_fp32*(a0: GgmlFp16T): cfloat {.cdecl,
    importc: "ggml_fp16_to_fp32".}
proc ggml_fp32_to_fp16*(a0: cfloat): GgmlFp16T {.cdecl,
    importc: "ggml_fp32_to_fp16".}
proc ggml_fp16_to_fp32_row*(a0: ptr GgmlFp16T; a1: ptr cfloat; a2: int64): void {.
    cdecl, importc: "ggml_fp16_to_fp32_row".}
proc ggml_fp32_to_fp16_row*(a0: ptr cfloat; a1: ptr GgmlFp16T; a2: int64): void {.
    cdecl, importc: "ggml_fp32_to_fp16_row".}
proc ggml_fp32_to_bf16*(a0: cfloat): GgmlBf16T {.cdecl,
    importc: "ggml_fp32_to_bf16".}
proc ggml_bf16_to_fp32*(a0: GgmlBf16T): cfloat {.cdecl,
    importc: "ggml_bf16_to_fp32".}
proc ggml_bf16_to_fp32_row*(a0: ptr GgmlBf16T; a1: ptr cfloat; a2: int64): void {.
    cdecl, importc: "ggml_bf16_to_fp32_row".}
proc ggml_fp32_to_bf16_row_ref*(a0: ptr cfloat; a1: ptr GgmlBf16T; a2: int64): void {.
    cdecl, importc: "ggml_fp32_to_bf16_row_ref".}
proc ggml_fp32_to_bf16_row*(a0: ptr cfloat; a1: ptr GgmlBf16T; a2: int64): void {.
    cdecl, importc: "ggml_fp32_to_bf16_row".}
var GGML_TENSOR_SIZE*: csize_t
proc ggml_guid_matches*(guid_a: GgmlGuidT; guid_b: GgmlGuidT): bool {.cdecl,
    importc: "ggml_guid_matches".}
proc ggml_time_init*(): void {.cdecl, importc: "ggml_time_init".}
proc ggml_time_ms*(): int64 {.cdecl, importc: "ggml_time_ms".}
proc ggml_time_us*(): int64 {.cdecl, importc: "ggml_time_us".}
proc ggml_cycles*(): int64 {.cdecl, importc: "ggml_cycles".}
proc ggml_cycles_per_ms*(): int64 {.cdecl, importc: "ggml_cycles_per_ms".}
proc ggml_fopen*(fname: cstring; mode: cstring): ptr FILE {.cdecl,
    importc: "ggml_fopen".}
proc ggml_print_object*(obj: ptr StructGgmlObject): void {.cdecl,
    importc: "ggml_print_object".}
proc ggml_print_objects*(ctx: ptr StructGgmlContext): void {.cdecl,
    importc: "ggml_print_objects".}
proc ggml_nelements*(tensor: ptr StructGgmlTensor): int64 {.cdecl,
    importc: "ggml_nelements".}
proc ggml_nrows*(tensor: ptr StructGgmlTensor): int64 {.cdecl,
    importc: "ggml_nrows".}
proc ggml_nbytes*(tensor: ptr StructGgmlTensor): csize_t {.cdecl,
    importc: "ggml_nbytes".}
proc ggml_nbytes_pad*(tensor: ptr StructGgmlTensor): csize_t {.cdecl,
    importc: "ggml_nbytes_pad".}
proc ggml_blck_size*(type_arg: EnumGgmlType): int64 {.cdecl,
    importc: "ggml_blck_size".}
proc ggml_type_size*(type_arg: EnumGgmlType): csize_t {.cdecl,
    importc: "ggml_type_size".}
proc ggml_row_size*(type_arg: EnumGgmlType; ne: int64): csize_t {.cdecl,
    importc: "ggml_row_size".}
proc ggml_type_sizef*(type_arg: EnumGgmlType): cdouble {.cdecl,
    importc: "ggml_type_sizef".}
proc ggml_type_name*(type_arg: EnumGgmlType): cstring {.cdecl,
    importc: "ggml_type_name".}
proc ggml_op_name*(op: EnumGgmlOp): cstring {.cdecl, importc: "ggml_op_name".}
proc ggml_op_symbol*(op: EnumGgmlOp): cstring {.cdecl, importc: "ggml_op_symbol".}
proc ggml_unary_op_name*(op: EnumGgmlUnaryOp): cstring {.cdecl,
    importc: "ggml_unary_op_name".}
proc ggml_op_desc*(t: ptr StructGgmlTensor): cstring {.cdecl,
    importc: "ggml_op_desc".}
proc ggml_element_size*(tensor: ptr StructGgmlTensor): csize_t {.cdecl,
    importc: "ggml_element_size".}
proc ggml_is_quantized*(type_arg: EnumGgmlType): bool {.cdecl,
    importc: "ggml_is_quantized".}
proc ggml_ftype_to_ggml_type*(ftype: EnumGgmlFtype): EnumGgmlType {.cdecl,
    importc: "ggml_ftype_to_ggml_type".}
proc ggml_is_transposed*(tensor: ptr StructGgmlTensor): bool {.cdecl,
    importc: "ggml_is_transposed".}
proc ggml_is_permuted*(tensor: ptr StructGgmlTensor): bool {.cdecl,
    importc: "ggml_is_permuted".}
proc ggml_is_empty*(tensor: ptr StructGgmlTensor): bool {.cdecl,
    importc: "ggml_is_empty".}
proc ggml_is_scalar*(tensor: ptr StructGgmlTensor): bool {.cdecl,
    importc: "ggml_is_scalar".}
proc ggml_is_vector*(tensor: ptr StructGgmlTensor): bool {.cdecl,
    importc: "ggml_is_vector".}
proc ggml_is_matrix*(tensor: ptr StructGgmlTensor): bool {.cdecl,
    importc: "ggml_is_matrix".}
proc ggml_is_3d*(tensor: ptr StructGgmlTensor): bool {.cdecl,
    importc: "ggml_is_3d".}
proc ggml_n_dims*(tensor: ptr StructGgmlTensor): cint {.cdecl,
    importc: "ggml_n_dims".}
proc ggml_is_contiguous*(tensor: ptr StructGgmlTensor): bool {.cdecl,
    importc: "ggml_is_contiguous".}
proc ggml_is_contiguous_0*(tensor: ptr StructGgmlTensor): bool {.cdecl,
    importc: "ggml_is_contiguous_0".}
proc ggml_is_contiguous_1*(tensor: ptr StructGgmlTensor): bool {.cdecl,
    importc: "ggml_is_contiguous_1".}
proc ggml_is_contiguous_2*(tensor: ptr StructGgmlTensor): bool {.cdecl,
    importc: "ggml_is_contiguous_2".}
proc ggml_is_contiguously_allocated*(tensor: ptr StructGgmlTensor): bool {.
    cdecl, importc: "ggml_is_contiguously_allocated".}
proc ggml_is_contiguous_channels*(tensor: ptr StructGgmlTensor): bool {.cdecl,
    importc: "ggml_is_contiguous_channels".}
proc ggml_are_same_shape*(t0: ptr StructGgmlTensor; t1: ptr StructGgmlTensor): bool {.
    cdecl, importc: "ggml_are_same_shape".}
proc ggml_are_same_stride*(t0: ptr StructGgmlTensor; t1: ptr StructGgmlTensor): bool {.
    cdecl, importc: "ggml_are_same_stride".}
proc ggml_can_repeat*(t0: ptr StructGgmlTensor; t1: ptr StructGgmlTensor): bool {.
    cdecl, importc: "ggml_can_repeat".}
proc ggml_tensor_overhead*(): csize_t {.cdecl, importc: "ggml_tensor_overhead".}
proc ggml_validate_row_data*(type_arg: EnumGgmlType; data: pointer;
                             nbytes: csize_t): bool {.cdecl,
    importc: "ggml_validate_row_data".}
proc ggml_init*(params: StructGgmlInitParams): ptr StructGgmlContext {.cdecl,
    importc: "ggml_init".}
proc ggml_reset*(ctx: ptr StructGgmlContext): void {.cdecl,
    importc: "ggml_reset".}
proc ggml_free*(ctx: ptr StructGgmlContext): void {.cdecl, importc: "ggml_free".}
proc ggml_used_mem*(ctx: ptr StructGgmlContext): csize_t {.cdecl,
    importc: "ggml_used_mem".}
proc ggml_get_no_alloc*(ctx: ptr StructGgmlContext): bool {.cdecl,
    importc: "ggml_get_no_alloc".}
proc ggml_set_no_alloc*(ctx: ptr StructGgmlContext; no_alloc: bool): void {.
    cdecl, importc: "ggml_set_no_alloc".}
proc ggml_get_mem_buffer*(ctx: ptr StructGgmlContext): pointer {.cdecl,
    importc: "ggml_get_mem_buffer".}
proc ggml_get_mem_size*(ctx: ptr StructGgmlContext): csize_t {.cdecl,
    importc: "ggml_get_mem_size".}
proc ggml_get_max_tensor_size*(ctx: ptr StructGgmlContext): csize_t {.cdecl,
    importc: "ggml_get_max_tensor_size".}
proc ggml_new_tensor*(ctx: ptr StructGgmlContext; type_arg: EnumGgmlType;
                      n_dims: cint; ne: ptr int64): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_new_tensor".}
proc ggml_new_tensor_1d*(ctx: ptr StructGgmlContext; type_arg: EnumGgmlType;
                         ne0: int64): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_new_tensor_1d".}
proc ggml_new_tensor_2d*(ctx: ptr StructGgmlContext; type_arg: EnumGgmlType;
                         ne0: int64; ne1: int64): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_new_tensor_2d".}
proc ggml_new_tensor_3d*(ctx: ptr StructGgmlContext; type_arg: EnumGgmlType;
                         ne0: int64; ne1: int64; ne2: int64): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_new_tensor_3d".}
proc ggml_new_tensor_4d*(ctx: ptr StructGgmlContext; type_arg: EnumGgmlType;
                         ne0: int64; ne1: int64; ne2: int64; ne3: int64): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_new_tensor_4d".}
proc ggml_new_buffer*(ctx: ptr StructGgmlContext; nbytes: csize_t): pointer {.
    cdecl, importc: "ggml_new_buffer".}
proc ggml_dup_tensor*(ctx: ptr StructGgmlContext; src: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_dup_tensor".}
proc ggml_view_tensor*(ctx: ptr StructGgmlContext; src: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_view_tensor".}
proc ggml_get_first_tensor*(ctx: ptr StructGgmlContext): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_get_first_tensor".}
proc ggml_get_next_tensor*(ctx: ptr StructGgmlContext;
                           tensor: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_get_next_tensor".}
proc ggml_get_tensor*(ctx: ptr StructGgmlContext; name: cstring): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_get_tensor".}
proc ggml_unravel_index*(tensor: ptr StructGgmlTensor; i: int64; i0: ptr int64;
                         i1: ptr int64; i2: ptr int64; i3: ptr int64): void {.
    cdecl, importc: "ggml_unravel_index".}
proc ggml_get_unary_op*(tensor: ptr StructGgmlTensor): EnumGgmlUnaryOp {.cdecl,
    importc: "ggml_get_unary_op".}
proc ggml_get_data*(tensor: ptr StructGgmlTensor): pointer {.cdecl,
    importc: "ggml_get_data".}
proc ggml_get_data_f32*(tensor: ptr StructGgmlTensor): ptr cfloat {.cdecl,
    importc: "ggml_get_data_f32".}
proc ggml_get_name*(tensor: ptr StructGgmlTensor): cstring {.cdecl,
    importc: "ggml_get_name".}
proc ggml_set_name*(tensor: ptr StructGgmlTensor; name: cstring): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_set_name".}
proc ggml_format_name*(tensor: ptr StructGgmlTensor; fmt: cstring): ptr StructGgmlTensor {.
    cdecl, varargs, importc: "ggml_format_name".}
proc ggml_set_input*(tensor: ptr StructGgmlTensor): void {.cdecl,
    importc: "ggml_set_input".}
proc ggml_set_output*(tensor: ptr StructGgmlTensor): void {.cdecl,
    importc: "ggml_set_output".}
proc ggml_set_param*(tensor: ptr StructGgmlTensor): void {.cdecl,
    importc: "ggml_set_param".}
proc ggml_set_loss*(tensor: ptr StructGgmlTensor): void {.cdecl,
    importc: "ggml_set_loss".}
proc ggml_dup*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_dup".}
proc ggml_dup_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_dup_inplace".}
proc ggml_add*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
               b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_add".}
proc ggml_add_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_add_inplace".}
proc ggml_add_cast*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                    b: ptr StructGgmlTensor; type_arg: EnumGgmlType): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_add_cast".}
proc ggml_add1*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_add1".}
proc ggml_add1_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                        b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_add1_inplace".}
proc ggml_acc*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
               b: ptr StructGgmlTensor; nb1: csize_t; nb2: csize_t;
               nb3: csize_t; offset: csize_t): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_acc".}
proc ggml_acc_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       b: ptr StructGgmlTensor; nb1: csize_t; nb2: csize_t;
                       nb3: csize_t; offset: csize_t): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_acc_inplace".}
proc ggml_sub*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
               b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_sub".}
proc ggml_sub_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_sub_inplace".}
proc ggml_mul*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
               b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_mul".}
proc ggml_mul_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_mul_inplace".}
proc ggml_div*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
               b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_div".}
proc ggml_div_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_div_inplace".}
proc ggml_sqr*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_sqr".}
proc ggml_sqr_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_sqr_inplace".}
proc ggml_sqrt*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_sqrt".}
proc ggml_sqrt_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_sqrt_inplace".}
proc ggml_log*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_log".}
proc ggml_log_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_log_inplace".}
proc ggml_sin*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_sin".}
proc ggml_sin_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_sin_inplace".}
proc ggml_cos*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_cos".}
proc ggml_cos_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_cos_inplace".}
proc ggml_sum*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_sum".}
proc ggml_sum_rows*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_sum_rows".}
proc ggml_mean*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_mean".}
proc ggml_argmax*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_argmax".}
proc ggml_count_equal*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_count_equal".}
proc ggml_repeat*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                  b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_repeat".}
proc ggml_repeat_back*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_repeat_back".}
proc ggml_concat*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                  b: ptr StructGgmlTensor; dim: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_concat".}
proc ggml_abs*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_abs".}
proc ggml_abs_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_abs_inplace".}
proc ggml_sgn*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_sgn".}
proc ggml_sgn_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_sgn_inplace".}
proc ggml_neg*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_neg".}
proc ggml_neg_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_neg_inplace".}
proc ggml_step*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_step".}
proc ggml_step_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_step_inplace".}
proc ggml_tanh*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_tanh".}
proc ggml_tanh_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_tanh_inplace".}
proc ggml_elu*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_elu".}
proc ggml_elu_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_elu_inplace".}
proc ggml_relu*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_relu".}
proc ggml_leaky_relu*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                      negative_slope: cfloat; inplace: bool): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_leaky_relu".}
proc ggml_relu_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_relu_inplace".}
proc ggml_sigmoid*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_sigmoid".}
proc ggml_sigmoid_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_sigmoid_inplace".}
proc ggml_gelu*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_gelu".}
proc ggml_gelu_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_gelu_inplace".}
proc ggml_gelu_quick*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_gelu_quick".}
proc ggml_gelu_quick_inplace*(ctx: ptr StructGgmlContext;
                              a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_gelu_quick_inplace".}
proc ggml_silu*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_silu".}
proc ggml_silu_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_silu_inplace".}
proc ggml_silu_back*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                     b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_silu_back".}
proc ggml_hardswish*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_hardswish".}
proc ggml_hardsigmoid*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_hardsigmoid".}
proc ggml_exp*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_exp".}
proc ggml_exp_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_exp_inplace".}
proc ggml_norm*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor; eps: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_norm".}
proc ggml_norm_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                        eps: cfloat): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_norm_inplace".}
proc ggml_rms_norm*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                    eps: cfloat): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_rms_norm".}
proc ggml_rms_norm_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                            eps: cfloat): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_rms_norm_inplace".}
proc ggml_group_norm*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                      n_groups: cint; eps: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_group_norm".}
proc ggml_group_norm_inplace*(ctx: ptr StructGgmlContext;
                              a: ptr StructGgmlTensor; n_groups: cint;
                              eps: cfloat): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_group_norm_inplace".}
proc ggml_l2_norm*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   eps: cfloat): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_l2_norm".}
proc ggml_l2_norm_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                           eps: cfloat): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_l2_norm_inplace".}
proc ggml_rms_norm_back*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                         b: ptr StructGgmlTensor; eps: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_rms_norm_back".}
proc ggml_mul_mat*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_mul_mat".}
proc ggml_mul_mat_set_prec*(a: ptr StructGgmlTensor; prec: EnumGgmlPrec): void {.
    cdecl, importc: "ggml_mul_mat_set_prec".}
proc ggml_mul_mat_id*(ctx: ptr StructGgmlContext; as_arg: ptr StructGgmlTensor;
                      b: ptr StructGgmlTensor; ids: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_mul_mat_id".}
proc ggml_out_prod*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                    b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_out_prod".}
proc ggml_scale*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor; s: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_scale".}
proc ggml_scale_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                         s: cfloat): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_scale_inplace".}
proc ggml_set*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
               b: ptr StructGgmlTensor; nb1: csize_t; nb2: csize_t;
               nb3: csize_t; offset: csize_t): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_set".}
proc ggml_set_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       b: ptr StructGgmlTensor; nb1: csize_t; nb2: csize_t;
                       nb3: csize_t; offset: csize_t): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_set_inplace".}
proc ggml_set_1d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                  b: ptr StructGgmlTensor; offset: csize_t): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_set_1d".}
proc ggml_set_1d_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                          b: ptr StructGgmlTensor; offset: csize_t): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_set_1d_inplace".}
proc ggml_set_2d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                  b: ptr StructGgmlTensor; nb1: csize_t; offset: csize_t): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_set_2d".}
proc ggml_set_2d_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                          b: ptr StructGgmlTensor; nb1: csize_t; offset: csize_t): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_set_2d_inplace".}
proc ggml_cpy*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
               b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_cpy".}
proc ggml_cast*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                type_arg: EnumGgmlType): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_cast".}
proc ggml_cont*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_cont".}
proc ggml_cont_1d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   ne0: int64): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_cont_1d".}
proc ggml_cont_2d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   ne0: int64; ne1: int64): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_cont_2d".}
proc ggml_cont_3d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   ne0: int64; ne1: int64; ne2: int64): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_cont_3d".}
proc ggml_cont_4d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   ne0: int64; ne1: int64; ne2: int64; ne3: int64): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_cont_4d".}
proc ggml_reshape*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_reshape".}
proc ggml_reshape_1d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                      ne0: int64): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_reshape_1d".}
proc ggml_reshape_2d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                      ne0: int64; ne1: int64): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_reshape_2d".}
proc ggml_reshape_3d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                      ne0: int64; ne1: int64; ne2: int64): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_reshape_3d".}
proc ggml_reshape_4d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                      ne0: int64; ne1: int64; ne2: int64; ne3: int64): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_reshape_4d".}
proc ggml_view_1d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   ne0: int64; offset: csize_t): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_view_1d".}
proc ggml_view_2d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   ne0: int64; ne1: int64; nb1: csize_t; offset: csize_t): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_view_2d".}
proc ggml_view_3d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   ne0: int64; ne1: int64; ne2: int64; nb1: csize_t;
                   nb2: csize_t; offset: csize_t): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_view_3d".}
proc ggml_view_4d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   ne0: int64; ne1: int64; ne2: int64; ne3: int64; nb1: csize_t;
                   nb2: csize_t; nb3: csize_t; offset: csize_t): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_view_4d".}
proc ggml_permute*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   axis0: cint; axis1: cint; axis2: cint; axis3: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_permute".}
proc ggml_transpose*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_transpose".}
proc ggml_get_rows*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                    b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_get_rows".}
proc ggml_get_rows_back*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                         b: ptr StructGgmlTensor; c: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_get_rows_back".}
proc ggml_diag*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_diag".}
proc ggml_diag_mask_inf*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                         n_past: cint): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_diag_mask_inf".}
proc ggml_diag_mask_inf_inplace*(ctx: ptr StructGgmlContext;
                                 a: ptr StructGgmlTensor; n_past: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_diag_mask_inf_inplace".}
proc ggml_diag_mask_zero*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                          n_past: cint): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_diag_mask_zero".}
proc ggml_diag_mask_zero_inplace*(ctx: ptr StructGgmlContext;
                                  a: ptr StructGgmlTensor; n_past: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_diag_mask_zero_inplace".}
proc ggml_soft_max*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_soft_max".}
proc ggml_soft_max_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_soft_max_inplace".}
proc ggml_soft_max_ext*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                        mask: ptr StructGgmlTensor; scale: cfloat;
                        max_bias: cfloat): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_soft_max_ext".}
proc ggml_soft_max_ext_back*(ctx: ptr StructGgmlContext;
                             a: ptr StructGgmlTensor; b: ptr StructGgmlTensor;
                             scale: cfloat; max_bias: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_soft_max_ext_back".}
proc ggml_soft_max_ext_back_inplace*(ctx: ptr StructGgmlContext;
                                     a: ptr StructGgmlTensor;
                                     b: ptr StructGgmlTensor; scale: cfloat;
                                     max_bias: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_soft_max_ext_back_inplace".}
proc ggml_rope*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                b: ptr StructGgmlTensor; n_dims: cint; mode: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_rope".}
proc ggml_rope_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                        b: ptr StructGgmlTensor; n_dims: cint; mode: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_rope_inplace".}
proc ggml_rope_ext*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                    b: ptr StructGgmlTensor; c: ptr StructGgmlTensor;
                    n_dims: cint; mode: cint; n_ctx_orig: cint;
                    freq_base: cfloat; freq_scale: cfloat; ext_factor: cfloat;
                    attn_factor: cfloat; beta_fast: cfloat; beta_slow: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_rope_ext".}
proc ggml_rope_multi*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                      b: ptr StructGgmlTensor; c: ptr StructGgmlTensor;
                      n_dims: cint; sections: array[4'i64, cint]; mode: cint;
                      n_ctx_orig: cint; freq_base: cfloat; freq_scale: cfloat;
                      ext_factor: cfloat; attn_factor: cfloat;
                      beta_fast: cfloat; beta_slow: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_rope_multi".}
proc ggml_rope_ext_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                            b: ptr StructGgmlTensor; c: ptr StructGgmlTensor;
                            n_dims: cint; mode: cint; n_ctx_orig: cint;
                            freq_base: cfloat; freq_scale: cfloat;
                            ext_factor: cfloat; attn_factor: cfloat;
                            beta_fast: cfloat; beta_slow: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_rope_ext_inplace".}
proc ggml_rope_custom*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       b: ptr StructGgmlTensor; n_dims: cint; mode: cint;
                       n_ctx_orig: cint; freq_base: cfloat; freq_scale: cfloat;
                       ext_factor: cfloat; attn_factor: cfloat;
                       beta_fast: cfloat; beta_slow: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_rope_custom".}
proc ggml_rope_custom_inplace*(ctx: ptr StructGgmlContext;
                               a: ptr StructGgmlTensor; b: ptr StructGgmlTensor;
                               n_dims: cint; mode: cint; n_ctx_orig: cint;
                               freq_base: cfloat; freq_scale: cfloat;
                               ext_factor: cfloat; attn_factor: cfloat;
                               beta_fast: cfloat; beta_slow: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_rope_custom_inplace".}
proc ggml_rope_yarn_corr_dims*(n_dims: cint; n_ctx_orig: cint;
                               freq_base: cfloat; beta_fast: cfloat;
                               beta_slow: cfloat; dims: array[2'i64, cfloat]): void {.
    cdecl, importc: "ggml_rope_yarn_corr_dims".}
proc ggml_rope_ext_back*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                         b: ptr StructGgmlTensor; c: ptr StructGgmlTensor;
                         n_dims: cint; mode: cint; n_ctx_orig: cint;
                         freq_base: cfloat; freq_scale: cfloat;
                         ext_factor: cfloat; attn_factor: cfloat;
                         beta_fast: cfloat; beta_slow: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_rope_ext_back".}
proc ggml_rope_multi_back*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                           b: ptr StructGgmlTensor; c: ptr StructGgmlTensor;
                           n_dims: cint; sections: array[4'i64, cint];
                           mode: cint; n_ctx_orig: cint; freq_base: cfloat;
                           freq_scale: cfloat; ext_factor: cfloat;
                           attn_factor: cfloat; beta_fast: cfloat;
                           beta_slow: cfloat): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_rope_multi_back".}
proc ggml_clamp*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                 min: cfloat; max: cfloat): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_clamp".}
proc ggml_im2col*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                  b: ptr StructGgmlTensor; s0: cint; s1: cint; p0: cint;
                  p1: cint; d0: cint; d1: cint; is_2D: bool;
                  dst_type: EnumGgmlType): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_im2col".}
proc ggml_im2col_back*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       b: ptr StructGgmlTensor; ne: ptr int64; s0: cint;
                       s1: cint; p0: cint; p1: cint; d0: cint; d1: cint;
                       is_2D: bool): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_im2col_back".}
proc ggml_conv_1d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   b: ptr StructGgmlTensor; s0: cint; p0: cint; d0: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_conv_1d".}
proc ggml_conv_1d_ph*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                      b: ptr StructGgmlTensor; s: cint; d: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_conv_1d_ph".}
proc ggml_conv_1d_dw*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                      b: ptr StructGgmlTensor; s0: cint; p0: cint; d0: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_conv_1d_dw".}
proc ggml_conv_1d_dw_ph*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                         b: ptr StructGgmlTensor; s0: cint; d0: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_conv_1d_dw_ph".}
proc ggml_conv_transpose_1d*(ctx: ptr StructGgmlContext;
                             a: ptr StructGgmlTensor; b: ptr StructGgmlTensor;
                             s0: cint; p0: cint; d0: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_conv_transpose_1d".}
proc ggml_conv_2d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   b: ptr StructGgmlTensor; s0: cint; s1: cint; p0: cint;
                   p1: cint; d0: cint; d1: cint): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_conv_2d".}
proc ggml_conv_2d_sk_p0*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                         b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_conv_2d_sk_p0".}
proc ggml_conv_2d_s1_ph*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                         b: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_conv_2d_s1_ph".}
proc ggml_conv_2d_dw*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                      b: ptr StructGgmlTensor; s0: cint; s1: cint; p0: cint;
                      p1: cint; d0: cint; d1: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_conv_2d_dw".}
proc ggml_conv_2d_dw_direct*(ctx: ptr StructGgmlContext;
                             a: ptr StructGgmlTensor; b: ptr StructGgmlTensor;
                             stride0: cint; stride1: cint; pad0: cint;
                             pad1: cint; dilation0: cint; dilation1: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_conv_2d_dw_direct".}
proc ggml_conv_transpose_2d_p0*(ctx: ptr StructGgmlContext;
                                a: ptr StructGgmlTensor;
                                b: ptr StructGgmlTensor; stride: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_conv_transpose_2d_p0".}
proc ggml_pool_1d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   op: EnumGgmlOpPool; k0: cint; s0: cint; p0: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_pool_1d".}
proc ggml_pool_2d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   op: EnumGgmlOpPool; k0: cint; k1: cint; s0: cint; s1: cint;
                   p0: cfloat; p1: cfloat): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_pool_2d".}
proc ggml_pool_2d_back*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                        af: ptr StructGgmlTensor; op: EnumGgmlOpPool; k0: cint;
                        k1: cint; s0: cint; s1: cint; p0: cfloat; p1: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_pool_2d_back".}
proc ggml_upscale*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   scale_factor: cint; mode: EnumGgmlScaleMode): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_upscale".}
proc ggml_upscale_ext*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       ne0: cint; ne1: cint; ne2: cint; ne3: cint;
                       mode: EnumGgmlScaleMode): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_upscale_ext".}
proc ggml_pad*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor; p0: cint;
               p1: cint; p2: cint; p3: cint): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_pad".}
proc ggml_pad_reflect_1d*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                          p0: cint; p1: cint): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_pad_reflect_1d".}
proc ggml_timestep_embedding*(ctx: ptr StructGgmlContext;
                              timesteps: ptr StructGgmlTensor; dim: cint;
                              max_period: cint): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_timestep_embedding".}
proc ggml_argsort*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                   order: EnumGgmlSortOrder): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_argsort".}
proc ggml_arange*(ctx: ptr StructGgmlContext; start: cfloat; stop: cfloat;
                  step: cfloat): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_arange".}
proc ggml_top_k*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor; k: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_top_k".}
proc ggml_flash_attn_ext*(ctx: ptr StructGgmlContext; q: ptr StructGgmlTensor;
                          k: ptr StructGgmlTensor; v: ptr StructGgmlTensor;
                          mask: ptr StructGgmlTensor; scale: cfloat;
                          max_bias: cfloat; logit_softcap: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_flash_attn_ext".}
proc ggml_flash_attn_ext_set_prec*(a: ptr StructGgmlTensor; prec: EnumGgmlPrec): void {.
    cdecl, importc: "ggml_flash_attn_ext_set_prec".}
proc ggml_flash_attn_ext_get_prec*(a: ptr StructGgmlTensor): EnumGgmlPrec {.
    cdecl, importc: "ggml_flash_attn_ext_get_prec".}
proc ggml_flash_attn_back*(ctx: ptr StructGgmlContext; q: ptr StructGgmlTensor;
                           k: ptr StructGgmlTensor; v: ptr StructGgmlTensor;
                           d: ptr StructGgmlTensor; masked: bool): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_flash_attn_back".}
proc ggml_ssm_conv*(ctx: ptr StructGgmlContext; sx: ptr StructGgmlTensor;
                    c: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_ssm_conv".}
proc ggml_ssm_scan*(ctx: ptr StructGgmlContext; s: ptr StructGgmlTensor;
                    x: ptr StructGgmlTensor; dt: ptr StructGgmlTensor;
                    A: ptr StructGgmlTensor; B: ptr StructGgmlTensor;
                    C: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_ssm_scan".}
proc ggml_win_part*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor; w: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_win_part".}
proc ggml_win_unpart*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                      w0: cint; h0: cint; w: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_win_unpart".}
proc ggml_unary*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                 op: EnumGgmlUnaryOp): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_unary".}
proc ggml_unary_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                         op: EnumGgmlUnaryOp): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_unary_inplace".}
proc ggml_get_rel_pos*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       qh: cint; kh: cint): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_get_rel_pos".}
proc ggml_add_rel_pos*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       pw: ptr StructGgmlTensor; ph: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_add_rel_pos".}
proc ggml_add_rel_pos_inplace*(ctx: ptr StructGgmlContext;
                               a: ptr StructGgmlTensor;
                               pw: ptr StructGgmlTensor;
                               ph: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_add_rel_pos_inplace".}
proc ggml_rwkv_wkv6*(ctx: ptr StructGgmlContext; k: ptr StructGgmlTensor;
                     v: ptr StructGgmlTensor; r: ptr StructGgmlTensor;
                     tf: ptr StructGgmlTensor; td: ptr StructGgmlTensor;
                     state: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_rwkv_wkv6".}
proc ggml_gated_linear_attn*(ctx: ptr StructGgmlContext;
                             k: ptr StructGgmlTensor; v: ptr StructGgmlTensor;
                             q: ptr StructGgmlTensor; g: ptr StructGgmlTensor;
                             state: ptr StructGgmlTensor; scale: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_gated_linear_attn".}
proc ggml_rwkv_wkv7*(ctx: ptr StructGgmlContext; r: ptr StructGgmlTensor;
                     w: ptr StructGgmlTensor; k: ptr StructGgmlTensor;
                     v: ptr StructGgmlTensor; a: ptr StructGgmlTensor;
                     b: ptr StructGgmlTensor; state: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_rwkv_wkv7".}
proc ggml_map_custom1*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       fun: GgmlCustom1OpT; n_tasks: cint; userdata: pointer): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_map_custom1".}
proc ggml_map_custom1_inplace*(ctx: ptr StructGgmlContext;
                               a: ptr StructGgmlTensor; fun: GgmlCustom1OpT;
                               n_tasks: cint; userdata: pointer): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_map_custom1_inplace".}
proc ggml_map_custom2*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       b: ptr StructGgmlTensor; fun: GgmlCustom2OpT;
                       n_tasks: cint; userdata: pointer): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_map_custom2".}
proc ggml_map_custom2_inplace*(ctx: ptr StructGgmlContext;
                               a: ptr StructGgmlTensor; b: ptr StructGgmlTensor;
                               fun: GgmlCustom2OpT; n_tasks: cint;
                               userdata: pointer): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_map_custom2_inplace".}
proc ggml_map_custom3*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                       b: ptr StructGgmlTensor; c: ptr StructGgmlTensor;
                       fun: GgmlCustom3OpT; n_tasks: cint; userdata: pointer): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_map_custom3".}
proc ggml_map_custom3_inplace*(ctx: ptr StructGgmlContext;
                               a: ptr StructGgmlTensor; b: ptr StructGgmlTensor;
                               c: ptr StructGgmlTensor; fun: GgmlCustom3OpT;
                               n_tasks: cint; userdata: pointer): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_map_custom3_inplace".}
proc ggml_custom_4d*(ctx: ptr StructGgmlContext; type_arg: EnumGgmlType;
                     ne0: int64; ne1: int64; ne2: int64; ne3: int64;
                     args: ptr ptr StructGgmlTensor; n_args: cint;
                     fun: GgmlCustomOpT; n_tasks: cint; userdata: pointer): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_custom_4d".}
proc ggml_custom_inplace*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                          args: ptr ptr StructGgmlTensor; n_args: cint;
                          fun: GgmlCustomOpT; n_tasks: cint; userdata: pointer): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_custom_inplace".}
proc ggml_cross_entropy_loss*(ctx: ptr StructGgmlContext;
                              a: ptr StructGgmlTensor; b: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_cross_entropy_loss".}
proc ggml_cross_entropy_loss_back*(ctx: ptr StructGgmlContext;
                                   a: ptr StructGgmlTensor;
                                   b: ptr StructGgmlTensor;
                                   c: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_cross_entropy_loss_back".}
proc ggml_opt_step_adamw*(ctx: ptr StructGgmlContext; a: ptr StructGgmlTensor;
                          grad: ptr StructGgmlTensor; m: ptr StructGgmlTensor;
                          v: ptr StructGgmlTensor;
                          adamw_params: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_opt_step_adamw".}
proc ggml_build_forward_expand*(cgraph: ptr StructGgmlCgraph;
                                tensor: ptr StructGgmlTensor): void {.cdecl,
    importc: "ggml_build_forward_expand".}
proc ggml_build_backward_expand*(ctx: ptr StructGgmlContext;
                                 cgraph: ptr StructGgmlCgraph;
                                 grad_accs: ptr ptr StructGgmlTensor): void {.
    cdecl, importc: "ggml_build_backward_expand".}
proc ggml_new_graph*(ctx: ptr StructGgmlContext): ptr StructGgmlCgraph {.cdecl,
    importc: "ggml_new_graph".}
proc ggml_new_graph_custom*(ctx: ptr StructGgmlContext; size: csize_t;
                            grads: bool): ptr StructGgmlCgraph {.cdecl,
    importc: "ggml_new_graph_custom".}
proc ggml_graph_dup*(ctx: ptr StructGgmlContext; cgraph: ptr StructGgmlCgraph;
                     force_grads: bool): ptr StructGgmlCgraph {.cdecl,
    importc: "ggml_graph_dup".}
proc ggml_graph_cpy*(src: ptr StructGgmlCgraph; dst: ptr StructGgmlCgraph): void {.
    cdecl, importc: "ggml_graph_cpy".}
proc ggml_graph_reset*(cgraph: ptr StructGgmlCgraph): void {.cdecl,
    importc: "ggml_graph_reset".}
proc ggml_graph_clear*(cgraph: ptr StructGgmlCgraph): void {.cdecl,
    importc: "ggml_graph_clear".}
proc ggml_graph_size*(cgraph: ptr StructGgmlCgraph): cint {.cdecl,
    importc: "ggml_graph_size".}
proc ggml_graph_node*(cgraph: ptr StructGgmlCgraph; i: cint): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_graph_node".}
proc ggml_graph_nodes*(cgraph: ptr StructGgmlCgraph): ptr ptr StructGgmlTensor {.
    cdecl, importc: "ggml_graph_nodes".}
proc ggml_graph_n_nodes*(cgraph: ptr StructGgmlCgraph): cint {.cdecl,
    importc: "ggml_graph_n_nodes".}
proc ggml_graph_add_node*(cgraph: ptr StructGgmlCgraph;
                          tensor: ptr StructGgmlTensor): void {.cdecl,
    importc: "ggml_graph_add_node".}
proc ggml_graph_overhead*(): csize_t {.cdecl, importc: "ggml_graph_overhead".}
proc ggml_graph_overhead_custom*(size: csize_t; grads: bool): csize_t {.cdecl,
    importc: "ggml_graph_overhead_custom".}
proc ggml_graph_get_tensor*(cgraph: ptr StructGgmlCgraph; name: cstring): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_graph_get_tensor".}
proc ggml_graph_get_grad*(cgraph: ptr StructGgmlCgraph;
                          node: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_graph_get_grad".}
proc ggml_graph_get_grad_acc*(cgraph: ptr StructGgmlCgraph;
                              node: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_graph_get_grad_acc".}
proc ggml_graph_export*(cgraph: ptr StructGgmlCgraph; fname: cstring): void {.
    cdecl, importc: "ggml_graph_export".}
proc ggml_graph_import*(fname: cstring; ctx_data: ptr ptr StructGgmlContext;
                        ctx_eval: ptr ptr StructGgmlContext): ptr StructGgmlCgraph {.
    cdecl, importc: "ggml_graph_import".}
proc ggml_graph_print*(cgraph: ptr StructGgmlCgraph): void {.cdecl,
    importc: "ggml_graph_print".}
proc ggml_graph_dump_dot*(gb: ptr StructGgmlCgraph; gf: ptr StructGgmlCgraph;
                          filename: cstring): void {.cdecl,
    importc: "ggml_graph_dump_dot".}
proc ggml_log_set*(log_callback: GgmlLogCallback; user_data: pointer): void {.
    cdecl, importc: "ggml_log_set".}
proc ggml_set_zero*(tensor: ptr StructGgmlTensor): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_set_zero".}
proc ggml_quantize_init*(type_arg: EnumGgmlType): void {.cdecl,
    importc: "ggml_quantize_init".}
proc ggml_quantize_free*(): void {.cdecl, importc: "ggml_quantize_free".}
proc ggml_quantize_requires_imatrix*(type_arg: EnumGgmlType): bool {.cdecl,
    importc: "ggml_quantize_requires_imatrix".}
proc ggml_quantize_chunk*(type_arg: EnumGgmlType; src: ptr cfloat; dst: pointer;
                          start: int64; nrows: int64; n_per_row: int64;
                          imatrix: ptr cfloat): csize_t {.cdecl,
    importc: "ggml_quantize_chunk".}
proc ggml_get_type_traits*(type_arg: EnumGgmlType): ptr StructGgmlTypeTraits {.
    cdecl, importc: "ggml_get_type_traits".}
proc ggml_threadpool_params_default*(n_threads: cint): StructGgmlThreadpoolParams {.
    cdecl, importc: "ggml_threadpool_params_default".}
proc ggml_threadpool_params_init*(p: ptr StructGgmlThreadpoolParams;
                                  n_threads: cint): void {.cdecl,
    importc: "ggml_threadpool_params_init".}
proc ggml_threadpool_params_match*(p0: ptr StructGgmlThreadpoolParams;
                                   p1: ptr StructGgmlThreadpoolParams): bool {.
    cdecl, importc: "ggml_threadpool_params_match".}
proc ggml_tallocr_new*(buffer: GgmlBackendBufferT): StructGgmlTallocr {.cdecl,
    importc: "ggml_tallocr_new".}
proc ggml_tallocr_alloc*(talloc: ptr StructGgmlTallocr;
                         tensor: ptr StructGgmlTensor): EnumGgmlStatus {.cdecl,
    importc: "ggml_tallocr_alloc".}
proc ggml_gallocr_new*(buft: GgmlBackendBufferTypeT): GgmlGallocrT {.cdecl,
    importc: "ggml_gallocr_new".}
proc ggml_gallocr_new_n*(bufts: ptr GgmlBackendBufferTypeT; n_bufs: cint): GgmlGallocrT {.
    cdecl, importc: "ggml_gallocr_new_n".}
proc ggml_gallocr_free*(galloc: GgmlGallocrT): void {.cdecl,
    importc: "ggml_gallocr_free".}
proc ggml_gallocr_reserve*(galloc: GgmlGallocrT; graph: ptr StructGgmlCgraph): bool {.
    cdecl, importc: "ggml_gallocr_reserve".}
proc ggml_gallocr_reserve_n*(galloc: GgmlGallocrT; graph: ptr StructGgmlCgraph;
                             node_buffer_ids: ptr cint;
                             leaf_buffer_ids: ptr cint): bool {.cdecl,
    importc: "ggml_gallocr_reserve_n".}
proc ggml_gallocr_alloc_graph*(galloc: GgmlGallocrT; graph: ptr StructGgmlCgraph): bool {.
    cdecl, importc: "ggml_gallocr_alloc_graph".}
proc ggml_gallocr_get_buffer_size*(galloc: GgmlGallocrT; buffer_id: cint): csize_t {.
    cdecl, importc: "ggml_gallocr_get_buffer_size".}
proc ggml_backend_alloc_ctx_tensors_from_buft*(ctx: ptr StructGgmlContext;
    buft: GgmlBackendBufferTypeT): ptr StructGgmlBackendBuffer {.cdecl,
    importc: "ggml_backend_alloc_ctx_tensors_from_buft".}
proc ggml_backend_alloc_ctx_tensors*(ctx: ptr StructGgmlContext;
                                     backend: GgmlBackendT): ptr StructGgmlBackendBuffer {.
    cdecl, importc: "ggml_backend_alloc_ctx_tensors".}
proc ggml_backend_buft_name*(buft: GgmlBackendBufferTypeT): cstring {.cdecl,
    importc: "ggml_backend_buft_name".}
proc ggml_backend_buft_alloc_buffer*(buft: GgmlBackendBufferTypeT; size: csize_t): GgmlBackendBufferT {.
    cdecl, importc: "ggml_backend_buft_alloc_buffer".}
proc ggml_backend_buft_get_alignment*(buft: GgmlBackendBufferTypeT): csize_t {.
    cdecl, importc: "ggml_backend_buft_get_alignment".}
proc ggml_backend_buft_get_max_size*(buft: GgmlBackendBufferTypeT): csize_t {.
    cdecl, importc: "ggml_backend_buft_get_max_size".}
proc ggml_backend_buft_get_alloc_size*(buft: GgmlBackendBufferTypeT;
                                       tensor: ptr StructGgmlTensor): csize_t {.
    cdecl, importc: "ggml_backend_buft_get_alloc_size".}
proc ggml_backend_buft_is_host*(buft: GgmlBackendBufferTypeT): bool {.cdecl,
    importc: "ggml_backend_buft_is_host".}
proc ggml_backend_buft_get_device*(buft: GgmlBackendBufferTypeT): GgmlBackendDevT {.
    cdecl, importc: "ggml_backend_buft_get_device".}
proc ggml_backend_buffer_name*(buffer: GgmlBackendBufferT): cstring {.cdecl,
    importc: "ggml_backend_buffer_name".}
proc ggml_backend_buffer_free*(buffer: GgmlBackendBufferT): void {.cdecl,
    importc: "ggml_backend_buffer_free".}
proc ggml_backend_buffer_get_base*(buffer: GgmlBackendBufferT): pointer {.cdecl,
    importc: "ggml_backend_buffer_get_base".}
proc ggml_backend_buffer_get_size*(buffer: GgmlBackendBufferT): csize_t {.cdecl,
    importc: "ggml_backend_buffer_get_size".}
proc ggml_backend_buffer_init_tensor*(buffer: GgmlBackendBufferT;
                                      tensor: ptr StructGgmlTensor): EnumGgmlStatus {.
    cdecl, importc: "ggml_backend_buffer_init_tensor".}
proc ggml_backend_buffer_get_alignment*(buffer: GgmlBackendBufferT): csize_t {.
    cdecl, importc: "ggml_backend_buffer_get_alignment".}
proc ggml_backend_buffer_get_max_size*(buffer: GgmlBackendBufferT): csize_t {.
    cdecl, importc: "ggml_backend_buffer_get_max_size".}
proc ggml_backend_buffer_get_alloc_size*(buffer: GgmlBackendBufferT;
    tensor: ptr StructGgmlTensor): csize_t {.cdecl,
    importc: "ggml_backend_buffer_get_alloc_size".}
proc ggml_backend_buffer_clear*(buffer: GgmlBackendBufferT; value: uint8): void {.
    cdecl, importc: "ggml_backend_buffer_clear".}
proc ggml_backend_buffer_is_host*(buffer: GgmlBackendBufferT): bool {.cdecl,
    importc: "ggml_backend_buffer_is_host".}
proc ggml_backend_buffer_set_usage*(buffer: GgmlBackendBufferT;
                                    usage: EnumGgmlBackendBufferUsage): void {.
    cdecl, importc: "ggml_backend_buffer_set_usage".}
proc ggml_backend_buffer_get_usage*(buffer: GgmlBackendBufferT): EnumGgmlBackendBufferUsage {.
    cdecl, importc: "ggml_backend_buffer_get_usage".}
proc ggml_backend_buffer_get_type*(buffer: GgmlBackendBufferT): GgmlBackendBufferTypeT {.
    cdecl, importc: "ggml_backend_buffer_get_type".}
proc ggml_backend_buffer_reset*(buffer: GgmlBackendBufferT): void {.cdecl,
    importc: "ggml_backend_buffer_reset".}
proc ggml_backend_tensor_copy*(src: ptr StructGgmlTensor;
                               dst: ptr StructGgmlTensor): void {.cdecl,
    importc: "ggml_backend_tensor_copy".}
proc ggml_backend_guid*(backend: GgmlBackendT): GgmlGuidT {.cdecl,
    importc: "ggml_backend_guid".}
proc ggml_backend_name*(backend: GgmlBackendT): cstring {.cdecl,
    importc: "ggml_backend_name".}
proc ggml_backend_free*(backend: GgmlBackendT): void {.cdecl,
    importc: "ggml_backend_free".}
proc ggml_backend_get_default_buffer_type*(backend: GgmlBackendT): GgmlBackendBufferTypeT {.
    cdecl, importc: "ggml_backend_get_default_buffer_type".}
proc ggml_backend_alloc_buffer*(backend: GgmlBackendT; size: csize_t): GgmlBackendBufferT {.
    cdecl, importc: "ggml_backend_alloc_buffer".}
proc ggml_backend_get_alignment*(backend: GgmlBackendT): csize_t {.cdecl,
    importc: "ggml_backend_get_alignment".}
proc ggml_backend_get_max_size*(backend: GgmlBackendT): csize_t {.cdecl,
    importc: "ggml_backend_get_max_size".}
proc ggml_backend_tensor_set_async*(backend: GgmlBackendT;
                                    tensor: ptr StructGgmlTensor; data: pointer;
                                    offset: csize_t; size: csize_t): void {.
    cdecl, importc: "ggml_backend_tensor_set_async".}
proc ggml_backend_tensor_get_async*(backend: GgmlBackendT;
                                    tensor: ptr StructGgmlTensor; data: pointer;
                                    offset: csize_t; size: csize_t): void {.
    cdecl, importc: "ggml_backend_tensor_get_async".}
proc ggml_backend_tensor_set*(tensor: ptr StructGgmlTensor; data: pointer;
                              offset: csize_t; size: csize_t): void {.cdecl,
    importc: "ggml_backend_tensor_set".}
proc ggml_backend_tensor_get*(tensor: ptr StructGgmlTensor; data: pointer;
                              offset: csize_t; size: csize_t): void {.cdecl,
    importc: "ggml_backend_tensor_get".}
proc ggml_backend_tensor_memset*(tensor: ptr StructGgmlTensor; value: uint8;
                                 offset: csize_t; size: csize_t): void {.cdecl,
    importc: "ggml_backend_tensor_memset".}
proc ggml_backend_synchronize*(backend: GgmlBackendT): void {.cdecl,
    importc: "ggml_backend_synchronize".}
proc ggml_backend_graph_plan_create*(backend: GgmlBackendT;
                                     cgraph: ptr StructGgmlCgraph): GgmlBackendGraphPlanT {.
    cdecl, importc: "ggml_backend_graph_plan_create".}
proc ggml_backend_graph_plan_free*(backend: GgmlBackendT;
                                   plan: GgmlBackendGraphPlanT): void {.cdecl,
    importc: "ggml_backend_graph_plan_free".}
proc ggml_backend_graph_plan_compute*(backend: GgmlBackendT;
                                      plan: GgmlBackendGraphPlanT): EnumGgmlStatus {.
    cdecl, importc: "ggml_backend_graph_plan_compute".}
proc ggml_backend_graph_compute*(backend: GgmlBackendT;
                                 cgraph: ptr StructGgmlCgraph): EnumGgmlStatus {.
    cdecl, importc: "ggml_backend_graph_compute".}
proc ggml_backend_graph_compute_async*(backend: GgmlBackendT;
                                       cgraph: ptr StructGgmlCgraph): EnumGgmlStatus {.
    cdecl, importc: "ggml_backend_graph_compute_async".}
proc ggml_backend_supports_op*(backend: GgmlBackendT; op: ptr StructGgmlTensor): bool {.
    cdecl, importc: "ggml_backend_supports_op".}
proc ggml_backend_supports_buft*(backend: GgmlBackendT;
                                 buft: GgmlBackendBufferTypeT): bool {.cdecl,
    importc: "ggml_backend_supports_buft".}
proc ggml_backend_offload_op*(backend: GgmlBackendT; op: ptr StructGgmlTensor): bool {.
    cdecl, importc: "ggml_backend_offload_op".}
proc ggml_backend_tensor_copy_async*(backend_src: GgmlBackendT;
                                     backend_dst: GgmlBackendT;
                                     src: ptr StructGgmlTensor;
                                     dst: ptr StructGgmlTensor): void {.cdecl,
    importc: "ggml_backend_tensor_copy_async".}
proc ggml_backend_get_device*(backend: GgmlBackendT): GgmlBackendDevT {.cdecl,
    importc: "ggml_backend_get_device".}
proc ggml_backend_event_new*(device: GgmlBackendDevT): GgmlBackendEventT {.
    cdecl, importc: "ggml_backend_event_new".}
proc ggml_backend_event_free*(event: GgmlBackendEventT): void {.cdecl,
    importc: "ggml_backend_event_free".}
proc ggml_backend_event_record*(event: GgmlBackendEventT; backend: GgmlBackendT): void {.
    cdecl, importc: "ggml_backend_event_record".}
proc ggml_backend_event_synchronize*(event: GgmlBackendEventT): void {.cdecl,
    importc: "ggml_backend_event_synchronize".}
proc ggml_backend_event_wait*(backend: GgmlBackendT; event: GgmlBackendEventT): void {.
    cdecl, importc: "ggml_backend_event_wait".}
proc ggml_backend_dev_name*(device: GgmlBackendDevT): cstring {.cdecl,
    importc: "ggml_backend_dev_name".}
proc ggml_backend_dev_description*(device: GgmlBackendDevT): cstring {.cdecl,
    importc: "ggml_backend_dev_description".}
proc ggml_backend_dev_memory*(device: GgmlBackendDevT; free: ptr csize_t;
                              total: ptr csize_t): void {.cdecl,
    importc: "ggml_backend_dev_memory".}
proc ggml_backend_dev_type*(device: GgmlBackendDevT): EnumGgmlBackendDevType {.
    cdecl, importc: "ggml_backend_dev_type".}
proc ggml_backend_dev_get_props*(device: GgmlBackendDevT;
                                 props: ptr StructGgmlBackendDevProps): void {.
    cdecl, importc: "ggml_backend_dev_get_props".}
proc ggml_backend_dev_backend_reg*(device: GgmlBackendDevT): GgmlBackendRegT {.
    cdecl, importc: "ggml_backend_dev_backend_reg".}
proc ggml_backend_dev_init*(device: GgmlBackendDevT; params: cstring): GgmlBackendT {.
    cdecl, importc: "ggml_backend_dev_init".}
proc ggml_backend_dev_buffer_type*(device: GgmlBackendDevT): GgmlBackendBufferTypeT {.
    cdecl, importc: "ggml_backend_dev_buffer_type".}
proc ggml_backend_dev_host_buffer_type*(device: GgmlBackendDevT): GgmlBackendBufferTypeT {.
    cdecl, importc: "ggml_backend_dev_host_buffer_type".}
proc ggml_backend_dev_buffer_from_host_ptr*(device: GgmlBackendDevT;
    ptr_arg: pointer; size: csize_t; max_tensor_size: csize_t): GgmlBackendBufferT {.
    cdecl, importc: "ggml_backend_dev_buffer_from_host_ptr".}
proc ggml_backend_dev_supports_op*(device: GgmlBackendDevT;
                                   op: ptr StructGgmlTensor): bool {.cdecl,
    importc: "ggml_backend_dev_supports_op".}
proc ggml_backend_dev_supports_buft*(device: GgmlBackendDevT;
                                     buft: GgmlBackendBufferTypeT): bool {.
    cdecl, importc: "ggml_backend_dev_supports_buft".}
proc ggml_backend_dev_offload_op*(device: GgmlBackendDevT;
                                  op: ptr StructGgmlTensor): bool {.cdecl,
    importc: "ggml_backend_dev_offload_op".}
proc ggml_backend_reg_name*(reg: GgmlBackendRegT): cstring {.cdecl,
    importc: "ggml_backend_reg_name".}
proc ggml_backend_reg_dev_count*(reg: GgmlBackendRegT): csize_t {.cdecl,
    importc: "ggml_backend_reg_dev_count".}
proc ggml_backend_reg_dev_get*(reg: GgmlBackendRegT; index: csize_t): GgmlBackendDevT {.
    cdecl, importc: "ggml_backend_reg_dev_get".}
proc ggml_backend_reg_get_proc_address*(reg: GgmlBackendRegT; name: cstring): pointer {.
    cdecl, importc: "ggml_backend_reg_get_proc_address".}
proc ggml_backend_device_register*(device: GgmlBackendDevT): void {.cdecl,
    importc: "ggml_backend_device_register".}
proc ggml_backend_reg_count*(): csize_t {.cdecl,
    importc: "ggml_backend_reg_count".}
proc ggml_backend_reg_get*(index: csize_t): GgmlBackendRegT {.cdecl,
    importc: "ggml_backend_reg_get".}
proc ggml_backend_reg_by_name*(name: cstring): GgmlBackendRegT {.cdecl,
    importc: "ggml_backend_reg_by_name".}
proc ggml_backend_dev_count*(): csize_t {.cdecl,
    importc: "ggml_backend_dev_count".}
proc ggml_backend_dev_get*(index: csize_t): GgmlBackendDevT {.cdecl,
    importc: "ggml_backend_dev_get".}
proc ggml_backend_dev_by_name*(name: cstring): GgmlBackendDevT {.cdecl,
    importc: "ggml_backend_dev_by_name".}
proc ggml_backend_dev_by_type*(type_arg: EnumGgmlBackendDevType): GgmlBackendDevT {.
    cdecl, importc: "ggml_backend_dev_by_type".}
proc ggml_backend_init_by_name*(name: cstring; params: cstring): GgmlBackendT {.
    cdecl, importc: "ggml_backend_init_by_name".}
proc ggml_backend_init_by_type*(type_arg: EnumGgmlBackendDevType;
                                params: cstring): GgmlBackendT {.cdecl,
    importc: "ggml_backend_init_by_type".}
proc ggml_backend_init_best*(): GgmlBackendT {.cdecl,
    importc: "ggml_backend_init_best".}
proc ggml_backend_load*(path: cstring): GgmlBackendRegT {.cdecl,
    importc: "ggml_backend_load".}
proc ggml_backend_unload*(reg: GgmlBackendRegT): void {.cdecl,
    importc: "ggml_backend_unload".}
proc ggml_backend_load_all*(): void {.cdecl, importc: "ggml_backend_load_all".}
proc ggml_backend_load_all_from_path*(dir_path: cstring): void {.cdecl,
    importc: "ggml_backend_load_all_from_path".}
proc ggml_backend_sched_new*(backends: ptr GgmlBackendT;
                             bufts: ptr GgmlBackendBufferTypeT;
                             n_backends: cint; graph_size: csize_t;
                             parallel: bool; op_offload: bool): GgmlBackendSchedT {.
    cdecl, importc: "ggml_backend_sched_new".}
proc ggml_backend_sched_free*(sched: GgmlBackendSchedT): void {.cdecl,
    importc: "ggml_backend_sched_free".}
proc ggml_backend_sched_reserve*(sched: GgmlBackendSchedT;
                                 measure_graph: ptr StructGgmlCgraph): bool {.
    cdecl, importc: "ggml_backend_sched_reserve".}
proc ggml_backend_sched_get_n_backends*(sched: GgmlBackendSchedT): cint {.cdecl,
    importc: "ggml_backend_sched_get_n_backends".}
proc ggml_backend_sched_get_backend*(sched: GgmlBackendSchedT; i: cint): GgmlBackendT {.
    cdecl, importc: "ggml_backend_sched_get_backend".}
proc ggml_backend_sched_get_n_splits*(sched: GgmlBackendSchedT): cint {.cdecl,
    importc: "ggml_backend_sched_get_n_splits".}
proc ggml_backend_sched_get_n_copies*(sched: GgmlBackendSchedT): cint {.cdecl,
    importc: "ggml_backend_sched_get_n_copies".}
proc ggml_backend_sched_get_buffer_size*(sched: GgmlBackendSchedT;
    backend: GgmlBackendT): csize_t {.cdecl, importc: "ggml_backend_sched_get_buffer_size".}
proc ggml_backend_sched_set_tensor_backend*(sched: GgmlBackendSchedT;
    node: ptr StructGgmlTensor; backend: GgmlBackendT): void {.cdecl,
    importc: "ggml_backend_sched_set_tensor_backend".}
proc ggml_backend_sched_get_tensor_backend*(sched: GgmlBackendSchedT;
    node: ptr StructGgmlTensor): GgmlBackendT {.cdecl,
    importc: "ggml_backend_sched_get_tensor_backend".}
proc ggml_backend_sched_alloc_graph*(sched: GgmlBackendSchedT;
                                     graph: ptr StructGgmlCgraph): bool {.cdecl,
    importc: "ggml_backend_sched_alloc_graph".}
proc ggml_backend_sched_graph_compute*(sched: GgmlBackendSchedT;
                                       graph: ptr StructGgmlCgraph): EnumGgmlStatus {.
    cdecl, importc: "ggml_backend_sched_graph_compute".}
proc ggml_backend_sched_graph_compute_async*(sched: GgmlBackendSchedT;
    graph: ptr StructGgmlCgraph): EnumGgmlStatus {.cdecl,
    importc: "ggml_backend_sched_graph_compute_async".}
proc ggml_backend_sched_synchronize*(sched: GgmlBackendSchedT): void {.cdecl,
    importc: "ggml_backend_sched_synchronize".}
proc ggml_backend_sched_reset*(sched: GgmlBackendSchedT): void {.cdecl,
    importc: "ggml_backend_sched_reset".}
proc ggml_backend_sched_set_eval_callback*(sched: GgmlBackendSchedT;
    callback: GgmlBackendSchedEvalCallback; user_data: pointer): void {.cdecl,
    importc: "ggml_backend_sched_set_eval_callback".}
proc ggml_backend_graph_copy*(backend: GgmlBackendT; graph: ptr StructGgmlCgraph): StructGgmlBackendGraphCopy {.
    cdecl, importc: "ggml_backend_graph_copy".}
proc ggml_backend_graph_copy_free*(copy: StructGgmlBackendGraphCopy): void {.
    cdecl, importc: "ggml_backend_graph_copy_free".}
proc ggml_backend_compare_graph_backend*(backend1: GgmlBackendT;
    backend2: GgmlBackendT; graph: ptr StructGgmlCgraph;
    callback: GgmlBackendEvalCallback; user_data: pointer): bool {.cdecl,
    importc: "ggml_backend_compare_graph_backend".}
proc ggml_backend_tensor_alloc*(buffer: GgmlBackendBufferT;
                                tensor: ptr StructGgmlTensor; addr_arg: pointer): EnumGgmlStatus {.
    cdecl, importc: "ggml_backend_tensor_alloc".}
proc ggml_backend_view_init*(tensor: ptr StructGgmlTensor): EnumGgmlStatus {.
    cdecl, importc: "ggml_backend_view_init".}
proc ggml_backend_cpu_buffer_from_ptr*(ptr_arg: pointer; size: csize_t): GgmlBackendBufferT {.
    cdecl, importc: "ggml_backend_cpu_buffer_from_ptr".}
proc ggml_backend_cpu_buffer_type*(): GgmlBackendBufferTypeT {.cdecl,
    importc: "ggml_backend_cpu_buffer_type".}
proc ggml_numa_init*(numa: EnumGgmlNumaStrategy): void {.cdecl,
    importc: "ggml_numa_init".}
proc ggml_is_numa*(): bool {.cdecl, importc: "ggml_is_numa".}
proc ggml_new_i32*(ctx: ptr StructGgmlContext; value: int32): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_new_i32".}
proc ggml_new_f32*(ctx: ptr StructGgmlContext; value: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_new_f32".}
proc ggml_set_i32*(tensor: ptr StructGgmlTensor; value: int32): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_set_i32".}
proc ggml_set_f32*(tensor: ptr StructGgmlTensor; value: cfloat): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_set_f32".}
proc ggml_get_i32_1d*(tensor: ptr StructGgmlTensor; i: cint): int32 {.cdecl,
    importc: "ggml_get_i32_1d".}
proc ggml_set_i32_1d*(tensor: ptr StructGgmlTensor; i: cint; value: int32): void {.
    cdecl, importc: "ggml_set_i32_1d".}
proc ggml_get_i32_nd*(tensor: ptr StructGgmlTensor; i0: cint; i1: cint;
                      i2: cint; i3: cint): int32 {.cdecl,
    importc: "ggml_get_i32_nd".}
proc ggml_set_i32_nd*(tensor: ptr StructGgmlTensor; i0: cint; i1: cint;
                      i2: cint; i3: cint; value: int32): void {.cdecl,
    importc: "ggml_set_i32_nd".}
proc ggml_get_f32_1d*(tensor: ptr StructGgmlTensor; i: cint): cfloat {.cdecl,
    importc: "ggml_get_f32_1d".}
proc ggml_set_f32_1d*(tensor: ptr StructGgmlTensor; i: cint; value: cfloat): void {.
    cdecl, importc: "ggml_set_f32_1d".}
proc ggml_get_f32_nd*(tensor: ptr StructGgmlTensor; i0: cint; i1: cint;
                      i2: cint; i3: cint): cfloat {.cdecl,
    importc: "ggml_get_f32_nd".}
proc ggml_set_f32_nd*(tensor: ptr StructGgmlTensor; i0: cint; i1: cint;
                      i2: cint; i3: cint; value: cfloat): void {.cdecl,
    importc: "ggml_set_f32_nd".}
proc ggml_threadpool_new*(params: ptr StructGgmlThreadpoolParams): ptr StructGgmlThreadpool {.
    cdecl, importc: "ggml_threadpool_new".}
proc ggml_threadpool_free*(threadpool: ptr StructGgmlThreadpool): void {.cdecl,
    importc: "ggml_threadpool_free".}
proc ggml_threadpool_get_n_threads*(threadpool: ptr StructGgmlThreadpool): cint {.
    cdecl, importc: "ggml_threadpool_get_n_threads".}
proc ggml_threadpool_pause*(threadpool: ptr StructGgmlThreadpool): void {.cdecl,
    importc: "ggml_threadpool_pause".}
proc ggml_threadpool_resume*(threadpool: ptr StructGgmlThreadpool): void {.
    cdecl, importc: "ggml_threadpool_resume".}
proc ggml_graph_plan*(cgraph: ptr StructGgmlCgraph; n_threads: cint;
                      threadpool: ptr StructGgmlThreadpool): StructGgmlCplan {.
    cdecl, importc: "ggml_graph_plan".}
proc ggml_graph_compute*(cgraph: ptr StructGgmlCgraph;
                         cplan: ptr StructGgmlCplan): EnumGgmlStatus {.cdecl,
    importc: "ggml_graph_compute".}
proc ggml_graph_compute_with_ctx*(ctx: ptr StructGgmlContext;
                                  cgraph: ptr StructGgmlCgraph; n_threads: cint): EnumGgmlStatus {.
    cdecl, importc: "ggml_graph_compute_with_ctx".}
proc ggml_cpu_has_sse3*(): cint {.cdecl, importc: "ggml_cpu_has_sse3".}
proc ggml_cpu_has_ssse3*(): cint {.cdecl, importc: "ggml_cpu_has_ssse3".}
proc ggml_cpu_has_avx*(): cint {.cdecl, importc: "ggml_cpu_has_avx".}
proc ggml_cpu_has_avx_vnni*(): cint {.cdecl, importc: "ggml_cpu_has_avx_vnni".}
proc ggml_cpu_has_avx2*(): cint {.cdecl, importc: "ggml_cpu_has_avx2".}
proc ggml_cpu_has_bmi2*(): cint {.cdecl, importc: "ggml_cpu_has_bmi2".}
proc ggml_cpu_has_f16c*(): cint {.cdecl, importc: "ggml_cpu_has_f16c".}
proc ggml_cpu_has_fma*(): cint {.cdecl, importc: "ggml_cpu_has_fma".}
proc ggml_cpu_has_avx512*(): cint {.cdecl, importc: "ggml_cpu_has_avx512".}
proc ggml_cpu_has_avx512_vbmi*(): cint {.cdecl,
    importc: "ggml_cpu_has_avx512_vbmi".}
proc ggml_cpu_has_avx512_vnni*(): cint {.cdecl,
    importc: "ggml_cpu_has_avx512_vnni".}
proc ggml_cpu_has_avx512_bf16*(): cint {.cdecl,
    importc: "ggml_cpu_has_avx512_bf16".}
proc ggml_cpu_has_amx_int8*(): cint {.cdecl, importc: "ggml_cpu_has_amx_int8".}
proc ggml_cpu_has_neon*(): cint {.cdecl, importc: "ggml_cpu_has_neon".}
proc ggml_cpu_has_arm_fma*(): cint {.cdecl, importc: "ggml_cpu_has_arm_fma".}
proc ggml_cpu_has_fp16_va*(): cint {.cdecl, importc: "ggml_cpu_has_fp16_va".}
proc ggml_cpu_has_dotprod*(): cint {.cdecl, importc: "ggml_cpu_has_dotprod".}
proc ggml_cpu_has_matmul_int8*(): cint {.cdecl,
    importc: "ggml_cpu_has_matmul_int8".}
proc ggml_cpu_has_sve*(): cint {.cdecl, importc: "ggml_cpu_has_sve".}
proc ggml_cpu_get_sve_cnt*(): cint {.cdecl, importc: "ggml_cpu_get_sve_cnt".}
proc ggml_cpu_has_sme*(): cint {.cdecl, importc: "ggml_cpu_has_sme".}
proc ggml_cpu_has_riscv_v*(): cint {.cdecl, importc: "ggml_cpu_has_riscv_v".}
proc ggml_cpu_has_vsx*(): cint {.cdecl, importc: "ggml_cpu_has_vsx".}
proc ggml_cpu_has_vxe*(): cint {.cdecl, importc: "ggml_cpu_has_vxe".}
proc ggml_cpu_has_wasm_simd*(): cint {.cdecl, importc: "ggml_cpu_has_wasm_simd".}
proc ggml_cpu_has_llamafile*(): cint {.cdecl, importc: "ggml_cpu_has_llamafile".}
proc ggml_get_type_traits_cpu*(type_arg: EnumGgmlType): ptr StructGgmlTypeTraitsCpu {.
    cdecl, importc: "ggml_get_type_traits_cpu".}
proc ggml_cpu_init*(): void {.cdecl, importc: "ggml_cpu_init".}
proc ggml_backend_cpu_init*(): GgmlBackendT {.cdecl,
    importc: "ggml_backend_cpu_init".}
proc ggml_backend_is_cpu*(backend: GgmlBackendT): bool {.cdecl,
    importc: "ggml_backend_is_cpu".}
proc ggml_backend_cpu_set_n_threads*(backend_cpu: GgmlBackendT; n_threads: cint): void {.
    cdecl, importc: "ggml_backend_cpu_set_n_threads".}
proc ggml_backend_cpu_set_threadpool*(backend_cpu: GgmlBackendT;
                                      threadpool: GgmlThreadpoolT): void {.
    cdecl, importc: "ggml_backend_cpu_set_threadpool".}
proc ggml_backend_cpu_set_abort_callback*(backend_cpu: GgmlBackendT;
    abort_callback: GgmlAbortCallback; abort_callback_data: pointer): void {.
    cdecl, importc: "ggml_backend_cpu_set_abort_callback".}
proc ggml_backend_cpu_reg*(): GgmlBackendRegT {.cdecl,
    importc: "ggml_backend_cpu_reg".}
proc ggml_cpu_fp32_to_fp16*(a0: ptr cfloat; a1: ptr GgmlFp16T; a2: int64): void {.
    cdecl, importc: "ggml_cpu_fp32_to_fp16".}
proc ggml_cpu_fp16_to_fp32*(a0: ptr GgmlFp16T; a1: ptr cfloat; a2: int64): void {.
    cdecl, importc: "ggml_cpu_fp16_to_fp32".}
proc ggml_cpu_fp32_to_bf16*(a0: ptr cfloat; a1: ptr GgmlBf16T; a2: int64): void {.
    cdecl, importc: "ggml_cpu_fp32_to_bf16".}
proc ggml_cpu_bf16_to_fp32*(a0: ptr GgmlBf16T; a1: ptr cfloat; a2: int64): void {.
    cdecl, importc: "ggml_cpu_bf16_to_fp32".}
proc ggml_opt_dataset_init*(type_data: EnumGgmlType; type_label: EnumGgmlType;
                            ne_datapoint: int64; ne_label: int64; ndata: int64;
                            ndata_shard: int64): GgmlOptDatasetT {.cdecl,
    importc: "ggml_opt_dataset_init".}
proc ggml_opt_dataset_free*(dataset: GgmlOptDatasetT): void {.cdecl,
    importc: "ggml_opt_dataset_free".}
proc ggml_opt_dataset_ndata*(dataset: GgmlOptDatasetT): int64 {.cdecl,
    importc: "ggml_opt_dataset_ndata".}
proc ggml_opt_dataset_data*(dataset: GgmlOptDatasetT): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_opt_dataset_data".}
proc ggml_opt_dataset_labels*(dataset: GgmlOptDatasetT): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_opt_dataset_labels".}
proc ggml_opt_dataset_shuffle*(opt_ctx: GgmlOptContextT;
                               dataset: GgmlOptDatasetT; idata: int64): void {.
    cdecl, importc: "ggml_opt_dataset_shuffle".}
proc ggml_opt_dataset_get_batch*(dataset: GgmlOptDatasetT;
                                 data_batch: ptr StructGgmlTensor;
                                 labels_batch: ptr StructGgmlTensor;
                                 ibatch: int64): void {.cdecl,
    importc: "ggml_opt_dataset_get_batch".}
proc ggml_opt_dataset_get_batch_host*(dataset: GgmlOptDatasetT;
                                      data_batch: pointer;
                                      nb_data_batch: csize_t;
                                      labels_batch: pointer; ibatch: int64): void {.
    cdecl, importc: "ggml_opt_dataset_get_batch_host".}
proc ggml_opt_get_default_optimizer_params*(userdata: pointer): StructGgmlOptOptimizerParams {.
    cdecl, importc: "ggml_opt_get_default_optimizer_params".}
proc ggml_opt_get_constant_optimizer_params*(userdata: pointer): StructGgmlOptOptimizerParams {.
    cdecl, importc: "ggml_opt_get_constant_optimizer_params".}
proc ggml_opt_default_params*(backend_sched: GgmlBackendSchedT;
                              loss_type: EnumGgmlOptLossType): StructGgmlOptParams {.
    cdecl, importc: "ggml_opt_default_params".}
proc ggml_opt_init*(params: StructGgmlOptParams): GgmlOptContextT {.cdecl,
    importc: "ggml_opt_init".}
proc ggml_opt_free*(opt_ctx: GgmlOptContextT): void {.cdecl,
    importc: "ggml_opt_free".}
proc ggml_opt_reset*(opt_ctx: GgmlOptContextT; optimizer: bool): void {.cdecl,
    importc: "ggml_opt_reset".}
proc ggml_opt_inputs*(opt_ctx: GgmlOptContextT): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_opt_inputs".}
proc ggml_opt_outputs*(opt_ctx: GgmlOptContextT): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_opt_outputs".}
proc ggml_opt_labels*(opt_ctx: GgmlOptContextT): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_opt_labels".}
proc ggml_opt_loss*(opt_ctx: GgmlOptContextT): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_opt_loss".}
proc ggml_opt_pred*(opt_ctx: GgmlOptContextT): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_opt_pred".}
proc ggml_opt_ncorrect*(opt_ctx: GgmlOptContextT): ptr StructGgmlTensor {.cdecl,
    importc: "ggml_opt_ncorrect".}
proc ggml_opt_grad_acc*(opt_ctx: GgmlOptContextT; node: ptr StructGgmlTensor): ptr StructGgmlTensor {.
    cdecl, importc: "ggml_opt_grad_acc".}
proc ggml_opt_result_init*(): GgmlOptResultT {.cdecl,
    importc: "ggml_opt_result_init".}
proc ggml_opt_result_free*(result: GgmlOptResultT): void {.cdecl,
    importc: "ggml_opt_result_free".}
proc ggml_opt_result_reset*(result: GgmlOptResultT): void {.cdecl,
    importc: "ggml_opt_result_reset".}
proc ggml_opt_result_ndata*(result: GgmlOptResultT; ndata: ptr int64): void {.
    cdecl, importc: "ggml_opt_result_ndata".}
proc ggml_opt_result_loss*(result: GgmlOptResultT; loss: ptr cdouble;
                           unc: ptr cdouble): void {.cdecl,
    importc: "ggml_opt_result_loss".}
proc ggml_opt_result_pred*(result: GgmlOptResultT; pred: ptr int32): void {.
    cdecl, importc: "ggml_opt_result_pred".}
proc ggml_opt_result_accuracy*(result: GgmlOptResultT; accuracy: ptr cdouble;
                               unc: ptr cdouble): void {.cdecl,
    importc: "ggml_opt_result_accuracy".}
proc ggml_opt_prepare_alloc*(opt_ctx: GgmlOptContextT;
                             ctx_compute: ptr StructGgmlContext;
                             gf: ptr StructGgmlCgraph;
                             inputs: ptr StructGgmlTensor;
                             outputs: ptr StructGgmlTensor): void {.cdecl,
    importc: "ggml_opt_prepare_alloc".}
proc ggml_opt_alloc*(opt_ctx: GgmlOptContextT; backward: bool): void {.cdecl,
    importc: "ggml_opt_alloc".}
proc ggml_opt_eval*(opt_ctx: GgmlOptContextT; result: GgmlOptResultT): void {.
    cdecl, importc: "ggml_opt_eval".}
proc ggml_opt_epoch*(opt_ctx: GgmlOptContextT; dataset: GgmlOptDatasetT;
                     result_train: GgmlOptResultT; result_eval: GgmlOptResultT;
                     idata_split: int64; callback_train: GgmlOptEpochCallback;
                     callback_eval: GgmlOptEpochCallback): void {.cdecl,
    importc: "ggml_opt_epoch".}
proc ggml_opt_epoch_callback_progress_bar*(train: bool;
    opt_ctx: GgmlOptContextT; dataset: GgmlOptDatasetT; result: GgmlOptResultT;
    ibatch: int64; ibatch_max: int64; t_start_us: int64): void {.cdecl,
    importc: "ggml_opt_epoch_callback_progress_bar".}
proc ggml_opt_fit*(backend_sched: GgmlBackendSchedT;
                   ctx_compute: ptr StructGgmlContext;
                   inputs: ptr StructGgmlTensor; outputs: ptr StructGgmlTensor;
                   dataset: GgmlOptDatasetT; loss_type: EnumGgmlOptLossType;
                   get_opt_pars: GgmlOptGetOptimizerParams; nepoch: int64;
                   nbatch_logical: int64; val_split: cfloat; silent: bool): void {.
    cdecl, importc: "ggml_opt_fit".}
proc llama_model_default_params*(): StructLlamaModelParams {.cdecl,
    importc: "llama_model_default_params".}
proc llama_context_default_params*(): StructLlamaContextParams {.cdecl,
    importc: "llama_context_default_params".}
proc llama_sampler_chain_default_params*(): StructLlamaSamplerChainParams {.
    cdecl, importc: "llama_sampler_chain_default_params".}
proc llama_model_quantize_default_params*(): StructLlamaModelQuantizeParams {.
    cdecl, importc: "llama_model_quantize_default_params".}
proc llama_backend_init*(): void {.cdecl, importc: "llama_backend_init".}
proc llama_backend_free*(): void {.cdecl, importc: "llama_backend_free".}
proc llama_numa_init*(numa: EnumGgmlNumaStrategy): void {.cdecl,
    importc: "llama_numa_init".}
proc llama_attach_threadpool*(ctx: ptr StructLlamaContext;
                              threadpool: GgmlThreadpoolT;
                              threadpool_batch: GgmlThreadpoolT): void {.cdecl,
    importc: "llama_attach_threadpool".}
proc llama_detach_threadpool*(ctx: ptr StructLlamaContext): void {.cdecl,
    importc: "llama_detach_threadpool".}
proc llama_load_model_from_file*(path_model: cstring;
                                 params: StructLlamaModelParams): ptr StructLlamaModel {.
    cdecl, importc: "llama_load_model_from_file".}
proc llama_model_load_from_file*(path_model: cstring;
                                 params: StructLlamaModelParams): ptr StructLlamaModel {.
    cdecl, importc: "llama_model_load_from_file".}
proc llama_model_load_from_splits*(paths: ptr cstring; n_paths: csize_t;
                                   params: StructLlamaModelParams): ptr StructLlamaModel {.
    cdecl, importc: "llama_model_load_from_splits".}
proc llama_model_save_to_file*(model: ptr StructLlamaModel; path_model: cstring): void {.
    cdecl, importc: "llama_model_save_to_file".}
proc llama_free_model*(model: ptr StructLlamaModel): void {.cdecl,
    importc: "llama_free_model".}
proc llama_model_free*(model: ptr StructLlamaModel): void {.cdecl,
    importc: "llama_model_free".}
proc llama_init_from_model*(model: ptr StructLlamaModel;
                            params: StructLlamaContextParams): ptr StructLlamaContext {.
    cdecl, importc: "llama_init_from_model".}
proc llama_new_context_with_model*(model: ptr StructLlamaModel;
                                   params: StructLlamaContextParams): ptr StructLlamaContext {.
    cdecl, importc: "llama_new_context_with_model".}
proc llama_free*(ctx: ptr StructLlamaContext): void {.cdecl,
    importc: "llama_free".}
proc llama_time_us*(): int64 {.cdecl, importc: "llama_time_us".}
proc llama_max_devices*(): csize_t {.cdecl, importc: "llama_max_devices".}
proc llama_supports_mmap*(): bool {.cdecl, importc: "llama_supports_mmap".}
proc llama_supports_mlock*(): bool {.cdecl, importc: "llama_supports_mlock".}
proc llama_supports_gpu_offload*(): bool {.cdecl,
    importc: "llama_supports_gpu_offload".}
proc llama_supports_rpc*(): bool {.cdecl, importc: "llama_supports_rpc".}
proc llama_n_ctx*(ctx: ptr StructLlamaContext): uint32 {.cdecl,
    importc: "llama_n_ctx".}
proc llama_n_batch*(ctx: ptr StructLlamaContext): uint32 {.cdecl,
    importc: "llama_n_batch".}
proc llama_n_ubatch*(ctx: ptr StructLlamaContext): uint32 {.cdecl,
    importc: "llama_n_ubatch".}
proc llama_n_seq_max*(ctx: ptr StructLlamaContext): uint32 {.cdecl,
    importc: "llama_n_seq_max".}
proc llama_n_ctx_train*(model: ptr StructLlamaModel): int32 {.cdecl,
    importc: "llama_n_ctx_train".}
proc llama_n_embd*(model: ptr StructLlamaModel): int32 {.cdecl,
    importc: "llama_n_embd".}
proc llama_n_layer*(model: ptr StructLlamaModel): int32 {.cdecl,
    importc: "llama_n_layer".}
proc llama_n_head*(model: ptr StructLlamaModel): int32 {.cdecl,
    importc: "llama_n_head".}
proc llama_n_vocab*(vocab: ptr StructLlamaVocab): int32 {.cdecl,
    importc: "llama_n_vocab".}
proc llama_get_model*(ctx: ptr StructLlamaContext): ptr StructLlamaModel {.
    cdecl, importc: "llama_get_model".}
proc llama_get_kv_self*(ctx: ptr StructLlamaContext): ptr StructLlamaKvCache {.
    cdecl, importc: "llama_get_kv_self".}
proc llama_pooling_type*(ctx: ptr StructLlamaContext): EnumLlamaPoolingType {.
    cdecl, importc: "llama_pooling_type".}
proc llama_model_get_vocab*(model: ptr StructLlamaModel): ptr StructLlamaVocab {.
    cdecl, importc: "llama_model_get_vocab".}
proc llama_model_rope_type*(model: ptr StructLlamaModel): EnumLlamaRopeType {.
    cdecl, importc: "llama_model_rope_type".}
proc llama_model_n_ctx_train*(model: ptr StructLlamaModel): int32 {.cdecl,
    importc: "llama_model_n_ctx_train".}
proc llama_model_n_embd*(model: ptr StructLlamaModel): int32 {.cdecl,
    importc: "llama_model_n_embd".}
proc llama_model_n_layer*(model: ptr StructLlamaModel): int32 {.cdecl,
    importc: "llama_model_n_layer".}
proc llama_model_n_head*(model: ptr StructLlamaModel): int32 {.cdecl,
    importc: "llama_model_n_head".}
proc llama_model_n_head_kv*(model: ptr StructLlamaModel): int32 {.cdecl,
    importc: "llama_model_n_head_kv".}
proc llama_model_rope_freq_scale_train*(model: ptr StructLlamaModel): cfloat {.
    cdecl, importc: "llama_model_rope_freq_scale_train".}
proc llama_vocab_type*(vocab: ptr StructLlamaVocab): EnumLlamaVocabType {.cdecl,
    importc: "llama_vocab_type".}
proc llama_vocab_n_tokens*(vocab: ptr StructLlamaVocab): int32 {.cdecl,
    importc: "llama_vocab_n_tokens".}
proc llama_model_meta_val_str*(model: ptr StructLlamaModel; key: cstring;
                               buf: cstring; buf_size: csize_t): int32 {.cdecl,
    importc: "llama_model_meta_val_str".}
proc llama_model_meta_count*(model: ptr StructLlamaModel): int32 {.cdecl,
    importc: "llama_model_meta_count".}
proc llama_model_meta_key_by_index*(model: ptr StructLlamaModel; i: int32;
                                    buf: cstring; buf_size: csize_t): int32 {.
    cdecl, importc: "llama_model_meta_key_by_index".}
proc llama_model_meta_val_str_by_index*(model: ptr StructLlamaModel; i: int32;
                                        buf: cstring; buf_size: csize_t): int32 {.
    cdecl, importc: "llama_model_meta_val_str_by_index".}
proc llama_model_desc*(model: ptr StructLlamaModel; buf: cstring;
                       buf_size: csize_t): int32 {.cdecl,
    importc: "llama_model_desc".}
proc llama_model_size*(model: ptr StructLlamaModel): uint64 {.cdecl,
    importc: "llama_model_size".}
proc llama_model_chat_template*(model: ptr StructLlamaModel; name: cstring): cstring {.
    cdecl, importc: "llama_model_chat_template".}
proc llama_model_n_params*(model: ptr StructLlamaModel): uint64 {.cdecl,
    importc: "llama_model_n_params".}
proc llama_model_has_encoder*(model: ptr StructLlamaModel): bool {.cdecl,
    importc: "llama_model_has_encoder".}
proc llama_model_has_decoder*(model: ptr StructLlamaModel): bool {.cdecl,
    importc: "llama_model_has_decoder".}
proc llama_model_decoder_start_token*(model: ptr StructLlamaModel): LlamaToken {.
    cdecl, importc: "llama_model_decoder_start_token".}
proc llama_model_is_recurrent*(model: ptr StructLlamaModel): bool {.cdecl,
    importc: "llama_model_is_recurrent".}
proc llama_model_quantize*(fname_inp: cstring; fname_out: cstring;
                           params: ptr LlamaModelQuantizeParams): uint32 {.
    cdecl, importc: "llama_model_quantize".}
proc llama_adapter_lora_init*(model: ptr StructLlamaModel; path_lora: cstring): ptr StructLlamaAdapterLora {.
    cdecl, importc: "llama_adapter_lora_init".}
proc llama_adapter_lora_free*(adapter: ptr StructLlamaAdapterLora): void {.
    cdecl, importc: "llama_adapter_lora_free".}
proc llama_set_adapter_lora*(ctx: ptr StructLlamaContext;
                             adapter: ptr StructLlamaAdapterLora; scale: cfloat): int32 {.
    cdecl, importc: "llama_set_adapter_lora".}
proc llama_rm_adapter_lora*(ctx: ptr StructLlamaContext;
                            adapter: ptr StructLlamaAdapterLora): int32 {.cdecl,
    importc: "llama_rm_adapter_lora".}
proc llama_clear_adapter_lora*(ctx: ptr StructLlamaContext): void {.cdecl,
    importc: "llama_clear_adapter_lora".}
proc llama_apply_adapter_cvec*(ctx: ptr StructLlamaContext; data: ptr cfloat;
                               len: csize_t; n_embd: int32; il_start: int32;
                               il_end: int32): int32 {.cdecl,
    importc: "llama_apply_adapter_cvec".}
proc llama_kv_cache_view_init*(ctx: ptr StructLlamaContext; n_seq_max: int32): StructLlamaKvCacheView {.
    cdecl, importc: "llama_kv_cache_view_init".}
proc llama_kv_cache_view_free*(view: ptr StructLlamaKvCacheView): void {.cdecl,
    importc: "llama_kv_cache_view_free".}
proc llama_kv_cache_view_update*(ctx: ptr StructLlamaContext;
                                 view: ptr StructLlamaKvCacheView): void {.
    cdecl, importc: "llama_kv_cache_view_update".}
proc llama_kv_self_n_tokens*(ctx: ptr StructLlamaContext): int32 {.cdecl,
    importc: "llama_kv_self_n_tokens".}
proc llama_get_kv_cache_token_count*(ctx: ptr StructLlamaContext): int32 {.
    cdecl, importc: "llama_get_kv_cache_token_count".}
proc llama_kv_self_used_cells*(ctx: ptr StructLlamaContext): int32 {.cdecl,
    importc: "llama_kv_self_used_cells".}
proc llama_get_kv_cache_used_cells*(ctx: ptr StructLlamaContext): int32 {.cdecl,
    importc: "llama_get_kv_cache_used_cells".}
proc llama_kv_self_clear*(ctx: ptr StructLlamaContext): void {.cdecl,
    importc: "llama_kv_self_clear".}
proc llama_kv_self_seq_rm*(ctx: ptr StructLlamaContext; seq_id: LlamaSeqId;
                           p0: LlamaPos; p1: LlamaPos): bool {.cdecl,
    importc: "llama_kv_self_seq_rm".}
proc llama_kv_self_seq_cp*(ctx: ptr StructLlamaContext; seq_id_src: LlamaSeqId;
                           seq_id_dst: LlamaSeqId; p0: LlamaPos; p1: LlamaPos): void {.
    cdecl, importc: "llama_kv_self_seq_cp".}
proc llama_kv_self_seq_keep*(ctx: ptr StructLlamaContext; seq_id: LlamaSeqId): void {.
    cdecl, importc: "llama_kv_self_seq_keep".}
proc llama_kv_self_seq_add*(ctx: ptr StructLlamaContext; seq_id: LlamaSeqId;
                            p0: LlamaPos; p1: LlamaPos; delta: LlamaPos): void {.
    cdecl, importc: "llama_kv_self_seq_add".}
proc llama_kv_self_seq_div*(ctx: ptr StructLlamaContext; seq_id: LlamaSeqId;
                            p0: LlamaPos; p1: LlamaPos; d: cint): void {.cdecl,
    importc: "llama_kv_self_seq_div".}
proc llama_kv_self_seq_pos_max*(ctx: ptr StructLlamaContext; seq_id: LlamaSeqId): LlamaPos {.
    cdecl, importc: "llama_kv_self_seq_pos_max".}
proc llama_kv_self_defrag*(ctx: ptr StructLlamaContext): void {.cdecl,
    importc: "llama_kv_self_defrag".}
proc llama_kv_self_can_shift*(ctx: ptr StructLlamaContext): bool {.cdecl,
    importc: "llama_kv_self_can_shift".}
proc llama_kv_self_update*(ctx: ptr StructLlamaContext): void {.cdecl,
    importc: "llama_kv_self_update".}
proc llama_kv_cache_clear*(ctx: ptr StructLlamaContext): void {.cdecl,
    importc: "llama_kv_cache_clear".}
proc llama_kv_cache_seq_rm*(ctx: ptr StructLlamaContext; seq_id: LlamaSeqId;
                            p0: LlamaPos; p1: LlamaPos): bool {.cdecl,
    importc: "llama_kv_cache_seq_rm".}
proc llama_kv_cache_seq_cp*(ctx: ptr StructLlamaContext; seq_id_src: LlamaSeqId;
                            seq_id_dst: LlamaSeqId; p0: LlamaPos; p1: LlamaPos): void {.
    cdecl, importc: "llama_kv_cache_seq_cp".}
proc llama_kv_cache_seq_keep*(ctx: ptr StructLlamaContext; seq_id: LlamaSeqId): void {.
    cdecl, importc: "llama_kv_cache_seq_keep".}
proc llama_kv_cache_seq_add*(ctx: ptr StructLlamaContext; seq_id: LlamaSeqId;
                             p0: LlamaPos; p1: LlamaPos; delta: LlamaPos): void {.
    cdecl, importc: "llama_kv_cache_seq_add".}
proc llama_kv_cache_seq_div*(ctx: ptr StructLlamaContext; seq_id: LlamaSeqId;
                             p0: LlamaPos; p1: LlamaPos; d: cint): void {.cdecl,
    importc: "llama_kv_cache_seq_div".}
proc llama_kv_cache_seq_pos_max*(ctx: ptr StructLlamaContext; seq_id: LlamaSeqId): LlamaPos {.
    cdecl, importc: "llama_kv_cache_seq_pos_max".}
proc llama_kv_cache_defrag*(ctx: ptr StructLlamaContext): void {.cdecl,
    importc: "llama_kv_cache_defrag".}
proc llama_kv_cache_can_shift*(ctx: ptr StructLlamaContext): bool {.cdecl,
    importc: "llama_kv_cache_can_shift".}
proc llama_kv_cache_update*(ctx: ptr StructLlamaContext): void {.cdecl,
    importc: "llama_kv_cache_update".}
proc llama_state_get_size*(ctx: ptr StructLlamaContext): csize_t {.cdecl,
    importc: "llama_state_get_size".}
proc llama_get_state_size*(ctx: ptr StructLlamaContext): csize_t {.cdecl,
    importc: "llama_get_state_size".}
proc llama_state_get_data*(ctx: ptr StructLlamaContext; dst: ptr uint8;
                           size: csize_t): csize_t {.cdecl,
    importc: "llama_state_get_data".}
proc llama_copy_state_data*(ctx: ptr StructLlamaContext; dst: ptr uint8): csize_t {.
    cdecl, importc: "llama_copy_state_data".}
proc llama_state_set_data*(ctx: ptr StructLlamaContext; src: ptr uint8;
                           size: csize_t): csize_t {.cdecl,
    importc: "llama_state_set_data".}
proc llama_set_state_data*(ctx: ptr StructLlamaContext; src: ptr uint8): csize_t {.
    cdecl, importc: "llama_set_state_data".}
proc llama_state_load_file*(ctx: ptr StructLlamaContext; path_session: cstring;
                            tokens_out: ptr LlamaToken;
                            n_token_capacity: csize_t;
                            n_token_count_out: ptr csize_t): bool {.cdecl,
    importc: "llama_state_load_file".}
proc llama_load_session_file*(ctx: ptr StructLlamaContext;
                              path_session: cstring; tokens_out: ptr LlamaToken;
                              n_token_capacity: csize_t;
                              n_token_count_out: ptr csize_t): bool {.cdecl,
    importc: "llama_load_session_file".}
proc llama_state_save_file*(ctx: ptr StructLlamaContext; path_session: cstring;
                            tokens: ptr LlamaToken; n_token_count: csize_t): bool {.
    cdecl, importc: "llama_state_save_file".}
proc llama_save_session_file*(ctx: ptr StructLlamaContext;
                              path_session: cstring; tokens: ptr LlamaToken;
                              n_token_count: csize_t): bool {.cdecl,
    importc: "llama_save_session_file".}
proc llama_state_seq_get_size*(ctx: ptr StructLlamaContext; seq_id: LlamaSeqId): csize_t {.
    cdecl, importc: "llama_state_seq_get_size".}
proc llama_state_seq_get_data*(ctx: ptr StructLlamaContext; dst: ptr uint8;
                               size: csize_t; seq_id: LlamaSeqId): csize_t {.
    cdecl, importc: "llama_state_seq_get_data".}
proc llama_state_seq_set_data*(ctx: ptr StructLlamaContext; src: ptr uint8;
                               size: csize_t; dest_seq_id: LlamaSeqId): csize_t {.
    cdecl, importc: "llama_state_seq_set_data".}
proc llama_state_seq_save_file*(ctx: ptr StructLlamaContext; filepath: cstring;
                                seq_id: LlamaSeqId; tokens: ptr LlamaToken;
                                n_token_count: csize_t): csize_t {.cdecl,
    importc: "llama_state_seq_save_file".}
proc llama_state_seq_load_file*(ctx: ptr StructLlamaContext; filepath: cstring;
                                dest_seq_id: LlamaSeqId;
                                tokens_out: ptr LlamaToken;
                                n_token_capacity: csize_t;
                                n_token_count_out: ptr csize_t): csize_t {.
    cdecl, importc: "llama_state_seq_load_file".}
proc llama_batch_get_one*(tokens: ptr LlamaToken; n_tokens: int32): StructLlamaBatch {.
    cdecl, importc: "llama_batch_get_one".}
proc llama_batch_init*(n_tokens: int32; embd: int32; n_seq_max: int32): StructLlamaBatch {.
    cdecl, importc: "llama_batch_init".}
proc llama_batch_free*(batch: StructLlamaBatch): void {.cdecl,
    importc: "llama_batch_free".}
proc llama_encode*(ctx: ptr StructLlamaContext; batch: StructLlamaBatch): int32 {.
    cdecl, importc: "llama_encode".}
proc llama_decode*(ctx: ptr StructLlamaContext; batch: StructLlamaBatch): int32 {.
    cdecl, importc: "llama_decode".}
proc llama_set_n_threads*(ctx: ptr StructLlamaContext; n_threads: int32;
                          n_threads_batch: int32): void {.cdecl,
    importc: "llama_set_n_threads".}
proc llama_n_threads*(ctx: ptr StructLlamaContext): int32 {.cdecl,
    importc: "llama_n_threads".}
proc llama_n_threads_batch*(ctx: ptr StructLlamaContext): int32 {.cdecl,
    importc: "llama_n_threads_batch".}
proc llama_set_embeddings*(ctx: ptr StructLlamaContext; embeddings: bool): void {.
    cdecl, importc: "llama_set_embeddings".}
proc llama_set_causal_attn*(ctx: ptr StructLlamaContext; causal_attn: bool): void {.
    cdecl, importc: "llama_set_causal_attn".}
proc llama_set_warmup*(ctx: ptr StructLlamaContext; warmup: bool): void {.cdecl,
    importc: "llama_set_warmup".}
proc llama_set_abort_callback*(ctx: ptr StructLlamaContext;
                               abort_callback: GgmlAbortCallback;
                               abort_callback_data: pointer): void {.cdecl,
    importc: "llama_set_abort_callback".}
proc llama_synchronize*(ctx: ptr StructLlamaContext): void {.cdecl,
    importc: "llama_synchronize".}
proc llama_get_logits*(ctx: ptr StructLlamaContext): ptr cfloat {.cdecl,
    importc: "llama_get_logits".}
proc llama_get_logits_ith*(ctx: ptr StructLlamaContext; i: int32): ptr cfloat {.
    cdecl, importc: "llama_get_logits_ith".}
proc llama_get_embeddings*(ctx: ptr StructLlamaContext): ptr cfloat {.cdecl,
    importc: "llama_get_embeddings".}
proc llama_get_embeddings_ith*(ctx: ptr StructLlamaContext; i: int32): ptr cfloat {.
    cdecl, importc: "llama_get_embeddings_ith".}
proc llama_get_embeddings_seq*(ctx: ptr StructLlamaContext; seq_id: LlamaSeqId): ptr cfloat {.
    cdecl, importc: "llama_get_embeddings_seq".}
proc llama_vocab_get_text*(vocab: ptr StructLlamaVocab; token: LlamaToken): cstring {.
    cdecl, importc: "llama_vocab_get_text".}
proc llama_vocab_get_score*(vocab: ptr StructLlamaVocab; token: LlamaToken): cfloat {.
    cdecl, importc: "llama_vocab_get_score".}
proc llama_vocab_get_attr*(vocab: ptr StructLlamaVocab; token: LlamaToken): EnumLlamaTokenAttr {.
    cdecl, importc: "llama_vocab_get_attr".}
proc llama_vocab_is_eog*(vocab: ptr StructLlamaVocab; token: LlamaToken): bool {.
    cdecl, importc: "llama_vocab_is_eog".}
proc llama_vocab_is_control*(vocab: ptr StructLlamaVocab; token: LlamaToken): bool {.
    cdecl, importc: "llama_vocab_is_control".}
proc llama_vocab_bos*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_vocab_bos".}
proc llama_vocab_eos*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_vocab_eos".}
proc llama_vocab_eot*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_vocab_eot".}
proc llama_vocab_sep*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_vocab_sep".}
proc llama_vocab_nl*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_vocab_nl".}
proc llama_vocab_pad*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_vocab_pad".}
proc llama_vocab_get_add_bos*(vocab: ptr StructLlamaVocab): bool {.cdecl,
    importc: "llama_vocab_get_add_bos".}
proc llama_vocab_get_add_eos*(vocab: ptr StructLlamaVocab): bool {.cdecl,
    importc: "llama_vocab_get_add_eos".}
proc llama_vocab_fim_pre*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_vocab_fim_pre".}
proc llama_vocab_fim_suf*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_vocab_fim_suf".}
proc llama_vocab_fim_mid*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_vocab_fim_mid".}
proc llama_vocab_fim_pad*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_vocab_fim_pad".}
proc llama_vocab_fim_rep*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_vocab_fim_rep".}
proc llama_vocab_fim_sep*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_vocab_fim_sep".}
proc llama_token_get_text*(vocab: ptr StructLlamaVocab; token: LlamaToken): cstring {.
    cdecl, importc: "llama_token_get_text".}
proc llama_token_get_score*(vocab: ptr StructLlamaVocab; token: LlamaToken): cfloat {.
    cdecl, importc: "llama_token_get_score".}
proc llama_token_get_attr*(vocab: ptr StructLlamaVocab; token: LlamaToken): EnumLlamaTokenAttr {.
    cdecl, importc: "llama_token_get_attr".}
proc llama_token_is_eog*(vocab: ptr StructLlamaVocab; token: LlamaToken): bool {.
    cdecl, importc: "llama_token_is_eog".}
proc llama_token_is_control*(vocab: ptr StructLlamaVocab; token: LlamaToken): bool {.
    cdecl, importc: "llama_token_is_control".}
proc llama_token_bos*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_token_bos".}
proc llama_token_eos*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_token_eos".}
proc llama_token_eot*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_token_eot".}
proc llama_token_cls*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_token_cls".}
proc llama_token_sep*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_token_sep".}
proc llama_token_nl*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_token_nl".}
proc llama_token_pad*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_token_pad".}
proc llama_add_bos_token*(vocab: ptr StructLlamaVocab): bool {.cdecl,
    importc: "llama_add_bos_token".}
proc llama_add_eos_token*(vocab: ptr StructLlamaVocab): bool {.cdecl,
    importc: "llama_add_eos_token".}
proc llama_token_fim_pre*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_token_fim_pre".}
proc llama_token_fim_suf*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_token_fim_suf".}
proc llama_token_fim_mid*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_token_fim_mid".}
proc llama_token_fim_pad*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_token_fim_pad".}
proc llama_token_fim_rep*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_token_fim_rep".}
proc llama_token_fim_sep*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_token_fim_sep".}
proc llama_vocab_cls*(vocab: ptr StructLlamaVocab): LlamaToken {.cdecl,
    importc: "llama_vocab_cls".}
proc llama_tokenize*(vocab: ptr StructLlamaVocab; text: cstring;
                     text_len: int32; tokens: ptr LlamaToken;
                     n_tokens_max: int32; add_special: bool; parse_special: bool): int32 {.
    cdecl, importc: "llama_tokenize".}
proc llama_token_to_piece*(vocab: ptr StructLlamaVocab; token: LlamaToken;
                           buf: cstring; length: int32; lstrip: int32;
                           special: bool): int32 {.cdecl,
    importc: "llama_token_to_piece".}
proc llama_detokenize*(vocab: ptr StructLlamaVocab; tokens: ptr LlamaToken;
                       n_tokens: int32; text: cstring; text_len_max: int32;
                       remove_special: bool; unparse_special: bool): int32 {.
    cdecl, importc: "llama_detokenize".}
proc llama_chat_apply_template*(tmpl: cstring; chat: ptr StructLlamaChatMessage;
                                n_msg: csize_t; add_ass: bool; buf: cstring;
                                length: int32): int32 {.cdecl,
    importc: "llama_chat_apply_template".}
proc llama_chat_builtin_templates*(output: ptr cstring; len: csize_t): int32 {.
    cdecl, importc: "llama_chat_builtin_templates".}
proc llama_sampler_init*(iface: ptr StructLlamaSamplerI;
                         ctx: LlamaSamplerContextT): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_init".}
proc llama_sampler_name*(smpl: ptr StructLlamaSampler): cstring {.cdecl,
    importc: "llama_sampler_name".}
proc llama_sampler_accept*(smpl: ptr StructLlamaSampler; token: LlamaToken): void {.
    cdecl, importc: "llama_sampler_accept".}
proc llama_sampler_apply*(smpl: ptr StructLlamaSampler;
                          cur_p: ptr LlamaTokenDataArray): void {.cdecl,
    importc: "llama_sampler_apply".}
proc llama_sampler_reset*(smpl: ptr StructLlamaSampler): void {.cdecl,
    importc: "llama_sampler_reset".}
proc llama_sampler_clone*(smpl: ptr StructLlamaSampler): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_clone".}
proc llama_sampler_free*(smpl: ptr StructLlamaSampler): void {.cdecl,
    importc: "llama_sampler_free".}
proc llama_sampler_chain_init*(params: StructLlamaSamplerChainParams): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_chain_init".}
proc llama_sampler_chain_add*(chain: ptr StructLlamaSampler;
                              smpl: ptr StructLlamaSampler): void {.cdecl,
    importc: "llama_sampler_chain_add".}
proc llama_sampler_chain_get*(chain: ptr StructLlamaSampler; i: int32): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_chain_get".}
proc llama_sampler_chain_n*(chain: ptr StructLlamaSampler): cint {.cdecl,
    importc: "llama_sampler_chain_n".}
proc llama_sampler_chain_remove*(chain: ptr StructLlamaSampler; i: int32): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_chain_remove".}
proc llama_sampler_init_greedy*(): ptr StructLlamaSampler {.cdecl,
    importc: "llama_sampler_init_greedy".}
proc llama_sampler_init_dist*(seed: uint32): ptr StructLlamaSampler {.cdecl,
    importc: "llama_sampler_init_dist".}
proc llama_sampler_init_softmax*(): ptr StructLlamaSampler {.cdecl,
    importc: "llama_sampler_init_softmax".}
proc llama_sampler_init_top_k*(k: int32): ptr StructLlamaSampler {.cdecl,
    importc: "llama_sampler_init_top_k".}
proc llama_sampler_init_top_p*(p: cfloat; min_keep: csize_t): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_init_top_p".}
proc llama_sampler_init_min_p*(p: cfloat; min_keep: csize_t): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_init_min_p".}
proc llama_sampler_init_typical*(p: cfloat; min_keep: csize_t): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_init_typical".}
proc llama_sampler_init_temp*(t: cfloat): ptr StructLlamaSampler {.cdecl,
    importc: "llama_sampler_init_temp".}
proc llama_sampler_init_temp_ext*(t: cfloat; delta: cfloat; exponent: cfloat): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_init_temp_ext".}
proc llama_sampler_init_xtc*(p: cfloat; t: cfloat; min_keep: csize_t;
                             seed: uint32): ptr StructLlamaSampler {.cdecl,
    importc: "llama_sampler_init_xtc".}
proc llama_sampler_init_top_n_sigma*(n: cfloat): ptr StructLlamaSampler {.cdecl,
    importc: "llama_sampler_init_top_n_sigma".}
proc llama_sampler_init_mirostat*(n_vocab: int32; seed: uint32; tau: cfloat;
                                  eta: cfloat; m: int32): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_init_mirostat".}
proc llama_sampler_init_mirostat_v2*(seed: uint32; tau: cfloat; eta: cfloat): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_init_mirostat_v2".}
proc llama_sampler_init_grammar*(vocab: ptr StructLlamaVocab;
                                 grammar_str: cstring; grammar_root: cstring): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_init_grammar".}
proc llama_sampler_init_grammar_lazy*(vocab: ptr StructLlamaVocab;
                                      grammar_str: cstring;
                                      grammar_root: cstring;
                                      trigger_words: ptr cstring;
                                      num_trigger_words: csize_t;
                                      trigger_tokens: ptr LlamaToken;
                                      num_trigger_tokens: csize_t): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_init_grammar_lazy".}
proc llama_sampler_init_grammar_lazy_patterns*(vocab: ptr StructLlamaVocab;
    grammar_str: cstring; grammar_root: cstring; trigger_patterns: ptr cstring;
    num_trigger_patterns: csize_t; trigger_tokens: ptr LlamaToken;
    num_trigger_tokens: csize_t): ptr StructLlamaSampler {.cdecl,
    importc: "llama_sampler_init_grammar_lazy_patterns".}
proc llama_sampler_init_penalties*(penalty_last_n: int32;
                                   penalty_repeat: cfloat; penalty_freq: cfloat;
                                   penalty_present: cfloat): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_init_penalties".}
proc llama_sampler_init_dry*(vocab: ptr StructLlamaVocab; n_ctx_train: int32;
                             dry_multiplier: cfloat; dry_base: cfloat;
                             dry_allowed_length: int32;
                             dry_penalty_last_n: int32;
                             seq_breakers: ptr cstring; num_breakers: csize_t): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_init_dry".}
proc llama_sampler_init_logit_bias*(n_vocab: int32; n_logit_bias: int32;
                                    logit_bias: ptr LlamaLogitBias): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_init_logit_bias".}
proc llama_sampler_init_infill*(vocab: ptr StructLlamaVocab): ptr StructLlamaSampler {.
    cdecl, importc: "llama_sampler_init_infill".}
proc llama_sampler_get_seed*(smpl: ptr StructLlamaSampler): uint32 {.cdecl,
    importc: "llama_sampler_get_seed".}
proc llama_sampler_sample*(smpl: ptr StructLlamaSampler;
                           ctx: ptr StructLlamaContext; idx: int32): LlamaToken {.
    cdecl, importc: "llama_sampler_sample".}
proc llama_split_path*(split_path: cstring; maxlen: csize_t;
                       path_prefix: cstring; split_no: cint; split_count: cint): cint {.
    cdecl, importc: "llama_split_path".}
proc llama_split_prefix*(split_prefix: cstring; maxlen: csize_t;
                         split_path: cstring; split_no: cint; split_count: cint): cint {.
    cdecl, importc: "llama_split_prefix".}
proc llama_print_system_info*(): cstring {.cdecl,
    importc: "llama_print_system_info".}
proc llama_log_set*(log_callback: GgmlLogCallback; user_data: pointer): void {.
    cdecl, importc: "llama_log_set".}
proc llama_perf_context*(ctx: ptr StructLlamaContext): StructLlamaPerfContextData {.
    cdecl, importc: "llama_perf_context".}
proc llama_perf_context_print*(ctx: ptr StructLlamaContext): void {.cdecl,
    importc: "llama_perf_context_print".}
proc llama_perf_context_reset*(ctx: ptr StructLlamaContext): void {.cdecl,
    importc: "llama_perf_context_reset".}
proc llama_perf_sampler*(chain: ptr StructLlamaSampler): StructLlamaPerfSamplerData {.
    cdecl, importc: "llama_perf_sampler".}
proc llama_perf_sampler_print*(chain: ptr StructLlamaSampler): void {.cdecl,
    importc: "llama_perf_sampler_print".}
proc llama_perf_sampler_reset*(chain: ptr StructLlamaSampler): void {.cdecl,
    importc: "llama_perf_sampler_reset".}
proc llama_opt_param_filter_all*(tensor: ptr StructGgmlTensor; userdata: pointer): bool {.
    cdecl, importc: "llama_opt_param_filter_all".}
proc llama_opt_init*(lctx: ptr StructLlamaContext; model: ptr StructLlamaModel;
                     lopt_params: StructLlamaOptParams): void {.cdecl,
    importc: "llama_opt_init".}
proc llama_opt_epoch*(lctx: ptr StructLlamaContext; dataset: GgmlOptDatasetT;
                      result_train: GgmlOptResultT; result_eval: GgmlOptResultT;
                      idata_split: int64; callback_train: GgmlOptEpochCallback;
                      callback_eval: GgmlOptEpochCallback): void {.cdecl,
    importc: "llama_opt_epoch".}