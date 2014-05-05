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
module Marginal
  module SU2XPlane

    Version="1.60"

    # Debug
    TraceEvents=false
    #Sketchup.send_action "showRubyPanel:"
    Benchmark=false

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
    P_UV=4		# UV
    P_A=2		# Animation angle

    extension = SketchupExtension.new('SketchUp2XPlane', File.join(File.dirname(__FILE__), File.basename(__FILE__,'.rb'), 'loader.rb'))
    extension.description = 'Provides ability to import and export models in X-Plane v8/v9/v10 .obj format. See Help->X-Plane for instructions.'
    extension.version = Version
    extension.creator = 'Jonathan Harris'
    extension.copyright = '2006-2014, Jonathan Harris. Licensed under GPLv2.'
    Sketchup.register_extension(extension, true)

  end
end
