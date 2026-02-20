# frozen_string_literal: true

# This file ports Homebrew version detection and comparison behavior for browser use.
# Derived from Homebrew's `Library/Homebrew/version.rb` and `version/parser.rb`.
# Homebrew is BSD-2-Clause licensed: https://github.com/Homebrew/brew/blob/master/LICENSE.txt

require "pathname"
require "uri"

class Version
  include Comparable

  class Parser
    def parse(_spec)
      raise NotImplementedError
    end
  end

  class RegexParser < Parser
    def initialize(regex, &block)
      @regex = regex
      @block = block
    end

    def parse(spec)
      match = @regex.match(self.class.process_spec(spec))
      return nil unless match

      version = match.captures.first
      return nil if version.nil? || version.empty?

      @block ? @block.call(version) : version
    end

    def self.process_spec(_spec)
      raise NotImplementedError
    end
  end

  class UrlParser < RegexParser
    def self.process_spec(spec)
      spec.to_s
    end
  end

  class StemParser < RegexParser
    SOURCEFORGE_DOWNLOAD_REGEX = %r{(?:sourceforge\.net|sf\.net)/.*/download$}
    NO_FILE_EXTENSION_REGEX = /\.[^a-zA-Z]+$/

    def self.process_spec(spec)
      spec_s = spec.to_s
      basename = basename_without_query(spec_s)

      return basename if spec_s.end_with?("/")

      if spec_s.match?(SOURCEFORGE_DOWNLOAD_REGEX)
        return stem(dirname_basename(spec_s))
      end

      return basename if spec_s.match?(NO_FILE_EXTENSION_REGEX)

      stem(basename)
    end

    def self.basename_without_query(spec_s)
      File.basename(strip_query(spec_s))
    end

    def self.dirname_basename(spec_s)
      File.basename(File.dirname(strip_query(spec_s)))
    end

    def self.strip_query(spec_s)
      spec_s.sub(/[?#].*\z/, "")
    end

    def self.stem(path)
      basename = File.basename(path)
      ext = homebrew_extname(basename)
      return basename if ext.empty?

      File.basename(basename, ext)
    end

    def self.homebrew_extname(basename)
      archive_ext = basename[/(\.(tar|cpio|pax)\.(gz|bz2|lz|xz|zst|Z))\z/, 1]
      return archive_ext if archive_ext

      return "" if basename.match?(/\b\d+\.\d+[^.]*\z/) && !basename.end_with?(".7z")

      File.extname(basename)
    end
  end

  class Token
    include Comparable

    attr_reader :value

    def self.create(val)
      case val
      when /\A#{AlphaToken::PATTERN}\z/o then AlphaToken
      when /\A#{BetaToken::PATTERN}\z/o then BetaToken
      when /\A#{RCToken::PATTERN}\z/o then RCToken
      when /\A#{PreToken::PATTERN}\z/o then PreToken
      when /\A#{PatchToken::PATTERN}\z/o then PatchToken
      when /\A#{PostToken::PATTERN}\z/o then PostToken
      when /\A#{NumericToken::PATTERN}\z/o then NumericToken
      when /\A#{StringToken::PATTERN}\z/o then StringToken
      else raise "Cannot find a matching token pattern"
      end.new(val)
    end

    def self.from(val)
      return NULL_TOKEN if val.nil? || (val.respond_to?(:null?) && val.null?)

      case val
      when Token then val
      when String then Token.create(val)
      when Integer then Token.create(val.to_s)
      end
    end

    def initialize(value)
      @value = value
    end

    def <=>(_other)
      raise NotImplementedError
    end

    def inspect
      "#<#{self.class.name} #{value.inspect}>"
    end

    def hash
      value.hash
    end

    def to_f
      value.to_f
    end

    def to_i
      value.to_i
    end

    def to_str
      value.to_s
    end

    def to_s
      to_str
    end

    def numeric?
      false
    end

    def null?
      false
    end

    def blank?
      null?
    end
  end

  class NullToken < Token
    def initialize
      super(nil)
    end

    def <=>(other)
      other = Token.from(other)
      return nil unless other

      case other
      when NullToken
        0
      when NumericToken
        other.value.zero? ? 0 : -1
      when AlphaToken, BetaToken, PreToken, RCToken
        1
      else
        -1
      end
    end

    def null?
      true
    end

    def blank?
      true
    end

    def inspect
      "#<#{self.class.name}>"
    end
  end
  private_constant :NullToken

  NULL_TOKEN = NullToken.new.freeze

  class StringToken < Token
    PATTERN = /[a-z]+/i

    def initialize(value)
      super(value.to_s)
    end

    def <=>(other)
      other = Token.from(other)
      return nil unless other

      case other
      when StringToken
        value <=> other.value
      when NumericToken, NullToken
        -(other <=> self)
      end
    end
  end

  class NumericToken < Token
    PATTERN = /[0-9]+/i

    def initialize(value)
      super(value.to_i)
    end

    def <=>(other)
      other = Token.from(other)
      return nil unless other

      case other
      when NumericToken
        value <=> other.value
      when StringToken
        1
      when NullToken
        -(other <=> self)
      end
    end

    def numeric?
      true
    end
  end

  class CompositeToken < StringToken
    def rev
      value[/[0-9]+/].to_i
    end
  end

  class AlphaToken < CompositeToken
    PATTERN = /alpha[0-9]*|a[0-9]+/i

    def <=>(other)
      other = Token.from(other)
      return nil unless other

      case other
      when AlphaToken
        rev <=> other.rev
      when BetaToken, RCToken, PreToken, PatchToken, PostToken
        -1
      else
        super
      end
    end
  end

  class BetaToken < CompositeToken
    PATTERN = /beta[0-9]*|b[0-9]+/i

    def <=>(other)
      other = Token.from(other)
      return nil unless other

      case other
      when BetaToken
        rev <=> other.rev
      when AlphaToken
        1
      when PreToken, RCToken, PatchToken, PostToken
        -1
      else
        super
      end
    end
  end

  class PreToken < CompositeToken
    PATTERN = /pre[0-9]*/i

    def <=>(other)
      other = Token.from(other)
      return nil unless other

      case other
      when PreToken
        rev <=> other.rev
      when AlphaToken, BetaToken
        1
      when RCToken, PatchToken, PostToken
        -1
      else
        super
      end
    end
  end

  class RCToken < CompositeToken
    PATTERN = /rc[0-9]*/i

    def <=>(other)
      other = Token.from(other)
      return nil unless other

      case other
      when RCToken
        rev <=> other.rev
      when AlphaToken, BetaToken, PreToken
        1
      when PatchToken, PostToken
        -1
      else
        super
      end
    end
  end

  class PatchToken < CompositeToken
    PATTERN = /p[0-9]*/i

    def <=>(other)
      other = Token.from(other)
      return nil unless other

      case other
      when PatchToken
        rev <=> other.rev
      when AlphaToken, BetaToken, RCToken, PreToken
        1
      else
        super
      end
    end
  end

  class PostToken < CompositeToken
    PATTERN = /.post[0-9]+/i

    def <=>(other)
      other = Token.from(other)
      return nil unless other

      case other
      when PostToken
        rev <=> other.rev
      when AlphaToken, BetaToken, RCToken, PreToken
        1
      else
        super
      end
    end
  end

  SCAN_PATTERN = Regexp.union(
    AlphaToken::PATTERN,
    BetaToken::PATTERN,
    PreToken::PATTERN,
    RCToken::PATTERN,
    PatchToken::PATTERN,
    PostToken::PATTERN,
    NumericToken::PATTERN,
    StringToken::PATTERN
  ).freeze

  NUMERIC_WITH_OPTIONAL_DOTS = /(?:\d+(?:\.\d+)*)/.source.freeze
  NUMERIC_WITH_DOTS = /(?:\d+(?:\.\d+)+)/.source.freeze
  MINOR_OR_PATCH = /(?:\d+(?:\.\d+){1,2})/.source.freeze
  CONTENT_SUFFIX = /(?:[._-](?i:bin|dist|stable|src|sources?|final|full))/.source.freeze
  PRERELEASE_SUFFIX = /(?:[._-]?(?i:alpha|beta|pre|rc)\.?\d{,2})/.source.freeze

  VERSION_PARSERS = [
    StemParser.new(/(?:^|[._-]?)v?(\d{4}-\d{2}-\d{2})/),
    UrlParser.new(%r{github\.com/.+/(?:zip|tar)ball/(?:v|\w+-)?((?:\d+[._-])+\d*)$}),
    UrlParser.new(/[_-]([Rr]\d+[AaBb]\d*(?:-\d+)?)/),
    StemParser.new(/((?:\d+_)+\d+)$/) { |s| s.tr("_", ".") },
    StemParser.new(/[_-](#{NUMERIC_WITH_DOTS}-(?:p|P|rc|RC)?\d+)#{CONTENT_SUFFIX}?$/),
    StemParser.new(/^v?(#{NUMERIC_WITH_DOTS}(?:-#{NUMERIC_WITH_OPTIONAL_DOTS})+)/),
    UrlParser.new(/[-v](#{NUMERIC_WITH_OPTIONAL_DOTS})$/),
    StemParser.new(/-(\d+-\d+)/),
    StemParser.new(/-(#{NUMERIC_WITH_OPTIONAL_DOTS})$/),
    StemParser.new(/-(#{NUMERIC_WITH_OPTIONAL_DOTS}(.post\d+)?)$/),
    StemParser.new(/-(#{NUMERIC_WITH_OPTIONAL_DOTS}(?:[abc]|rc|RC)\d*)$/),
    StemParser.new(/-(#{NUMERIC_WITH_OPTIONAL_DOTS}-(?:alpha|beta|rc)\d*)$/),
    StemParser.new(/-(#{MINOR_OR_PATCH})-w(?:in)?(?:32|64)$/),
    StemParser.new(/\.(#{MINOR_OR_PATCH})\+opam$/),
    StemParser.new(/[_-](#{MINOR_OR_PATCH}(?:-\d+)?)[._-](?:i[36]86|x86|x64(?:[_-](?:32|64))?)$/),
    StemParser.new(/[-.vV]?(#{NUMERIC_WITH_DOTS}#{PRERELEASE_SUFFIX})/),
    StemParser.new(/(#{NUMERIC_WITH_OPTIONAL_DOTS})$/),
    StemParser.new(/[-vV](#{NUMERIC_WITH_DOTS}[abc]?)#{CONTENT_SUFFIX}$/),
    StemParser.new(/-(#{NUMERIC_WITH_DOTS})-/),
    StemParser.new(/_(#{NUMERIC_WITH_OPTIONAL_DOTS}[abc]?)\.orig$/),
    StemParser.new(/-v?(\d[^-]+)/),
    StemParser.new(/_v?(\d[^_]+)/),
    UrlParser.new(%r{/(?:[rvV]_?)?(\d+\.\d+(?:\.\d+){,2})}),
    StemParser.new(/\.v(\d+[a-z]?)/),
    UrlParser.new(/[-.vV]?(#{NUMERIC_WITH_DOTS}#{PRERELEASE_SUFFIX}?)/)
  ].freeze

  def self.formula_optionally_versioned_regex(name, full: true)
    /#{"^" if full}#{Regexp.escape(name.to_s)}(@\d[\d.]*)?#{"$" if full}/
  end

  def self.detect(url, **specs)
    parse(specs.fetch(:tag, url), detected_from_url: true)
  end

  def self.parse(spec, detected_from_url: false)
    raw_spec = spec.to_s
    if detected_from_url
      begin
        raw_spec = URI.decode_www_form_component(raw_spec)
      rescue ArgumentError
        raw_spec = spec.to_s
      end
    end

    parsed_spec = Pathname.new(raw_spec)
    VERSION_PARSERS.each do |parser|
      version = parser.parse(parsed_spec)
      return new(version, detected_from_url: detected_from_url) if version && !version.empty?
    end

    NULL
  end

  HEAD_VERSION_REGEX = /\AHEAD(?:-(?<commit>.*))?\Z/

  def initialize(val, detected_from_url: false)
    version = val.to_str
    raise ArgumentError, "Version must not be empty" if version.strip.empty?

    @version = version
    @detected_from_url = detected_from_url
  end

  def detected_from_url?
    @detected_from_url
  end

  def head?
    !!(@version&.match?(HEAD_VERSION_REGEX))
  end

  def commit
    @version&.match(HEAD_VERSION_REGEX)&.[](:commit)
  end

  def update_commit(commit)
    raise ArgumentError, "Cannot update commit for non-HEAD version." unless head?

    @version = commit ? "HEAD-#{commit}" : "HEAD"
  end

  def null?
    @version.nil?
  end

  def compare(comparator, other)
    case comparator
    when ">=" then self >= other
    when ">" then self > other
    when "<" then self < other
    when "<=" then self <= other
    when "==" then self == other
    when "!=" then self != other
    else raise ArgumentError, "Unknown comparator: #{comparator}"
    end
  end

  def <=>(other)
    other = case other
    when String
      if other.empty?
        return nil if null?

        return 1
      end

      Version.new(other)
    when Integer
      Version.new(other.to_s)
    when Token
      if other.null?
        return nil if null?

        return 1
      end

      Version.new(other.to_s)
    when Version
      if other.null?
        return nil if null?

        return 1
      end

      other
    when nil
      return 1
    else
      return nil
    end

    return -1 if null?
    return 0 if @version == other.version
    return 1 if head? && !other.head?
    return -1 if !head? && other.head?
    return 0 if head? && other.head?

    ltokens = tokens
    rtokens = other.tokens
    max_len = [ltokens.length, rtokens.length].max
    l = 0
    r = 0

    while l < max_len
      a = ltokens[l] || NULL_TOKEN
      b = rtokens[r] || NULL_TOKEN

      if a == b
        l += 1
        r += 1
        next
      elsif a.numeric? && !b.numeric?
        return 1 if a > NULL_TOKEN

        l += 1
      elsif !a.numeric? && b.numeric?
        return -1 if b > NULL_TOKEN

        r += 1
      else
        return (a <=> b)
      end
    end

    0
  end

  def ==(other)
    return false if null?

    super
  end
  alias eql? ==

  def major
    return NULL_TOKEN if null?

    tokens.first
  end

  def minor
    return NULL_TOKEN if null?

    tokens[1] || NULL_TOKEN
  end

  def patch
    return NULL_TOKEN if null?

    tokens[2] || NULL_TOKEN
  end

  def major_minor
    return self if null?

    values = tokens[0..1]
    values.empty? ? NULL : self.class.new(values.join("."))
  end

  def major_minor_patch
    return self if null?

    values = tokens[0..2]
    values.empty? ? NULL : self.class.new(values.join("."))
  end

  def hash
    @version.hash
  end

  def to_f
    return Float::NAN if null?

    @version.to_f
  end

  def to_i
    @version.to_i
  end

  def to_str
    raise NoMethodError, "undefined method `to_str` for #{self.class}:NULL" if null?

    @version.to_str
  end

  def to_s
    @version.to_s
  end

  def inspect
    return "#<Version::NULL>" if null?

    "#<Version #{self}>"
  end

  def freeze
    tokens
    super
  end

  protected

  attr_reader :version

  def tokens
    @tokens ||= begin
      if @version.nil?
        []
      else
        @version.scan(SCAN_PATTERN).map { |token| Token.create(token) }
      end
    end
  end

  NULL = Version.new("NULL").tap { |v| v.instance_variable_set(:@version, nil) }.freeze
end

module BrewVersionBridge
  module_function

  def detect_version(url)
    version = Version.detect(url.to_s)
    version.null? ? nil : version.to_s
  rescue StandardError
    nil
  end

  def parse_version(version_str)
    return nil if version_str.nil? || version_str.strip.empty?

    version = Version.parse(version_str.to_s, detected_from_url: false)
    version.null? ? nil : version.to_s
  rescue StandardError
    nil
  end

  def compare_versions(left, right)
    return nil if left.nil? || right.nil?

    Version.new(left.to_s) <=> Version.new(right.to_s)
  rescue StandardError
    nil
  end
end

begin
  require "js"

  bridge = JS.global[:Object].new
  bridge[:detectVersion] = proc { |url| BrewVersionBridge.detect_version(url.to_s) }
  bridge[:parseVersion] = proc { |version| BrewVersionBridge.parse_version(version.to_s) }
  bridge[:compareVersions] = proc { |left, right| BrewVersionBridge.compare_versions(left.to_s, right.to_s) }
  JS.global[:BrewVersionCheck] = bridge
rescue LoadError
  # Running outside ruby.wasm; bridge is only needed in browser.
end
