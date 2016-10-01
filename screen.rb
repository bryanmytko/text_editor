class Screen
  def self.with_screen
    TTY.with_tty do |tty|
      screen = self.new(tty)
      screen.configure_tty
      begin
        raise NotATTY if screen.height == 0
        yield screen, tty
      ensure
        screen.restore_tty
        tty.puts
      end
    end
  end

  class NotATTY < RuntimeError; end

  attr_reader :tty

  def initialize(tty)
    @tty = tty
    @original_stty_state = tty.stty("-g")
  end

  def configure_tty
    # -echo: terminal doesn't echo typed characters back to the terminal
    # -icanon: terminal doesn't  interpret special characters (like backspace)
    tty.stty("raw -echo -icanon")
  end

  def restore_tty
    tty.stty("#{@original_stty_state}")
  end

  def suspend
    restore_tty
    begin
      yield
      configure_tty
    rescue
      restore_tty
    end
  end

  def with_cursor_hidden(&block)
    write_bytes(ANSI.hide_cursor)
    begin
      block.call
    ensure
      write_bytes(ANSI.show_cursor)
    end
  end

  def height
    tty.winsize[0]
  end

  def width
    tty.winsize[1]
  end

  def cursor_up(lines)
    write_bytes(ANSI.cursor_up(lines))
  end

  def newline
    write_bytes("\n")
  end

  def write(text)
    write_bytes(ANSI.clear_line)
    write_bytes("\r")

    text.components.each do |component|
      if component.is_a? String
        write_bytes(expand_tabs(component))
      elsif component == :inverse
        write_bytes(ANSI.inverse)
      elsif component == :reset
        write_bytes(ANSI.reset)
      else
        if component =~ /_/
          fg, bg = component.to_s.split(/_/).map(&:to_sym)
        else
          fg, bg = component, :default
        end
        write_bytes(ANSI.color(fg, bg))
      end
    end
  end

  def expand_tabs(string)
    # Modified from http://markmail.org/message/avdjw34ahxi447qk
    tab_width = 8
    string.gsub(/([^\t\n]*)\t/) do
      $1 + " " * (tab_width - ($1.size % tab_width))
    end
  end

  def write_bytes(bytes)
    tty.console_file.write(bytes)
  end
end

class Text
  attr_reader :components

  def self.[](*args)
    if args.length == 1 && args[0].is_a?(Text)
      # When called as `Text[some_text]`, just return the existing text.
      args[0]
    else
      new(args)
    end
  end

  def initialize(components)
    @components = components
  end

  def ==(other)
    components == other.components
  end

  def +(other)
    Text[*(components + other.components)]
  end

  def truncate_to_width(width)
    chars_remaining = width

    # Truncate each string to the number of characters left within our
    # allowed width. Leave anything else alone. This may result in empty
    # strings and unused ANSI control codes in the output, but that's fine.
    components = self.components.map do |component|
      if component.is_a?(String)
        component = component[0, chars_remaining]
        chars_remaining -= component.length
      end
      component
    end

    Text.new(components)
  end
end

class ANSI
  ESC = 27.chr

  class << self
    def escape(sequence)
      ESC + "[" + sequence
    end

    def clear
      escape "2J"
    end

    def hide_cursor
      escape "?25l"
    end

    def show_cursor
      escape "?25h"
    end

    def cursor_up(lines)
      escape "#{lines}A"
    end

    def clear_line
      escape "2K"
    end

    def color(fg, bg=:default)
      fg_codes = {
        :black => 30,
        :red => 31,
        :green => 32,
        :yellow => 33,
        :blue => 34,
        :magenta => 35,
        :cyan => 36,
        :white => 37,
        :default => 39,
      }
      bg_codes = {
        :black => 40,
        :red => 41,
        :green => 42,
        :yellow => 43,
        :blue => 44,
        :magenta => 45,
        :cyan => 46,
        :white => 47,
        :default => 49,
      }
      fg_code = fg_codes.fetch(fg)
      bg_code = bg_codes.fetch(bg)
      escape "#{fg_code};#{bg_code}m"
    end

    def inverse
      escape("7m")
    end

    def reset
      escape("0m")
    end
  end
end

class TTY < Struct.new(:console_file)
  def self.with_tty(&block)
    # Selecta reads data from stdin and writes it to stdout, so we can't draw
    # UI and receive keystrokes through them. Fortunately, all modern
    # Unix-likes provide /dev/tty, which IO.console gives us.
    console_file = IO.console
    tty = TTY.new(console_file)
    block.call(tty)
  end

  def get_available_input
    input = console_file.getc
    while console_file.ready?
      input += console_file.getc
    end
    input
  end

  def puts
    console_file.puts
  end

  def winsize
    console_file.winsize
  end

  def stty(args)
    command("stty #{args}").strip
  end

  private

  # Run a command with the TTY as stdin, capturing the output via a pipe
  def command(command)
    IO.pipe do |read_io, write_io|
      pid = Process.spawn(command, :in => "/dev/tty", :out => write_io)
      Process.wait(pid)
      raise "Command failed: #{command.inspect}" unless $?.success?
      write_io.close
      read_io.read
    end
  end
end
