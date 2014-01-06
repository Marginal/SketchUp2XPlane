require 'sketchup.rb'

class XPL10n

  def self.resource_file(file_name)
    f = Sketchup.find_support_file(file_name, "Plugins/SU2XPlane/Resources/#{Sketchup.get_locale.downcase.split('-')[0]}")
    if f
      return f
    end
    # Default to english
    f = Sketchup.find_support_file(file_name, "Plugins/SU2XPlane/Resources/en")
    return f || nil
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
        @@table[tokens[0][1..-1]] = tokens[1].split(%r{"\s*;})[0] if (tokens.length==2 && tokens[0][0...1]=='"' && tokens[1][-1..-1]==';')
      end
    end
  end

end
