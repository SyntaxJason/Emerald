# compiler/tools/installer/src/emerald_installer.cr
require "compress/zip"
require "file_utils"
require "http/client"
require "http/server"
require "json"
require "uri"

module EmeraldInstaller
  VERSION = "0.3.0"

  class InstallError < Exception
  end

  class CommandLine
    getter command : String
    getter prefix : String?
    getter payload : String?
    getter url : String?
    getter force : Bool
    getter yes : Bool
    getter configure_env : Bool

    def initialize(@command : String, @prefix : String?, @payload : String?, @url : String?, @force : Bool, @yes : Bool, @configure_env : Bool)
    end

    def download_url : String
      @url || ReleaseDownloader::DEFAULT_URL
    end

    def self.parse(args : Array(String)) : CommandLine
      command = args.first? || "ui"
      command = "help" if command == "--help" || command == "-h"
      prefix = nil
      payload = nil
      url = nil
      force = false
      yes = false
      configure_env = true

      index = 1
      while index < args.size
        arg = args[index]

        if arg == "--prefix"
          prefix = read_value(args, index, arg)
          index += 2
          next
        end

        if arg == "--payload"
          payload = read_value(args, index, arg)
          index += 2
          next
        end

        if arg == "--url"
          url = read_value(args, index, arg)
          index += 2
          next
        end

        if arg == "--force"
          force = true
          index += 1
          next
        end

        if arg == "--yes"
          yes = true
          index += 1
          next
        end

        if arg == "--set-env"
          configure_env = true
          index += 1
          next
        end

        if arg == "--no-env"
          configure_env = false
          index += 1
          next
        end

        if arg == "--help"
          command = "help"
          index += 1
          next
        end

        raise InstallError.new("Unknown option: #{arg}")
      end

      CommandLine.new(command, prefix, payload, url, force, yes, configure_env)
    end

    private def self.read_value(args : Array(String), index : Int32, name : String) : String
      value = args[index + 1]?
      raise InstallError.new("#{name} expects a value") unless value
      value
    end
  end

  class Platform
    def self.windows? : Bool
      {{ flag?(:win32) }}
    end

    def self.home : String
      home = ENV["HOME"]?
      return home if home && !home.empty?

      userprofile = ENV["USERPROFILE"]?
      return userprofile if userprofile && !userprofile.empty?

      raise InstallError.new("Cannot determine user home directory")
    end

    def self.default_prefix : String
      if windows?
        local_app_data = ENV["LOCALAPPDATA"]?
        return File.join(local_app_data, "Emerald") if local_app_data && !local_app_data.empty?
        return File.join(home, "AppData", "Local", "Emerald")
      end

      File.join(home, ".local", "Emerald")
    end

    def self.executable_name : String
      return "emeraldc.exe" if windows?
      "emeraldc"
    end

    def self.path_hint(bin_dir : String) : String
      if windows?
        return "Add #{bin_dir} to your user PATH from Windows Settings or PowerShell."
      end

      "Environment setup writes EMERALD_HOME, EMERALD_STDLIB, and adds #{bin_dir} to PATH for supported shells."
    end

    def self.temp_dir : String
      tmpdir = ENV["TMPDIR"]?
      return tmpdir if tmpdir && !tmpdir.empty?

      temp = ENV["TEMP"]?
      return temp if temp && !temp.empty?

      tmp = ENV["TMP"]?
      return tmp if tmp && !tmp.empty?

      return File.join(home, "AppData", "Local", "Temp") if windows?
      "/tmp"
    end
  end

  class InstallLayout
    getter prefix : String
    getter bin_dir : String
    getter stdlib_dir : String
    getter compiler_path : String
    getter manifest_path : String

    def initialize(prefix : String)
      @prefix = File.expand_path(prefix)
      @bin_dir = File.join(@prefix, "bin")
      @stdlib_dir = File.join(@prefix, "stdlib")
      @compiler_path = File.join(@bin_dir, Platform.executable_name)
      @manifest_path = File.join(@prefix, "install.txt")
    end
  end

  class TempWorkspace
    getter root : String
    getter archive_path : String
    getter extract_dir : String

    def initialize(@root : String)
      @archive_path = File.join(@root, "Emerald-Latest.zip")
      @extract_dir = File.join(@root, "extracted")
    end

    def self.create : TempWorkspace
      id = "#{Time.utc.to_unix_ms}-#{Random.rand(1_000_000)}"
      root = File.join(Platform.temp_dir, "emerald-installer-#{id}")
      FileUtils.mkdir_p(root)
      TempWorkspace.new(root)
    end
  end

  class ReleaseDownloader
    DEFAULT_URL = "https://emerald-lang.eu/install/latest"
    MAX_REDIRECTS = 5

    def self.download(url : String, target : String)
      download(url, target, 0)
    end

    private def self.download(url : String, target : String, redirects : Int32)
      raise InstallError.new("Too many redirects while downloading #{url}") if redirects > MAX_REDIRECTS

      HTTP::Client.get(url) do |response|
        if redirect?(response.status_code)
          location = response.headers["Location"]?
          raise InstallError.new("Download redirected without Location header: #{url}") unless location
          download(resolve_redirect(url, location), target, redirects + 1)
          return
        end

        unless success?(response.status_code)
          raise InstallError.new("Download failed with HTTP #{response.status_code}: #{url}")
        end

        FileUtils.mkdir_p(File.dirname(target))
        File.open(target, "w") do |file|
          IO.copy(response.body_io, file)
        end
      end
    end

    private def self.success?(status : Int32) : Bool
      status >= 200 && status < 300
    end

    private def self.redirect?(status : Int32) : Bool
      status == 301 || status == 302 || status == 303 || status == 307 || status == 308
    end

    private def self.resolve_redirect(current_url : String, location : String) : String
      return location if location.starts_with?("http://") || location.starts_with?("https://")

      current = URI.parse(current_url)
      scheme = current.scheme || "https"
      host = current.host
      raise InstallError.new("Cannot resolve redirect without host: #{current_url}") unless host

      port = current.port
      authority = port ? "#{host}:#{port}" : host

      if location.starts_with?("/")
        return "#{scheme}://#{authority}#{location}"
      end

      path = current.path || "/"
      slash_index = path.rindex('/')
      parent = slash_index ? path[0...slash_index] : ""
      "#{scheme}://#{authority}#{parent}/#{location}"
    end
  end

  class ZipExtractor
    def self.extract(archive_path : String, target_dir : String)
      FileUtils.rm_rf(target_dir) if File.exists?(target_dir)
      FileUtils.mkdir_p(target_dir)

      Compress::Zip::File.open(archive_path) do |zip|
        zip.entries.each do |entry|
          relative = normalize_entry(entry.filename)
          next if relative.empty?

          target = safe_target(target_dir, relative)

          if entry.dir?
            FileUtils.mkdir_p(target)
            next
          end

          FileUtils.mkdir_p(File.dirname(target))
          entry.open do |input|
            File.open(target, "w") do |output|
              IO.copy(input, output)
            end
          end
        end
      end
    end

    private def self.normalize_entry(filename : String) : String
      parts = [] of String
      filename.gsub('\\', '/').split('/').each do |part|
        next if part.empty? || part == "."
        raise InstallError.new("Unsafe zip entry: #{filename}") if part == ".."
        parts << part
      end

      return "" if parts.empty?

      result = parts.first
      parts[1..-1].each do |part|
        result = File.join(result, part)
      end
      result
    end

    private def self.safe_target(root : String, relative : String) : String
      expanded_root = File.expand_path(root)
      expanded_target = File.expand_path(File.join(expanded_root, relative))
      separator = File::SEPARATOR.to_s
      root_prefix = expanded_root.ends_with?(separator) ? expanded_root : "#{expanded_root}#{separator}"

      if expanded_target != expanded_root && !expanded_target.starts_with?(root_prefix)
        raise InstallError.new("Unsafe zip target: #{relative}")
      end

      expanded_target
    end
  end

  class Payload
    getter root : String
    getter compiler_path : String
    getter stdlib_path : String
    getter cleanup_root : String?

    def initialize(@root : String, @compiler_path : String, @stdlib_path : String, @cleanup_root : String? = nil)
    end

    def cleanup
      cleanup = @cleanup_root
      FileUtils.rm_rf(cleanup) if cleanup && Dir.exists?(cleanup)
    end

    def self.download(url : String) : Payload
      workspace = TempWorkspace.create

      begin
        puts "Downloading Emerald from #{url}"
        ReleaseDownloader.download(url, workspace.archive_path)

        puts "Extracting Emerald payload"
        ZipExtractor.extract(workspace.archive_path, workspace.extract_dir)

        payload = try_from_any(workspace.extract_dir)
        raise InstallError.new("Downloaded archive does not contain emeraldc and stdlib") unless payload

        Payload.new(payload.root, payload.compiler_path, payload.stdlib_path, workspace.root)
      rescue error
        FileUtils.rm_rf(workspace.root) if Dir.exists?(workspace.root)
        raise error
      end
    end

    def self.discover(explicit : String?) : Payload
      if explicit
        payload = try_from_any(File.expand_path(explicit))
        return payload if payload
        raise InstallError.new("No Emerald payload found at #{explicit}")
      end

      roots = [] of String
      roots << Dir.current

      executable_dir = File.dirname(File.expand_path(PROGRAM_NAME))
      roots << executable_dir

      roots.each do |root|
        each_parent(root) do |candidate|
          payload = try_from_any(candidate)
          return payload if payload
        end
      end

      raise InstallError.new("No Emerald payload found. Pass --payload <path> or use install without --payload to download the latest release.")
    end

    def self.try_discover(explicit : String?) : Payload?
      return nil unless explicit
      try_from_any(File.expand_path(explicit))
    end

    private def self.each_parent(start : String)
      current = File.expand_path(start)

      loop do
        yield current

        parent = File.dirname(current)
        break if parent == current
        current = parent
      end
    end

    private def self.try_from_any(root : String) : Payload?
      payload_dir = File.join(root, "payload")
      payload = try_from_payload_dir(payload_dir)
      return payload if payload

      payload = try_from_payload_dir(root)
      return payload if payload

      each_child_directory(root) do |child|
        payload = try_from_payload_dir(child)
        return payload if payload
      end

      try_from_repo_root(root)
    end

    private def self.each_child_directory(root : String)
      return unless Dir.exists?(root)

      Dir.each_child(root) do |child|
        path = File.join(root, child)
        yield path if Dir.exists?(path)
      end
    end

    private def self.try_from_payload_dir(root : String) : Payload?
      stdlib_dir = File.join(root, "stdlib")
      return nil unless Dir.exists?(stdlib_dir)

      compiler = nil
      bin_dir = File.join(root, "bin")
      compiler = find_compiler(bin_dir) if Dir.exists?(bin_dir)
      compiler ||= find_compiler(root)
      return nil unless compiler

      Payload.new(root, compiler, stdlib_dir)
    end

    private def self.try_from_repo_root(root : String) : Payload?
      stdlib_dir = File.join(root, "stdlib")
      bin_dir = File.join(root, "compiler", "bin")
      return nil unless Dir.exists?(stdlib_dir)
      return nil unless Dir.exists?(bin_dir)

      compiler = find_compiler(bin_dir)
      return nil unless compiler

      Payload.new(root, compiler, stdlib_dir)
    end

    private def self.find_compiler(bin_dir : String) : String?
      names = Platform.windows? ? ["emeraldc.exe", "emeraldc"] : ["emeraldc", "emeraldc.exe"]

      names.each do |name|
        path = File.join(bin_dir, name)
        return path if File.exists?(path)
      end

      nil
    end
  end

  class FileTree
    def self.copy_file(source : String, target : String)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(source, target)
    end

    def self.copy_directory(source : String, target : String)
      raise InstallError.new("Directory not found: #{source}") unless Dir.exists?(source)

      FileUtils.rm_rf(target) if File.exists?(target)
      FileUtils.mkdir_p(target)

      Dir.each_child(source) do |entry|
        copy_tree(File.join(source, entry), File.join(target, entry))
      end
    end

    private def self.copy_tree(source : String, target : String)
      if File.directory?(source)
        FileUtils.mkdir_p(target)
        Dir.each_child(source) do |entry|
          copy_tree(File.join(source, entry), File.join(target, entry))
        end
        return
      end

      copy_file(source, target)
    end
  end


  class EnvironmentConfigurator
    START_MARKER = ">>> Emerald installer >>>"
    END_MARKER = "<<< Emerald installer <<<"

    def self.apply(layout : InstallLayout)
      Platform.windows? ? apply_windows(layout) : apply_linux(layout)
    end

    def self.summary(layout : InstallLayout) : String
      "EMERALD_HOME=#{layout.prefix}, EMERALD_STDLIB=#{layout.stdlib_dir}, PATH includes #{layout.bin_dir}"
    end

    private def self.apply_windows(layout : InstallLayout)
      script = String.build do |io|
        io << "$home = " << powershell_string(layout.prefix) << "\n"
        io << "$stdlib = " << powershell_string(layout.stdlib_dir) << "\n"
        io << "$bin = " << powershell_string(layout.bin_dir) << "\n"
        io << "[Environment]::SetEnvironmentVariable('EMERALD_HOME', $home, 'User')\n"
        io << "[Environment]::SetEnvironmentVariable('EMERALD_STDLIB', $stdlib, 'User')\n"
        io << "$path = [Environment]::GetEnvironmentVariable('Path', 'User')\n"
        io << "if ([string]::IsNullOrWhiteSpace($path)) { $next = $bin }\n"
        io << "elseif (($path -split ';') -contains $bin) { $next = $path }\n"
        io << "else { $next = $path + ';' + $bin }\n"
        io << "[Environment]::SetEnvironmentVariable('Path', $next, 'User')\n"
      end

      output = IO::Memory.new
      error = IO::Memory.new
      status = Process.run("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script], output: output, error: error)

      unless status.success?
        detail = error.to_s.strip
        detail = output.to_s.strip if detail.empty?
        raise InstallError.new("Failed to configure Windows environment: #{detail}")
      end
    end

    private def self.apply_linux(layout : InstallLayout)
      write_fish_config(layout)
      write_posix_profile(layout)
    end

    private def self.write_fish_config(layout : InstallLayout)
      path = File.join(Platform.home, ".config", "fish", "conf.d", "emerald.fish")
      FileUtils.mkdir_p(File.dirname(path))

      File.open(path, "w") do |file|
        file.puts "set -gx EMERALD_HOME #{fish_string(layout.prefix)}"
        file.puts "set -gx EMERALD_STDLIB #{fish_string(layout.stdlib_dir)}"
        file.puts "fish_add_path #{fish_string(layout.bin_dir)}"
      end
    end

    private def self.write_posix_profile(layout : InstallLayout)
      profile = File.join(Platform.home, ".profile")
      block = String.build do |io|
        io.puts "# #{START_MARKER}"
        io.puts "export EMERALD_HOME=#{posix_string(layout.prefix)}"
        io.puts "export EMERALD_STDLIB=#{posix_string(layout.stdlib_dir)}"
        io.puts "case \":$PATH:\" in"
        io.puts "  *\":$EMERALD_HOME/bin:\"*) ;;"
        io.puts "  *) export PATH=\"$EMERALD_HOME/bin:$PATH\" ;;"
        io.puts "esac"
        io.puts "# #{END_MARKER}"
      end

      write_managed_block(profile, block)
    end

    private def self.write_managed_block(path : String, block : String)
      current = File.exists?(path) ? File.read(path) : ""
      cleaned = remove_managed_block(current).rstrip
      content = cleaned.empty? ? "#{block}\n" : "#{cleaned}\n\n#{block}\n"

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end

    private def self.remove_managed_block(content : String) : String
      lines = content.lines
      result = [] of String
      skipping = false

      lines.each do |line|
        if line.includes?(START_MARKER)
          skipping = true
          next
        end

        if line.includes?(END_MARKER)
          skipping = false
          next
        end

        result << line unless skipping
      end

      result.join
    end

    private def self.powershell_string(value : String) : String
      "'#{value.gsub("'", "''")}'"
    end

    private def self.fish_string(value : String) : String
      "'#{value.gsub("'", "\\'")}'"
    end

    private def self.posix_string(value : String) : String
      "\"#{value.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("$", "\\$")}\""
    end
  end

  class Browser
    def self.open(url : String)
      if Platform.windows?
        Process.run("cmd", ["/c", "start", "", url])
        return
      end

      opener = ENV["BROWSER"]?
      if opener && !opener.empty?
        Process.run(opener, [url])
        return
      end

      Process.run("xdg-open", [url])
    rescue
    end
  end

  class InstallerUi
    PORT_START = 47830
    PORT_END = 47850

    def initialize(@command_line : CommandLine)
    end

    def start : Int32
      server = HTTP::Server.new do |context|
        handle(context)
      end

      address = bind(server)
      url = "http://#{address.address}:#{address.port}/"

      puts "Emerald Installer UI"
      puts url
      Browser.open(url)

      server.listen
      0
    end

    private def bind(server : HTTP::Server) : Socket::IPAddress
      (PORT_START..PORT_END).each do |port|
        begin
          return server.bind_tcp("127.0.0.1", port)
        rescue
        end
      end

      raise InstallError.new("No free local UI port found in #{PORT_START}..#{PORT_END}")
    end

    private def handle(context : HTTP::Server::Context)
      request = context.request

      if request.method == "GET" && request.path == "/"
        html(context)
        return
      end

      if request.method == "GET" && request.path == "/api/paths"
        paths(context)
        return
      end

      if request.method == "GET" && request.path == "/api/doctor"
        doctor(context)
        return
      end

      if request.method == "POST" && request.path == "/api/install"
        install(context)
        return
      end

      if request.method == "POST" && request.path == "/api/uninstall"
        uninstall(context)
        return
      end

      context.response.status_code = 404
      context.response.print "Not found"
    end

    private def html(context : HTTP::Server::Context)
      context.response.content_type = "text/html; charset=utf-8"
      context.response.print UI_HTML
    end

    private def paths(context : HTTP::Server::Context)
      layout = InstallLayout.new(Platform.default_prefix)

      json(context) do |json|
        json.field "ok", true
        json.field "prefix", layout.prefix
        json.field "binDir", layout.bin_dir
        json.field "stdlibDir", layout.stdlib_dir
        json.field "compilerPath", layout.compiler_path
        json.field "downloadUrl", @command_line.download_url
        json.field "version", VERSION
      end
    end

    private def doctor(context : HTTP::Server::Context)
      layout = InstallLayout.new(Platform.default_prefix)

      json(context) do |json|
        json.field "ok", true
        json.field "version", VERSION
        json.field "prefix", layout.prefix
        json.field "compilerPath", layout.compiler_path
        json.field "stdlibDir", layout.stdlib_dir
        json.field "installed", File.exists?(layout.compiler_path) && Dir.exists?(layout.stdlib_dir)
        json.field "environment", EnvironmentConfigurator.summary(layout)
      end
    end

    private def install(context : HTTP::Server::Context)
      params = read_params(context)
      prefix = clean_param(params["prefix"]?) || Platform.default_prefix
      url = clean_param(params["url"]?) || @command_line.download_url
      payload_path = clean_param(params["payload"]?)
      force = truthy?(params["force"]?)
      configure_env = params["configureEnv"]? != "false"

      layout = InstallLayout.new(prefix)
      payload = payload_path ? Payload.discover(payload_path) : Payload.download(url)

      begin
        Installer.new(layout, payload).install(force, configure_env)

        json(context) do |json|
          json.field "ok", true
          json.field "message", "Emerald installed successfully."
          json.field "compilerPath", layout.compiler_path
          json.field "stdlibDir", layout.stdlib_dir
          json.field "environment", EnvironmentConfigurator.summary(layout)
        end
      ensure
        payload.cleanup
      end
    rescue error : InstallError
      error_json(context, error.message || "Install failed")
    end

    private def uninstall(context : HTTP::Server::Context)
      params = read_params(context)
      prefix = clean_param(params["prefix"]?) || Platform.default_prefix
      layout = InstallLayout.new(prefix)

      Installer.uninstall(layout, true)

      json(context) do |json|
        json.field "ok", true
        json.field "message", "Emerald removed from #{layout.prefix}."
      end
    rescue error : InstallError
      error_json(context, error.message || "Uninstall failed")
    end

    private def read_params(context : HTTP::Server::Context) : URI::Params
      body = context.request.body.try(&.gets_to_end) || ""
      URI::Params.parse(body)
    end

    private def clean_param(value : String?) : String?
      return nil unless value
      stripped = value.strip
      stripped.empty? ? nil : stripped
    end

    private def truthy?(value : String?) : Bool
      value == "true" || value == "1" || value == "yes" || value == "on"
    end

    private def json(context : HTTP::Server::Context)
      context.response.content_type = "application/json; charset=utf-8"

      JSON.build(context.response) do |json|
        json.object do
          yield json
        end
      end
    end

    private def error_json(context : HTTP::Server::Context, message : String)
      context.response.status_code = 400

      json(context) do |json|
        json.field "ok", false
        json.field "message", message
      end
    end

    UI_HTML = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Emerald Installer</title>
    <style>
    :root {
      --bg: #0a0a0a;
      --bg-elev: #111111;
      --bg-card: #0f0f0f;
      --bg-card-hover: #131313;
      --border: #1d1d1d;
      --border-strong: #262626;
      --fg: #f5f5f5;
      --fg-dim: #999999;
      --fg-mute: #6b6b6b;
      --emerald: #10b981;
      --emerald-bright: #34d399;
      --emerald-soft: #6ee7b7;
      --purple: #c084fc;
      --blue: #93c5fd;
      --yellow: #fcd34d;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      background:
    radial-gradient(circle at 50% -20%, rgba(16, 185, 129, 0.16), transparent 42%),
    radial-gradient(circle at 10% 20%, rgba(192, 132, 252, 0.08), transparent 28%),
    var(--bg);
      color: var(--fg);
      font-family: Inter, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      letter-spacing: -0.011em;
    }
    main {
      width: min(1120px, calc(100% - 32px));
      margin: 0 auto;
      padding: 56px 0;
    }
    .hero {
      text-align: center;
      padding: 28px 0 44px;
    }
    .logo {
      width: 76px;
      height: 76px;
      margin: 0 auto 22px;
      object-fit: contain;
      border: 1px solid rgba(16, 185, 129, 0.28);
      border-radius: 22px;
      padding: 8px;
      background: rgba(16, 185, 129, 0.06);
      box-shadow: 0 0 52px rgba(16, 185, 129, 0.24);
    }
    h1 {
      font-size: clamp(2.8rem, 7vw, 5.6rem);
      line-height: 1;
      letter-spacing: -0.06em;
      margin: 0;
    }
    .accent {
      background: linear-gradient(180deg, var(--emerald-soft), var(--emerald));
      -webkit-background-clip: text;
      background-clip: text;
      color: transparent;
    }
    .subtitle {
      max-width: 680px;
      margin: 20px auto 0;
      color: var(--fg-dim);
      font-size: 17px;
      line-height: 1.7;
    }
    .grid {
      display: grid;
      grid-template-columns: 1fr;
      gap: 18px;
    }
    @media (min-width: 920px) {
      .grid { grid-template-columns: 1.1fr 0.9fr; }
    }
    .card {
      background: rgba(15, 15, 15, 0.86);
      border: 1px solid var(--border);
      border-radius: 18px;
      padding: 24px;
      backdrop-filter: blur(18px);
      box-shadow: 0 24px 90px rgba(0, 0, 0, 0.28);
    }
    .card h2 {
      margin: 0 0 18px;
      font-size: 19px;
    }
    .field {
      margin: 16px 0;
    }
    label {
      display: block;
      color: var(--fg-dim);
      font-size: 13px;
      margin-bottom: 8px;
    }
    input {
      width: 100%;
      background: #0b0b0b;
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 13px 14px;
      color: var(--fg);
      font: 13px "JetBrains Mono", "Fira Code", monospace;
      outline: none;
    }
    input:focus {
      border-color: var(--emerald);
      box-shadow: 0 0 0 4px rgba(16, 185, 129, 0.08);
    }
    .row {
      display: flex;
      gap: 12px;
      flex-wrap: wrap;
    }
    .check {
      display: flex;
      align-items: center;
      gap: 10px;
      color: var(--fg-dim);
      font-size: 14px;
      margin-top: 12px;
    }
    .check input {
      width: auto;
    }
    button {
      border: 0;
      border-radius: 12px;
      padding: 12px 18px;
      font-weight: 650;
      cursor: pointer;
      transition: transform .14s ease, background .14s ease, color .14s ease, border .14s ease;
    }
    button:hover { transform: translateY(-1px); }
    .primary {
      color: #07130f;
      background: linear-gradient(180deg, var(--emerald-soft), var(--emerald));
    }
    .secondary {
      color: var(--fg);
      background: var(--bg-elev);
      border: 1px solid var(--border);
    }
    .secondary:hover {
      border-color: var(--border-strong);
      background: #161616;
    }
    .status {
      min-height: 180px;
      background: #090909;
      border: 1px solid var(--border);
      border-radius: 14px;
      padding: 18px;
      color: var(--fg-dim);
      font: 13px/1.65 "JetBrains Mono", "Fira Code", monospace;
      white-space: pre-wrap;
    }
    .pill {
      display: inline-flex;
      gap: 8px;
      align-items: center;
      border: 1px solid rgba(16, 185, 129, 0.18);
      background: rgba(16, 185, 129, 0.06);
      color: var(--emerald-bright);
      border-radius: 999px;
      padding: 7px 12px;
      font: 12px "JetBrains Mono", monospace;
      margin-bottom: 18px;
    }
    .meta {
      display: grid;
      gap: 12px;
    }
    .meta div {
      padding: 14px;
      border: 1px solid var(--border);
      border-radius: 14px;
      background: #0b0b0b;
    }
    .meta strong {
      display: block;
      color: var(--fg);
      margin-bottom: 6px;
    }
    .meta span {
      color: var(--fg-dim);
      font: 12px "JetBrains Mono", monospace;
      word-break: break-all;
    }
    </style>
    </head>
    <body>
    <main>
      <section class="hero">
    <img class="logo" alt="Emerald logo" src="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxMDAgODAiIHdpZHRoPSI1MDAiIGhlaWdodD0iNDAwIj4KICAgIDwhLS0gVG9wIGNyb3duOiA1IGZhY2V0cyBpbiBhIHJvdyAtLT4KICAgIDxwb2x5Z29uIGZpbGw9IiM2ZWU3YjciIHN0cm9rZT0iIzAwMCIgc3Ryb2tlLXdpZHRoPSIwLjgiIHN0cm9rZS1saW5lam9pbj0icm91bmQiIHBvaW50cz0iMCwyNSAyMCwyNSAxMiwwIi8+CiAgICA8cG9seWdvbiBmaWxsPSIjMzRkMzk5IiBzdHJva2U9IiMwMDAiIHN0cm9rZS13aWR0aD0iMC44IiBzdHJva2UtbGluZWpvaW49InJvdW5kIiBwb2ludHM9IjIwLDI1IDQwLDI1IDMyLDAgMTIsMCIvPgogICAgPHBvbHlnb24gZmlsbD0iIzEwYjk4MSIgc3Ryb2tlPSIjMDAwIiBzdHJva2Utd2lkdGg9IjAuOCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCIgcG9pbnRzPSI0MCwyNSA2MCwyNSA2OCwwIDMyLDAiLz4KICAgIDxwb2x5Z29uIGZpbGw9IiMzNGQzOTkiIHN0cm9rZT0iIzAwMCIgc3Ryb2tlLXdpZHRoPSIwLjgiIHN0cm9rZS1saW5lam9pbj0icm91bmQiIHBvaW50cz0iNjAsMjUgODAsMjUgODgsMCA2OCwwIi8+CiAgICA8cG9seWdvbiBmaWxsPSIjNmVlN2I3IiBzdHJva2U9IiMwMDAiIHN0cm9rZS13aWR0aD0iMC44IiBzdHJva2UtbGluZWpvaW49InJvdW5kIiBwb2ludHM9IjgwLDI1IDEwMCwyNSA4OCwwIi8+CiAgICA8IS0tIFBhdmlsaW9uOiA0IGxhcmdlIGZhY2V0cyBtZWV0aW5nIGF0IGJvdHRvbSBwb2ludCAtLT4KICAgIDxwb2x5Z29uIGZpbGw9IiMwNTk2NjkiIHN0cm9rZT0iIzAwMCIgc3Ryb2tlLXdpZHRoPSIwLjgiIHN0cm9rZS1saW5lam9pbj0icm91bmQiIHBvaW50cz0iMCwyNSAzMCwyNSA1MCw4MCIvPgogICAgPHBvbHlnb24gZmlsbD0iIzEwYjk4MSIgc3Ryb2tlPSIjMDAwIiBzdHJva2Utd2lkdGg9IjAuOCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCIgcG9pbnRzPSIzMCwyNSA1MCwyNSA1MCw4MCIvPgogICAgPHBvbHlnb24gZmlsbD0iIzM0ZDM5OSIgc3Ryb2tlPSIjMDAwIiBzdHJva2Utd2lkdGg9IjAuOCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCIgcG9pbnRzPSI1MCwyNSA3MCwyNSA1MCw4MCIvPgogICAgPHBvbHlnb24gZmlsbD0iIzA1OTY2OSIgc3Ryb2tlPSIjMDAwIiBzdHJva2Utd2lkdGg9IjAuOCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCIgcG9pbnRzPSI3MCwyNSAxMDAsMjUgNTAsODAiLz4KPC9zdmc+Cg==">
    <div class="pill">Emerald Installer · local UI</div>
    <h1>Install <span class="accent">Emerald.</span></h1>
    <p class="subtitle">Download the latest compiler and STDLib, install them into your user directory, and configure EMERALD_HOME, EMERALD_STDLIB, and PATH automatically.</p>
      </section>

      <section class="grid">
    <div class="card">
      <h2>Install settings</h2>
      <div class="field">
        <label for="prefix">Install prefix</label>
        <input id="prefix" spellcheck="false">
      </div>
      <div class="field">
        <label for="url">Download URL</label>
        <input id="url" spellcheck="false">
      </div>
      <div class="field">
        <label for="payload">Offline payload path</label>
        <input id="payload" placeholder="Leave empty to download latest" spellcheck="false">
      </div>
      <label class="check"><input id="force" type="checkbox" checked> Replace existing installation</label>
      <label class="check"><input id="configureEnv" type="checkbox" checked> Configure environment variables automatically</label>
      <div class="row" style="margin-top: 22px;">
        <button class="primary" onclick="installEmerald()">Install Emerald</button>
        <button class="secondary" onclick="doctor()">Doctor</button>
        <button class="secondary" onclick="uninstallEmerald()">Uninstall</button>
      </div>
    </div>

    <div class="card">
      <h2>Current target</h2>
      <div class="meta">
        <div><strong>Compiler</strong><span id="compilerPath"></span></div>
        <div><strong>STDLib</strong><span id="stdlibPath"></span></div>
        <div><strong>Version</strong><span id="version"></span></div>
      </div>
      <h2 style="margin-top: 22px;">Status</h2>
      <div id="status" class="status">Ready.</div>
    </div>
      </section>
    </main>
    <script>
    const statusBox = document.getElementById("status");

    function setStatus(text) {
      statusBox.textContent = text;
    }

    function formBody() {
      const params = new URLSearchParams();
      params.set("prefix", document.getElementById("prefix").value);
      params.set("url", document.getElementById("url").value);
      params.set("payload", document.getElementById("payload").value);
      params.set("force", document.getElementById("force").checked ? "true" : "false");
      params.set("configureEnv", document.getElementById("configureEnv").checked ? "true" : "false");
      return params;
    }

    async function loadPaths() {
      const response = await fetch("/api/paths");
      const data = await response.json();
      document.getElementById("prefix").value = data.prefix;
      document.getElementById("url").value = data.downloadUrl;
      document.getElementById("compilerPath").textContent = data.compilerPath;
      document.getElementById("stdlibPath").textContent = data.stdlibDir;
      document.getElementById("version").textContent = data.version;
    }

    async function installEmerald() {
      setStatus("Downloading and installing Emerald...");
      const response = await fetch("/api/install", { method: "POST", body: formBody() });
      const data = await response.json();
      setStatus(JSON.stringify(data, null, 2));
    }

    async function doctor() {
      setStatus("Checking installation...");
      const response = await fetch("/api/doctor");
      const data = await response.json();
      setStatus(JSON.stringify(data, null, 2));
    }

    async function uninstallEmerald() {
      if (!confirm("Remove Emerald from the selected install prefix?")) return;
      setStatus("Removing Emerald...");
      const response = await fetch("/api/uninstall", { method: "POST", body: formBody() });
      const data = await response.json();
      setStatus(JSON.stringify(data, null, 2));
    }

    loadPaths().catch(error => setStatus(String(error)));
    </script>
    </body>
    </html>
    HTML
  end

  class Installer
    def self.uninstall(layout : InstallLayout, yes : Bool)
      raise InstallError.new("Refusing to uninstall without --yes") unless yes

      FileUtils.rm_rf(layout.prefix)

      puts "Removed #{layout.prefix}"
    end

    def self.doctor(layout : InstallLayout, payload : Payload?, download_url : String)
      puts "Emerald installer #{VERSION}"
      puts "Install prefix:   #{layout.prefix}"
      puts "Download URL:     #{download_url}"

      if payload
        puts "Payload root:     #{payload.root}"
        puts "Payload compiler: #{payload.compiler_path}"
        puts "Payload STDLib:   #{payload.stdlib_path}"
        puts "Payload OK:       #{File.exists?(payload.compiler_path) && Dir.exists?(payload.stdlib_path)}"
      else
        puts "Payload root:     not checked"
        puts "Payload OK:       not checked"
      end

      puts "Target compiler:  #{layout.compiler_path}"
      puts "Target STDLib:    #{layout.stdlib_dir}"
      puts "Install OK:       #{File.exists?(layout.compiler_path) && Dir.exists?(layout.stdlib_dir)}"
      puts EnvironmentConfigurator.summary(layout)
    end

    def initialize(@layout : InstallLayout, @payload : Payload)
    end

    def install(force : Bool, configure_env : Bool = true)
      guard_install_target(force)

      FileUtils.mkdir_p(@layout.bin_dir)
      FileUtils.mkdir_p(@layout.prefix)

      FileTree.copy_file(@payload.compiler_path, @layout.compiler_path)
      make_executable(@layout.compiler_path)
      FileTree.copy_directory(@payload.stdlib_path, @layout.stdlib_dir)
      write_manifest

      if configure_env
        EnvironmentConfigurator.apply(@layout)
      end

      puts "Installed Emerald"
      puts "Compiler: #{@layout.compiler_path}"
      puts "STDLib:   #{@layout.stdlib_dir}"
      puts EnvironmentConfigurator.summary(@layout)
    end

    private def guard_install_target(force : Bool)
      return if force

      if File.exists?(@layout.compiler_path)
        raise InstallError.new("Compiler already exists at #{@layout.compiler_path}. Use --force to replace it.")
      end

      if Dir.exists?(@layout.stdlib_dir)
        raise InstallError.new("STDLib already exists at #{@layout.stdlib_dir}. Use --force to replace it.")
      end
    end

    private def make_executable(path : String)
      return if Platform.windows?

      File.chmod(path, 0o755)
    end

    private def write_manifest
      File.open(@layout.manifest_path, "w") do |file|
        file.puts "Emerald install"
        file.puts "version=#{VERSION}"
        file.puts "compiler=#{@layout.compiler_path}"
        file.puts "stdlib=#{@layout.stdlib_dir}"
        file.puts "payload=#{@payload.root}"
      end
    end
  end

  class App
    def self.run(args : Array(String)) : Int32
      command_line = CommandLine.parse(args)

      if command_line.command == "help"
        print_help
        return 0
      end

      if command_line.command == "version"
        puts VERSION
        return 0
      end

      if command_line.command == "ui"
        return InstallerUi.new(command_line).start
      end

      prefix = command_line.prefix || Platform.default_prefix
      layout = InstallLayout.new(prefix)

      if command_line.command == "print-path"
        puts layout.bin_dir
        return 0
      end

      if command_line.command == "uninstall"
        Installer.uninstall(layout, command_line.yes)
        return 0
      end

      if command_line.command == "doctor"
        payload = Payload.try_discover(command_line.payload)
        Installer.doctor(layout, payload, command_line.download_url)
        return 0
      end

      if command_line.command == "install"
        payload = resolve_payload(command_line)

        begin
          Installer.new(layout, payload).install(command_line.force, command_line.configure_env)
        ensure
          payload.cleanup
        end

        return 0
      end

      raise InstallError.new("Unknown command: #{command_line.command}")
    rescue error : InstallError
      STDERR.puts "Error: #{error.message}"
      STDERR.puts
      print_help
      1
    end

    private def self.resolve_payload(command_line : CommandLine) : Payload
      explicit = command_line.payload
      return Payload.discover(explicit) if explicit

      Payload.download(command_line.download_url)
    end

    private def self.print_help
      puts <<-HELP
      Emerald Installer #{VERSION}

      Usage:
        emerald-installer ui [--url <url>]
        emerald-installer install [--url <url>] [--prefix <path>] [--force] [--no-env]
        emerald-installer install --payload <path> [--prefix <path>] [--force] [--no-env]
        emerald-installer uninstall [--prefix <path>] --yes
        emerald-installer doctor [--payload <path>] [--prefix <path>] [--url <url>]
        emerald-installer print-path [--prefix <path>]
        emerald-installer version
        emerald-installer help

      Running without arguments starts the graphical browser UI.

      Default install paths:
        Windows: %LOCALAPPDATA%\\Emerald
        Linux:   $HOME/.local/Emerald

      Default download:
        https://emerald-lang.eu/install/latest

      Downloaded archive layout:
        Emerald-Latest.zip must contain emeraldc and stdlib.
        It may also contain a top-level directory containing emeraldc and stdlib.

      Environment setup:
        Install configures EMERALD_HOME, EMERALD_STDLIB, and PATH by default.
        Use --no-env to disable environment changes.

      Offline payload paths:
        A payload directory may contain emeraldc and stdlib or bin/emeraldc and stdlib.
        A repository root with compiler/bin/emeraldc and stdlib also works.
      HELP
    end
  end
end

exit EmeraldInstaller::App.run(ARGV)
