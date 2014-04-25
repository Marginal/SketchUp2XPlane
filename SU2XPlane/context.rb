#
# X-Plane context menu
#
# Copyright (c) 2006-2013 Jonathan Harris
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#

module Marginal
  module SU2XPlane

    # SketchUp's Menu API doesn't allow for tri-state menu items, so we fake it up in two parts:
    # - XPlaneValidateAttr is a conventional Menu validator, but just returns MF_GRAYED or not depending on whether the selection is valid (i.e. contains faces)
    # - XPlaneTestAttr returns the submenu name with a check mark or dash manually pre-pended

    # Sets the attribute if *any* of the selected Faces don't have it
    def self.XPlaneToggleAttr(attr)
      setting = nil
      ss = Sketchup.active_model.selection
      ss.each do |ent|
        if ent.typename=="Face"
          if ent.get_attribute(ATTR_DICT, attr, 0)==0
            setting=true
            break
          end
        end
      end
      if setting
        Sketchup.active_model.selection.each do |ent|
          if ent.typename=="Face"
            if attr==ATTR_HARD_NAME
              ent.delete_attribute(ATTR_DICT, ATTR_DECK_NAME)	# mutually exclusive
            elsif attr==ATTR_DECK_NAME
              ent.delete_attribute(ATTR_DICT, ATTR_HARD_NAME)	# mutually exclusive
            end
            ent.set_attribute(ATTR_DICT, attr, 1)	# 1 for backwards compatibility
          end
        end
      else	# clearing
        Sketchup.active_model.selection.each do |ent|
          ent.delete_attribute(ATTR_DICT, attr) if ent.typename=="Face"
        end
      end
    end

    # Return menu name with check mark pre-prended, or with dash if some elements have the attribute but others don't
    def self.XPlaneTestAttr(attr, name)
      someactive=nil
      someinactive=nil
      Sketchup.active_model.selection.each do |ent|
        if ent.typename=="Face"
          if ent.get_attribute(ATTR_DICT, attr, 0)==0
            someinactive=true
          else
            someactive=true
          end
        end
      end
      name=L10N.t(name)
      if !someactive && !someinactive
        return "\xE2\x80\x87\xE2\x80\x82"+name	# U+2007 figure space & U+2002 en space
      elsif someactive && someinactive
        return "\xE2\x88\x92 "+name		# U+2212 minus
      elsif someactive
        if Object::RUBY_PLATFORM =~ /darwin/i
          return "\xE2\x9C\x93 "+name		# U+2713 check mark (not supported in Windows UI fonts)
        else
          return "\xE2\x97\x8f "+name		# U+25CF back circle
        end
      else
        return "\xE2\x80\x87\xE2\x80\x82"+name	# U+2007 figure space & U+2002 en space
      end
    end

    # Return MF_GRAYED if any Components/Groups selected (but ignore Edges)
    def self.XPlaneValidateAttr(attr)
      ss = Sketchup.active_model.selection
      return MF_GRAYED if ss.empty?
      ss.each do |ent|
        return MF_GRAYED if (ent.typename!="Face" && ent.typename!="Edge")
      end
      return MF_ENABLED
    end

  end
end
