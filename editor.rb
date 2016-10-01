#!/usr/bin/env ruby

class Editor
  def main
    Screen.with_screen do |screen|
      loop do
        char = read_char
        render(char)
      end
    end
  end

  def read_char
    $stdin.readChar
  end

  def render(char)
    puts char
  end
end

Editor.new.main
