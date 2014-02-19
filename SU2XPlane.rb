#
# X-Plane importer/exporter for SketchUp
#
# Copyright (c) 2006-2014 Jonathan Harris
# 
# Mail: <x-plane@marginal.org.uk>
# Web:  http://marginal.org.uk/x-planescenery/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#

require 'sketchup.rb'
require 'extensions.rb'

# Constants
module SU2XPlane
  Version="1.59"

  # Debug
  TraceEvents=false

  # X-Plane attributes
  ATTR_DICT="X-Plane"
  ATTR_DECK_NAME="deck"
  ATTR_HARD_NAME="poly"	# incorrect dictionary key not fixed for compatibility
  ATTR_POLY_NAME="hard"	# ditto
  ATTR_ALPHA_NAME="alpha"
  ATTR_SHINY_NAME="shiny"

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
extension.copyright='2006-2014'
Sketchup.register_extension extension, true

require_all Sketchup.find_support_file('SU2XPlane', 'Plugins')

# Add UI
if !file_loaded?("SU2XPlane.rb")
  begin
    Sketchup.register_importer(XPlaneImporter.new)
    UI.menu("File").add_item(XPL10n.t('Export X-Plane Object')) { XPlaneExport() }
    UI.menu("Tools").add_item(XPL10n.t('Highlight Untextured')) { XPlaneHighlight() }

    UI.add_context_menu_handler do |menu|
      if !Sketchup.active_model.selection.empty?
        menu.add_separator
        submenu = menu.add_submenu "X-Plane"
        hard=submenu.add_item(XPlaneTestAttr(SU2XPlane::ATTR_HARD_NAME, 'Hard')) {
          XPlaneToggleAttr(SU2XPlane::ATTR_HARD_NAME) }
        submenu.set_validation_proc(hard) {
          XPlaneValidateAttr(SU2XPlane::ATTR_HARD_NAME) }
        deck=submenu.add_item(XPlaneTestAttr(SU2XPlane::ATTR_DECK_NAME, 'Hard Deck')) {
          XPlaneToggleAttr(SU2XPlane::ATTR_DECK_NAME) }
        submenu.set_validation_proc(deck) {
          XPlaneValidateAttr(SU2XPlane::ATTR_DECK_NAME) }
        poly=submenu.add_item(XPlaneTestAttr(SU2XPlane::ATTR_POLY_NAME, 'Ground')) {
          XPlaneToggleAttr(SU2XPlane::ATTR_POLY_NAME) }
        submenu.set_validation_proc(poly) {
          XPlaneValidateAttr(SU2XPlane::ATTR_POLY_NAME) }
        alpha=submenu.add_item(XPlaneTestAttr(SU2XPlane::ATTR_ALPHA_NAME, 'Alpha')) {
          XPlaneToggleAttr(SU2XPlane::ATTR_ALPHA_NAME) }
        submenu.set_validation_proc(alpha) {
          XPlaneValidateAttr(SU2XPlane::ATTR_ALPHA_NAME) }
        shiny=submenu.add_item(XPlaneTestAttr(SU2XPlane::ATTR_SHINY_NAME, 'Shiny')) {
          XPlaneToggleAttr(SU2XPlane::ATTR_SHINY_NAME) }
        submenu.set_validation_proc(shiny) {
          XPlaneValidateAttr(SU2XPlane::ATTR_SHINY_NAME) }
        anim=submenu.add_item("\xE2\x80\x87\xE2\x80\x82"+XPL10n.t('Animation...')) {	# U+2007 figure space & U+2002 en space
          XPlaneMakeAnimation() }
      end
    end
  rescue NameError => e
    puts "Error: #{e.inspect}", e.backtrace	# Report to console
    UI.menu("File").add_item('SU2XPlane plugin folder is missing!') {}
  end

  help = XPL10n.resource_file('SU2XPlane.html')
  if help
    UI.menu("Help").add_item("X-Plane") { UI.openURL("file://" + help) }
  else
    UI.menu("Help").add_item("X-Plane") { UI.messagebox('X-Plane help files are missing!') }
  end
  file_loaded("SU2XPlane.rb")
end

#Sketchup.send_action "showRubyPanel:"
