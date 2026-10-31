require 'pty'
require 'io/console'
require 'tmpdir'

tmux_bin, mode_keys = ARGV
plugin_dir = File.expand_path('../..', __dir__)
content = "alpha beta\ngamma delta\nepsilon zeta\neta qux zeta\nquux end\n"
failed = false

Dir.mktmpdir('tmux-jump-e2e') do |dir|
  Dir.mkdir("#{dir}/bin")
  File.symlink(File.expand_path(tmux_bin), "#{dir}/bin/tmux")
  env = { 'PATH' => "#{dir}/bin:#{ENV['PATH']}", 'TMUX' => nil }
  File.write("#{dir}/content", content)
  File.write("#{dir}/tmux.conf", <<~CONF)
    set -g mode-keys #{mode_keys}
    set -g status off
    set -g set-clipboard off
    set -g @jump-key j
    run-shell #{plugin_dir}/tmux-jump.tmux
  CONF

  [['j', 'qux zeta'], ['f', 'quux end']].each do |label, expected|
    socket = "tmux-jump-e2e-#{Process.pid}-#{label}"
    tmux = ->(*args) { IO.popen(env, ['tmux', '-L', socket, *args], err: %i[child out], &:read) }
    read, write, pid = PTY.spawn(env, 'tmux', '-L', socket, '-f', "#{dir}/tmux.conf",
                                 'new-session', "cat #{dir}/content; sleep 300")
    read.winsize = [8, 40]
    drain = Thread.new { loop { read.readpartial(4096) rescue break } }
    sleep 1.0
    write.write(2.chr + 'j')
    sleep 0.8
    write.write('q')
    sleep 1.2
    write.write(label)
    sleep 1.2
    tmux.('send-keys', '-X', 'copy-end-of-line')
    text = tmux.('show-buffer')
    version = tmux.('display-message', '-p', '#{version}').strip
    ok = text.start_with?(expected)
    failed ||= !ok
    puts format('%-9s %-5s label=%s %-4s %p', version, mode_keys, label, ok ? 'ok' : 'MISS', text[0, 12])
    tmux.('kill-server')
    Process.kill('TERM', pid) rescue nil
    drain.kill
  end
end
exit(failed ? 1 : 0)
