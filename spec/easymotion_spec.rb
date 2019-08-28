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

  describe '#positions_of' do
    context 'with a simple screen' do
      let(:screen) do
        tmp_screen = <<~EOS
          ~$ echo 'hello world! easymotion for tmux :)'
          hello world! easymotion for tmux :)
          ~$
        EOS
        tmp_screen[0..-2] # no newline ending
      end

      it 'returns the correct positions' do
        expect(positions_of('h', screen)).to eq [9, 46]
        expect(positions_of('e', screen)).to eq [3, 22, 59]
        expect(positions_of('s', screen)).to eq []
      end

      context 'with some colorized screen' do
        it 'returns the correct positions'
      end
    end
  end

  describe '#prompt_position_index'

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
      it 'raises a time out error'
    end
  end
end
