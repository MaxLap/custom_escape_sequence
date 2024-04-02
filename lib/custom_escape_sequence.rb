# frozen_string_literal: true

require_relative "custom_escape_sequence/version"

# Helps processing a string that contains special characters/sequence and has escape sequences to
# also allow the special characters to be used without being special.
# Little lexicon for this gem:
#   Custom sequence: A sequence of characters that mean something special and needs to be handled
#                    together as a unit. Classic examples: "\n" often means a newline character.
#   Escaping sequence: A sequence of characters that precedes a custom sequence (or another
#                      escaping sequence) to indicate that said custom/escaping sequence must
#                      be used as-is. Classic examples: "\\" often means a single blackslash,
#                      and "\\n" often means a backslash and the letter "n".
#   Special sequence: TODO
#
# For example, you could have '%' be a custom characters and use '!' to escape them when needed.
# So doing "hello%" would consider the % to be special in the methods of this function.
# "hello!%" would not have a special %, and in the end would be turned into "hello%"
# "hello!!%" would have special %, and in the end, would be turned into "hello!"
# "hello!! you%" would have a special %, and in the end would be turned into "hello!! you". Since the escape characters
# did not precede the special character (%), they are left as is instead of being halved.
class CustomEscapeSequence
  def initialize(custom_pattern, escape: "\\", default_escape: nil)
    if !escape.is_a?(String) && !default_escape.is_a?(String)
      raise ":escape is not a String, so you must define a default_escape that is a String"
    end

    default_escape ||= escape
    raise "default_escape must be a String, not #{default_escape.inspect}" unless default_escape.is_a?(String)

    @default_escape = default_escape
    @custom_sequence_re = self.class.to_escaped_regex(custom_pattern)
    @escape_sequence_re = self.class.to_escaped_regex(escape)

    raise "default_escape doesn't get matched by the :escape" unless @default_escape.match(@escape_sequence_re)

    @isolate_special_sequences_re = Regexp.new("(" + @escape_sequence_re.source + "*" + @custom_sequence_re.source + ")")
    @isolate_escape_sequences_re = Regexp.new("(" + @escape_sequence_re.source + "*)" + @custom_sequence_re.source)
    @isolate_ending_escape_sequences_re = Regexp.new("(" + @escape_sequence_re.source + "*)$")
  end

  # This is the main way to use CustomEscapeSequence.
  # Returns an array where the even indexes are the raw parts of a string and the odd indexes are single
  # unescaped custom sequences. The returned array always has an odd number of elements.
  # Odd indexed elements may be empty string in the case of consecutive custom sequence or when
  # the string starts or ends with a custom sequence.
  def isolate(string_or_parts)
    parts = isolate_special_sequences(string_or_parts)

    parts = parts.each_slice(2).map do |raw_part, special_sequence|
      parse_special_sequence(raw_part, special_sequence)
    end

    self.class.merge_around_nils(parts.flatten)
  end

  # Split the string on the unescaped custom sequences. Only the raw parts of the string are returned.
  # CustomEscapeSequence.new('%', escape: '!').split("hello%world!%fun!!%stuff! and more!!")
  #    => ["hello", "world%fun!", "stuff! and more!!"]
  def split(string_or_parts)
    result = isolate(string_or_parts)
    result.values_at(*(0...result.size).step(2))
  end

  # Escape the custom sequences in the string.
  # Every special sequence will be escaped, meaning:
  #   every escape sequence in the special sequence gets duplicated
  #   the default_escape is inserted before the custom sequence (even if there were already escape sequences)
  # Note: escape sequences that are not preceding a custom sequence are not affected.
  # The resulting string can be passed to #isolate and there will not be any character isolated.
  # CustomEscapeSequence.new('%', escape: '!').escape("hello%world!%fun!!%stuff! and more!!")
  #    => "hello!%world!!!%fun!!!!!%stuff! and more!!"
  def escape(string_or_parts)
    parts = isolate_special_sequences(string_or_parts)

    parts = parts.each_slice(2).map do |raw_part, special_sequence|
      [raw_part, escape_special_sequence(special_sequence)]
    end

    parts.flatten.join
  end

  # Merges the custom_sequences back into a string. Basically the inverse of isolate.
  # Receives an input like isolate's output. (Array, even index are raw parts, odd are custom_sequences)
  # CustomEscapeSequence.new('%', escape: '!').merge_back(["hello", "%", "world%fun!", "%", "stuff! and more!!"])
  #    => "hello%world!%fun!!%stuff! and more!!"
  def merge_back(string_or_parts)
    return string_or_parts if string_or_parts.is_a? String

    parts = string_or_parts.each_slice(2).map do |raw_part, custom_sequence|
      merge_back_custom_sequence(raw_part, custom_sequence)
    end

    result = self.class.merge_around_nils(parts.flatten)

    return result.first if result.size == 1
    result
  end

  # protected # I hate protected/private, just painful to debug.

  # If passed a string, escapes the special regex characters of it and turn it into a non-capturing group in a regex.
  # If passed a regex, simply puts its source in a non-capturing group in a regex.
  def self.to_escaped_regex(text)
    if text.is_a?(Regexp)
      regex_source = text.source
    elsif text.is_a?(String)
      regex_source = Regexp.escape(text)
    else
      raise "Unsupported type #{text.class}: #{text.inspect}"
    end
    Regexp.new("(?:#{regex_source})")
  end

  def is_custom_sequence_handled? custom_sequence
    @is_custom_sequence_re ||= Regexp.new("^" + @custom_sequence_re.source + "$")
    !custom_sequence[@is_custom_sequence_re].nil?
  end

  # Split the string on the special sequences (not on the custom sequence, that's #isolate's job).
  # So the special sequences are on the odd indexes and the raw parts are on the even indexes.
  def isolate_special_sequences(string_or_parts)
    parts = if string_or_parts.is_a? String
      [string_or_parts]
    else
      string_or_parts
    end

    parts = parts.each_slice(2).map do |raw_part, other_custom_sequence|
      result = raw_part.split(@isolate_special_sequences_re, -1)
      [result, other_custom_sequence]
    end

    parts.flatten
  end

  # Split a special sequence in two:
  # returns an array containing 2 values:
  #   * An Array containing each escapes sequences individually
  #   * The custom sequence that got matched
  # CustomEscapeSequence.new('%', escape: '!').extract_from_special_sequence('!!!%')
  #    => [['!', '!', '!'], '%']
  def extract_from_special_sequence(special_sequence)
    # Using #match#captures to only get the captured escapes without the custom_sequence which was also matched.
    escapes_string = special_sequence.match(@isolate_escape_sequences_re).captures.join
    escapes_array = split_escape_sequences(escapes_string)
    specials_string = special_sequence[escapes_string.size..]
    [escapes_array, specials_string]
  end

  # Returns an array of each escape sequence individually.
  def split_escape_sequences(escapes_string)
    escapes_string.scan(@escape_sequence_re)
  end

  # Parses a special sequence.
  # Needs to receives the previous part of your string, since extra escapes and escaped custom_sequences will be added
  # to it and returned too.
  # This returns [previous_raw_part, custom_sequence_or_nil]
  # This is what happens:
  #   Every odd-indexed escape sequences are appended to the returned previous_raw_part
  #   If there was an odd number of escape sequences, then
  #       the custom sequence is also appended to the returned previous_raw_part
  #       custom sequence returned is nil, to indicate that there were no unescaped custom sequence in this special sequence.
  #   If there was an even number of escape sequences, then
  #       the custom sequence is not escaped and it will be returned as custom sequence.
  def parse_special_sequence(previous_raw_part, special_sequence)
    return [previous_raw_part, special_sequence] if special_sequence.nil?

    escapes_array, custom_sequence = extract_from_special_sequence(special_sequence)

    previous_raw_part += escapes_array.values_at(*(1...escapes_array.size).step(2)).join("")
    if escapes_array.size.odd?
      previous_raw_part += custom_sequence
      custom_sequence = nil
    end

    [previous_raw_part, custom_sequence]
  end

  # Escapes a special sequence, meaning:
  #   every escape sequence gets duplicated
  #   the default_escape is inserted before the custom sequence
  def escape_special_sequence(special_sequence)
    return if special_sequence.nil?
    escapes_array, custom_sequence = extract_from_special_sequence(special_sequence)

    escapes_array.map { |e| e + e }.join + @default_escape + custom_sequence
  end

  # Merges a custom sequence at the end of previous_raw_part, handling escapes correctly. Basically the inverse of isolate.
  # This is what happens:
  #   if custom_sequence isn't handled by this instance, everything is returned as is [previous_raw_part, custom_sequence]
  #
  #   if previous_raw_part ends with an escape sequence or more, they will all be duplicated.
  #   the custom sequence will be appended added at the end of previous_raw_part.
  #   return [new_previous_raw_part, nil]
  # Calling isolate on the resulting previous_raw_part (first returned value) will give back the same components as what
  # was passed to this function (unless the previous_raw_part contained other custom_sequences that were not escaped, as isolate will split them all up).
  def merge_back_custom_sequence(previous_raw_part, custom_sequence)
    return [previous_raw_part, custom_sequence] if custom_sequence.nil?
    return [previous_raw_part, custom_sequence] unless is_custom_sequence_handled?(custom_sequence)

    ending_escapes_string = previous_raw_part[@isolate_ending_escape_sequences_re]
    return [previous_raw_part + custom_sequence, nil] unless ending_escapes_string

    previous_raw_part = previous_raw_part[0...(previous_raw_part.size - ending_escapes_string.size)]
    ending_escapes_array = split_escape_sequences(ending_escapes_string)

    previous_raw_part = previous_raw_part + ending_escapes_array.map { |s| s + s }.join + custom_sequence
    [previous_raw_part, nil]
  end

  # Receives a list of strings or nils. Nils get removed and the string that follows them appended to the one before them.
  # Returns a new list.
  # We have this: ["hello", "%", "world%", nil, "fun!", "%", "stuff! and more!!"]
  # We want this: ["hello", "%", "world%fun!", "%", "stuff! and more!!"]
  def self.merge_around_nils(parts)
    result = []
    merge_next = false

    parts.each do |s|
      if s.nil?
        merge_next = true
      elsif merge_next
        result[-1] += s
        merge_next = false
      else
        result << s
      end
    end

    result
  end
end
