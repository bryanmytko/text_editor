#!/usr/bin/env ruby

require "io/console"
require_relative "screen"

class Editor
  def main
    Screen.with_screen do |screen|
      loop do
        char = read_char
        if char == ?\C-c
          raise SystemExit
        end

        render(char.inspect)
      end
    end
  end

  def read_char
    $stdin.readchar
  end

  def render(char)
    $stdout.write char
  end
end

Editor.new.main
