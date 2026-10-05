require 'tempfile'

ENV['JUMP_BACKGROUND_COLOR'] ||= "\e[0m\e[32m"
ENV['JUMP_FOREGROUND_COLOR'] ||= "\e[1m\e[31m"
ENV['JUMP_KEYS'] ||= 'jfhgkdlsa'
ENV['JUMP_KEYS_POSITION'] ||= 'left'

require_relative '../scripts/tmux-jump'

TMUX_BIN = ENV.fetch('TMUX_BIN', 'tmux')
TMUX_VERSION = IO.popen([TMUX_BIN, '-V'], &:read).strip.sub(/\Atmux /, '')
PANE_WIDTH = 40
PANE_HEIGHT = 8

def tmux(*args)
  IO.popen([TMUX_BIN, '-L', "tmux-jump-spec-#{Process.pid}", *args], err: %i[child out], &:read)
end

def start_pane(content, mode_keys, options = {})
  file = Tempfile.new('tmux-jump-content')
  file.write(content)
  file.close
  tmux('-f', '/dev/null', 'new-session', '-d', '-x', PANE_WIDTH.to_s, '-y', PANE_HEIGHT.to_s)
  tmux('resize-window', '-x', PANE_WIDTH.to_s, '-y', PANE_HEIGHT.to_s)
  tmux('set-option', '-g', 'mode-keys', mode_keys)
  options.each do |name, value|
    skip "tmux has no #{name} option" unless tmux('set-option', '-g', name, value).empty?
  end
  pane = tmux('display-message', '-p', '#{pane_id}').strip
  expect(tmux('display-message', '-p', '-t', pane, '#{pane_width}x#{pane_height}').strip)
    .to eq "#{PANE_WIDTH}x#{PANE_HEIGHT}"
  tmux('respawn-pane', '-k', '-t', pane, "cat #{file.path}; sleep 300")
  50.times do
    break unless tmux('capture-pane', '-p', '-t', pane).strip.empty?
    sleep 0.05
  end
  pane
end

def scroll_position(pane)
  tmux('display-message', '-p', '-t', pane, '#{scroll_position}').to_i
end

def jump(pane, marker)
  in_mode = tmux('display-message', '-p', '-t', pane, '#{pane_in_mode}').strip == '1'
  scroll = scroll_position(pane)
  start = -scroll
  screen_chars = tmux('capture-pane', '-p', '-t', pane, '-S', start.to_s,
                      '-E', (start + PANE_HEIGHT - 1).to_s)[0..-2]
  jump_to = screen_chars.index(marker)
  expect(jump_to).not_to be_nil
  expect(positions_of(marker[0], screen_chars)).to include(jump_to)

  tmux('send-keys', '-X', '-t', pane, 'cancel') if in_mode
  tmux('copy-mode', '-t', pane)
  version = tmux('display-message', '-p', '#{version}').strip
  zero_width = JumpPosition.zero_width_chars(version, screen_chars, ->(args) { tmux(*args) })
  JumpPosition.commands(version, jump_to, screen_chars, scroll, zero_width).each do |command|
    tmux('send-keys', '-X', '-t', pane, *command)
  end
end

def text_under_cursor(pane)
  tmux('send-keys', '-X', '-t', pane, 'copy-end-of-line')
  tmux('show-buffer')
end

JOINED = "\u{1F1EC}\u{1F1E7}\u{1F1EB}\u{1F1F7} \u270b\u{1F3FD} \u{1F44D}\u{1F3FD} \u{1F468}\u200d\u{1F4BB} \u1100\u1161\u11a8 \u0915\u093f"

CASES = [
  ['a target several rows down', "alpha beta\ngamma delta\nepsilon zeta\neta thetaX\n", 'thetaX'],
  ['a blank top line', "\nalpha beta\n\ngamma delta tgt\n", 'tgt'],
  ['a line indented past the pane width', "#{' ' * PANE_WIDTH}hello\nworld\n", 'world'],
  ['a target on a line indented past the pane width', "#{' ' * PANE_WIDTH}hello world\n", 'world'],
  ['blank top lines and a target at the start of a line', "\n\ntgt x\nfoo\n", 'tgt'],
  ['a target at the start of a line', "foo t\ntgt\n", 'tgt'],
  ['a space target', "x\na, b\n", ' b'],
  ['emoji, joined emoji and combining marks',
   "at \u26a0\ufe0f warn\n\u2714\ufe0f done \u{1F468}\u200d\u{1F4BB} e\u0301 tok\n", 'tok'],
  ['double-width characters', "\u4e2d\u6587 at tt\ntest \u4e2d tq\n", 'tq'],
  ['a double-width target', "ab \u4e2dx \u4e2dy\n", "\u4e2dy"],
  ['a wrapped line', "top\n#{'aaaa ' * 9}tWRAP end\n", 'tWRAP'],
  ['a repeated target on a wrapped line', "t1 t2 t3 #{'a' * PANE_WIDTH}\n", 't3'],
  ['an accent and a repeated target on a wrapped line', "e\u0301 t1 t2 t3 #{'a' * PANE_WIDTH}\n", 't3'],
  ['a target in the last column', "#{'a' * (PANE_WIDTH - 2)} t\nfoo\n", 't'],
  ['an accent and a double-width target', "e\u0301 \u4e2dx \u4e2dy\n", "\u4e2dy"],
  ['an accent and a target in the last column', "e\u0301#{'a' * (PANE_WIDTH - 3)} t\nfoo\n", 't'],
  ['mixed case', "The Tall tree\nTOP tip\n", 'tip'],
  ['a target in the top-left cell', "tango x\n", 'tango'],
  ['the same char in the top-left cell', "tango\nfoo tz\n", 'tz'],
  ['joined sequences and a decomposed accent target', "#{JOINED} e\u0301tok\n", "e\u0301tok"],
  ['joined sequences and a double-width target', "#{JOINED} \u4e2dx \u4e2dy\n", "\u4e2dy"],
  ['an accented target', "e\u0301a xe\u0301 e\u0301b\n", "e\u0301b"],
  ['a zero width joiner before ASCII and a decomposed accent target', "a\u200db e\u0301x\n", "e\u0301x", unsearchable_on: [3, 3]],
  ['a soft hyphen', "x t\u00ad tgt\n", 'tgt'],
  ['a soft hyphen and a decomposed accent target', "a\u00ad e\u0301x\n", "e\u0301x"],
  ['a text presentation selector on the target', "x \u2714\ufe0e1 \u2714\ufe0e2\n", "\u2714\ufe0e2"],
  ['a spacing mark and a target after it', "x \u0915\u093f \u0915x\n", "\u0915x"],
  ['a spacing mark and a decomposed accent target', "\u0915\u093f e\u0301x\n", "e\u0301x"],
  ['a Hangul vowel and final after a Latin letter and a decomposed accent target', "a\u1161\u11a8 e\u0301x\n", "e\u0301x"],
  ['a C1 control and a decomposed accent target', "a\u0085b e\u0301x\n", "e\u0301x", since: [3, 2]],
  ['a spacing mark with its own cell by codepoint-widths and a target after it', "x \u0915\u093f \u0915x\n", "\u0915x",
   tmux_options: { 'codepoint-widths' => 'U+093F=1' }],
  ['a skin tone before its base and a decomposed accent target', "\u{1F3FD}\u{1F44D} e\u0301x\n", "e\u0301x"]
] + %w[; \\ ' " $ { } # % ~ - /].map do |char|
  ["the special char #{char}", "#{char}1 x#{char}2 #{char}mark\n", "#{char}mark"]
end

RSpec.describe "jump positioning (#{TMUX_BIN})" do
  after { tmux('kill-server') }

  %w[vi emacs].each do |mode_keys|
    context "with mode-keys #{mode_keys}" do
      CASES.each do |description, content, marker, options = {}|
        it "lands on the target with #{description}" do
          unsearchable_on = options[:unsearchable_on]
          if unsearchable_on && JumpPosition.tmux_at_least?(TMUX_VERSION, *unsearchable_on) &&
             !JumpPosition.tmux_at_least?(TMUX_VERSION, unsearchable_on[0], unsearchable_on[1] + 1)
            skip 'the joiner is captured after the target base character'
          end
          skip 'the width is only queried from tmux 3.2' if options[:since] && !JumpPosition.tmux_at_least?(TMUX_VERSION, *options[:since])
          pane = start_pane(content, mode_keys, options.fetch(:tmux_options, {}))
          jump(pane, marker)
          expect(text_under_cursor(pane)).to start_with(marker)
        end
      end

      {
        'a scrolled view' => (1..60).map { |i| "t line #{i}\n" }.join,
        'a scrolled view with a blank top row and the cursor past the first column' =>
          (1..30).map { |i| "t line #{i}\n\n" }.join + 'prompt> '
      }.each do |description, content|
        it "keeps #{description} and lands on the target" do
          pane = start_pane(content, mode_keys)
          tmux('copy-mode', '-t', pane)
          tmux('send-keys', '-X', '-t', pane, '-N', '10', 'scroll-up')
          expect(scroll_position(pane)).to eq 10
          marker = tmux('capture-pane', '-p', '-t', pane, '-S', '-10', '-E', '-3').lines[3].chomp
          jump(pane, marker)
          expect(scroll_position(pane)).to eq 10
          expect(text_under_cursor(pane)).to start_with(marker)
        end
      end

      context 'with casesensitive' do
        around do |example|
          ENV['JUMP_KEY_CASE'] = 'casesensitive'
          example.run
          ENV.delete('JUMP_KEY_CASE')
        end

        [["t1 xT2 t3 Tmark\n", 'Tmark'], ["T1 xt2 T3 tmark\n", 'tmark']].each do |content, marker|
          it "lands on #{marker}" do
            pane = start_pane(content, mode_keys)
            jump(pane, marker)
            expect(text_under_cursor(pane)).to start_with(marker)
          end
        end
      end
    end
  end
end
