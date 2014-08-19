module Byebug
  module InfoFunctions
    def info_catch(*_args)
      return print "No frame selected.\n" unless @state.context

      if Byebug.catchpoints && !Byebug.catchpoints.empty?
        Byebug.catchpoints.each do |exception, _hits|
          print "#{exception}: #{exception.is_a?(Class)}\n"
        end
      else
        print "No exceptions set to be caught.\n"
      end
    end
  end

  class InfoCommand < Command
    include Columnize
    self.allow_in_control = true

    Subcommands = [
       ['args'              , 1, 'Argument variables of current stack frame'  ],
       ['breakpoints'       , 1, 'Status of user-settable breakpoints',
                                 'Without argument, list info about all '   \
                                 'breakpoints. With an integer argument, '  \
                                 'list info on that breakpoint.'              ],
       ['catch'             , 3, 'Exceptions that can be caught in the '    \
                                 'current stack frame'                        ],
       ['display'           , 2, 'Expressions to display when program stops'  ],
       ['file'              , 4, 'Info about a particular file read in',
                                 'After the file name is supplied, you can' \
                                 'list file attributes that you wish to '   \
                                 'see. Attributes include: "all", "basic",' \
                                 ' "breakpoint", "lines", "mtime", "path" ' \
                                 'and "sha1".'                                ],
       ['files'             , 5, 'File names and timestamps of files read in' ],
       ['line'              , 2, 'Line number and file name of current '    \
                                 'position in source file'                    ],
       ['program'           , 2, 'Execution status of the program'            ]
    ].map do |name, min, help|
      Subcmd.new(name, min, help)
    end unless defined?(Subcommands)

    InfoFileSubcommands = [
      ['all'        , 1, 'All file information available - breakpoints, '   \
                         'lines, mtime, path and sha1'                        ],
      ['basic'      , 2, 'basic information - path, number of lines'          ],
      ['breakpoints', 2, 'Show trace line numbers',
                         'These are the line number where a breakpoint '    \
                         'can be set.'                                        ],
      ['lines'      , 1, 'Show number of lines in the file'                   ],
      ['mtime'      , 1, 'Show modification time of file'                     ],
      ['path'       , 4, 'Show full file path name for file'                  ],
      ['sha1'       , 1, 'Show SHA1 hash of contents of the file'             ]
    ].map do |name, min, help|
      Subcmd.new(name, min, help)
    end unless defined?(InfoFileSubcommands)

    def regexp
      /^\s* i(?:nfo)? (?:\s+(.+))? \s*$/x
    end

    def execute
      return print InfoCommand.help unless @match[1]

      args = @match[1].split(/[ \t]+/)
      param = args.shift
      subcmd = Command.find(Subcommands, param)
      return errmsg "Unknown info command #{param}\n" unless subcmd

      if @state.context
        send("info_#{subcmd.name}", *args)
      else
        errmsg "info_#{subcmd.name} not available without a context.\n"
      end
    end

    def info_args(*args)
      locals = @state.context.frame_locals
      args = @state.context.frame_args
      return if args == [[:rest]]

      args.map do |_, name|
        s = "#{name} = #{locals[name].inspect}"
        s[Setting[:width] - 3..-1] = '...' if s.size > Setting[:width]
        print "#{s}\n"
      end
    end

    def info_breakpoint(brkpt)
      expr = brkpt.expr.nil? ? '' : " if #{brkpt.expr}"
      interp = format("%-3d %-3s at %s:%s%s", brkpt.id,
                                              brkpt.enabled? ? 'y' : 'n',
                                              brkpt.source, brkpt.pos, expr)
      print("#{interp}\n")
      hits = brkpt.hit_count
      if hits > 0
        s = (hits > 1) ? 's' : ''
        print "\tbreakpoint already hit #{hits} time#{s}\n"
      end
    end
    private :info_breakpoint

    def info_breakpoints(*args)
      return print "No breakpoints.\n" if Byebug.breakpoints.empty?

      brkpts = Byebug.breakpoints.sort_by { |b| b.id }
      unless args.empty?
        indices = args.map { |a| a.to_i }
        brkpts = brkpts.select { |b| indices.member?(b.id) }
        return errmsg "No breakpoints found among list given.\n" if
          brkpts.empty?
      end
      print "Num Enb What\n"
      brkpts.each { |b| info_breakpoint(b) }
    end

    def info_display(*_args)
      return print "There are no auto-display expressions now.\n" unless
        @state.display.find { |d| d[0] }

      print "Auto-display expressions now in effect:\n" \
            "Num Enb Expression\n"
      n = 1
      @state.display.each do |d|
        interp = format("%3d: %s  %s", n, d[0] ? 'y' : 'n', d[1])
        print "#{interp}\n"
        n += 1
      end
    end

    def info_file_path(file)
      print "File #{file}"
      path = File.expand_path(file)
      print " - #{path}\n" if path && path != file
    end
    private :info_file_path

    def info_file_lines(file)
      lines = File.foreach(file)
      print "\t#{lines.count} lines\n" if lines
    end
    private :info_file_lines

    def info_file_breakpoints(file)
      breakpoints = LineCache.trace_line_numbers(file)
      if breakpoints
        print "\tbreakpoint line numbers:\n"
        print columnize(breakpoints.to_a.sort, Setting[:width])
      end
    end
    private :info_file_breakpoints

    def info_file_mtime(file)
      stat = File.stat(file)
      print "\t#{stat.mtime}\n" if stat
    end
    private :info_file_mtime

    def info_file_sha1(file)
      print "\t#{Digest::SHA1.hexdigest(file)}\n"
    end
    private :info_file_sha1

    def info_file(*args)
      return info_files unless args[0]

      subcmd = Command.find(InfoFileSubcommands, args[1] || 'basic')
      return errmsg "Invalid parameter #{args[1]}\n" unless subcmd

      if %w(all basic).member?(subcmd.name)
        info_file_path(args[0])
        info_file_lines(args[0])
        if subcmd.name == 'all'
          info_file_breakpoints(args[0])
          info_file_mtime(args[0])
          info_file_sha1(args[0])
        end
      else
        print "File #{args[0]}\n" if subcmd.name != 'path'
        send("info_file_#{subcmd.name}", args[0])
      end
    end

    def info_files(*_args)
      files = SCRIPT_LINES__.keys
      files.uniq.sort.each do |file|
        info_file_path(file)
        info_file_mtime(file)
      end
    end

    def info_line(*_args)
      print "Line #{@state.line} of \"#{@state.file}\"\n"
    end

    def print_hash(vars)
      vars.keys.sort.each do |name|
        begin
          s = "#{name} = #{vars[name].inspect}"
        rescue
          begin
            s = "#{name} = #{vars[name]}"
            rescue
              s = "#{name} = *Error in evaluation*"
          end
        end
        s[Setting[:width] - 3..-1] = '...' if s.size > Setting[:width]
        print "#{s}\n"
      end
    end
    private :print_hash

    def info_stop_reason(stop_reason)
      case stop_reason
      when :step
        print "It stopped after stepping, next'ing or initial start.\n"
      when :breakpoint
        print("It stopped at a breakpoint.\n")
      when :catchpoint
        print("It stopped at a catchpoint.\n")
      else
        print("unknown reason: #{@state.context.stop_reason}\n")
      end
    end
    private :info_stop_reason

    def info_program(*_args)
      if @state.context.dead?
        print "The program crashed.\n"
        print "Exception: #{Byebug.last_exception.inspect}\n" if Byebug.last_exception
        return
      end

      print 'Program stopped. '
      info_stop_reason @state.context.stop_reason
    end

    def info_variables(*_args)
      locals = @state.context.frame_locals
      locals[:self] = @state.context.frame_self(@state.frame_pos)
      print_hash(locals)

      obj = bb_eval('self')
      var_list(obj.instance_variables, obj.instance_eval { binding })
      var_class_self
    end

    class << self
      def names
        %w(info)
      end

      def description
        <<-EOD.gsub(/^ {8}/, '')

          info[ subcommand]

          Generic command for showing things about the program being debugged.

        EOD
      end

      def help(subcmds = [])
        return description + format_subcmds if subcmds.empty?

        subcmd = subcmds.first
        return format_subcmd(subcmd) unless 'file' == subcmd && subcmds[2]

        subsubcmd = Command.find(InfoFileSubcommands, subcmds[2])
        return "\nInvalid \"file\" attribute \"#{args[2]}\"." unless subsubcmd

        subsubcmd.short_help
      end
    end
  end
end
