module Emerald
  module RuntimePrelude
    extend self

    def emit(io : IO, emit_llvm : Bool = false)
      io << <<-PRELUDE
      require "http/client"
      require "socket"

      abstract class EmeraldBoxBase
      end

      class EmeraldBox(T) < EmeraldBoxBase
        getter value : T
        def initialize(@value : T); end

        def to_s(io : IO)
          io << @value.to_s
        end
      end

      class EmeraldResult
        @ok : Bool
        @payload : EmeraldBoxBase

        protected def initialize(@ok : Bool, @payload : EmeraldBoxBase); end

        def self.ok(v) : EmeraldResult
          EmeraldResult.new(true, EmeraldBox.new(v))
        end

        def self.err(e) : EmeraldResult
          EmeraldResult.new(false, EmeraldBox.new(e))
        end

        def is_ok? : Bool
          @ok
        end

        def is_err? : Bool
          !@ok
        end

        def raw_value : EmeraldBoxBase
          @payload
        end

        def to_s(io : IO)
          if @ok
            io << "Ok(" << @payload.to_s << ")"
          else
            io << "Err(" << @payload.to_s << ")"
          end
        end
      end


      module EmeraldRuntimeSocket
        @@mutex = Mutex.new
        @@next_handle = 1_i64
        @@sockets = {} of Int64 => TCPSocket
        @@listeners = {} of Int64 => TCPServer

        def self.connect(host : String, port : Int64) : Int64
          store_socket(TCPSocket.new(host, port.to_i32))
        end

        def self.listen(host : String, port : Int64) : Int64
          store_listener(TCPServer.new(host, port.to_i32))
        end

        def self.socket_open?(handle : Int64) : Bool
          @@mutex.synchronize { @@sockets.has_key?(handle) }
        end

        def self.listener_open?(handle : Int64) : Bool
          @@mutex.synchronize { @@listeners.has_key?(handle) }
        end

        def self.read_text(handle : Int64) : String
          socket_for(handle).gets_to_end
        end

        def self.read_line(handle : Int64) : String
          socket_for(handle).gets || ""
        end

        def self.write_text(handle : Int64, text : String) : Bool
          socket = socket_for(handle)
          socket << text
          socket.flush
          true
        end

        def self.close_socket(handle : Int64) : Bool
          socket = @@mutex.synchronize { @@sockets.delete(handle) }
          return false unless socket

          socket.close
          true
        rescue ex : Exception
          false
        end

        def self.close_listener(handle : Int64) : Bool
          listener = @@mutex.synchronize { @@listeners.delete(handle) }
          return false unless listener

          listener.close
          true
        rescue ex : Exception
          false
        end

        def self.accept(handle : Int64) : Int64
          store_socket(listener_for(handle).accept)
        end

        private def self.store_socket(socket : TCPSocket) : Int64
          @@mutex.synchronize do
            handle = @@next_handle
            @@next_handle += 1_i64
            @@sockets[handle] = socket
            handle
          end
        end

        private def self.store_listener(listener : TCPServer) : Int64
          @@mutex.synchronize do
            handle = @@next_handle
            @@next_handle += 1_i64
            @@listeners[handle] = listener
            handle
          end
        end

        private def self.socket_for(handle : Int64) : TCPSocket
          @@mutex.synchronize { @@sockets[handle]? } || raise "TCP connection is not open"
        end

        private def self.listener_for(handle : Int64) : TCPServer
          @@mutex.synchronize { @@listeners[handle]? } || raise "TCP listener is not open"
        end
      end

      class EmeraldFiber(T)
        @channel : Channel(T)
        @fiber : Fiber

        def initialize(&block : -> T)
          @channel = Channel(T).new(1)
          ch = @channel
          @fiber = spawn { ch.send(block.call) }
        end

        def self.spawn(&block : -> T) : EmeraldFiber(T) forall T
          EmeraldFiber(T).new(&block)
        end

        def await : T
          @channel.receive
        end
      end

      class EmeraldThread(T)
        @channel : Channel(T)
        @thread : Thread

        def initialize(&block : -> T)
          @channel = Channel(T).new(1)
          ch = @channel
          @thread = Thread.new { ch.send(block.call) }
        end

        def self.spawn(&block : -> T) : EmeraldThread(T) forall T
          EmeraldThread(T).new(&block)
        end

        def await : T
          @channel.receive
        end
      end

      PRELUDE

      emit_llvm_runtime(io) if emit_llvm
    end

    private def emit_llvm_runtime(io : IO)
      io << <<-PRELUDE
      require "llvm"

      alias EmeraldLLVMContextRef = LibLLVM::ContextRef
      alias EmeraldLLVMModuleRef = LibLLVM::ModuleRef
      alias EmeraldLLVMBuilderRef = LibLLVM::BuilderRef
      alias EmeraldLLVMTypeRef = LibLLVM::TypeRef
      alias EmeraldLLVMValueRef = LibLLVM::ValueRef
      alias EmeraldLLVMBasicBlockRef = LibLLVM::BasicBlockRef

      lib LibLLVM
        fun emerald_slot_parent = LLVMGetBasicBlockParent(block : BasicBlockRef) : ValueRef
        fun emerald_slot_entry = LLVMGetEntryBasicBlock(function : ValueRef) : BasicBlockRef
        fun emerald_slot_context = LLVMGetTypeContext(type : TypeRef) : ContextRef
        fun emerald_slot_first = LLVMGetFirstInstruction(block : BasicBlockRef) : ValueRef
        fun emerald_slot_next = LLVMGetNextInstruction(instruction : ValueRef) : ValueRef
        fun emerald_slot_phi = LLVMIsAPHINode(value : ValueRef) : ValueRef
        fun emerald_slot_before = LLVMPositionBuilderBefore(builder : BuilderRef, instruction : ValueRef)
        fun emerald_frem = LLVMBuildFRem(builder : BuilderRef, lhs : ValueRef, rhs : ValueRef, name : Char*) : ValueRef
        fun initialize_x86_target_info = LLVMInitializeX86TargetInfo
        fun initialize_x86_target = LLVMInitializeX86Target
        fun initialize_x86_target_mc = LLVMInitializeX86TargetMC
        fun initialize_x86_asm_printer = LLVMInitializeX86AsmPrinter
        fun initialize_x86_asm_parser = LLVMInitializeX86AsmParser
        fun initialize_aarch64_target_info = LLVMInitializeAArch64TargetInfo
        fun initialize_aarch64_target = LLVMInitializeAArch64Target
        fun initialize_aarch64_target_mc = LLVMInitializeAArch64TargetMC
        fun initialize_aarch64_asm_printer = LLVMInitializeAArch64AsmPrinter
        fun initialize_aarch64_asm_parser = LLVMInitializeAArch64AsmParser
      end

      module EmeraldRuntimeLlvm
        RETURN_STATUS_ACTION = LLVM::VerifierFailureAction::ReturnStatusAction
        ASSEMBLY_FILE = 0_i32
        OBJECT_FILE = 1_i32

        @@last_error = ""
        @@last_link_command = ""
        @@last_link_output = ""
        @@last_link_error = ""
        @@last_runtime_command = ""
        @@last_runtime_output = ""
        @@last_runtime_error = ""

        def self.initialize_native_target : Bool
          @@last_error = ""
          LLVM.init_native_target
          true
        rescue ex : Exception
          @@last_error = ex.message || ex.class.name
          false
        end

        def self.initialize_target(triple : String) : Bool
          @@last_error = ""
          normalized = LLVM.normalize_triple(triple)

          if normalized.includes?("x86_64") || normalized.includes?("i686") || normalized.includes?("i386")
            LibLLVM.initialize_x86_target_info
            LibLLVM.initialize_x86_target
            LibLLVM.initialize_x86_target_mc
            LibLLVM.initialize_x86_asm_printer
            LibLLVM.initialize_x86_asm_parser
            return true
          end

          if normalized.includes?("aarch64") || normalized.includes?("arm64")
            LibLLVM.initialize_aarch64_target_info
            LibLLVM.initialize_aarch64_target
            LibLLVM.initialize_aarch64_target_mc
            LibLLVM.initialize_aarch64_asm_printer
            LibLLVM.initialize_aarch64_asm_parser
            return true
          end

          LLVM.init_native_target
          true
        rescue ex : Exception
          @@last_error = ex.message || ex.class.name
          false
        end

        def self.default_target_triple : String
          LLVM.default_target_triple
        end

        def self.normalize_target_triple(triple : String) : String
          LLVM.normalize_triple(triple)
        end

        def self.lookup_target(triple : String) : Int64
          @@last_error = ""

          target_ref = Pointer(Void).null.as(LibLLVM::TargetRef)
          error_message = Pointer(UInt8).null
          status = LibLLVM.get_target_from_triple(triple.to_unsafe, pointerof(target_ref), pointerof(error_message))

          if status == 0
            return raw(target_ref)
          end

          @@last_error = error_message.null? ? "LLVM target lookup failed for \#{triple}" : String.new(error_message)
          dispose_error_message(error_message)
          0_i64
        end

        def self.last_error : String
          @@last_error
        end

        def self.native_object_extension : String
          {% if flag?(:win32) %}
            ".obj"
          {% else %}
            ".o"
          {% end %}
        end

        def self.native_executable_extension : String
          {% if flag?(:win32) %}
            ".exe"
          {% else %}
            ""
          {% end %}
        end

        def self.target_name(target_handle : Int64) : String
          pointer = LibLLVM.get_target_name(target(target_handle))
          return "" if pointer.null?

          String.new(pointer)
        end

        def self.target_description(target_handle : Int64) : String
          pointer = LibLLVM.get_target_description(target(target_handle))
          return "" if pointer.null?

          String.new(pointer)
        end

        def self.create_target_machine(target_handle : Int64, triple : String, cpu : String, features : String, optimization_level : Int64) : Int64
          @@last_error = ""
          level = LLVM::CodeGenOptLevel.from_value(normalize_optimization_level(optimization_level))
          machine = LibLLVM.create_target_machine(target(target_handle), triple.to_unsafe, cpu.to_unsafe, features.to_unsafe, level, LLVM::RelocMode::Default, LLVM::CodeModel::Default)
          return raw(machine) unless machine.null?

          @@last_error = "LLVM target machine creation failed for \#{triple}"
          0_i64
        rescue ex : Exception
          @@last_error = ex.message || ex.class.name
          0_i64
        end

        def self.dispose_target_machine(machine_handle : Int64)
          return if machine_handle == 0_i64

          LibLLVM.dispose_target_machine(target_machine(machine_handle))
          nil
        end

        def self.target_machine_apply_data_layout(machine_handle : Int64, module_handle : Int64) : Bool
          @@last_error = ""
          data = LibLLVM.create_target_data_layout(target_machine(machine_handle))

          if data.null?
            @@last_error = "LLVM target data layout creation failed"
            return false
          end

          LibLLVM.set_module_data_layout(mod(module_handle), data)
          LibLLVM.dispose_target_data(data)
          true
        rescue ex : Exception
          @@last_error = ex.message || ex.class.name
          false
        end

        def self.target_machine_emit_object_file(machine_handle : Int64, module_handle : Int64, path : String) : Bool
          emit_target_machine_file(machine_handle, module_handle, path, OBJECT_FILE)
        end

        def self.target_machine_emit_assembly_file(machine_handle : Int64, module_handle : Int64, path : String) : Bool
          emit_target_machine_file(machine_handle, module_handle, path, ASSEMBLY_FILE)
        end

        def self.run_passes(module_handle : Int64, passes : String) : Bool
          @@last_error = ""
          options = LibLLVM.create_pass_builder_options
          error = LibLLVM.run_passes(mod(module_handle), passes.to_unsafe, target_machine(0_i64), options)
          LibLLVM.dispose_pass_builder_options(options)

          unless error.null?
            message = LibLLVM.get_error_message(error)
            @@last_error = message.null? ? "LLVM pass pipeline failed" : String.new(message)
            LibLLVM.dispose_error_message(message) unless message.null?
            return false
          end

          true
        rescue ex : Exception
          @@last_error = ex.message || ex.class.name
          false
        end

        def self.link_executable(output : String, object_files, library_paths, libraries, extra_args) : Bool
          @@last_link_command = ""
          @@last_link_output = ""
          @@last_link_error = ""

          ensure_parent_directory(output)

          command = ENV["EMERALD_CC"]? || default_c_compiler
          args = [] of String
          extra_values = [] of String
          filtered_extra_values = [] of String

          append_string_list(extra_values, extra_args)
          command = extract_compiler_override(command, extra_values, filtered_extra_values)
          linker_extra_values = [] of String
          target_name = extract_emerald_target(filtered_extra_values, linker_extra_values)
          filtered_extra_values = linker_extra_values
          append_string_list(args, object_files)
          append_default_linker_args(args, filtered_extra_values, target_name)

          library_path_values = [] of String
          append_string_list(library_path_values, library_paths)
          library_path_values.each do |path|
            args << "-L\#{path}"
          end

          library_values = [] of String
          append_string_list(library_values, libraries)
          library_values.each do |library|
            args << "-l\#{library}"
          end

          filtered_extra_values.each do |argument|
            args << argument
          end

          if ENV["EMERALD_RUNTIME_ENABLE_LLVM"]? == "1"
            if llvm_lib_dir = ENV["EMERALD_LLVM_LIB_DIR"]?
              args << "-L" + llvm_lib_dir unless llvm_lib_dir.empty?
            end

            llvm_library = ENV["EMERALD_LLVM_LIBRARY"]? || "LLVM"
            args << "-l" + llvm_library
          end

          args << "-o"
          args << output

          @@last_link_command = ([command] + args).join(" ")
          output_buffer = IO::Memory.new
          error_buffer = IO::Memory.new

          status = Process.run(command, args, output: output_buffer, error: error_buffer)

          @@last_link_output = output_buffer.to_s
          @@last_link_error = error_buffer.to_s
          status.success?
        rescue ex : Exception
          @@last_link_error = ex.message || ex.class.name
          false
        end

        def self.linker_last_command : String
          @@last_link_command
        end

        def self.linker_last_output : String
          @@last_link_output
        end

        def self.linker_last_error : String
          @@last_link_error
        end

        def self.runtime_source_path : String
          find_runtime_file("emerald_runtime.c")
        end

        def self.runtime_header_path : String
          find_runtime_file("emerald_runtime.h")
        end

        def self.runtime_flow_library_name : String
          ""
        end

        def self.runtime_flow_library_path : String
          ""
        end

        def self.ensure_parent_directory(path : String)
          parent = File.dirname(path)
          Dir.mkdir_p(parent) unless parent == "." || parent.empty?
        end

        def self.compile_runtime_object(source : String, output : String, extra_args) : Bool
          @@last_runtime_command = ""
          @@last_runtime_output = ""
          @@last_runtime_error = ""

          ensure_parent_directory(output)

          unless File.exists?(source)
            @@last_runtime_error = "Emerald runtime source not found: " + source
            return false
          end

          command = ENV["EMERALD_CC"]? || default_c_compiler
          args = [] of String
          extra_values = [] of String
          filtered_extra_values = [] of String
          append_string_list(extra_values, extra_args)
          command = extract_compiler_override(command, extra_values, filtered_extra_values)
          runtime_extra_values = [] of String
          extract_emerald_target(filtered_extra_values, runtime_extra_values)
          filtered_extra_values = runtime_extra_values

          args << "-std=c11"
          args << "-O2"
          args << "-I" + File.dirname(source)

          if ENV["EMERALD_RUNTIME_ENABLE_LLVM"]? == "1"
            args << "-DEMERALD_RUNTIME_ENABLE_LLVM=1"
          end

          filtered_extra_values.each do |argument|
            args << argument
          end

          args << "-c"
          args << source
          args << "-o"
          args << output

          @@last_runtime_command = ([command] + args).join(" ")
          output_buffer = IO::Memory.new
          error_buffer = IO::Memory.new

          status = Process.run(command, args, output: output_buffer, error: error_buffer)

          @@last_runtime_output = output_buffer.to_s
          @@last_runtime_error = error_buffer.to_s
          status.success?
        rescue ex : Exception
          @@last_runtime_error = ex.message || ex.class.name
          false
        end

        def self.compile_ir_object(source : String, output : String, extra_args) : Bool
          @@last_runtime_command = ""
          @@last_runtime_output = ""
          @@last_runtime_error = ""

          ensure_parent_directory(output)

          unless File.exists?(source)
            @@last_runtime_error = "Emerald runtime source not found: " + source
            return false
          end

          command = ENV["EMERALD_CC"]? || default_c_compiler
          args = [] of String
          extra_values = [] of String
          filtered_extra_values = [] of String
          append_string_list(extra_values, extra_args)
          command = extract_compiler_override(command, extra_values, filtered_extra_values)
          runtime_extra_values = [] of String
          extract_emerald_target(filtered_extra_values, runtime_extra_values)
          filtered_extra_values = runtime_extra_values

          args << "-O2"
          args << "-I" + File.dirname(source)

          if ENV["EMERALD_RUNTIME_ENABLE_LLVM"]? == "1"
            args << "-DEMERALD_RUNTIME_ENABLE_LLVM=1"
          end

          filtered_extra_values.each do |argument|
            args << argument
          end

          args << "-c"
          args << source
          args << "-o"
          args << output

          @@last_runtime_command = ([command] + args).join(" ")
          output_buffer = IO::Memory.new
          error_buffer = IO::Memory.new

          status = Process.run(command, args, output: output_buffer, error: error_buffer)

          @@last_runtime_output = output_buffer.to_s
          @@last_runtime_error = error_buffer.to_s
          status.success?
        rescue ex : Exception
          @@last_runtime_error = ex.message || ex.class.name
          false
        end

        def self.runtime_last_command : String
          @@last_runtime_command
        end

        def self.runtime_last_output : String
          @@last_runtime_output
        end

        def self.runtime_last_error : String
          @@last_runtime_error
        end

        def self.create_context : Int64
          raw(LibLLVM.create_context)
        end

        def self.dispose_context(handle : Int64)
          return if handle == 0_i64

          LibLLVM.dispose_context(context(handle))
          nil
        end

        def self.create_module(context_handle : Int64, name : String) : Int64
          raw(LibLLVM.module_create_with_name_in_context(name.to_unsafe, context(context_handle)))
        end

        def self.dispose_module(handle : Int64)
          handle
          nil
        end

        def self.module_set_target(handle : Int64, triple : String)
          LibLLVM.set_target(mod(handle), triple.to_unsafe)
          nil
        end

        def self.module_to_ir(handle : Int64) : String
          message = LibLLVM.print_module_to_string(mod(handle))
          return "" if message.null?

          result = String.new(message)
          LibLLVM.dispose_message(message)
          result
        end

        def self.module_write_ir(handle : Int64, path : String) : Bool
          ensure_parent_directory(path)
          error_message = Pointer(Pointer(UInt8)).malloc(1)
          error_message.value = Pointer(UInt8).null
          status = LibLLVM.print_module_to_file(mod(handle), path.to_unsafe, error_message)
          return true if status == 0

          dispose_error_message(error_message.value)
          false
        end

        def self.module_verify(handle : Int64) : Bool
          error_message = Pointer(Pointer(UInt8)).malloc(1)
          error_message.value = Pointer(UInt8).null
          status = LibLLVM.verify_module(mod(handle), RETURN_STATUS_ACTION, error_message)
          dispose_error_message(error_message.value)
          status == 0
        end

        def self.module_verify_message(handle : Int64) : String
          error_message = Pointer(Pointer(UInt8)).malloc(1)
          error_message.value = Pointer(UInt8).null
          status = LibLLVM.verify_module(mod(handle), RETURN_STATUS_ACTION, error_message)
          return "" if status == 0
          return "LLVM verification failed" if error_message.value.null?

          result = String.new(error_message.value)
          LibLLVM.dispose_message(error_message.value)
          result
        end

        def self.create_builder(context_handle : Int64) : Int64
          raw(LibLLVM.create_builder_in_context(context(context_handle)))
        end

        def self.dispose_builder(handle : Int64)
          return if handle == 0_i64

          LibLLVM.dispose_builder(builder(handle))
          nil
        end

        def self.current_block(builder_handle : Int64) : Int64
          raw(LibLLVM.get_insert_block(builder(builder_handle)))
        end

        def self.void_type(context_handle : Int64) : Int64
          raw(LibLLVM.void_type_in_context(context(context_handle)))
        end

        def self.i1_type(context_handle : Int64) : Int64
          raw(LibLLVM.int1_type_in_context(context(context_handle)))
        end

        def self.i8_type(context_handle : Int64) : Int64
          raw(LibLLVM.int8_type_in_context(context(context_handle)))
        end

        def self.i16_type(context_handle : Int64) : Int64
          raw(LibLLVM.int16_type_in_context(context(context_handle)))
        end

        def self.i32_type(context_handle : Int64) : Int64
          raw(LibLLVM.int32_type_in_context(context(context_handle)))
        end

        def self.i64_type(context_handle : Int64) : Int64
          raw(LibLLVM.int64_type_in_context(context(context_handle)))
        end

        def self.int_type(context_handle : Int64, bits : Int64) : Int64
          raw(LibLLVM.int_type_in_context(context(context_handle), bits.to_u32))
        end

        def self.float_type(context_handle : Int64) : Int64
          raw(LibLLVM.float_type_in_context(context(context_handle)))
        end

        def self.double_type(context_handle : Int64) : Int64
          raw(LibLLVM.double_type_in_context(context(context_handle)))
        end

        def self.opaque_pointer_type(context_handle : Int64) : Int64
          {% if LibLLVM::IS_LT_150 %}
            raw(LibLLVM.pointer_type(LibLLVM.int8_type_in_context(context(context_handle)), 0_u32))
          {% else %}
            raw(LibLLVM.pointer_type_in_context(context(context_handle), 0_u32))
          {% end %}
        end

        def self.pointer_type(type_handle : Int64) : Int64
          raw(LibLLVM.pointer_type(llvm_type(type_handle), 0_u32))
        end

        def self.array_type(type_handle : Int64, count : Int64) : Int64
          raw(LibLLVM.array_type(llvm_type(type_handle), count.to_u32))
        end

        def self.struct_type(context_handle : Int64, element_types, packed : Bool) : Int64
          with_type_refs(element_types) do |types, count|
            raw(LibLLVM.struct_type_in_context(context(context_handle), types, count, packed ? 1 : 0))
          end
        end

        def self.named_struct_type(context_handle : Int64, name : String) : Int64
          raw(LibLLVM.struct_create_named(context(context_handle), name.to_unsafe))
        end

        def self.struct_set_body(type_handle : Int64, element_types, packed : Bool)
          with_type_refs(element_types) do |types, count|
            LibLLVM.struct_set_body(llvm_type(type_handle), types, count, packed ? 1 : 0)
          end
          nil
        end

        def self.function_type(return_type_handle : Int64) : Int64
          raw(LibLLVM.function_type(llvm_type(return_type_handle), Pointer(EmeraldLLVMTypeRef).null, 0_u32, 0_i32))
        end

        def self.function_type_with_params(return_type_handle : Int64, param_types, variadic : Bool) : Int64
          with_type_refs(param_types) do |types, count|
            raw(LibLLVM.function_type(llvm_type(return_type_handle), types, count, variadic ? 1 : 0))
          end
        end

        def self.type_to_ir(type_handle : Int64) : String
          message = LibLLVM.print_type_to_string(llvm_type(type_handle))
          return "" if message.null?

          result = String.new(message)
          LibLLVM.dispose_message(message)
          result
        end

        def self.size_of(type_handle : Int64) : Int64
          raw(LibLLVM.size_of(llvm_type(type_handle)))
        end

        def self.align_of(type_handle : Int64) : Int64
          raw(LibLLVM.align_of(llvm_type(type_handle)))
        end

        def self.add_function(module_handle : Int64, name : String, function_type_handle : Int64) : Int64
          raw(LibLLVM.add_function(mod(module_handle), name.to_unsafe, llvm_type(function_type_handle)))
        end

        def self.get_function(module_handle : Int64, name : String) : Int64
          {% if LibLLVM::IS_LT_200 %}
            raw(LibLLVM.get_named_function(mod(module_handle), name.to_unsafe))
          {% else %}
            raw(LibLLVM.get_named_function_with_length(mod(module_handle), name.to_unsafe, name.bytesize))
          {% end %}
        end

        def self.function_parameter_count(function_handle : Int64) : Int64
          LibLLVM.get_count_params(value(function_handle)).to_i64
        end

        def self.function_parameter(function_handle : Int64, index : Int64) : Int64
          raw(LibLLVM.get_param(value(function_handle), index.to_u32))
        end

        def self.append_block(context_handle : Int64, function_handle : Int64, name : String) : Int64
          raw(LibLLVM.append_basic_block_in_context(context(context_handle), value(function_handle), name.to_unsafe))
        end

        def self.block_name(block_handle : Int64) : String
          pointer = LibLLVM.get_basic_block_name(block(block_handle))
          return "" if pointer.null?

          String.new(pointer)
        end

        def self.add_global(module_handle : Int64, name : String, type_handle : Int64) : Int64
          raw(LibLLVM.add_global(mod(module_handle), llvm_type(type_handle), name.to_unsafe))
        end

        def self.get_global(module_handle : Int64, name : String) : Int64
          {% if LibLLVM::IS_LT_200 %}
            raw(LibLLVM.get_named_global(mod(module_handle), name.to_unsafe))
          {% else %}
            raw(LibLLVM.get_named_global_with_length(mod(module_handle), name.to_unsafe, name.bytesize))
          {% end %}
        end

        def self.global_set_initializer(global_handle : Int64, value_handle : Int64)
          LibLLVM.set_initializer(value(global_handle), value(value_handle))
          nil
        end

        def self.global_set_constant(global_handle : Int64, constant : Bool)
          LibLLVM.set_global_constant(value(global_handle), constant ? 1 : 0)
          nil
        end

        def self.value_set_linkage(value_handle : Int64, linkage : Int64)
          LibLLVM.set_linkage(value(value_handle), LLVM::Linkage.from_value(linkage.to_i32))
          nil
        end

        def self.value_type(value_handle : Int64) : Int64
          raw(LibLLVM.type_of(value(value_handle)))
        end

        def self.value_name(value_handle : Int64) : String
          pointer = LibLLVM.get_value_name(value(value_handle))
          return "" if pointer.null?

          String.new(pointer)
        end

        def self.value_set_name(value_handle : Int64, name : String)
          LibLLVM.set_value_name(value(value_handle), name.to_unsafe)
          nil
        end

        def self.value_to_ir(value_handle : Int64) : String
          message = LibLLVM.print_value_to_string(value(value_handle))
          return "" if message.null?

          result = String.new(message)
          LibLLVM.dispose_message(message)
          result
        end

        def self.position_at_end(builder_handle : Int64, block_handle : Int64)
          LibLLVM.position_builder_at_end(builder(builder_handle), block(block_handle))
          nil
        end

        def self.return_void(builder_handle : Int64)
          LibLLVM.build_ret_void(builder(builder_handle))
          nil
        end

        def self.return_value(builder_handle : Int64, value_handle : Int64)
          LibLLVM.build_ret(builder(builder_handle), value(value_handle))
          nil
        end

        def self.build_branch(builder_handle : Int64, block_handle : Int64) : Int64
          raw(LibLLVM.build_br(builder(builder_handle), block(block_handle)))
        end

        def self.build_conditional_branch(builder_handle : Int64, condition_handle : Int64, true_block_handle : Int64, false_block_handle : Int64) : Int64
          raw(LibLLVM.build_cond(builder(builder_handle), value(condition_handle), block(true_block_handle), block(false_block_handle)))
        end

        def self.build_unreachable(builder_handle : Int64) : Int64
          raw(LibLLVM.build_unreachable(builder(builder_handle)))
        end

        def self.const_integer_text(type_handle : Int64, text : String) : Int64
          raw(LibLLVM.const_int(llvm_type(type_handle), text.to_i64.to_u64!, 1_i32))
        end
        def self.const_float_text(type_handle : Int64, text : String) : Int64
          raise "Float literal out of range" unless text.to_f64.finite?
          raw(LibLLVM.const_real_of_string_and_size(llvm_type(type_handle), text.to_unsafe, text.bytesize.to_u32))
        end
        def self.build_extract_value(builder_handle : Int64, value_handle : Int64, index : Int64, name : String) : Int64
          raw(LibLLVM.build_extract_value(builder(builder_handle), value(value_handle), index.to_u32, name.to_unsafe))
        end
        def self.build_float_operation(b : Int64, l : Int64, r : Int64, operation : Int64, name : String) : Int64
          result = case operation
          when 0 then LibLLVM.build_fadd(builder(b), value(l), value(r), name.to_unsafe)
          when 1 then LibLLVM.build_fsub(builder(b), value(l), value(r), name.to_unsafe)
          when 2 then LibLLVM.build_fmul(builder(b), value(l), value(r), name.to_unsafe)
          when 3 then LibLLVM.build_fdiv(builder(b), value(l), value(r), name.to_unsafe)
          when 4 then LibLLVM.emerald_frem(builder(b), value(l), value(r), name.to_unsafe)
          when 5 then LibLLVM.build_fcmp(builder(b), LLVM::RealPredicate.new(4), value(l), value(r), name.to_unsafe)
          when 6 then LibLLVM.build_fcmp(builder(b), LLVM::RealPredicate.new(5), value(l), value(r), name.to_unsafe)
          when 7 then LibLLVM.build_fcmp(builder(b), LLVM::RealPredicate.new(2), value(l), value(r), name.to_unsafe)
          when 8 then LibLLVM.build_fcmp(builder(b), LLVM::RealPredicate.new(3), value(l), value(r), name.to_unsafe)
          when 9 then LibLLVM.build_fcmp(builder(b), LLVM::RealPredicate.new(1), value(l), value(r), name.to_unsafe)
          when 10 then LibLLVM.build_fcmp(builder(b), LLVM::RealPredicate.new(14), value(l), value(r), name.to_unsafe)
          when 11 then LibLLVM.build_si2fp(builder(b), value(l), llvm_type(r), name.to_unsafe)
          when 12 then LibLLVM.build_fneg(builder(b), value(l), name.to_unsafe)
          else raise "Invalid Float operation"
          end
          raw(result)
        end

        def self.const_int(type_handle : Int64, number : Int64) : Int64
          raw(LibLLVM.const_int(llvm_type(type_handle), number.to_u64!, 1_i32))
        end

        def self.const_bool(type_handle : Int64, flag : Bool) : Int64
          raw(LibLLVM.const_int(llvm_type(type_handle), flag ? 1_u64 : 0_u64, 0_i32))
        end

        def self.const_null(type_handle : Int64) : Int64
          raw(LibLLVM.const_null(llvm_type(type_handle)))
        end

        def self.const_pointer_null(type_handle : Int64) : Int64
          raw(LibLLVM.const_pointer_null(llvm_type(type_handle)))
        end

        def self.const_string(context_handle : Int64, text : String, null_terminate : Bool) : Int64
          {% if LibLLVM::IS_LT_190 %}
            raw(LibLLVM.const_string_in_context(context(context_handle), text.to_unsafe, text.bytesize.to_u32, null_terminate ? 0 : 1))
          {% else %}
            raw(LibLLVM.const_string_in_context2(context(context_handle), text.to_unsafe, text.bytesize, null_terminate ? 0 : 1))
          {% end %}
        end

        def self.const_struct(context_handle : Int64, values, packed : Bool) : Int64
          with_value_refs(values) do |refs, count|
            raw(LibLLVM.const_struct_in_context(context(context_handle), refs, count, packed ? 1 : 0))
          end
        end

        def self.const_array(type_handle : Int64, values) : Int64
          with_value_refs(values) do |refs, count|
            raw(LibLLVM.const_array(llvm_type(type_handle), refs, count))
          end
        end

        def self.build_add(builder_handle : Int64, left_handle : Int64, right_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_add(builder(builder_handle), value(left_handle), value(right_handle), name.to_unsafe))
        end

        def self.build_sub(builder_handle : Int64, left_handle : Int64, right_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_sub(builder(builder_handle), value(left_handle), value(right_handle), name.to_unsafe))
        end

        def self.build_mul(builder_handle : Int64, left_handle : Int64, right_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_mul(builder(builder_handle), value(left_handle), value(right_handle), name.to_unsafe))
        end

        def self.build_signed_div(builder_handle : Int64, left_handle : Int64, right_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_sdiv(builder(builder_handle), value(left_handle), value(right_handle), name.to_unsafe))
        end

        def self.build_unsigned_div(builder_handle : Int64, left_handle : Int64, right_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_udiv(builder(builder_handle), value(left_handle), value(right_handle), name.to_unsafe))
        end

        def self.build_signed_rem(builder_handle : Int64, left_handle : Int64, right_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_srem(builder(builder_handle), value(left_handle), value(right_handle), name.to_unsafe))
        end

        def self.build_unsigned_rem(builder_handle : Int64, left_handle : Int64, right_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_urem(builder(builder_handle), value(left_handle), value(right_handle), name.to_unsafe))
        end

        def self.build_neg(builder_handle : Int64, value_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_neg(builder(builder_handle), value(value_handle), name.to_unsafe))
        end

        def self.build_and(builder_handle : Int64, left_handle : Int64, right_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_and(builder(builder_handle), value(left_handle), value(right_handle), name.to_unsafe))
        end

        def self.build_or(builder_handle : Int64, left_handle : Int64, right_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_or(builder(builder_handle), value(left_handle), value(right_handle), name.to_unsafe))
        end

        def self.build_xor(builder_handle : Int64, left_handle : Int64, right_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_xor(builder(builder_handle), value(left_handle), value(right_handle), name.to_unsafe))
        end

        def self.build_not(builder_handle : Int64, value_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_not(builder(builder_handle), value(value_handle), name.to_unsafe))
        end

        def self.build_shift_left(builder_handle : Int64, left_handle : Int64, right_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_shl(builder(builder_handle), value(left_handle), value(right_handle), name.to_unsafe))
        end

        def self.build_logical_shift_right(builder_handle : Int64, left_handle : Int64, right_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_lshr(builder(builder_handle), value(left_handle), value(right_handle), name.to_unsafe))
        end

        def self.build_arithmetic_shift_right(builder_handle : Int64, left_handle : Int64, right_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_ashr(builder(builder_handle), value(left_handle), value(right_handle), name.to_unsafe))
        end

        def self.build_int_compare(builder_handle : Int64, predicate : Int64, left_handle : Int64, right_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_icmp(builder(builder_handle), LLVM::IntPredicate.from_value(predicate.to_i32), value(left_handle), value(right_handle), name.to_unsafe))
        end

        def self.build_entry_alloca(builder_handle : Int64, type_handle : Int64, name : String) : Int64
          current = LibLLVM.get_insert_block(builder(builder_handle))
          return 0_i64 if current.null?
          slot_type = llvm_type(type_handle)
          entry = LibLLVM.emerald_slot_entry(LibLLVM.emerald_slot_parent(current))
          slots = LibLLVM.create_builder_in_context(LibLLVM.emerald_slot_context(slot_type))
          first = LibLLVM.emerald_slot_first(entry)
          while !first.null? && !LibLLVM.emerald_slot_phi(first).null?
            first = LibLLVM.emerald_slot_next(first)
          end
          if first.null?
            LibLLVM.position_builder_at_end(slots, entry)
          else
            LibLLVM.emerald_slot_before(slots, first)
          end
          result = raw(LibLLVM.build_alloca(slots, slot_type, name.to_unsafe))
          LibLLVM.dispose_builder(slots)
          result
        end

        def self.build_alloca(builder_handle : Int64, type_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_alloca(builder(builder_handle), llvm_type(type_handle), name.to_unsafe))
        end

        def self.build_load(builder_handle : Int64, type_handle : Int64, pointer_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_load2(builder(builder_handle), llvm_type(type_handle), value(pointer_handle), name.to_unsafe))
        end

        def self.build_store(builder_handle : Int64, value_handle : Int64, pointer_handle : Int64) : Int64
          raw(LibLLVM.build_store(builder(builder_handle), value(value_handle), value(pointer_handle)))
        end

        def self.build_gep(builder_handle : Int64, source_type_handle : Int64, pointer_handle : Int64, indices, name : String) : Int64
          with_value_refs(indices) do |refs, count|
            raw(LibLLVM.build_gep2(builder(builder_handle), llvm_type(source_type_handle), value(pointer_handle), refs, count, name.to_unsafe))
          end
        end

        def self.build_inbounds_gep(builder_handle : Int64, source_type_handle : Int64, pointer_handle : Int64, indices, name : String) : Int64
          with_value_refs(indices) do |refs, count|
            raw(LibLLVM.build_inbounds_gep2(builder(builder_handle), llvm_type(source_type_handle), value(pointer_handle), refs, count, name.to_unsafe))
          end
        end

        def self.build_global_string_pointer(builder_handle : Int64, text : String, name : String) : Int64
          raw(LibLLVM.build_global_string_ptr(builder(builder_handle), text.to_unsafe, name.to_unsafe))
        end

        def self.build_call(builder_handle : Int64, function_type_handle : Int64, function_handle : Int64, args, name : String) : Int64
          with_value_refs(args) do |refs, count|
            raw(LibLLVM.build_call2(builder(builder_handle), llvm_type(function_type_handle), value(function_handle), refs, count, name.to_unsafe))
          end
        end

        def self.build_phi(builder_handle : Int64, type_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_phi(builder(builder_handle), llvm_type(type_handle), name.to_unsafe))
        end

        def self.add_incoming(phi_handle : Int64, value_handle : Int64, block_handle : Int64)
          values = Pointer(EmeraldLLVMValueRef).malloc(1)
          blocks = Pointer(EmeraldLLVMBasicBlockRef).malloc(1)
          values[0] = value(value_handle)
          blocks[0] = block(block_handle)
          LibLLVM.add_incoming(value(phi_handle), values, blocks, 1_u32)
          nil
        end

        def self.build_select(builder_handle : Int64, condition_handle : Int64, true_handle : Int64, false_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_select(builder(builder_handle), value(condition_handle), value(true_handle), value(false_handle), name.to_unsafe))
        end

        def self.build_truncate(builder_handle : Int64, value_handle : Int64, type_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_trunc(builder(builder_handle), value(value_handle), llvm_type(type_handle), name.to_unsafe))
        end

        def self.build_zero_extend(builder_handle : Int64, value_handle : Int64, type_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_zext(builder(builder_handle), value(value_handle), llvm_type(type_handle), name.to_unsafe))
        end

        def self.build_sign_extend(builder_handle : Int64, value_handle : Int64, type_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_sext(builder(builder_handle), value(value_handle), llvm_type(type_handle), name.to_unsafe))
        end

        def self.build_pointer_to_int(builder_handle : Int64, value_handle : Int64, type_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_ptr2int(builder(builder_handle), value(value_handle), llvm_type(type_handle), name.to_unsafe))
        end

        def self.build_int_to_pointer(builder_handle : Int64, value_handle : Int64, type_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_int2ptr(builder(builder_handle), value(value_handle), llvm_type(type_handle), name.to_unsafe))
        end

        def self.build_bit_cast(builder_handle : Int64, value_handle : Int64, type_handle : Int64, name : String) : Int64
          raw(LibLLVM.build_bit_cast(builder(builder_handle), value(value_handle), llvm_type(type_handle), name.to_unsafe))
        end

        def self.external_linkage : Int64
          LLVM::Linkage::External.value.to_i64
        end

        def self.internal_linkage : Int64
          LLVM::Linkage::Internal.value.to_i64
        end

        def self.private_linkage : Int64
          LLVM::Linkage::Private.value.to_i64
        end

        private def self.emit_target_machine_file(machine_handle : Int64, module_handle : Int64, path : String, file_type : Int32) : Bool
          @@last_error = ""
          codegen = file_type == OBJECT_FILE ? LLVM::CodeGenFileType::ObjectFile : LLVM::CodeGenFileType::AssemblyFile
          status = LibLLVM.target_machine_emit_to_file(target_machine(machine_handle), mod(module_handle), path.to_unsafe, codegen, out error_message)
          return true if status == 0

          @@last_error = error_message.null? ? "LLVM target machine emit failed for \#{path}" : String.new(error_message)
          dispose_error_message(error_message)
          false
        rescue ex : Exception
          @@last_error = ex.message || ex.class.name
          false
        end

        private def self.normalize_optimization_level(level : Int64) : Int32
          return 0_i32 if level <= 0
          return 1_i32 if level == 1
          return 2_i32 if level == 2

          3_i32
        end

        private def self.copy_and_dispose_message(message : UInt8*) : String
          return "" if message.null?

          result = String.new(message)
          LibLLVM.dispose_message(message)
          result
        end

        private def self.append_string_list(target : Array(String), source)
          count = source.size.to_i
          index = 0

          while index < count
            target << source.get(index.to_i64)
            index += 1
          end
        end

        private def self.extract_compiler_override(default_command : String, source : Array(String), target : Array(String)) : String
          command = default_command
          prefix = "--emerald-cc="

          source.each do |argument|
            if argument.starts_with?(prefix)
              command = argument[prefix.size, argument.size - prefix.size]
            else
              target << argument
            end
          end

          command
        end

        private def self.extract_emerald_target(source : Array(String), target : Array(String)) : String
          target_name = "native"
          prefix = "--emerald-target="

          source.each do |argument|
            if argument.starts_with?(prefix)
              target_name = argument[prefix.size, argument.size - prefix.size]
            else
              target << argument
            end
          end

          target_name
        end

        private def self.append_default_linker_args(target : Array(String), explicit_args : Array(String), target_name : String)
          {% if flag?(:linux) %}
            return if target_name.starts_with?("windows")
            return if ENV["EMERALD_LINK_PIE"]? == "1"
            return if has_explicit_pie_mode?(explicit_args)

            target << "-no-pie"
          {% end %}
        end

        private def self.has_explicit_pie_mode?(args : Array(String)) : Bool
          args.each do |argument|
            return true if argument == "-pie"
            return true if argument == "-no-pie"
            return true if argument == "-shared"
            return true if argument == "-static-pie"
            return true if argument == "-Wl,-pie"
            return true if argument == "-Wl,-no-pie"
          end

          false
        end

        private def self.default_c_compiler : String
          if compiler = ENV["CC"]?
            return compiler
          end

          {% if flag?(:windows) %}
            "clang.exe"
          {% else %}
            "clang"
          {% end %}
        end


        private def self.find_runtime_file(name : String) : String
          explicit_source = ENV["EMERALD_RUNTIME_SOURCE"]?
          return explicit_source if explicit_source && name == "emerald_runtime.c" && File.exists?(explicit_source)

          explicit_header = ENV["EMERALD_RUNTIME_HEADER"]?
          return explicit_header if explicit_header && name == "emerald_runtime.h" && File.exists?(explicit_header)

          roots = [] of String

          if home = ENV["EMERALD_HOME"]?
            roots << home
          end

          roots << Dir.current

          if executable = Process.executable_path
            executable_dir = File.dirname(executable)
            roots << executable_dir
            roots << File.join(executable_dir, "..")
            roots << File.join(executable_dir, "..", "..")
            roots << File.join(executable_dir, "..", "..", "..")
          end

          expanded_roots = [] of String
          roots.each do |root|
            expanded = File.expand_path(root)
            expanded_roots << expanded
            expanded_roots << File.expand_path(File.join(expanded, ".."))
            expanded_roots << File.expand_path(File.join(expanded, "..", ".."))
          end

          expanded_roots.uniq.each do |root|
            candidate = File.join(root, "runtime", name)
            return candidate if File.exists?(candidate)
          end

          ""
        end

        private def self.with_type_refs(items)
          count = items.size.to_i
          return yield Pointer(EmeraldLLVMTypeRef).null, 0_u32 if count == 0

          refs = Pointer(EmeraldLLVMTypeRef).malloc(count)
          index = 0
          while index < count
            refs[index] = llvm_type(items.get(index.to_i64).handle)
            index += 1
          end
          yield refs, count.to_u32
        end

        private def self.with_value_refs(items)
          count = items.size.to_i
          return yield Pointer(EmeraldLLVMValueRef).null, 0_u32 if count == 0

          refs = Pointer(EmeraldLLVMValueRef).malloc(count)
          index = 0
          while index < count
            refs[index] = value(items.get(index.to_i64).handle)
            index += 1
          end
          yield refs, count.to_u32
        end

        private def self.dispose_error_message(message : UInt8*)
          return if message.null?

          LibLLVM.dispose_message(message)
        end

        private def self.raw(pointer : Void*) : Int64
          return 0_i64 if pointer.null?

          pointer.address.to_i64
        end

        private def self.raw(pointer : EmeraldLLVMContextRef) : Int64
          return 0_i64 if pointer.null?

          pointer.as(Pointer(Void)).address.to_i64
        end

        private def self.raw(pointer : EmeraldLLVMModuleRef) : Int64
          return 0_i64 if pointer.null?

          pointer.as(Pointer(Void)).address.to_i64
        end

        private def self.raw(pointer : EmeraldLLVMBuilderRef) : Int64
          return 0_i64 if pointer.null?

          pointer.as(Pointer(Void)).address.to_i64
        end

        private def self.raw(pointer : EmeraldLLVMTypeRef) : Int64
          return 0_i64 if pointer.null?

          pointer.as(Pointer(Void)).address.to_i64
        end

        private def self.raw(pointer : EmeraldLLVMValueRef) : Int64
          return 0_i64 if pointer.null?

          pointer.as(Pointer(Void)).address.to_i64
        end

        private def self.raw(pointer : EmeraldLLVMBasicBlockRef) : Int64
          return 0_i64 if pointer.null?

          pointer.as(Pointer(Void)).address.to_i64
        end

        private def self.raw(pointer : LibLLVM::TargetRef) : Int64
          return 0_i64 if pointer.null?

          pointer.as(Pointer(Void)).address.to_i64
        end

        private def self.raw(pointer : LibLLVM::TargetMachineRef) : Int64
          return 0_i64 if pointer.null?

          pointer.as(Pointer(Void)).address.to_i64
        end

        private def self.target(handle : Int64) : LibLLVM::TargetRef
          Pointer(Void).new(handle.to_u64).as(LibLLVM::TargetRef)
        end

        private def self.target_machine(handle : Int64) : LibLLVM::TargetMachineRef
          Pointer(Void).new(handle.to_u64).as(LibLLVM::TargetMachineRef)
        end

        private def self.context(handle : Int64) : EmeraldLLVMContextRef
          Pointer(Void).new(handle.to_u64).as(EmeraldLLVMContextRef)
        end

        private def self.mod(handle : Int64) : EmeraldLLVMModuleRef
          Pointer(Void).new(handle.to_u64).as(EmeraldLLVMModuleRef)
        end

        private def self.builder(handle : Int64) : EmeraldLLVMBuilderRef
          Pointer(Void).new(handle.to_u64).as(EmeraldLLVMBuilderRef)
        end

        private def self.llvm_type(handle : Int64) : EmeraldLLVMTypeRef
          Pointer(Void).new(handle.to_u64).as(EmeraldLLVMTypeRef)
        end

        private def self.value(handle : Int64) : EmeraldLLVMValueRef
          Pointer(Void).new(handle.to_u64).as(EmeraldLLVMValueRef)
        end

        private def self.block(handle : Int64) : EmeraldLLVMBasicBlockRef
          Pointer(Void).new(handle.to_u64).as(EmeraldLLVMBasicBlockRef)
        end
      end

      PRELUDE
    end
  end
end
