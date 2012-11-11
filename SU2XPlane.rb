#
# X-Plane importer/exporter for SketchUp
#
# Copyright (c) 2006-2012 Jonathan Harris
# 
# Mail: <x-plane@marginal.org.uk>
# Web:  http://marginal.org.uk/x-planescenery/
#
# This software is licensed under a Creative Commons
#   Attribution-Noncommercial-ShareAlike license:
#   http://creativecommons.org/licenses/by-nc-sa/3.0/
#

require 'sketchup.rb'
require 'extensions.rb'
require_all Sketchup.find_support_file('SU2XPlane', 'Plugins')

# Constants
module SU2XPlane
  Version="1.50"

  # X-Plane attributes
  ATTR_DICT="X-Plane"
  ATTR_HARD_NAME="poly"	# incorrect dictionary key not fixed for compatibility
  ATTR_POLY_NAME="hard"	# ditto
  ATTR_ALPHA_NAME="alpha"

  # Animation attributes. Must be consistent with anim.js
  ANIM_DATAREF='dataref'
  ANIM_INDEX='index'
  ANIM_FRAME_='frame_'
  ANIM_MATRIX_='matrix_'
  ANIM_LOOP='loop'
  ANIM_HS_='hs_'
  ANIM_VAL_HIDE='hide'
  ANIM_VAL_SHOW='show'
  ANIM_HS_HIDESHOW='_hideshow'
  ANIM_HS_DATAREF='_dataref'
  ANIM_HS_INDEX='_index'
  ANIM_HS_FROM='_from'
  ANIM_HS_TO='_to'

  # Lights that we understand
  LIGHTNAMED=['LIGHT_NAMED', 'LIGHT_PARAM']
  LIGHTCUSTOM=['LIGHT_CUSTOM', 'LIGHT_SPILL_CUSTOM', 'smoke_black', 'smoke_white']

  # Output precision
  P_V=4		# Vertex
  P_N=3		# Normal
  P_UV=4	# UV
  P_A=2		# Animation angle

end


extension=SketchupExtension.new 'SketchUp2XPlane', 'SU2XPlane.rb'
extension.description='Provides ability to import and export models in X-Plane v8/v9/v10 .obj format. See Help->X-Plane for instructions.'
extension.version=SU2XPlane::Version
extension.creator='Jonathan Harris'
extension.copyright='2007-2012'
Sketchup.register_extension extension, true

if !file_loaded?("SU2XPlane.rb")
  begin
    XPlaneAppObserver.new.onOpenModel(Sketchup.active_model)	# Not sent by SketchUp on initial model - see https://developers.google.com/sketchup/docs/ourdoc/appobserver#onOpenModel
    Sketchup.register_importer(XPlaneImporter.new)
    UI.menu("File").add_item(XPL10n.t('Export X-Plane Object')) { XPlaneExport() }
    UI.menu("Tools").add_item(XPL10n.t('Highlight Untextured')) { XPlaneHighlight() }

    UI.add_context_menu_handler do |menu|
      if !Sketchup.active_model.selection.empty?
        menu.add_separator
        submenu = menu.add_submenu "X-Plane"
        hard=submenu.add_item(XPL10n.t('Hard'))         { XPlaneToggleAttr(SU2XPlane::ATTR_HARD_NAME) }
        submenu.set_validation_proc(hard)               { XPlaneValidateAttr(SU2XPlane::ATTR_HARD_NAME) }
        poly=submenu.add_item(XPL10n.t('Ground'))       { XPlaneToggleAttr(SU2XPlane::ATTR_POLY_NAME) }
        submenu.set_validation_proc(poly)               { XPlaneValidateAttr(SU2XPlane::ATTR_POLY_NAME) }
        alpha=submenu.add_item(XPL10n.t('Alpha'))       { XPlaneToggleAttr(SU2XPlane::ATTR_ALPHA_NAME) }
        submenu.set_validation_proc(alpha)              { XPlaneValidateAttr(SU2XPlane::ATTR_ALPHA_NAME) }
        anim=submenu.add_item(XPL10n.t('Animation...')) { XPlaneMakeAnimation() }
      end
    end
  rescue NameError => e
    puts "Error: #{e.inspect}", e.backtrace	# Report to console
    UI.menu("File").add_item('SU2XPlane plugin folder is missing!') {}
  end

  help=Dir.glob(File.join(Sketchup.find_support_file("Plugins"), '*-SU2XPlane_'+Sketchup.get_locale.upcase.split('-')[0]+'.html'))
  if help.empty?
    help=Dir.glob(File.join(Sketchup.find_support_file("Plugins"), '*-SU2XPlane.html'))
  end
  if help.first
    UI.menu("Help").add_item("X-Plane") { UI.openURL("file://" + help.first) }
  else
    UI.menu("Help").add_item("X-Plane") { UI.messagebox('X-Plane help files are missing!') }
  end
  file_loaded("SU2XPlane.rb")
end

#Sketchup.send_action "showRubyPanel:"
