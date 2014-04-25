require 'sketchup.rb'

module Marginal
  module SU2XPlane

    class L10N

      def self.resource_file(file_name)
        f = File.join(File.dirname(__FILE__), 'Resources', Sketchup.get_locale.downcase.split('-')[0], file_name)
        return f if File.file?(f)
        f = File.join(File.dirname(__FILE__), 'Resources', 'en', file_name)	# Default to english
        return File.file?(f) ? f : nil
      end

      def self.t(string)
        @@table[string] || string
      end

      # load string table. Assumes comments are whole-line, and that text doesn't contain '='.
      @@table={}
      f = self.resource_file('Localizable.strings')
      if f
        File.open(f) do |h|
          h.each do |line|
            line = line.split('//')[0].split('/*')[0]
            tokens = line.strip.split(%r{"\s*=\s*"})
            @@table[tokens[0][1..-1].gsub('\n',"\n")] = tokens[1].split(%r{"\s*;})[0].gsub('\n',"\n") if (tokens.length==2 && tokens[0][0...1]=='"' && tokens[1][-1..-1]==';')
          end
        end
      end

    end

  end
end
