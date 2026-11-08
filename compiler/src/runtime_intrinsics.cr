module Emerald
  class RuntimeStaticIntrinsic
    getter receiver : String
    getter method_name : String
    getter param_types : Array(String)
    getter return_type : String
    getter opcode : String
    getter category : String

    def initialize(@receiver, @method_name, @param_types, @return_type, @opcode, @category)
    end
  end

  module RuntimeStaticIntrinsics
    extend self

    @@all : Hash(Tuple(String, String), RuntimeStaticIntrinsic)?

    def all : Hash(Tuple(String, String), RuntimeStaticIntrinsic)
      @@all ||= build_all
    end

    def find(receiver : String, method_name : String) : RuntimeStaticIntrinsic?
      all[{receiver, method_name}]?
    end

    def receiver?(receiver : String) : Bool
      all.keys.any? { |key| key[0] == receiver }
    end

    def receivers : Array(String)
      all.keys.map { |key| key[0] }.uniq.sort
    end

    private def build_all : Hash(Tuple(String, String), RuntimeStaticIntrinsic)
      registry = {} of Tuple(String, String) => RuntimeStaticIntrinsic

      add_time(registry)
      add_console(registry)
      add_math(registry)
      add_filesystem(registry)
      add_native_bridge(registry)
      add_http(registry)
      add_tcp(registry)
      add_host_capabilities(registry)
      add_llvm(registry)

      registry
    end

    private def add_time(registry)
      add(registry, "Duration", "millis", ["Int"], "Std::Time::Duration", "duration.millis", "time")
      add(registry, "Duration", "seconds", ["Int"], "Std::Time::Duration", "duration.seconds", "time")
      add(registry, "Duration", "minutes", ["Int"], "Std::Time::Duration", "duration.minutes", "time")
      add(registry, "Duration", "hours", ["Int"], "Std::Time::Duration", "duration.hours", "time")
      add(registry, "Duration", "days", ["Int"], "Std::Time::Duration", "duration.days", "time")

      add(registry, "OffsetDateTime", "now", [] of String, "Std::Time::OffsetDateTime", "offsetDateTime.now", "time")
      add(registry, "OffsetDateTime", "utcNow", [] of String, "Std::Time::OffsetDateTime", "offsetDateTime.utcNow", "time")
      add(registry, "OffsetDateTime", "of", ["Int", "Int", "Int", "Int", "Int", "Int", "Int"], "Std::Time::OffsetDateTime", "offsetDateTime.of", "time")
    end

    private def add_console(registry)
      add(registry, "Console", "print", ["Any"], "Void", "console.print", "console")
      add(registry, "Console", "println", ["Any"], "Void", "console.println", "console")
      add(registry, "Console", "error", ["Any"], "Void", "console.error", "console")
      add(registry, "Console", "write", ["String"], "Void", "console.write", "console")
      add(registry, "Console", "writeLine", ["String"], "Void", "console.writeLine", "console")
      add(registry, "Console", "errorLine", ["String"], "Void", "console.errorLine", "console")
      add(registry, "Console", "blankLine", [] of String, "Void", "console.blankLine", "console")
      add(registry, "Console", "readLine", [] of String, "String", "console.readLine", "console")
      add(registry, "Console", "readLineOr", ["String"], "String", "console.readLineOr", "console")
      add(registry, "Console", "tryReadLine", [] of String, "Std::Result::IResult<String,String>", "console.tryReadLine", "console")
      add(registry, "Console", "prompt", ["String"], "String", "console.prompt", "console")
      add(registry, "Console", "promptOr", ["String", "String"], "String", "console.promptOr", "console")
      add(registry, "Console", "confirm", ["String"], "Bool", "console.confirm", "console")
      add(registry, "Console", "confirmOr", ["String", "Bool"], "Bool", "console.confirmOr", "console")
    end

    private def add_math(registry)
      add(registry, "Math", "abs", ["Int"], "Int", "math.abs", "math")
      add(registry, "Math", "min", ["Int", "Int"], "Int", "math.min", "math")
      add(registry, "Math", "max", ["Int", "Int"], "Int", "math.max", "math")
      add(registry, "Math", "clamp", ["Int", "Int", "Int"], "Int", "math.clamp", "math")
      add(registry, "NativeMath", "sqrt", ["Float"], "Float", "nativeMath.sqrt", "math")
      add(registry, "NativeMath", "absFloat", ["Float"], "Float", "nativeMath.absFloat", "math")
      add(registry, "NativeMath", "floor", ["Float"], "Float", "nativeMath.floor", "math")
      add(registry, "NativeMath", "ceil", ["Float"], "Float", "nativeMath.ceil", "math")
      add(registry, "NativeMath", "round", ["Float"], "Float", "nativeMath.round", "math")
      add(registry, "NativeMath", "sin", ["Float"], "Float", "nativeMath.sin", "math")
      add(registry, "NativeMath", "cos", ["Float"], "Float", "nativeMath.cos", "math")
      add(registry, "NativeMath", "tan", ["Float"], "Float", "nativeMath.tan", "math")
      add(registry, "NativeMath", "log", ["Float"], "Float", "nativeMath.log", "math")
      add(registry, "NativeMath", "log10", ["Float"], "Float", "nativeMath.log10", "math")
      add(registry, "NativeMath", "exp", ["Float"], "Float", "nativeMath.exp", "math")
      add(registry, "NativeMath", "pow", ["Float", "Float"], "Float", "nativeMath.pow", "math")
    end

    private def add_filesystem(registry)
      add(registry, "Path", "current", [] of String, "Std::Io::Path", "path.current", "filesystem")
      add(registry, "Path", "join", ["String", "String"], "String", "path.join", "filesystem")
      add(registry, "Path", "fileName", ["String"], "String", "path.fileName", "filesystem")
      add(registry, "Path", "extension", ["String"], "String", "path.extension", "filesystem")
      add(registry, "Path", "parent", ["String"], "String", "path.parent", "filesystem")

      add(registry, "File", "readText", ["String"], "String", "file.readText", "filesystem")
      add(registry, "File", "readLines", ["String"], "List<String>", "file.readLines", "filesystem")
      add(registry, "File", "writeText", ["String", "String"], "Void", "file.writeText", "filesystem")
      add(registry, "File", "appendText", ["String", "String"], "Void", "file.appendText", "filesystem")
      add(registry, "File", "tryReadText", ["String"], "Std::Result::IResult<String,String>", "file.tryReadText", "filesystem")
      add(registry, "File", "tryWriteText", ["String", "String"], "Std::Result::IResult<Bool,String>", "file.tryWriteText", "filesystem")
      add(registry, "File", "tryAppendText", ["String", "String"], "Std::Result::IResult<Bool,String>", "file.tryAppendText", "filesystem")
      add(registry, "File", "exists", ["String"], "Bool", "file.exists", "filesystem")
      add(registry, "File", "isFile", ["String"], "Bool", "file.isFile", "filesystem")
      add(registry, "File", "isDirectory", ["String"], "Bool", "file.isDirectory", "filesystem")
      add(registry, "File", "delete", ["String"], "Bool", "file.delete", "filesystem")
      add(registry, "File", "size", ["String"], "Int", "file.size", "filesystem")

      add(registry, "Directory", "exists", ["String"], "Bool", "directory.exists", "filesystem")
      add(registry, "Directory", "create", ["String"], "Bool", "directory.create", "filesystem")
      add(registry, "Directory", "delete", ["String"], "Bool", "directory.delete", "filesystem")
      add(registry, "Directory", "list", ["String"], "List<String>", "directory.list", "filesystem")
    end

    private def add_native_bridge(registry)
      add(registry, "NativeHash", "of", ["Any"], "Int", "native.hash.of", "native")
      add(registry, "NativeConsole", "write", ["String"], "Int", "native.console.write", "native")
      add(registry, "NativeConsole", "writeLine", ["String"], "Int", "native.console.writeLine", "native")
      add(registry, "NativeConsole", "errorLine", ["String"], "Int", "native.console.errorLine", "native")
      add(registry, "NativeConsole", "readLine", [] of String, "String", "native.console.readLine", "native")

      add(registry, "NativeFile", "exists", ["String"], "Bool", "native.file.exists", "native")
      add(registry, "NativeFile", "isFile", ["String"], "Bool", "native.file.isFile", "native")
      add(registry, "NativeFile", "readText", ["String"], "String", "native.file.readText", "native")
      add(registry, "NativeFile", "readLines", ["String"], "List<String>", "native.file.readLines", "native")
      add(registry, "NativeFile", "writeText", ["String", "String"], "Int", "native.file.writeText", "native")
      add(registry, "NativeFile", "appendText", ["String", "String"], "Int", "native.file.appendText", "native")
      add(registry, "NativeFile", "delete", ["String"], "Bool", "native.file.delete", "native")
      add(registry, "NativeFile", "size", ["String"], "Int", "native.file.size", "native")

      add(registry, "NativeDirectory", "exists", ["String"], "Bool", "native.directory.exists", "native")
      add(registry, "NativeDirectory", "create", ["String"], "Bool", "native.directory.create", "native")
      add(registry, "NativeDirectory", "delete", ["String"], "Bool", "native.directory.delete", "native")
      add(registry, "NativeDirectory", "list", ["String"], "List<String>", "native.directory.list", "native")

      add(registry, "NativePath", "current", [] of String, "String", "native.path.current", "native")
      add(registry, "NativePath", "join", ["String", "String"], "String", "native.path.join", "native")
      add(registry, "NativePath", "parent", ["String"], "String", "native.path.parent", "native")
      add(registry, "NativePath", "fileName", ["String"], "String", "native.path.fileName", "native")
      add(registry, "NativePath", "extension", ["String"], "String", "native.path.extension", "native")

      add(registry, "NativeEnv", "get", ["String"], "String", "native.env.get", "native")
      add(registry, "NativeEnv", "getOr", ["String", "String"], "String", "native.env.getOr", "native")
      add(registry, "NativeEnv", "has", ["String"], "Bool", "native.env.has", "native")
      add(registry, "NativeEnv", "args", [] of String, "List<String>", "native.env.args", "native")
      add(registry, "NativeEnv", "currentDirectory", [] of String, "String", "native.env.currentDirectory", "native")

      add(registry, "NativeProcess", "args", [] of String, "List<String>", "native.process.args", "native")
      add(registry, "NativeProcess", "command", [] of String, "String", "native.process.command", "native")
      add(registry, "NativeProcess", "exit", ["Int"], "Int", "native.process.exit", "native")

      add(registry, "NativeSystem", "os", [] of String, "String", "native.system.os", "native")
      add(registry, "NativeSystem", "isWindows", [] of String, "Bool", "native.system.isWindows", "native")
      add(registry, "NativeSystem", "isLinux", [] of String, "Bool", "native.system.isLinux", "native")
      add(registry, "NativeSystem", "lineSeparator", [] of String, "String", "native.system.lineSeparator", "native")
      add(registry, "NativeSystem", "pathSeparator", [] of String, "String", "native.system.pathSeparator", "native")
      add(registry, "NativeSystem", "directorySeparator", [] of String, "String", "native.system.directorySeparator", "native")
      add(registry, "NativeSystem", "arch", [] of String, "String", "native.system.arch", "native")
      add(registry, "NativeSystem", "processorCount", [] of String, "Int", "native.system.processorCount", "native")
      add(registry, "NativeSystem", "userName", [] of String, "String", "native.system.userName", "native")
      add(registry, "NativeSystem", "hostName", [] of String, "String", "native.system.hostName", "native")
      add(registry, "NativeSystem", "homeDirectory", [] of String, "String", "native.system.homeDirectory", "native")
      add(registry, "NativeSystem", "tempDirectory", [] of String, "String", "native.system.tempDirectory", "native")

      add(registry, "NativeTcp", "connect", ["String", "Int"], "Int", "native.tcp.connect", "native")
      add(registry, "NativeTcp", "listen", ["String", "Int"], "Int", "native.tcp.listen", "native")
      add(registry, "NativeTcp", "isOpen", ["Int"], "Bool", "native.tcp.isOpen", "native")
      add(registry, "NativeTcp", "listenerIsOpen", ["Int"], "Bool", "native.tcp.listenerIsOpen", "native")
      add(registry, "NativeTcp", "listenerPort", ["Int"], "Int", "native.tcp.listenerPort", "native")
      add(registry, "NativeTcp", "readText", ["Int"], "String", "native.tcp.readText", "native")
      add(registry, "NativeTcp", "readLine", ["Int"], "String", "native.tcp.readLine", "native")
      add(registry, "NativeTcp", "writeText", ["Int", "String"], "Bool", "native.tcp.writeText", "native")
      add(registry, "NativeTcp", "close", ["Int"], "Bool", "native.tcp.close", "native")
      add(registry, "NativeTcp", "accept", ["Int"], "Int", "native.tcp.accept", "native")
      add(registry, "NativeTcp", "closeListener", ["Int"], "Bool", "native.tcp.closeListener", "native")

      add(registry, "NativeUdp", "bind", ["String", "Int"], "Int", "native.udp.bind", "native")
      add(registry, "NativeUdp", "isOpen", ["Int"], "Bool", "native.udp.isOpen", "native")
      add(registry, "NativeUdp", "localPort", ["Int"], "Int", "native.udp.localPort", "native")
      add(registry, "NativeUdp", "sendText", ["Int", "String", "Int", "String"], "Bool", "native.udp.sendText", "native")
      add(registry, "NativeUdp", "receiveText", ["Int"], "String", "native.udp.receiveText", "native")
      add(registry, "NativeUdp", "lastSenderHost", ["Int"], "String", "native.udp.lastSenderHost", "native")
      add(registry, "NativeUdp", "lastSenderPort", ["Int"], "Int", "native.udp.lastSenderPort", "native")
      add(registry, "NativeUdp", "close", ["Int"], "Bool", "native.udp.close", "native")

      add(registry, "NativeUi", "init", [] of String, "Bool", "native.ui.init", "native")
      add(registry, "NativeUi", "backend", [] of String, "String", "native.ui.backend", "native")
      add(registry, "NativeUi", "createWindow", ["String", "Int", "Int"], "Int", "native.ui.createWindow", "native")
      add(registry, "NativeUi", "setHtml", ["Int", "String"], "Bool", "native.ui.setHtml", "native")
      add(registry, "NativeUi", "setTitle", ["Int", "String"], "Bool", "native.ui.setTitle", "native")
      add(registry, "NativeUi", "isOpen", ["Int"], "Bool", "native.ui.isOpen", "native")
      add(registry, "NativeUi", "pollAction", ["Int"], "String", "native.ui.pollAction", "native")
      add(registry, "NativeUi", "show", ["Int"], "Bool", "native.ui.show", "native")
      add(registry, "NativeUi", "close", ["Int"], "Bool", "native.ui.close", "native")
      add(registry, "NativeUi", "pump", [] of String, "Bool", "native.ui.pump", "native")
      add(registry, "NativeUi", "run", [] of String, "Int", "native.ui.run", "native")
    end

    private def add_http(registry)
      add(registry, "Http", "get", ["String"], "Std::Result::IResult<Std::Http::IHttpResponse,String>", "http.get", "network")
      add(registry, "Http", "postText", ["String", "String"], "Std::Result::IResult<Std::Http::IHttpResponse,String>", "http.postText", "network")
    end

    private def add_tcp(registry)
      add(registry, "Tcp", "connect", ["String", "Int"], "Std::Result::IResult<Std::Net::ITcpConnection,String>", "tcp.connect", "network")
      add(registry, "Tcp", "listen", ["String", "Int"], "Std::Result::IResult<Std::Net::ITcpListener,String>", "tcp.listen", "network")
      add(registry, "Tcp", "isOpen", ["Int"], "Bool", "tcp.isOpen", "network")
      add(registry, "Tcp", "listenerIsOpen", ["Int"], "Bool", "tcp.listenerIsOpen", "network")
      add(registry, "Tcp", "readText", ["Int"], "String", "tcp.readText", "network")
      add(registry, "Tcp", "readLine", ["Int"], "String", "tcp.readLine", "network")
      add(registry, "Tcp", "tryReadText", ["Int"], "Std::Result::IResult<String,String>", "tcp.tryReadText", "network")
      add(registry, "Tcp", "tryReadLine", ["Int"], "Std::Result::IResult<String,String>", "tcp.tryReadLine", "network")
      add(registry, "Tcp", "writeText", ["Int", "String"], "Bool", "tcp.writeText", "network")
      add(registry, "Tcp", "tryWriteText", ["Int", "String"], "Std::Result::IResult<Bool,String>", "tcp.tryWriteText", "network")
      add(registry, "Tcp", "close", ["Int"], "Bool", "tcp.close", "network")
      add(registry, "Tcp", "tryClose", ["Int"], "Std::Result::IResult<Bool,String>", "tcp.tryClose", "network")
      add(registry, "Tcp", "accept", ["Int"], "Std::Result::IResult<Std::Net::ITcpConnection,String>", "tcp.accept", "network")
      add(registry, "Tcp", "closeListener", ["Int"], "Bool", "tcp.closeListener", "network")
      add(registry, "Tcp", "tryCloseListener", ["Int"], "Std::Result::IResult<Bool,String>", "tcp.tryCloseListener", "network")
    end


    private def add_host_capabilities(registry)
      add(registry, "Env", "get", ["String"], "String", "env.get", "host")
      add(registry, "Env", "getOr", ["String", "String"], "String", "env.getOr", "host")
      add(registry, "Env", "has", ["String"], "Bool", "env.has", "host")
      add(registry, "Env", "args", [] of String, "List<String>", "env.args", "host")
      add(registry, "Env", "currentDirectory", [] of String, "String", "env.currentDirectory", "host")

      add(registry, "Process", "args", [] of String, "List<String>", "process.args", "host")
      add(registry, "Process", "command", [] of String, "String", "process.command", "host")
      add(registry, "Process", "exit", ["Int"], "Void", "process.exit", "host")

      add(registry, "System", "os", [] of String, "String", "system.os", "host")
      add(registry, "System", "isWindows", [] of String, "Bool", "system.isWindows", "host")
      add(registry, "System", "isLinux", [] of String, "Bool", "system.isLinux", "host")
      add(registry, "System", "lineSeparator", [] of String, "String", "system.lineSeparator", "host")
      add(registry, "System", "pathSeparator", [] of String, "String", "system.pathSeparator", "host")
      add(registry, "System", "directorySeparator", [] of String, "String", "system.directorySeparator", "host")

      add(registry, "Random", "nextInt", ["Int"], "Int", "random.nextInt", "host")
      add(registry, "Random", "nextIntBetween", ["Int", "Int"], "Int", "random.nextIntBetween", "host")
      add(registry, "Random", "nextBool", [] of String, "Bool", "random.nextBool", "host")

      add(registry, "Clock", "now", [] of String, "Std::Time::OffsetDateTime", "clock.now", "host")
      add(registry, "Clock", "utcNow", [] of String, "Std::Time::OffsetDateTime", "clock.utcNow", "host")
      add(registry, "Clock", "millis", [] of String, "Int", "clock.millis", "host")
      add(registry, "Clock", "sleep", ["Std::Time::Duration"], "Void", "clock.sleep", "host")
    end

    private def add_llvm(registry)
      llvm_type = "Std::Llvm::LlvmType"
      llvm_value = "Std::Llvm::LlvmValue"
      llvm_context = "Std::Llvm::LlvmContext"
      llvm_target = "Std::Llvm::LlvmTarget"
      llvm_string_list = "Std::Collections::IList<String>"
      llvm_type_list = "Std::Collections::IList<Std::Llvm::LlvmType>"
      llvm_value_list = "Std::Collections::IList<Std::Llvm::LlvmValue>"

      add(registry, "Llvm", "createContext", [] of String, llvm_context, "llvm.createContext", "llvm")
      add(registry, "Llvm", "initializeNativeTarget", [] of String, "Bool", "llvm.initializeNativeTarget", "llvm")
      add(registry, "Llvm", "initializeTarget", ["String"], "Bool", "llvm.initializeTarget", "llvm")
      add(registry, "Llvm", "defaultTargetTriple", [] of String, "String", "llvm.defaultTargetTriple", "llvm")
      add(registry, "Llvm", "normalizeTargetTriple", ["String"], "String", "llvm.normalizeTargetTriple", "llvm")
      add(registry, "Llvm", "lookupTarget", ["String"], llvm_target, "llvm.lookupTarget", "llvm")
      add(registry, "Llvm", "lastError", [] of String, "String", "llvm.lastError", "llvm")
      add(registry, "Llvm", "nativeObjectExtension", [] of String, "String", "llvm.nativeObjectExtension", "llvm")
      add(registry, "Llvm", "nativeExecutableExtension", [] of String, "String", "llvm.nativeExecutableExtension", "llvm")
      add(registry, "Llvm", "functionType", [llvm_type], llvm_type, "llvm.functionType", "llvm")
      add(registry, "Llvm", "constInt", [llvm_type, "Int"], llvm_value, "llvm.constInt", "llvm")
      add(registry, "Llvm", "constBool", [llvm_type, "Bool"], llvm_value, "llvm.constBool", "llvm")
      add(registry, "Llvm", "constNull", [llvm_type], llvm_value, "llvm.constNull", "llvm")
      add(registry, "Llvm", "constPointerNull", [llvm_type], llvm_value, "llvm.constPointerNull", "llvm")
      add(registry, "Llvm", "externalLinkage", [] of String, "Int", "llvm.externalLinkage", "llvm")
      add(registry, "Llvm", "internalLinkage", [] of String, "Int", "llvm.internalLinkage", "llvm")
      add(registry, "Llvm", "privateLinkage", [] of String, "Int", "llvm.privateLinkage", "llvm")

      add(registry, "LlvmNative", "initializeNativeTarget", [] of String, "Bool", "llvm.native.initialize_native_target", "llvm")
      add(registry, "LlvmNative", "initializeTarget", ["String"], "Bool", "llvm.native.initialize_target", "llvm")
      add(registry, "LlvmNative", "defaultTargetTriple", [] of String, "String", "llvm.native.default_target_triple", "llvm")
      add(registry, "LlvmNative", "normalizeTargetTriple", ["String"], "String", "llvm.native.normalize_target_triple", "llvm")
      add(registry, "LlvmNative", "lookupTarget", ["String"], "Int", "llvm.native.lookup_target", "llvm")
      add(registry, "LlvmNative", "lastError", [] of String, "String", "llvm.native.last_error", "llvm")
      add(registry, "LlvmNative", "nativeObjectExtension", [] of String, "String", "llvm.native.native_object_extension", "llvm")
      add(registry, "LlvmNative", "nativeExecutableExtension", [] of String, "String", "llvm.native.native_executable_extension", "llvm")
      add(registry, "LlvmNative", "targetName", ["Int"], "String", "llvm.native.target_name", "llvm")
      add(registry, "LlvmNative", "targetDescription", ["Int"], "String", "llvm.native.target_description", "llvm")
      add(registry, "LlvmNative", "createTargetMachine", ["Int", "String", "String", "String", "Int"], "Int", "llvm.native.create_target_machine", "llvm")
      add(registry, "LlvmNative", "disposeTargetMachine", ["Int"], "Void", "llvm.native.dispose_target_machine", "llvm")
      add(registry, "LlvmNative", "targetMachineApplyDataLayout", ["Int", "Int"], "Bool", "llvm.native.target_machine_apply_data_layout", "llvm")
      add(registry, "LlvmNative", "targetMachineEmitObjectFile", ["Int", "Int", "String"], "Bool", "llvm.native.target_machine_emit_object_file", "llvm")
      add(registry, "LlvmNative", "targetMachineEmitAssemblyFile", ["Int", "Int", "String"], "Bool", "llvm.native.target_machine_emit_assembly_file", "llvm")
      add(registry, "LlvmNative", "runPasses", ["Int", "String"], "Bool", "llvm.native.run_passes", "llvm")
      add(registry, "LlvmNative", "linkExecutable", ["String", llvm_string_list, llvm_string_list, llvm_string_list, llvm_string_list], "Bool", "llvm.native.link_executable", "llvm")
      add(registry, "LlvmNative", "linkerLastCommand", [] of String, "String", "llvm.native.linker_last_command", "llvm")
      add(registry, "LlvmNative", "linkerLastOutput", [] of String, "String", "llvm.native.linker_last_output", "llvm")
      add(registry, "LlvmNative", "linkerLastError", [] of String, "String", "llvm.native.linker_last_error", "llvm")
      add(registry, "LlvmNative", "runtimeSourcePath", [] of String, "String", "llvm.native.runtime_source_path", "llvm")
      add(registry, "LlvmNative", "runtimeHeaderPath", [] of String, "String", "llvm.native.runtime_header_path", "llvm")
      add(registry, "LlvmNative", "compileRuntimeObject", ["String", "String", llvm_string_list], "Bool", "llvm.native.compile_runtime_object", "llvm")
      add(registry, "LlvmNative", "compileIrObject", ["String", "String", llvm_string_list], "Bool", "llvm.native.compile_ir_object", "llvm")
      add(registry, "LlvmNative", "runtimeFlowLibraryName", [] of String, "String", "llvm.native.runtime_flow_library_name", "llvm")
      add(registry, "LlvmNative", "runtimeFlowLibraryPath", [] of String, "String", "llvm.native.runtime_flow_library_path", "llvm")
      add(registry, "LlvmNative", "runtimeLastCommand", [] of String, "String", "llvm.native.runtime_last_command", "llvm")
      add(registry, "LlvmNative", "runtimeLastOutput", [] of String, "String", "llvm.native.runtime_last_output", "llvm")
      add(registry, "LlvmNative", "runtimeLastError", [] of String, "String", "llvm.native.runtime_last_error", "llvm")

      add(registry, "LlvmNative", "constIntegerText", ["Int", "String"], "Int", "llvm.native.const_integer_text", "llvm")
      add(registry, "LlvmNative", "constFloatText", ["Int", "String"], "Int", "llvm.native.const_float_text", "llvm")
      add(registry, "LlvmNative", "buildExtractValue", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_extract_value", "llvm")
      add(registry, "LlvmNative", "buildFloatOperation", ["Int", "Int", "Int", "Int", "String"], "Int", "llvm.native.build_float_operation", "llvm")
      add(registry, "LlvmNative", "createContext", [] of String, "Int", "llvm.native.create_context", "llvm")
      add(registry, "LlvmNative", "disposeContext", ["Int"], "Void", "llvm.native.dispose_context", "llvm")
      add(registry, "LlvmNative", "createModule", ["Int", "String"], "Int", "llvm.native.create_module", "llvm")
      add(registry, "LlvmNative", "disposeModule", ["Int"], "Void", "llvm.native.dispose_module", "llvm")
      add(registry, "LlvmNative", "moduleSetTarget", ["Int", "String"], "Void", "llvm.native.module_set_target", "llvm")
      add(registry, "LlvmNative", "moduleToIr", ["Int"], "String", "llvm.native.module_to_ir", "llvm")
      add(registry, "LlvmNative", "moduleWriteIr", ["Int", "String"], "Bool", "llvm.native.module_write_ir", "llvm")
      add(registry, "LlvmNative", "moduleVerify", ["Int"], "Bool", "llvm.native.module_verify", "llvm")
      add(registry, "LlvmNative", "moduleVerifyMessage", ["Int"], "String", "llvm.native.module_verify_message", "llvm")

      add(registry, "LlvmNative", "createBuilder", ["Int"], "Int", "llvm.native.create_builder", "llvm")
      add(registry, "LlvmNative", "disposeBuilder", ["Int"], "Void", "llvm.native.dispose_builder", "llvm")
      add(registry, "LlvmNative", "currentBlock", ["Int"], "Int", "llvm.native.current_block", "llvm")

      add(registry, "LlvmNative", "voidType", ["Int"], "Int", "llvm.native.void_type", "llvm")
      add(registry, "LlvmNative", "i1Type", ["Int"], "Int", "llvm.native.i1_type", "llvm")
      add(registry, "LlvmNative", "i8Type", ["Int"], "Int", "llvm.native.i8_type", "llvm")
      add(registry, "LlvmNative", "i16Type", ["Int"], "Int", "llvm.native.i16_type", "llvm")
      add(registry, "LlvmNative", "i32Type", ["Int"], "Int", "llvm.native.i32_type", "llvm")
      add(registry, "LlvmNative", "i64Type", ["Int"], "Int", "llvm.native.i64_type", "llvm")
      add(registry, "LlvmNative", "intType", ["Int", "Int"], "Int", "llvm.native.int_type", "llvm")
      add(registry, "LlvmNative", "floatType", ["Int"], "Int", "llvm.native.float_type", "llvm")
      add(registry, "LlvmNative", "doubleType", ["Int"], "Int", "llvm.native.double_type", "llvm")
      add(registry, "LlvmNative", "opaquePointerType", ["Int"], "Int", "llvm.native.opaque_pointer_type", "llvm")
      add(registry, "LlvmNative", "pointerType", ["Int"], "Int", "llvm.native.pointer_type", "llvm")
      add(registry, "LlvmNative", "arrayType", ["Int", "Int"], "Int", "llvm.native.array_type", "llvm")
      add(registry, "LlvmNative", "structType", ["Int", llvm_type_list, "Bool"], "Int", "llvm.native.struct_type", "llvm")
      add(registry, "LlvmNative", "namedStructType", ["Int", "String"], "Int", "llvm.native.named_struct_type", "llvm")
      add(registry, "LlvmNative", "structSetBody", ["Int", llvm_type_list, "Bool"], "Void", "llvm.native.struct_set_body", "llvm")
      add(registry, "LlvmNative", "functionType", ["Int"], "Int", "llvm.native.function_type", "llvm")
      add(registry, "LlvmNative", "functionTypeWithParams", ["Int", llvm_type_list, "Bool"], "Int", "llvm.native.function_type_with_params", "llvm")
      add(registry, "LlvmNative", "typeToIr", ["Int"], "String", "llvm.native.type_to_ir", "llvm")
      add(registry, "LlvmNative", "sizeOf", ["Int"], "Int", "llvm.native.size_of", "llvm")
      add(registry, "LlvmNative", "alignOf", ["Int"], "Int", "llvm.native.align_of", "llvm")

      add(registry, "LlvmNative", "addFunction", ["Int", "String", "Int"], "Int", "llvm.native.add_function", "llvm")
      add(registry, "LlvmNative", "getFunction", ["Int", "String"], "Int", "llvm.native.get_function", "llvm")
      add(registry, "LlvmNative", "functionParameterCount", ["Int"], "Int", "llvm.native.function_parameter_count", "llvm")
      add(registry, "LlvmNative", "functionParameter", ["Int", "Int"], "Int", "llvm.native.function_parameter", "llvm")
      add(registry, "LlvmNative", "appendBlock", ["Int", "Int", "String"], "Int", "llvm.native.append_block", "llvm")
      add(registry, "LlvmNative", "blockName", ["Int"], "String", "llvm.native.block_name", "llvm")

      add(registry, "LlvmNative", "addGlobal", ["Int", "String", "Int"], "Int", "llvm.native.add_global", "llvm")
      add(registry, "LlvmNative", "getGlobal", ["Int", "String"], "Int", "llvm.native.get_global", "llvm")
      add(registry, "LlvmNative", "globalSetInitializer", ["Int", "Int"], "Void", "llvm.native.global_set_initializer", "llvm")
      add(registry, "LlvmNative", "globalSetConstant", ["Int", "Bool"], "Void", "llvm.native.global_set_constant", "llvm")
      add(registry, "LlvmNative", "valueSetLinkage", ["Int", "Int"], "Void", "llvm.native.value_set_linkage", "llvm")
      add(registry, "LlvmNative", "valueType", ["Int"], "Int", "llvm.native.value_type", "llvm")
      add(registry, "LlvmNative", "valueName", ["Int"], "String", "llvm.native.value_name", "llvm")
      add(registry, "LlvmNative", "valueSetName", ["Int", "String"], "Void", "llvm.native.value_set_name", "llvm")
      add(registry, "LlvmNative", "valueToIr", ["Int"], "String", "llvm.native.value_to_ir", "llvm")

      add(registry, "LlvmNative", "positionAtEnd", ["Int", "Int"], "Void", "llvm.native.position_at_end", "llvm")
      add(registry, "LlvmNative", "returnVoid", ["Int"], "Void", "llvm.native.return_void", "llvm")
      add(registry, "LlvmNative", "returnValue", ["Int", "Int"], "Void", "llvm.native.return_value", "llvm")
      add(registry, "LlvmNative", "buildBranch", ["Int", "Int"], "Int", "llvm.native.build_branch", "llvm")
      add(registry, "LlvmNative", "buildConditionalBranch", ["Int", "Int", "Int", "Int"], "Int", "llvm.native.build_conditional_branch", "llvm")
      add(registry, "LlvmNative", "buildUnreachable", ["Int"], "Int", "llvm.native.build_unreachable", "llvm")

      add(registry, "LlvmNative", "constInt", ["Int", "Int"], "Int", "llvm.native.const_int", "llvm")
      add(registry, "LlvmNative", "constBool", ["Int", "Bool"], "Int", "llvm.native.const_bool", "llvm")
      add(registry, "LlvmNative", "constNull", ["Int"], "Int", "llvm.native.const_null", "llvm")
      add(registry, "LlvmNative", "constPointerNull", ["Int"], "Int", "llvm.native.const_pointer_null", "llvm")
      add(registry, "LlvmNative", "constString", ["Int", "String", "Bool"], "Int", "llvm.native.const_string", "llvm")
      add(registry, "LlvmNative", "constStruct", ["Int", llvm_value_list, "Bool"], "Int", "llvm.native.const_struct", "llvm")
      add(registry, "LlvmNative", "constArray", ["Int", llvm_value_list], "Int", "llvm.native.const_array", "llvm")

      add(registry, "LlvmNative", "buildAdd", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_add", "llvm")
      add(registry, "LlvmNative", "buildSub", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_sub", "llvm")
      add(registry, "LlvmNative", "buildMul", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_mul", "llvm")
      add(registry, "LlvmNative", "buildSignedDiv", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_signed_div", "llvm")
      add(registry, "LlvmNative", "buildUnsignedDiv", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_unsigned_div", "llvm")
      add(registry, "LlvmNative", "buildSignedRem", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_signed_rem", "llvm")
      add(registry, "LlvmNative", "buildUnsignedRem", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_unsigned_rem", "llvm")
      add(registry, "LlvmNative", "buildNeg", ["Int", "Int", "String"], "Int", "llvm.native.build_neg", "llvm")
      add(registry, "LlvmNative", "buildAnd", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_and", "llvm")
      add(registry, "LlvmNative", "buildOr", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_or", "llvm")
      add(registry, "LlvmNative", "buildXor", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_xor", "llvm")
      add(registry, "LlvmNative", "buildNot", ["Int", "Int", "String"], "Int", "llvm.native.build_not", "llvm")
      add(registry, "LlvmNative", "buildShiftLeft", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_shift_left", "llvm")
      add(registry, "LlvmNative", "buildLogicalShiftRight", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_logical_shift_right", "llvm")
      add(registry, "LlvmNative", "buildArithmeticShiftRight", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_arithmetic_shift_right", "llvm")
      add(registry, "LlvmNative", "buildIntCompare", ["Int", "Int", "Int", "Int", "String"], "Int", "llvm.native.build_int_compare", "llvm")

      add(registry, "LlvmNative", "buildEntryAlloca", ["Int", "Int", "String"], "Int", "llvm.native.build_entry_alloca", "llvm")
      add(registry, "LlvmNative", "buildAlloca", ["Int", "Int", "String"], "Int", "llvm.native.build_alloca", "llvm")
      add(registry, "LlvmNative", "buildLoad", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_load", "llvm")
      add(registry, "LlvmNative", "buildStore", ["Int", "Int", "Int"], "Int", "llvm.native.build_store", "llvm")
      add(registry, "LlvmNative", "buildGep", ["Int", "Int", "Int", llvm_value_list, "String"], "Int", "llvm.native.build_gep", "llvm")
      add(registry, "LlvmNative", "buildInboundsGep", ["Int", "Int", "Int", llvm_value_list, "String"], "Int", "llvm.native.build_inbounds_gep", "llvm")
      add(registry, "LlvmNative", "buildGlobalStringPointer", ["Int", "String", "String"], "Int", "llvm.native.build_global_string_pointer", "llvm")
      add(registry, "LlvmNative", "buildCall", ["Int", "Int", "Int", llvm_value_list, "String"], "Int", "llvm.native.build_call", "llvm")
      add(registry, "LlvmNative", "buildPhi", ["Int", "Int", "String"], "Int", "llvm.native.build_phi", "llvm")
      add(registry, "LlvmNative", "addIncoming", ["Int", "Int", "Int"], "Void", "llvm.native.add_incoming", "llvm")
      add(registry, "LlvmNative", "buildSelect", ["Int", "Int", "Int", "Int", "String"], "Int", "llvm.native.build_select", "llvm")

      add(registry, "LlvmNative", "buildTruncate", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_truncate", "llvm")
      add(registry, "LlvmNative", "buildZeroExtend", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_zero_extend", "llvm")
      add(registry, "LlvmNative", "buildSignExtend", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_sign_extend", "llvm")
      add(registry, "LlvmNative", "buildPointerToInt", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_pointer_to_int", "llvm")
      add(registry, "LlvmNative", "buildIntToPointer", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_int_to_pointer", "llvm")
      add(registry, "LlvmNative", "buildBitCast", ["Int", "Int", "Int", "String"], "Int", "llvm.native.build_bit_cast", "llvm")
    end

    private def add(registry, receiver : String, method_name : String, param_types : Array(String), return_type : String, opcode : String, category : String)
      registry[{receiver, method_name}] = RuntimeStaticIntrinsic.new(receiver, method_name, param_types, return_type, opcode, category)
    end
  end
end
