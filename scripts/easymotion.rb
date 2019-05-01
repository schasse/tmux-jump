#!/usr/bin/env ruby

# ENV
PANE_NR = `tmux display-message -p "\#{pane_id}"`.strip
# PANE_NR = '%17'
tmux_data = `tmux lsp -a -F "\#{pane_tty};\#{pane_in_mode};\#{pane_id}" | grep #{PANE_NR}`.split(';')
PANE_MODE = tmux_data[1]
PANE_TTY_FILE = tmux_data[0]


# SPECIAL STRINGS
GRAY = "\e[0m\e[32m"
# RED = "\e[38;5;124m"
RED = "\e[1m\e[31m"
CLEAR_SEQ = "\e[2J"
HOME_SEQ = "\e[H"


# CONFIG
KEYS = 'jfhgkdlsnamvucixozyrpt'.each_char.to_a


# METHODS
def recover_screen_after
  saved_screen =
    `tmux capture-pane -ep -t #{PANE_NR}`[0..-2] # with colors...
      .gsub("\n", "\n\r")
  cursor_y, cursor_x, _ = `tmux lsp -a -F "\#{cursor_y};\#{cursor_x};\#{pane_id}" | grep #{PANE_NR}`.split(';')

  returns = yield

  File.open(PANE_TTY_FILE, 'a') do |tty|
    tty << "\e[0m" + CLEAR_SEQ + HOME_SEQ
    tty << saved_screen
    tty << "\e[#{cursor_y.to_i + 1};#{cursor_x.to_i + 1}H"
  end
  returns
end

def prompt_char
  read, write = IO.pipe
  path = "/proc/#{Process.pid}/fd/#{write.fileno}"
  `tmux command-prompt -1 -p 'char:' 'run-shell "printf %1 >> #{path}"'`
  char = read.getc
  write.close
  read.close
  char
end

def positions_of(jump_to_char, screen_chars)
  positions = []

  positions << 0 if screen_chars[0] =~ /\w/ && screen_chars[0].downcase == jump_to_char
  screen_chars.each_char.with_index do |char, i|
    if (char =~ /\w/).nil? && screen_chars[i+1] && screen_chars[i+1].downcase == jump_to_char
      positions << i+1
    end
  end
  positions
end

def draw_keys_onto_tty(screen_chars, positions, keys, key_len)
  File.open(PANE_TTY_FILE, 'a') do |tty|
    tty << "#{CLEAR_SEQ}#{HOME_SEQ}"
    cursor = 0
    positions.each_with_index do |pos, i|
      tty << "#{GRAY}#{screen_chars[cursor..pos-key_len].gsub("\n", "\n\r")}"
      tty << "#{RED}#{keys[i]}"
      cursor = pos + 1
    end
    tty << "#{GRAY}#{screen_chars[cursor..-1].gsub("\n", "\n\r")}"
    tty << HOME_SEQ
  end
end

def keys_for(position_count, keys = KEYS, key_len = 1)
  if position_count > keys.size
    keys_for(position_count, keys.product(keys).map(&:join), 2)
  else
    keys
  end
end

def prompt_position_index(positions, screen_chars)
  keys = keys_for positions.size
  key_len = keys.first.size
  draw_keys_onto_tty screen_chars, positions, keys, key_len
  key_index = KEYS.index(prompt_char)
  if key_len > 1
    magnitude = KEYS.size ** (key_len - 1)
    range_beginning = key_index * magnitude # p.e. 2 * 22^1
    range_ending = range_beginning + magnitude - 1
    remaining_positions = positions[range_beginning..range_ending]
    range_beginning + prompt_position_index(remaining_positions, screen_chars)
  else
    key_index
  end
end

def main
  `tmux send-keys -X -t #{PANE_NR} cancel` if PANE_MODE == '1'
  jump_to_char = prompt_char
  screen_chars =
    `tmux capture-pane -p -t #{PANE_NR}`[0..-2] # without colors
  positions = positions_of jump_to_char, screen_chars
  position_index = recover_screen_after do
    prompt_position_index positions, screen_chars
  end
  jump_to = positions[position_index]
  `tmux copy-mode -t #{PANE_NR}`
  `tmux send-keys -X -t #{PANE_NR} start-of-line`
  `tmux send-keys -X -t #{PANE_NR} top-line`
  `tmux send-keys -X -N #{jump_to} -t #{PANE_NR} cursor-right`
end

main
