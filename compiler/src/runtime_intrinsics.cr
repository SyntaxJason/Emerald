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
      add_http(registry)
      add_tcp(registry)
      add_host_capabilities(registry)

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

    private def add(registry, receiver : String, method_name : String, param_types : Array(String), return_type : String, opcode : String, category : String)
      registry[{receiver, method_name}] = RuntimeStaticIntrinsic.new(receiver, method_name, param_types, return_type, opcode, category)
    end
  end
end
