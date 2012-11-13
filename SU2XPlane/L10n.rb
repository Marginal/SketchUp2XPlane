class XPL10n

  @@table={}
  f=Sketchup.find_support_file('L10n_'+Sketchup.get_locale.upcase.split('-')[0]+'.txt', 'Plugins/SU2XPlane')
  if f
    File.open(f) do |h|
      h.each do |line|
        tokens=line.strip.split('=')
        @@table[tokens[0]]=tokens[1] if tokens.length==2
      end
    end
  end

  def self.t(string)
    @@table[string] || string
  end

end
