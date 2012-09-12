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
  Version="1.44"

  # X-Plane attributes
  ATTR_DICT="X-Plane"
  ATTR_HARD=1
  ATTR_HARD_NAME="poly"	# incorrect dictionary key not fixed for compatibility
  ATTR_POLY=2
  ATTR_POLY_NAME="hard"	# ditto
  ATTR_ALPHA=4
  ATTR_ALPHA_NAME="alpha"
  ATTR_SEQ=[
            ATTR_POLY, ATTR_POLY|ATTR_HARD,
            ATTR_POLY|ATTR_ALPHA, ATTR_POLY|ATTR_ALPHA|ATTR_HARD,
            0, ATTR_HARD,
            ATTR_ALPHA, ATTR_ALPHA|ATTR_HARD]

  # Lights that we understand
  LIGHTNAMED=['LIGHT_NAMED', 'LIGHT_PARAM']
  LIGHTCUSTOM=['LIGHT_CUSTOM', 'LIGHT_SPILL_CUSTOM', 'smoke_black', 'smoke_white']
end


extension=SketchupExtension.new 'SketchUp2XPlane', 'SU2XPlane.rb'
extension.description='Provides ability to import and export models in X-Plane v8/v9/v10 .obj format. See Help->X-Plane for instructions.'
extension.version=SU2XPlane::Version
extension.creator='Jonathan Harris'
extension.copyright='2007-2012'
Sketchup.register_extension extension, true

if !file_loaded?("SU2XPlane.rb")
  Sketchup.register_importer(XPlaneImporter.new)
  UI.menu("File").add_item("Export X-Plane Object") { XPlaneExport() }
  UI.menu("Tools").add_item("Highlight Untextured") { XPlaneHighlight() }

  UI.add_context_menu_handler do |menu|
    menu.add_separator
    submenu = menu.add_submenu "X-Plane"
    hard=submenu.add_item("Hard")      { XPlaneToggleAttr(SU2XPlane::ATTR_HARD_NAME) }
    submenu.set_validation_proc(hard)  { XPlaneValidateAttr(SU2XPlane::ATTR_HARD_NAME) }
    poly=submenu.add_item("Ground")    { XPlaneToggleAttr(SU2XPlane::ATTR_POLY_NAME) }
    submenu.set_validation_proc(poly)  { XPlaneValidateAttr(SU2XPlane::ATTR_POLY_NAME) }
    alpha=submenu.add_item("Alpha")    { XPlaneToggleAttr(SU2XPlane::ATTR_ALPHA_NAME) }
    submenu.set_validation_proc(alpha) { XPlaneValidateAttr(SU2XPlane::ATTR_ALPHA_NAME) }
  end

  help=Sketchup.find_support_file("SU2XPlane_"+Sketchup.get_locale.upcase.split('-')[0]+".html", "Plugins")
  if not help
    help=Sketchup.find_support_file("SU2XPlane.html", "Plugins")
  end
  if help
    UI.menu("Help").add_item("X-Plane") { UI.openURL("file://" + help) }
  end
  file_loaded("SU2XPlane.rb")
end

#Sketchup.send_action "showRubyPanel:"
