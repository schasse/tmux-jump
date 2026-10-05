require_relative '../scripts/jump_position'

RSpec.describe JumpPosition do
  describe '.cells' do
    {
      "e\u{301}" => { '3.1c' => 1 },
      "a\u{AD}" => { '3.1c' => 2, '3.7c' => 2 },
      "\u{915}\u{93F}" => { '3.1c' => 1 },
      "\u{2714}\u{FE0F}" => { '3.1c' => 1 },
      "\u{1F468}\u{200D}\u{1F4BB}" => { '3.2a' => 2, '3.3a' => 1, 'openbsd-6.9' => 2, 'openbsd-7.0' => 1 },
      "a\u{200D}b" => { '3.2a' => 2, '3.3a' => 2, '3.4' => 2, '3.7c' => 2 },
      "a\u{200D} b" => { '3.2a' => 3, '3.3a' => 3, '3.4' => 3, '3.7c' => 3 },
      "a\u{200D}\u{E9}" => { '3.2a' => 2, '3.3a' => 1, '3.4' => 1, '3.7c' => 1 },
      "\u{1F1EC}\u{1F1E7}\u{1F1EB}" => { '3.3a' => 3, '3.4' => 1, '3.6b' => 1, '3.7c' => 2, 'openbsd-7.3' => 3,
                                         'openbsd-7.4' => 1, 'openbsd-7.9' => 1, 'openbsd-8.0' => 2 },
      "\u{270B}\u{1F3FD}" => { '3.3a' => 2, '3.4' => 1, '3.6b' => 2, 'openbsd-7.8' => 1, 'openbsd-7.9' => 2 },
      "\u{1F44D}\u{1F3FD}" => { '3.3a' => 2, '3.4' => 1, '3.6b' => 1 },
      "\u{1F3FD}\u{1F44D}" => { '3.5a' => 2, '3.6b' => 1, '3.7c' => 1 },
      "a\u{1F3FD}" => { '3.4' => 2, '3.6b' => 2 },
      "\u{1100}\u{1161}\u{11A8}" => { '3.5a' => 3, '3.6b' => 1 }
    }.each do |text, counts|
      counts.each do |version, count|
        it "splits #{text.inspect} into #{count} cells on tmux #{version}" do
          expect(described_class.cells(version, text).size).to eq count
        end
      end
    end
  end

  describe '.cells with an explicit zero width set' do
    it 'keeps a spacing mark in its own cell' do
      expect(described_class.cells('3.4', "\u{915}\u{93F}", "\u{93F}" => false).size).to eq 2
    end

    it 'joins a spacing mark to its base' do
      expect(described_class.cells('3.4', "\u{915}\u{93F}", "\u{93F}" => true).size).to eq 1
    end

    it 'joins a Hangul vowel and final after a Latin letter' do
      zero_width = { "\u{1161}" => true, "\u{11A8}" => true }
      expect(described_class.cells('3.7c', "a\u{1161}\u{11A8}", zero_width).size).to eq 1
    end

    it 'keeps a Hangul vowel in its own cell after a Latin letter' do
      zero_width = { "\u{1161}" => false, "\u{11A8}" => false }
      expect(described_class.cells('3.7c', "a\u{1161}", zero_width).size).to eq 2
    end

    it 'falls back to the static rule for characters not in the set' do
      expect(described_class.cells('3.4', "e\u{301}\u{915}\u{93F}", "\u{93F}" => false).size).to eq 3
    end
  end

  describe '.zero_width_chars' do
    let(:calls) { [] }
    let(:run_tmux) { ->(args) { calls << args; "2 1\n" } }

    %w[3.2a openbsd-6.9 next-3.9].each do |version|
      it "queries tmux #{version}" do
        described_class.zero_width_chars(version, "\u{915}\u{93F}", run_tmux)
        expect(calls.size).to eq 1
      end
    end

    %w[3.1c openbsd-6.8].each do |version|
      it "makes no call for tmux #{version}" do
        expect(described_class.zero_width_chars(version, "\u{915}\u{93F}", run_tmux)).to eq({})
        expect(calls).to be_empty
      end
    end

    it 'maps a width of 1 to zero-width' do
      expect(described_class.zero_width_chars('3.4', "\u{93F}\u{301}", run_tmux)).to eq("\u{93F}" => false, "\u{301}" => true)
    end

    it 'queries each distinct candidate once' do
      described_class.zero_width_chars('3.4', "\u{93F}\u{301}\u{93F}", run_tmux)
      expect(calls).to eq [['display-message', '-p', "\#{w:\#{l:a\u{93F}}} \#{w:\#{l:a\u{301}}}"]]
    end

    it 'queries C1 controls' do
      expect(described_class.zero_width_chars('3.4', "a\u{85}b", ->(_) { "1\n" })).to eq("\u{85}" => true)
    end

    it 'makes no call without candidates' do
      expect(described_class.zero_width_chars('3.4', "abc \u{4E2D} \u{1F600}", run_tmux)).to eq({})
      expect(calls).to be_empty
    end

    ['', "2\n", "2 1 1\n", "0 1\n", nil].each do |malformed|
      it "returns {} for the answer #{malformed.inspect}" do
        expect(described_class.zero_width_chars('3.4', "\u{93F}\u{301}", ->(_) { malformed })).to eq({})
      end
    end
  end

  describe '.commands' do
    def column_command(version, screen, marker)
      described_class.commands(version, screen.index(marker), screen, 0).last
    end

    it 'jumps forward to an ASCII target on any tmux' do
      expect(column_command('3.1c', "t1 xt2 t3\n", 't3')).to eq ['-N', '2', 'jump-forward', 't']
    end

    it 'jumps forward to other single characters from tmux 3.2' do
      expect(column_command('3.2a', "\u{4E2D}1 \u{4E2D}2\n", "\u{4E2D}2")).to eq ['-N', '1', 'jump-forward', "\u{4E2D}"]
    end

    it 'moves right to other single characters on tmux 3.1' do
      expect(column_command('3.1c', "\u{4E2D}1 \u{4E2D}2\n", "\u{4E2D}2")).to eq ['-N', '3', 'cursor-right']
    end

    it 'maps OpenBSD releases to the tmux behaviour they ship' do
      expect(column_command('openbsd-6.8', "\u{4E2D}1 \u{4E2D}2\n", "\u{4E2D}2")).to eq ['-N', '3', 'cursor-right']
      expect(column_command('openbsd-6.9', "\u{4E2D}1 \u{4E2D}2\n", "\u{4E2D}2")).to eq ['-N', '1', 'jump-forward', "\u{4E2D}"]
    end

    it 'moves right by cells to a target of several code points' do
      expect(column_command('3.3a', "\u{1F468}\u{200D}\u{1F4BB} e\u{301}x\n", "e\u{301}x")).to eq ['-N', '2', 'cursor-right']
    end

    it 'escapes a semicolon target' do
      expect(column_command('3.7c', "x ;1\n", ';1')).to eq ['-N', '1', 'jump-forward', '\;']
    end

    it 'moves down past a blank top row inside a rectangle selection' do
      expect(described_class.commands('3.7c', 2, "\n\nab cd\n", 0))
        .to eq [['top-line'], ['begin-selection'], ['rectangle-toggle'], ['-N', '2', 'cursor-down'],
                ['rectangle-toggle'], ['clear-selection']]
    end
  end
end
