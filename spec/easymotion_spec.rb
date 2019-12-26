require_relative '../scripts/easymotion'
require 'pty'
require 'pry'

PANE_NR = '%68'
PANE_MODE = '0'

RSpec.describe 'tmux-easymotion' do
  before do
    @read, @write = PTY.open
    PANE_TTY_FILE = @write.path
  end

  after do
    @write.close
    @read.close
  end

  let(:simple_screen) do
    tmp_screen = <<~EOS
      ~$ echo 'hello world! easymotion for tmux :)'
      hello world! easymotion for tmux :)
      ~$
    EOS
    tmp_screen[0..-2] # no newline ending
  end

  let(:many_es_screen) do
    tmp_screen = <<~EOS
      ~$ echo 'eello eorld! easymotion eor emux :)'
      eello eorld! easymotion eor tmux :)
      ~$ echo 'eello eorld! easymotion eor emux :)'
      eello eorld! easymotion eor tmux :)
      ~$ echo 'eello eorld! easymotion eor emux :)'
      eello eorld! easymotion eor tmux :)
      ~$ echo 'eello eorld! easymotion eor emux :)'
      eello eorld! easymotion eor tmux :)
      ~$ echo 'eello eorld! easymotion eor emux :)'
      eello eorld! easymotion eor tmux :)
      ~$ echo 'eello eorld! easymotion eor emux :)'
      eello eorld! easymotion eor tmux :)
      ~$ echo 'eello eorld! easymotion eor emux :)'
      eello eorld! easymotion eor tmux :)
      ~$ echo 'eello eorld! easymotion eor emux :)'
      eello eorld! easymotion eor tmux :)
      ~$ echo 'eello eorld! easymotion eor emux :)'
      eello eorld! easymotion eor tmux :)
      ~$
    EOS
    tmp_screen[0..-2] # no newline ending
  end

  describe '#positions_of' do
    context 'with a simple screen' do
      it 'returns the correct positions' do
        expect(positions_of('h', simple_screen)).to eq [9, 46]
        expect(positions_of('e', simple_screen)).to eq [3, 22, 59]
        expect(positions_of('s', simple_screen)).to eq []
      end
    end
  end

  describe 'keys_for' do
    [
      [1, KEYS.size, 1],
      [(KEYS.size - 1), KEYS.size, 1],
      [KEYS.size, KEYS.size, 1],
      [(KEYS.size + 1), KEYS.size**2, 2],
      [(KEYS.size**2 - 1), KEYS.size**2, 2],
      [KEYS.size**2, KEYS.size**2, 2],
      [(KEYS.size**2 + 1), KEYS.size**3, 3],
      [(KEYS.size**3 - 1), KEYS.size**3, 3],
      [KEYS.size**3, KEYS.size**3, 3],
      [(KEYS.size**3 + 1), KEYS.size**4, 4]
    ].each do |position_count, key_size, key_len|
      it "returns the correct keys for #{position_count}" do
        calculated_keys = keys_for position_count
        expect(calculated_keys.size).to eq key_size
        expect(calculated_keys.first.size).to eq key_len
      end
    end
  end

  describe '#prompt_position_index' do
    context 'when prompt char returns a char thats not on the screen' do
      before do
        allow_any_instance_of(Object).to receive(:prompt_char).and_return 'b'
      end

      it 'returns nil' do
        expect(prompt_position_index([3, 22, 59], simple_screen)).to eq nil
      end
    end

    context 'when prompt char does not return any char' do
      before do
        allow_any_instance_of(Object).to receive(:prompt_char).and_return nil
      end

      it 'just returns nil' do
        expect(prompt_position_index([3, 22, 59], simple_screen)).to eq nil
      end
    end

    it "returns the index if it's just 1 possibility" do
      expect(prompt_position_index([100], simple_screen)).to eq 0
    end

    context 'with many times the same char (many possible positions)' do
      before do
        allow_any_instance_of(Object).to receive(:prompt_char).and_return 'j'
      end

      it 'returns the ccorrect position' do
        positions = (0..81).to_a
        expect(prompt_position_index(positions, many_es_screen)).to eq 0
      end
    end
  end

  describe '#prompt_char' do
    context 'when the prompting process answers' do
      before do
        expect(Kernel).to receive(:spawn) do |*args|
          expect(args.first).to eq 'tmux'
          tmux_child_process_command = args.last.scan(/"(.+)"/).first.first
          spawn tmux_child_process_command.gsub('%1', 'e')
        end
      end

      it 'returns the character' do
        expect(prompt_char).to eq 'e'
      end
    end

    context 'when the prompting process does not answer' do
      before do
        expect(Kernel).to receive(:spawn) do |*args|
          expect(args.first).to eq 'tmux'
          tmux_child_process_command = args.last.scan(/"(.+)"/).first.first
          spawn tmux_child_process_command.gsub('%1', 'e')
        end
        expect(Timeout).to receive(:timeout).and_raise Timeout::Error
      end

      it 'returns nil' do
        expect(prompt_char).to eq nil
      end
    end
  end
end
