#ifndef EMERALD_LLVM_COMPAT_H
#define EMERALD_LLVM_COMPAT_H

#include <stddef.h>
#include <stdint.h>

typedef struct LLVMOpaqueContext *LLVMContextRef;
typedef struct LLVMOpaqueModule *LLVMModuleRef;
typedef struct LLVMOpaqueType *LLVMTypeRef;
typedef struct LLVMOpaqueValue *LLVMValueRef;
typedef struct LLVMOpaqueBasicBlock *LLVMBasicBlockRef;
typedef struct LLVMOpaqueBuilder *LLVMBuilderRef;
typedef struct LLVMOpaqueTarget *LLVMTargetRef;
typedef struct LLVMOpaqueTargetMachine *LLVMTargetMachineRef;
typedef struct LLVMOpaqueTargetData *LLVMTargetDataRef;
typedef struct LLVMOpaqueError *LLVMErrorRef;
typedef struct LLVMOpaquePassBuilderOptions *LLVMPassBuilderOptionsRef;

typedef enum LLVMVerifierFailureAction {
    LLVMAbortProcessAction = 0,
    LLVMPrintMessageAction = 1,
    LLVMReturnStatusAction = 2
} LLVMVerifierFailureAction;

typedef enum LLVMCodeGenOptLevel {
    LLVMCodeGenLevelNone = 0,
    LLVMCodeGenLevelLess = 1,
    LLVMCodeGenLevelDefault = 2,
    LLVMCodeGenLevelAggressive = 3
} LLVMCodeGenOptLevel;

typedef enum LLVMRelocMode {
    LLVMRelocDefault = 0,
    LLVMRelocStatic = 1,
    LLVMRelocPIC = 2,
    LLVMRelocDynamicNoPic = 3,
    LLVMRelocROPI = 4,
    LLVMRelocRWPI = 5,
    LLVMRelocROPI_RWPI = 6
} LLVMRelocMode;

typedef enum LLVMCodeModel {
    LLVMCodeModelDefault = 0,
    LLVMCodeModelJITDefault = 1,
    LLVMCodeModelTiny = 2,
    LLVMCodeModelSmall = 3,
    LLVMCodeModelKernel = 4,
    LLVMCodeModelMedium = 5,
    LLVMCodeModelLarge = 6
} LLVMCodeModel;

typedef enum LLVMCodeGenFileType {
    LLVMAssemblyFile = 0,
    LLVMObjectFile = 1
} LLVMCodeGenFileType;

typedef enum LLVMLinkage {
    LLVMExternalLinkage = 0,
    LLVMAvailableExternallyLinkage = 1,
    LLVMLinkOnceAnyLinkage = 2,
    LLVMLinkOnceODRLinkage = 3,
    LLVMLinkOnceODRAutoHideLinkage = 4,
    LLVMWeakAnyLinkage = 5,
    LLVMWeakODRLinkage = 6,
    LLVMAppendingLinkage = 7,
    LLVMInternalLinkage = 8,
    LLVMPrivateLinkage = 9
} LLVMLinkage;

typedef enum LLVMRealPredicate {
    LLVMRealOEQ = 1, LLVMRealOGT = 2, LLVMRealOGE = 3,
    LLVMRealOLT = 4, LLVMRealOLE = 5, LLVMRealUNE = 14
} LLVMRealPredicate;

typedef enum LLVMIntPredicate {
    LLVMIntEQ = 32,
    LLVMIntNE = 33,
    LLVMIntUGT = 34,
    LLVMIntUGE = 35,
    LLVMIntULT = 36,
    LLVMIntULE = 37,
    LLVMIntSGT = 38,
    LLVMIntSGE = 39,
    LLVMIntSLT = 40,
    LLVMIntSLE = 41
} LLVMIntPredicate;

void LLVMInitializeX86TargetInfo(void);
void LLVMInitializeX86Target(void);
void LLVMInitializeX86TargetMC(void);
void LLVMInitializeX86AsmPrinter(void);
void LLVMInitializeX86AsmParser(void);
void LLVMInitializeAArch64TargetInfo(void);
void LLVMInitializeAArch64Target(void);
void LLVMInitializeAArch64TargetMC(void);
void LLVMInitializeAArch64AsmPrinter(void);
void LLVMInitializeAArch64AsmParser(void);

char *LLVMGetDefaultTargetTriple(void);
char *LLVMNormalizeTargetTriple(const char *triple);
int LLVMGetTargetFromTriple(const char *triple, LLVMTargetRef *target, char **error_message);
const char *LLVMGetTargetName(LLVMTargetRef target);
const char *LLVMGetTargetDescription(LLVMTargetRef target);
LLVMTargetMachineRef LLVMCreateTargetMachine(LLVMTargetRef target, const char *triple, const char *cpu, const char *features, LLVMCodeGenOptLevel level, LLVMRelocMode reloc, LLVMCodeModel model);
void LLVMDisposeTargetMachine(LLVMTargetMachineRef machine);
LLVMTargetDataRef LLVMCreateTargetDataLayout(LLVMTargetMachineRef machine);
void LLVMSetModuleDataLayout(LLVMModuleRef module, LLVMTargetDataRef data);
void LLVMDisposeTargetData(LLVMTargetDataRef data);
int LLVMTargetMachineEmitToFile(LLVMTargetMachineRef machine, LLVMModuleRef module, char *filename, LLVMCodeGenFileType file_type, char **error_message);

LLVMPassBuilderOptionsRef LLVMCreatePassBuilderOptions(void);
void LLVMDisposePassBuilderOptions(LLVMPassBuilderOptionsRef options);
LLVMErrorRef LLVMRunPasses(LLVMModuleRef module, const char *passes, LLVMTargetMachineRef machine, LLVMPassBuilderOptionsRef options);
char *LLVMGetErrorMessage(LLVMErrorRef error);
void LLVMDisposeErrorMessage(char *message);

LLVMContextRef LLVMContextCreate(void);
void LLVMContextDispose(LLVMContextRef context);
LLVMModuleRef LLVMModuleCreateWithNameInContext(const char *name, LLVMContextRef context);
void LLVMDisposeModule(LLVMModuleRef module);
void LLVMSetTarget(LLVMModuleRef module, const char *triple);
char *LLVMPrintModuleToString(LLVMModuleRef module);
int LLVMPrintModuleToFile(LLVMModuleRef module, const char *filename, char **error_message);
int LLVMVerifyModule(LLVMModuleRef module, LLVMVerifierFailureAction action, char **error_message);
void LLVMDisposeMessage(char *message);

LLVMBuilderRef LLVMCreateBuilderInContext(LLVMContextRef context);
void LLVMDisposeBuilder(LLVMBuilderRef builder);
LLVMBasicBlockRef LLVMGetInsertBlock(LLVMBuilderRef builder);
LLVMValueRef LLVMGetBasicBlockParent(LLVMBasicBlockRef block);
LLVMBasicBlockRef LLVMGetEntryBasicBlock(LLVMValueRef function);
LLVMContextRef LLVMGetTypeContext(LLVMTypeRef type);
LLVMValueRef LLVMGetFirstInstruction(LLVMBasicBlockRef block);
LLVMValueRef LLVMGetNextInstruction(LLVMValueRef instruction);
LLVMValueRef LLVMIsAPHINode(LLVMValueRef value);
void LLVMPositionBuilderBefore(LLVMBuilderRef builder, LLVMValueRef instruction);

LLVMTypeRef LLVMVoidTypeInContext(LLVMContextRef context);
LLVMTypeRef LLVMInt1TypeInContext(LLVMContextRef context);
LLVMTypeRef LLVMInt8TypeInContext(LLVMContextRef context);
LLVMTypeRef LLVMInt16TypeInContext(LLVMContextRef context);
LLVMTypeRef LLVMInt32TypeInContext(LLVMContextRef context);
LLVMTypeRef LLVMInt64TypeInContext(LLVMContextRef context);
LLVMTypeRef LLVMIntTypeInContext(LLVMContextRef context, unsigned bits);
LLVMTypeRef LLVMFloatTypeInContext(LLVMContextRef context);
LLVMTypeRef LLVMDoubleTypeInContext(LLVMContextRef context);
LLVMTypeRef LLVMPointerTypeInContext(LLVMContextRef context, unsigned address_space);
LLVMTypeRef LLVMPointerType(LLVMTypeRef type, unsigned address_space);
LLVMTypeRef LLVMArrayType(LLVMTypeRef type, unsigned count);
LLVMTypeRef LLVMStructTypeInContext(LLVMContextRef context, LLVMTypeRef *elements, unsigned count, int packed);
LLVMTypeRef LLVMStructCreateNamed(LLVMContextRef context, const char *name);
void LLVMStructSetBody(LLVMTypeRef type, LLVMTypeRef *elements, unsigned count, int packed);
LLVMTypeRef LLVMFunctionType(LLVMTypeRef return_type, LLVMTypeRef *params, unsigned count, int variadic);
char *LLVMPrintTypeToString(LLVMTypeRef type);
LLVMValueRef LLVMSizeOf(LLVMTypeRef type);
LLVMValueRef LLVMAlignOf(LLVMTypeRef type);

LLVMValueRef LLVMAddFunction(LLVMModuleRef module, const char *name, LLVMTypeRef function_type);
LLVMValueRef LLVMGetNamedFunction(LLVMModuleRef module, const char *name);
unsigned LLVMCountParams(LLVMValueRef function);
LLVMValueRef LLVMGetParam(LLVMValueRef function, unsigned index);
LLVMBasicBlockRef LLVMAppendBasicBlockInContext(LLVMContextRef context, LLVMValueRef function, const char *name);
const char *LLVMGetBasicBlockName(LLVMBasicBlockRef block);

LLVMValueRef LLVMAddGlobal(LLVMModuleRef module, LLVMTypeRef type, const char *name);
LLVMValueRef LLVMGetNamedGlobal(LLVMModuleRef module, const char *name);
void LLVMSetInitializer(LLVMValueRef global, LLVMValueRef value);
void LLVMSetGlobalConstant(LLVMValueRef global, int constant);
void LLVMSetLinkage(LLVMValueRef value, LLVMLinkage linkage);
LLVMTypeRef LLVMTypeOf(LLVMValueRef value);
const char *LLVMGetValueName(LLVMValueRef value);
void LLVMSetValueName(LLVMValueRef value, const char *name);
char *LLVMPrintValueToString(LLVMValueRef value);

void LLVMPositionBuilderAtEnd(LLVMBuilderRef builder, LLVMBasicBlockRef block);
LLVMValueRef LLVMBuildRetVoid(LLVMBuilderRef builder);
LLVMValueRef LLVMBuildRet(LLVMBuilderRef builder, LLVMValueRef value);
LLVMValueRef LLVMBuildBr(LLVMBuilderRef builder, LLVMBasicBlockRef block);
LLVMValueRef LLVMBuildCondBr(LLVMBuilderRef builder, LLVMValueRef condition, LLVMBasicBlockRef true_block, LLVMBasicBlockRef false_block);
LLVMValueRef LLVMBuildUnreachable(LLVMBuilderRef builder);

LLVMValueRef LLVMConstInt(LLVMTypeRef type, unsigned long long value, int sign_extend);
LLVMValueRef LLVMConstNull(LLVMTypeRef type);
LLVMValueRef LLVMConstPointerNull(LLVMTypeRef type);
LLVMValueRef LLVMConstStringInContext(LLVMContextRef context, const char *text, unsigned length, int dont_null_terminate);
LLVMValueRef LLVMConstStructInContext(LLVMContextRef context, LLVMValueRef *values, unsigned count, int packed);
LLVMValueRef LLVMConstArray(LLVMTypeRef type, LLVMValueRef *values, unsigned count);

LLVMValueRef LLVMBuildAdd(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildSub(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildMul(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildSDiv(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildUDiv(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildSRem(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildURem(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildNeg(LLVMBuilderRef builder, LLVMValueRef value, const char *name);
LLVMValueRef LLVMBuildAnd(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildOr(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildXor(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildNot(LLVMBuilderRef builder, LLVMValueRef value, const char *name);
LLVMValueRef LLVMBuildShl(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildLShr(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildAShr(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildICmp(LLVMBuilderRef builder, LLVMIntPredicate predicate, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildAlloca(LLVMBuilderRef builder, LLVMTypeRef type, const char *name);
LLVMValueRef LLVMIsAAllocaInst(LLVMValueRef value);
LLVMTypeRef LLVMGetAllocatedType(LLVMValueRef alloca);
LLVMValueRef LLVMBuildLoad2(LLVMBuilderRef builder, LLVMTypeRef type, LLVMValueRef pointer, const char *name);
LLVMValueRef LLVMBuildStore(LLVMBuilderRef builder, LLVMValueRef value, LLVMValueRef pointer);
LLVMValueRef LLVMBuildGEP2(LLVMBuilderRef builder, LLVMTypeRef source_type, LLVMValueRef pointer, LLVMValueRef *indices, unsigned count, const char *name);
LLVMValueRef LLVMBuildInBoundsGEP2(LLVMBuilderRef builder, LLVMTypeRef source_type, LLVMValueRef pointer, LLVMValueRef *indices, unsigned count, const char *name);
LLVMValueRef LLVMBuildGlobalStringPtr(LLVMBuilderRef builder, const char *text, const char *name);
LLVMValueRef LLVMBuildCall2(LLVMBuilderRef builder, LLVMTypeRef function_type, LLVMValueRef function, LLVMValueRef *args, unsigned count, const char *name);
LLVMValueRef LLVMBuildPhi(LLVMBuilderRef builder, LLVMTypeRef type, const char *name);
void LLVMAddIncoming(LLVMValueRef phi, LLVMValueRef *values, LLVMBasicBlockRef *blocks, unsigned count);
LLVMValueRef LLVMBuildExtractValue(LLVMBuilderRef builder, LLVMValueRef value, unsigned index, const char *name);
LLVMValueRef LLVMBuildSelect(LLVMBuilderRef builder, LLVMValueRef condition, LLVMValueRef true_value, LLVMValueRef false_value, const char *name);
LLVMValueRef LLVMBuildTrunc(LLVMBuilderRef builder, LLVMValueRef value, LLVMTypeRef type, const char *name);
LLVMValueRef LLVMBuildZExt(LLVMBuilderRef builder, LLVMValueRef value, LLVMTypeRef type, const char *name);
LLVMValueRef LLVMBuildSExt(LLVMBuilderRef builder, LLVMValueRef value, LLVMTypeRef type, const char *name);
LLVMValueRef LLVMBuildPtrToInt(LLVMBuilderRef builder, LLVMValueRef value, LLVMTypeRef type, const char *name);
LLVMValueRef LLVMBuildIntToPtr(LLVMBuilderRef builder, LLVMValueRef value, LLVMTypeRef type, const char *name);
LLVMValueRef LLVMBuildBitCast(LLVMBuilderRef builder, LLVMValueRef value, LLVMTypeRef type, const char *name);

LLVMValueRef LLVMConstRealOfStringAndSize(LLVMTypeRef type, const char *text, unsigned length);
LLVMValueRef LLVMBuildFAdd(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildFSub(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildFMul(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildFDiv(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildFRem(LLVMBuilderRef builder, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildFNeg(LLVMBuilderRef builder, LLVMValueRef value, const char *name);
LLVMValueRef LLVMBuildFCmp(LLVMBuilderRef builder, LLVMRealPredicate predicate, LLVMValueRef left, LLVMValueRef right, const char *name);
LLVMValueRef LLVMBuildSIToFP(LLVMBuilderRef builder, LLVMValueRef value, LLVMTypeRef type, const char *name);

/* Module inspection, attribute copying and IR parsing used to annotate
   runtime declarations before the optimization pipeline runs. */
typedef struct LLVMOpaqueAttributeRef *LLVMAttributeRef;
typedef struct LLVMOpaqueMemoryBuffer *LLVMMemoryBufferRef;
const char *LLVMGetTarget(LLVMModuleRef module);
LLVMContextRef LLVMGetModuleContext(LLVMModuleRef module);
LLVMValueRef LLVMGetFirstFunction(LLVMModuleRef module);
LLVMValueRef LLVMGetNextFunction(LLVMValueRef function);
int LLVMIsDeclaration(LLVMValueRef global);
unsigned LLVMGetAttributeCountAtIndex(LLVMValueRef function, unsigned index);
void LLVMGetAttributesAtIndex(LLVMValueRef function, unsigned index, LLVMAttributeRef *attributes);
void LLVMAddAttributeAtIndex(LLVMValueRef function, unsigned index, LLVMAttributeRef attribute);
LLVMMemoryBufferRef LLVMCreateMemoryBufferWithMemoryRangeCopy(const char *data, size_t length, const char *name);
int LLVMParseIRInContext(LLVMContextRef context, LLVMMemoryBufferRef buffer, LLVMModuleRef *module, char **message);

#endif
