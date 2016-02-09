# coding: utf-8
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

    # Six cases:
    # #                                                                 Symbol  Gray?  Action
    # 1 - Only Faces selected, none with attribute                       blank   no     set
    # 2 - Only Faces selected, some with attribute                       -       no     clear
    # 3 - Only Faces selected, all  with attribute                       /       no     clear
    # 4 - Selection includes non-Faces, no   Faces with attribute        blank   yes    none
    # 5 - Selection includes non-Faces, some Faces with attribute        -       no     clear
    # 6 - Selection includes non-Faces, all  Faces with attribute        -       no     clear

    #
    # Determine which of the above cases we're in.
    #
    # This is potentially expensive, and it's called twice per context menu entry (for the text and
    # for validation) multiplied by (currently) 5 attributes.
    # And again if a context menu entry is selected. So stop recursing as soon as we have enough info.
    def self.XPlaneAttrState(attr, entities)
      someactive = nil
      someinactive = nil
      somenonface = nil
      entities.each do |ent|
        if ent.is_a?(Sketchup::Face)
          if ent.get_attribute(ATTR_DICT, attr) == 1
            someactive = true
          else
            someinactive = true
          end
        elsif !ent.is_a?(Sketchup::Edge)	# ignore Edges
          somenonface = true
        end
      end

      return someactive, someinactive, somenonface if someactive && someinactive

      entities.each do |ent|
        if ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
          active, inactive, nonface = XPlaneAttrState(attr, ent.definition.entities)
          someactive |= active
          someinactive |= inactive
          break if someactive && someinactive
        end
      end

      return someactive, someinactive, somenonface

    end

    # Recursively clear
    def self.XPlaneClearAttr(attr, entities)
      entities.each do |ent|
        if ent.is_a?(Sketchup::Face)
          # Deleting the Attribute (or the dictionary) is potentially buggy, at least in SketchUp 2015 & 2016.
          # May be this issue: http://forums.sketchup.com/t/funny-behavior-of-delete-attribute/12614/8
          ent.set_attribute(ATTR_DICT, attr, 0) if ent.get_attribute(ATTR_DICT, attr, 0) != 0
        elsif ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
          XPlaneClearAttr(attr, ent.definition.entities)
        end
      end
    end

    # Set or clear the attribute
    def self.XPlaneToggleAttr(attr, name)
      model = Sketchup.active_model
      ss = model.selection
      someactive, someinactive, somenonface = XPlaneAttrState(attr, ss)

      model.start_operation(L10N.t(name), true, false, false)
      if someactive	# clearing - recursive
        XPlaneClearAttr(attr, ss)
      else		# setting - not recursive
        ss.each do |ent|
          if ent.is_a?(Sketchup::Face)
            if attr==ATTR_HARD_NAME
              ent.delete_attribute(ATTR_DICT, ATTR_DECK_NAME)	# mutually exclusive
            elsif attr==ATTR_DECK_NAME
              ent.delete_attribute(ATTR_DICT, ATTR_HARD_NAME)	# mutually exclusive
            end
            ent.set_attribute(ATTR_DICT, attr, 1)	# 1 for backwards compatibility
          end
        end
      end
      model.commit_operation
    end

    # SketchUp's Menu API doesn't allow for tri-state menu items, so we fake it up in two parts:
    # - XPlaneValidateAttr is a conventional Menu validator, but just returns MF_GRAYED or not depending on whether we're in case #4
    # - XPlaneTestAttr returns the submenu name with a check mark or dash manually pre-pended

    # Return menu name with check mark pre-prended, or with dash if some elements have the attribute but others don't
    def self.XPlaneTestAttr(attr, name)
      someactive, someinactive, somenonface = XPlaneAttrState(attr, Sketchup.active_model.selection)
      name=L10N.t(name)
      if !someactive				# Case #1 or #4
        return "\xE2\x80\x83 "+name			# U+2003 em space
      elsif !someinactive && !somenonface	# Case #3
        if Object::RUBY_PLATFORM =~ /darwin/i
          return "\xE2\x9C\x93 "+name			# U+2713 check mark
        else
          return "\xE2\x9C\x94\xE2\x80\x8A "+name	# U+2714 heavy check mark & U+2008 hair space
        end
      else
        return "\xE2\x88\x92\xE2\x80\x88 "+name		# U+2212 minus & U+2008 punctuation space
      end
    end

    # Return MF_GRAYED if case #4 - selection includes non-Faces, no Faces with attribute
    def self.XPlaneValidateAttr(attr)
      someactive, someinactive, somenonface = XPlaneAttrState(attr, Sketchup.active_model.selection)
      return somenonface && !someactive ? MF_GRAYED : MF_ENABLED
    end

  end
end
