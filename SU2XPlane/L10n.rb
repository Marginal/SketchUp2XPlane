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

  @@table={}
  f = self.resource_file('Localizable.strings')
  if f
    File.open(f) do |h|
      h.each do |line|
        tokens=line.strip.split('=')
        @@table[tokens[0]]=tokens[1] if tokens.length==2
      end
    end
  end

end
