#!/usr/bin/env ruby
require 'timeout'
require 'tempfile'
require 'open3'

# SPECIAL STRINGS
GRAY = ENV['JUMP_BACKGROUND_COLOR'].gsub('\e', "\e")
# RED = "\e[38;5;124m"
RED = ENV['JUMP_FOREGROUND_COLOR'].gsub('\e', "\e")
CLEAR_SEQ = "\e[2J"
HOME_SEQ = "\e[H"
RESET_COLORS = "\e[0m"
ENTER_ALTERNATE_SCREEN = "\e[?1049h"
RESTORE_NORMAL_SCREEN = "\e[?1049l"
NEWLINE = "\r\n"

# CONFIG
KEYS = 'jfhgkdlsa'.each_char.to_a
Config = Struct.new(
  :pane_nr,
  :pane_tty_file,
  :pane_mode,
  :cursor_y,
  :cursor_x,
  :alternate_on,
  :scroll_position,
  :pane_width,
  :pane_height,
  :tmp_file
).new

# METHODS
def recover_screen_after
  if Config.alternate_on == '1'
    recover_alternate_screen_after do
      yield
    end
  else
    recover_normal_screen_after do
      yield
    end
  end
end

def recover_normal_screen_after
  File.open(Config.pane_tty_file, 'a') do |tty|
    tty << ENTER_ALTERNATE_SCREEN + HOME_SEQ
  end

  begin
    returns = yield
  rescue Timeout::Error
    # user took too long, but we recover anyways
  end

  File.open(Config.pane_tty_file, 'a') do |tty|
    tty << RESTORE_NORMAL_SCREEN
  end
  returns
end

def recover_alternate_screen_after
  saved_screen =
    `tmux capture-pane -ep -t #{Config.pane_nr}`[0..-2] # with colors...
      .gsub("\n", NEWLINE)
  File.open(Config.pane_tty_file, 'a') do |tty|
    tty << CLEAR_SEQ + HOME_SEQ
  end

  begin
    returns = yield
  rescue Timeout::Error
    # user took too long, but we recover anyways
  end

  File.open(Config.pane_tty_file, 'a') do |tty|
    tty << RESET_COLORS + CLEAR_SEQ
    tty << saved_screen
    tty << "\e[#{Config.cursor_y.to_i + 1};#{Config.cursor_x.to_i + 1}H"
    tty << RESET_COLORS
  end
  returns
end

def prompt_char! # raises Timeout::Error
  tmp_file = Tempfile.new 'tmux-jump'
  Kernel.spawn(
    'tmux', 'command-prompt', '-1', '-p', 'char:',
    "run-shell \"printf '%1' >> #{tmp_file.path}\"")
  result_queue = Queue.new
  thread_0 = async_read_char_from_file! tmp_file, result_queue
  thread_1 = async_detect_user_escape result_queue
  char = result_queue.pop
  thread_0.exit
  thread_1.exit
  char
end

def async_read_char_from_file!(tmp_file, result_queue)
  thread = Thread.new do
    result_queue.push read_char_from_file! tmp_file
  end
  thread.abort_on_exception = true
  thread
end

def read_char_from_file!(tmp_file) # raises Timeout::Error
  char = nil
  Timeout.timeout(10) do
    begin
      loop do # busy waiting with files :/
        break if char = tmp_file.getc
      end
    end
  end
  File.delete tmp_file
  char
end

def async_detect_user_escape(result_queue)
  Thread.new do
    last_activity =
      Open3.capture2 'tmux', 'display-message', '-p', '#{session_activity}'
    loop do
      new_activity =
        Open3.capture2 'tmux', 'display-message', '-p', '#{session_activity}'
      sleep 0.05
      if last_activity != new_activity
        result_queue.push nil
      end
    end
  end
end

def make_screen_lines(screen_chars)
  screen_lines = screen_chars.split("\n")
  screen_lines.each_with_index do |screen_line, i|
    screen_lines[i] = screen_line + ' ' * (Config.pane_width - screen_line.size)
  end
  screen_lines += [' ' * Config.pane_width] * (Config.pane_height - screen_lines.size)
  screen_lines
end

def positions_of(jump_to_char, screen_lines)
  positions = []
  offset = 0
  screen_lines.each_with_index do |screen_line, line_idx|
    prev_char = ''
    screen_line.each_char.each_with_index do |char, column_idx|
      positions << [line_idx, column_idx, offset] if !(prev_char =~ /\w/) && char.downcase == jump_to_char
      offset += 1
      prev_char = char
    end
    offset += NEWLINE.size
  end
  positions
end

def draw_keys_onto_tty(screen_lines, positions, keys, key_len)
  screen = screen_lines.join(NEWLINE)
  cursor = 0
  segments = []
  positions.each_with_index do |pos, i|
    offset = pos[2]
    if offset > cursor
      segments << GRAY
      segments << screen[cursor..offset-1]
    end
    segments << RED
    segments << keys[i]
    cursor = offset + key_len
  end
  if screen.size > cursor
    segments << GRAY
    segments << screen[cursor..-1]
  end
  screen_with_keys = segments.join()
  File.open(Config.pane_tty_file, 'a') do |tty|
    tty << screen_with_keys + HOME_SEQ
  end
end

def keys_for(position_count, keys = KEYS)
  if position_count > keys.size
    keys_for(position_count, keys.product(KEYS).map(&:join))
  else
    keys
  end
end

def prompt_position_index!(positions, screen_lines) # raises Timeout::Error
  return nil if positions.size == 0
  return 0 if positions.size == 1
  keys = keys_for positions.size
  key_len = keys.first.size
  draw_keys_onto_tty screen_lines, positions, keys, key_len
  key_index = KEYS.index(prompt_char!)
  if !key_index.nil? && key_len > 1
    magnitude = KEYS.size ** (key_len - 1)
    range_beginning = key_index * magnitude # p.e. 2 * 22^1
    range_ending = range_beginning + magnitude - 1
    remaining_positions = positions[range_beginning..range_ending]
    return nil if remaining_positions.nil?
    lower_index = prompt_position_index!(remaining_positions, screen_lines)
    return nil if lower_index.nil?
    range_beginning + lower_index
  else
    key_index
  end
end

def main
  begin
    jump_to_char = read_char_from_file! File.new(Config.tmp_file)
  rescue Timeout::Error
    Kernel.exit
  end
  `tmux send-keys -X -t #{Config.pane_nr} cancel` if Config.pane_mode == '1'
  start = -Config.scroll_position
  ending = -Config.scroll_position + Config.pane_height - 1
  screen_chars =
    `tmux capture-pane -p -t #{Config.pane_nr} -S #{start} -E #{ending}`[0..-2].gsub("︎", '') # without colors
  screen_lines = make_screen_lines screen_chars
  positions = positions_of jump_to_char, screen_lines
  position_index = recover_screen_after do
    prompt_position_index! positions, screen_lines
  end
  Kernel.exit 0 if position_index.nil?
  jump_to = positions[position_index]
  Kernel.exit 0 if jump_to.nil?
  `tmux copy-mode -t #{Config.pane_nr}`
  `tmux send-keys -X -t #{Config.pane_nr} top-line`
  `tmux send-keys -X -t #{Config.pane_nr} -N #{jump_to[0]} cursor-down` if jump_to[0] >= 1
  `tmux send-keys -X -t #{Config.pane_nr} start-of-line`
  `tmux send-keys -X -t #{Config.pane_nr} -N #{jump_to[1]} cursor-right` if jump_to[1] >= 1
end

if $PROGRAM_NAME == __FILE__
  Config.pane_nr = `tmux display-message -p "\#{pane_id}"`.strip
  format = '#{pane_id};#{pane_tty};#{pane_in_mode};#{cursor_y};#{cursor_x};'\
           '#{alternate_on};#{scroll_position};#{pane_width};#{pane_height}'
  tmux_data = `tmux display-message -p -t #{Config.pane_nr} -F "#{format}"`.strip.split(';')
  Config.pane_tty_file = tmux_data[1]
  Config.pane_mode = tmux_data[2]
  Config.cursor_y = tmux_data[3]
  Config.cursor_x = tmux_data[4]
  Config.alternate_on = tmux_data[5]
  Config.scroll_position = tmux_data[6].to_i
  Config.pane_width = tmux_data[7].to_i
  Config.pane_height = tmux_data[8].to_i
  Config.tmp_file = ARGV[0]
  main
end
