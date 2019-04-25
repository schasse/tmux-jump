#!/usr/bin/env ruby

pane_nr = `tmux display-message -p "\#{pane_id}"`.strip

tmux_data = `tmux lsp -a -F "\#{pane_tty};\#{pane_in_mode};\#{pane_id}" | grep #{pane_nr}`.split(';')
pane_mode = tmux_data[1]
`tmux send-keys -X -t #{pane_nr} cancel` if pane_mode == '1'
TTY_FILE = tmux_data[0]

saved_screen = `tmux capture-pane -ep -t #{pane_nr}` # with colors...

def prompt_char
  read, write = IO.pipe
  path = "/proc/#{Process.pid}/fd/#{write.fileno}"
  `tmux command-prompt -1 -p 'char:' 'run-shell "printf %1 >> #{path}"'`
  char = read.getc
  write.close
  read.close
  char
end

jump_char = prompt_char

CHARS =
  `tmux capture-pane -p -t #{pane_nr}` # without colors

CLEAR_SEQ = "\e[2J"

positions = []

positions << 0 if CHARS[0] =~ /\w/ && CHARS[0].downcase == jump_char

CHARS.each_char.with_index do |char, i|
  if (char =~ /\w/).nil? && CHARS[i+1] && CHARS[i+1].downcase == jump_char
    positions << i+1
  end
end

def draw_with_keys(positions, keys, key_len)
  gray = "\e[0m\e[32m"
  red = "\e[1m\e[31m"

  File.open(TTY_FILE, 'a') do |tty|
    tty << "#{CLEAR_SEQ}\n"
    cursor = 0
    positions.each_with_index do |pos, i|
      tty << "#{gray}#{CHARS[cursor..pos-key_len]}"
      tty << "#{red}#{keys[i]}"
      cursor = pos + 1
    end
    tty << "#{gray}#{CHARS[cursor..-2]}"
  end
end

KEYS = 'jfhgkdlsnamvucixozyrpt'.each_char.to_a

def draw(positions, keys = KEYS, key_len = 1)
  if positions.size > keys.size
    draw(positions, keys.product(keys).map(&:join), 2)
  else
    draw_with_keys positions, keys, key_len
    key_len
  end
end

def jump_to(positions)
  key_len = draw positions
  key_index = KEYS.index(prompt_char)
  if key_len > 1
    magnitude = KEYS.size ** (key_len - 1)
    range_beginning = key_index * magnitude # p.e. 2 * 22^1
    range_ending = range_beginning + magnitude - 1
    remaining_positions = positions[range_beginning..range_ending]
    range_beginning + jump_to(remaining_positions)
  else
    key_index
  end
end

jump_to = jump_to positions

left = CHARS.size - positions[jump_to]

File.open(TTY_FILE, 'a') do |tty|
  tty << "\e[0m" + CLEAR_SEQ
  tty << saved_screen[0..-2] + ' '
end

`tmux copy-mode -t #{pane_nr}`
`tmux send-keys -X -N #{left} -t #{pane_nr} cursor-left`
