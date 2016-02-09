require 'sketchup.rb'
require_all(File.dirname(__FILE__))

module Marginal
  module SU2XPlane

    # Add UI
    if !file_loaded?(__FILE__)

      Sketchup.register_importer(XPlaneImporter.new)
      UI.menu("File").add_item(L10N.t('Export X-Plane Object')) { XPlaneExport() }
      UI.menu("Tools").add_item(L10N.t('Highlight Untextured')) { XPlaneHighlight() }
      UI.menu("Tools").add_item(L10N.t('Reload Textures')) { XPlaneRefreshMaterials() }

      UI.add_context_menu_handler do |menu|
        if !Sketchup.active_model.selection.empty?
          menu.add_separator
          submenu = menu.add_submenu "X-Plane"
          anim = submenu.add_item("\xE2\x80\x83 "+L10N.t('Animation...')) { XPlaneMakeAnimation() }	# U+2003 em space
          poly = submenu.add_item(XPlaneTestAttr(ATTR_POLY_NAME, 'Ground')) { XPlaneToggleAttr(ATTR_POLY_NAME, 'Ground') }
          submenu.set_validation_proc(poly) { XPlaneValidateAttr(ATTR_POLY_NAME) }
          hard = submenu.add_item(XPlaneTestAttr(ATTR_HARD_NAME, 'Hard')) { XPlaneToggleAttr(ATTR_HARD_NAME, 'Hard') }
          submenu.set_validation_proc(hard) { XPlaneValidateAttr(ATTR_HARD_NAME) }
          deck = submenu.add_item(XPlaneTestAttr(ATTR_DECK_NAME, 'Hard Deck')) { XPlaneToggleAttr(ATTR_DECK_NAME, 'HardDeck') }
          submenu.set_validation_proc(deck) { XPlaneValidateAttr(ATTR_DECK_NAME) }
          shiny = submenu.add_item(XPlaneTestAttr(ATTR_SHINY_NAME, 'Shiny')) { XPlaneToggleAttr(ATTR_SHINY_NAME, 'Shiny') }
          submenu.set_validation_proc(shiny) { XPlaneValidateAttr(ATTR_SHINY_NAME) }
          alpha = submenu.add_item(XPlaneTestAttr(ATTR_ALPHA_NAME, 'Translucent')) { XPlaneToggleAttr(ATTR_ALPHA_NAME, 'Translucent') }
          submenu.set_validation_proc(alpha) { XPlaneValidateAttr(ATTR_ALPHA_NAME) }
          invis = submenu.add_item(XPlaneTestAttr(ATTR_INVISIBLE_NAME, 'Invisible')) { XPlaneToggleAttr(ATTR_INVISIBLE_NAME, 'Invisible') }
          submenu.set_validation_proc(invis) { XPlaneValidateAttr(ATTR_INVISIBLE_NAME) }
        end
      end

      help = L10N.resource_file('SU2XPlane.html')
      if help
        UI.menu("Help").add_item("X-Plane") { UI.openURL("file://" + help) }
      else
        UI.menu("Help").add_item("X-Plane") { UI.messagebox('X-Plane help files are missing!') }
      end

    end

    file_loaded(__FILE__)
  end
end
