require_relative '../scripts/jump_position'

RSpec.describe JumpPosition do
  describe '.tmux_at_least?' do
    {
      ['3.8-rc3', 3, 8] => true,
      ['3.8-rc4', 3, 9] => false,
      ['next-3.9', 3, 9] => true,
      ['next-3.9', 4, 0] => false,
      ['3.10', 3, 9] => true,
      ['openbsd-7.4', 3, 4] => true,
      ['openbsd-7.4', 3, 5] => false,
      ['openbsd-6.8', 3, 2] => false
    }.each do |(version, major, minor), expected|
      it "is #{expected} for #{version} against #{major}.#{minor}" do
        expect(described_class.tmux_at_least?(version, major, minor)).to eq expected
      end
    end
  end

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
