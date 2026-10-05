require 'tempfile'

ENV['JUMP_BACKGROUND_COLOR'] ||= "\e[0m\e[32m"
ENV['JUMP_FOREGROUND_COLOR'] ||= "\e[1m\e[31m"
ENV['JUMP_KEYS'] ||= 'jfhgkdlsa'
ENV['JUMP_KEYS_POSITION'] ||= 'left'
require_relative '../../scripts/tmux-jump'

TMUX_BIN, MODE_KEYS, SEED, SCREENS = ARGV
WIDTH = 40
HEIGHT = 8
SOCKET = "tmux-jump-compare-#{Process.pid}"

def tmux(*args)
  IO.popen([TMUX_BIN, '-L', SOCKET, *args], err: %i[child out], &:read)
end

def master_commands(jump_to, scroll)
  [['start-of-line'], ['top-line'], ['-N', '200', 'cursor-right'], ['start-of-line'], ['top-line'],
   ['-N', scroll.to_s, 'cursor-up'], ['-N', jump_to.to_s, 'cursor-right']]
end

def width(text, zero_width)
  text.each_char.inject(0) do |x, char|
    if char == "\t" then [(x / 8 + 1) * 8, WIDTH - 1].min
    elsif zero_width.fetch(char) { char =~ /\p{M}/ } then x
    elsif char =~ /[一-鿿가-힣ᄀ-ᅟ]/ then x + 2
    else x + 1
    end
  end
end

WORDS = %w[alpha beta gamma delta tx tt ab ba foo bar a b t x quux zeta]
INDIC_HANGUL = %W[\u0915\u093f \u0915\u093f\u0915 \u0928\u093e\u092e \u0939\u093f\u0928\u094d\u0926\u0940 \ud55c\uae00]
PUNCTUATION = [',', '.', '-', '(', ')', '!', ':', '/', '"']

def random_word(rng)
  case rng.rand(11)
  when 0 then Array.new(rng.rand(1..3)) { %W[中 文 字][rng.rand(3)] }.join + (rng.rand(2).zero? ? 'x' : '')
  when 1 then (rng.rand(2).zero? ? "é" : "é") + WORDS.sample(random: rng)
  when 2 then INDIC_HANGUL.sample(random: rng) + (rng.rand(2).zero? ? 'x' : WORDS.sample(random: rng))
  when 3 then WORDS.sample(random: rng) + PUNCTUATION.sample(random: rng)
  else WORDS.sample(random: rng)
  end
end

def random_line(rng)
  case rng.rand(8)
  when 0 then ''
  when 1 then Array.new(rng.rand(8..16)) { random_word(rng) }.join(' ')
  when 2 then Array.new(rng.rand(2..5)) { random_word(rng) }.join("\t")
  when 3 then (' ' * rng.rand(1..WIDTH + 4)) + random_word(rng)
  else Array.new(rng.rand(1..6)) { random_word(rng) }.join(' ')
  end
end

def random_content(rng)
  lines = Array.new(rng.rand(0..2)) { '' } + Array.new(rng.rand(4..24)) { random_line(rng) }
  lines.map { |line| "#{line}\n" }.join + (rng.rand(2).zero? ? 'prompt> ' : '')
end

def start_pane(file)
  tmux('-f', '/dev/null', 'new-session', '-d', '-x', WIDTH.to_s, '-y', HEIGHT.to_s)
  tmux('resize-window', '-x', WIDTH.to_s, '-y', HEIGHT.to_s)
  tmux('set-option', '-g', 'mode-keys', MODE_KEYS)
  pane = tmux('display-message', '-p', '#{pane_id}').strip
  size = tmux('display-message', '-p', '-t', pane, '#{pane_width}x#{pane_height}').strip
  abort "pane is #{size}, not #{WIDTH}x#{HEIGHT}" unless size == "#{WIDTH}x#{HEIGHT}"
  tmux('respawn-pane', '-k', '-t', pane, "cat #{file}; #{TMUX_BIN} wait-for -S ready; sleep 300")
  tmux('wait-for', 'ready')
  pane
end

def land(pane, commands)
  tmux('send-keys', '-X', '-t', pane, 'cancel') if tmux('display-message', '-p', '-t', pane, '#{pane_in_mode}').strip == '1'
  tmux('copy-mode', '-t', pane)
  commands.each { |command| tmux('send-keys', '-X', '-t', pane, *command) }
  tmux('display-message', '-p', '-t', pane, '#{copy_cursor_x} #{copy_cursor_y} #{scroll_position}').split.map(&:to_i)
end

rng = Random.new((SEED || 1).to_i)
version = nil
counts = Hash.new(0)
(SCREENS || 40).to_i.times do
  file = Tempfile.new('tmux-jump-compare')
  file.write(random_content(rng))
  file.close
  pane = start_pane(file.path)
  version ||= tmux('display-message', '-p', '#{version}').strip
  history = tmux('display-message', '-p', '-t', pane, '#{history_size}').to_i
  scroll = rng.rand(3).zero? ? 0 : rng.rand(0..[history, 12].min)
  if scroll > 0
    tmux('copy-mode', '-t', pane)
    tmux('send-keys', '-X', '-t', pane, '-N', scroll.to_s, 'scroll-up')
  end
  scroll = tmux('display-message', '-p', '-t', pane, '#{scroll_position}').to_i
  screen = tmux('capture-pane', '-p', '-t', pane, '-S', (-scroll).to_s, '-E', (-scroll + HEIGHT - 1).to_s)[0..-2]
  zero_width = JumpPosition.zero_width_chars(version, screen, ->(args) { tmux(*args) })
  typeable = screen.each_char.reject { |char| char == "\n" || char == "\t" || zero_width.fetch(char) { char =~ /\p{M}/ } }.uniq
  typeable.flat_map { |char| positions_of(char, screen) }.uniq.sort.each do |jump_to|
    target = [width(screen[0...jump_to][/[^\n]*\z/], zero_width), screen[0...jump_to].count("\n"), scroll]
    master = land(pane, master_commands(jump_to, scroll)) == target
    branch = land(pane, JumpPosition.commands(version, jump_to, screen, scroll, zero_width)) == target
    counts[:jumps] += 1
    counts[:master] += 1 if master
    counts[:branch] += 1 if branch
    next unless master && !branch

    counts[:regressions] += 1
    puts "regression: scroll=#{scroll} jump_to=#{jump_to} screen=#{screen.inspect}"
  end
  tmux('kill-server')
  file.unlink
end
puts format('%-9s %-5s jumps=%d master=%d branch=%d regressions=%d',
            version, MODE_KEYS, counts[:jumps], counts[:master], counts[:branch], counts[:regressions])
exit(counts[:regressions] > 0 ? 1 : 0)
