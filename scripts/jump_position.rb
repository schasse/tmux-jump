module JumpPosition
  ZERO_WIDTH = /[\p{M}\p{Cf}\u{2028}\u{2029}&&[^\u{AD}\u{302E}\u{302F}\u{16FF0}\u{16FF1}]]/
  WIDTH_VARYING = /[\p{M}\p{Cf}\p{Cn}\u{80}-\u{9F}\u{2028}\u{2029}\u{1160}-\u{11FF}\u{D7B0}-\u{D7FB}\u{3164}\u{FFA0}]/
  REGIONAL_INDICATOR = /[\u{1F1E6}-\u{1F1FF}]/
  SKIN_TONE = /[\u{1F3FB}-\u{1F3FF}]/
  SKIN_TONE_BASE = /\A[\u{1F44B}-\u{1F450}\u{1F466}-\u{1F469}\u{1F46E}\u{1F470}-\u{1F478}\u{1F47C}\u{1F481}-\u{1F483}\u{1F485}-\u{1F487}\u{1F4AA}\u{1F575}\u{1F57A}\u{1F590}\u{1F595}-\u{1F596}\u{1F645}-\u{1F647}\u{1F64B}-\u{1F64F}\u{1F6B4}-\u{1F6B6}\u{1F926}\u{1F937}-\u{1F939}\u{1F93D}-\u{1F93E}\u{1F9B5}-\u{1F9B6}\u{1F9B8}-\u{1F9B9}\u{1F9CD}-\u{1F9CF}\u{1F9D1}-\u{1F9DF}]\z/
  HANGUL_INITIAL = /[\u{1100}-\u{115E}\u{A960}-\u{A97C}]/
  HANGUL_VOWEL = /[\u{1161}-\u{11A7}\u{D7B0}-\u{D7C6}]/
  HANGUL_FINAL = /[\u{11A8}-\u{11FF}\u{D7CB}-\u{D7FB}]/
  OPENBSD_TMUX = { [8, 0] => [3, 7], [7, 9] => [3, 6], [7, 8] => [3, 5], [7, 4] => [3, 4], [7, 0] => [3, 3], [6, 9] => [3, 2] }

  def self.tmux_at_least?(version, major, minor)
    number = version.to_s.scan(/\d+/).first(2).map(&:to_i)
    if version.to_s.start_with?('openbsd-')
      number = OPENBSD_TMUX.find { |release, _| (number <=> release) >= 0 }&.last || [3, 1]
    end
    (number <=> [major, minor]) >= 0
  end

  def self.zero_width_chars(version, screen_chars, run_tmux)
    chars = screen_chars.scan(WIDTH_VARYING).uniq
    return {} if chars.empty? || !tmux_at_least?(version, 3, 2)

    format = chars.map { |char| "\#{w:\#{l:a#{char}}}" }.join(' ')
    widths = run_tmux.call(['display-message', '-p', format]).to_s.split
    return {} unless widths.size == chars.size && widths.all? { |width| %w[1 2 3].include?(width) }

    chars.zip(widths.map { |width| width == '1' }).to_h
  end

  def self.joins?(version, cell, char, zero_width = {})
    return true if zero_width.fetch(char) { char =~ ZERO_WIDTH }
    return false unless tmux_at_least?(version, 3, 3)
    return !char.ascii_only? if cell.end_with?("\u{200D}")

    if tmux_at_least?(version, 3, 6)
      flag = tmux_at_least?(version, 3, 7) ? /\A#{REGIONAL_INDICATOR}\z/ : /\A#{REGIONAL_INDICATOR}/
      (char =~ REGIONAL_INDICATOR && cell =~ flag) || (char =~ SKIN_TONE && cell =~ SKIN_TONE_BASE) ||
        (char =~ SKIN_TONE_BASE && cell =~ /\A#{SKIN_TONE}\z/) ||
        (char =~ HANGUL_VOWEL && cell =~ /#{HANGUL_INITIAL}\z/) ||
        (char =~ HANGUL_FINAL && cell =~ /#{HANGUL_VOWEL}\z/)
    elsif tmux_at_least?(version, 3, 4)
      (char =~ REGIONAL_INDICATOR || char =~ SKIN_TONE) && !cell.ascii_only?
    end
  end

  def self.cells(version, text, zero_width = {})
    text.each_char.each_with_object([]) do |char, cells|
      if !cells.empty? && joins?(version, cells.last, char, zero_width)
        cells.last << char
      else
        cells << char.dup
      end
    end
  end

  def self.commands(version, jump_to, screen_chars, scroll_position, zero_width = {})
    commands = [['top-line']]
    commands << ['-N', scroll_position.to_s, 'scroll-up'] << ['top-line'] if scroll_position > 0
    return commands if jump_to == 0

    rows = screen_chars[0...jump_to].split("\n", -1)
    row = rows.size - 1
    if row > 0 && rows.first.empty?
      commands << ['begin-selection'] << ['rectangle-toggle'] << ['-N', row.to_s, 'cursor-down'] <<
        ['rectangle-toggle'] << ['clear-selection']
    elsif row > 0
      commands << ['-N', row.to_s, 'cursor-down']
    end
    before = cells(version, rows.last, zero_width)
    return commands if before.empty?

    target = cells(version, screen_chars[jump_to..-1][/\A.*/], zero_width).first
    if target.size == 1 && (target.ascii_only? || tmux_at_least?(version, 3, 2))
      count = before.drop(1).count(target) + 1
      commands << ['-N', count.to_s, 'jump-forward', target == ';' ? '\;' : target]
    else
      commands << ['-N', before.size.to_s, 'cursor-right']
    end
  end
end
