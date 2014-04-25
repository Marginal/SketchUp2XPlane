#
# X-Plane animation helper
#
# Copyright (c) 2012-2013 Jonathan Harris
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#

#
# Fix up animations when the axes change due to:
# - Use of the "Change Axes" tool
# - Component is included into a new Group or component
# - Component Instance is copied
#

class Sketchup::Model
  attr_accessor(:XPDoneAxesModelObservers)
end

class Sketchup::ComponentInstance
  attr_accessor(:XPSavedTransformation)
end


module Marginal
  module SU2XPlane

    class XPlaneAxesAppObserver < Sketchup::AppObserver

      def initialize
        Sketchup.add_observer(self)
      end

      def onNewModel(model)
        onOpenModel(model)
      end

      def onOpenModel(model)
        # Hack! onOpenModel can be called multiple times if the user opens the model multiple times.
        # But we mustn't add multiple observers otherwise we would erroneously apply the axes fix up multiple times.
        if !model.XPDoneAxesModelObservers
          XPlaneToolsObserver.new(model)
          XPlaneSelectionObserver.new(model)
          XPlaneDefinitionsObserver.new(model)
          XPlaneModelObserver.new(model)
          XPlaneAnimEntitiesObserver.new(model)
          model.XPDoneAxesModelObservers=true
        end
      end

    end


    #
    # Monitor use of the "Change Axes" tool and fix up animations when the axes change
    #
    class XPlaneToolsObserver < Sketchup::ToolsObserver
      # Order of events when the Change Axes tool is applied:
      # onActiveToolChanged ComponentCSTool, 21126
      # onToolStateChanged  ComponentCSTool, 21126, 0
      # onToolStateChanged  ComponentCSTool, 21126, 0
      # component.transformation updated with new axes; child geometry and group/component origins shifted to compensate
      # onActiveToolChanged SelectionTool,   21022

      def initialize(model)
        @model=model
        @definition=nil	# ComponentDefinition of the component that is having its axes changed
        @model.tools.add_observer(self)
      end

      def onActiveToolChanged(tools, tool_name, tool_id)
        puts "onActiveToolChanged #{tool_name} #{tool_id} #{@model.selection.to_a}" if TraceEvents
        if !@model.valid?		# this can't happen
          @model.tools.remove_observer(self)
        elsif tool_id==21126
          # Change Axes tool
          c=@model.selection.first	# can be nil if the user is changing global axes
          if c && c.typename=='ComponentInstance' && c.XPCountFrames>0
            @definition=c.definition
            @definition.instances.each { |c| c.XPSavedTransformation=c.transformation }
            @definition.entities.each  { |c| c.XPSavedTransformation=c.transformation if c.typename=='ComponentInstance' && c.XPCountFrames>0 }
          else
            @definition=nil
          end
        elsif @definition && @definition.instances.first.XPSavedTransformation.to_a!=@definition.instances.first.transformation.to_a	# Transformation has no comparison operators
          # Change Axes tool finished and axes were changed
          @model.start_operation('Change Axes', true, false, true)	# Merge with the Change Axes tool's operation
          # replicate axes shift in stored keyframe positions for all instances
          @definition.instances.each do |c|
            shift=(@model.active_entities.include?(c) ? @model.edit_transform.inverse * c.transformation : c.transformation) * c.XPSavedTransformation.inverse
            (0...c.XPCountFrames).each do |frame|
              c.set_attribute(ATTR_DICT, ANIM_MATRIX_+frame.to_s, (shift * Geom::Transformation.new(c.get_attribute(ATTR_DICT, ANIM_MATRIX_+frame.to_s))).to_a)
            end
          end
          # shift immediate childrens' stored keyframe positions too
          @definition.entities.each do |c|
            if c.typename=='ComponentInstance' && c.XPCountFrames>0
              shift=c.transformation * c.XPSavedTransformation.inverse
              (0...c.XPCountFrames).each do |frame|
                c.set_attribute(ATTR_DICT, ANIM_MATRIX_+frame.to_s, (shift * Geom::Transformation.new(c.get_attribute(ATTR_DICT, ANIM_MATRIX_+frame.to_s))).to_a)
              end
            end
          end
          @model.commit_operation
          @definition=nil
        else
          # Some other tool, or Change Axes tool cancelled
          @definition=nil
        end
      end

      if TraceEvents
        def onToolStateChanged(tools, tool_name, tool_id, tool_state)
          puts "onToolStateChanged #{tool_name} #{tool_id} #{tool_state}"
        end
      end

    end


    #
    # Monitor change of selection in case the selection is made into a Component or Group
    #
    class XPlaneSelectionObserver < Sketchup::SelectionObserver

      def initialize(model)
        @model=model
        @model.selection.add_observer(self)
      end

      def onSelectionBulkChange(selection)
        puts "onSelectionBulkChange #{selection.to_a.inspect}" if TraceEvents
        selection.each do |e|
          if e.typename=='ComponentInstance'
            puts "#{e} #{e.name}",e.transformation.inspect if TraceEvents
            # Save transformations in case the user makes this selection into a Component or Group
            e.XPSavedTransformation=e.transformation if e.XPCountFrames>0
            # Save transformations of children in case the user explodes this Component
            e.definition.entities.each { |c| c.XPSavedTransformation=c.transformation if c.typename=='ComponentInstance' && c.XPCountFrames>0 }
          elsif e.typename=='Group'
            # Save transformations of children in case the user explodes this Group
            e.entities.each { |c| c.XPSavedTransformation=c.transformation if c.typename=='ComponentInstance' && c.XPCountFrames>0 }
          end
        end
      end

    end


    #
    # Monitor creation of new Components and Groups and fix up any animations contained in the new Component/Group
    #
    class XPlaneDefinitionsObserver < Sketchup::DefinitionsObserver

      def initialize(model)
        @model=model
        @model.definitions.add_observer(self)
      end

      def onComponentAdded(definitions, definition)
        puts "onComponentAdded #{definitions} #{definition}", "active:  #{@model.active_entities.to_a.inspect}", @model.edit_transform.inspect if TraceEvents
        # adjust immediate children for axes shift
        # @model.start_operation('Make Component/Group', true, false, true)	# Don't need to do this - we're still in the middle of the operation
        definition.entities.each do |c|
          # WTF? sometimes Sketchup refuses to make the requested new Component - in which case the sub-Components are new and don't have a saved Transformation
          if c.typename=='ComponentInstance' && c.XPSavedTransformation
            puts "#{c} #{c.name}", "current:", c.transformation.inspect, "saved:", c.XPSavedTransformation.inspect if TraceEvents
            shift=@model.edit_transform * c.transformation * c.XPSavedTransformation.inverse
            (0...c.XPCountFrames).each do |frame|
              puts "#{frame}: " + c.get_attribute(ATTR_DICT, ANIM_MATRIX_+frame.to_s).inspect if TraceEvents
              c.set_attribute(ATTR_DICT, ANIM_MATRIX_+frame.to_s, (shift * Geom::Transformation.new(c.get_attribute(ATTR_DICT, ANIM_MATRIX_+frame.to_s))).to_a)
            end
            c.XPSavedTransformation=c.transformation	# in case the user explodes the new parent Component/Group without changing selection
          end
        end
        # @model.commit_operation
      end

      if TraceEvents
        def onComponentRemoved(definitions, definition)
          # Component has already been stripped of its entities so this is of no use
          puts "onComponentRemoved #{definitions} #{definition}", "entities:#{definition.entities.to_a.inspect}"
        end
      end

    end


    #
    # Monitor Explode of Component or Group and fix up any animations
    #
    class XPlaneModelObserver < Sketchup::ModelObserver

      def initialize(model)
        model.add_observer(self)
      end

      if TraceEvents
        def onTransactionStart(model)
          puts "onTransactionStart #{model}"
        end

        def onTransactionCommit(model)
          puts "onTransactionCommit #{model}"
        end

        def onTransactionEmpty(model)
          puts "onTransactionEmpty #{model}"
        end

        def onTransactionUndo(model)
          puts "onTransactionUndo #{model}"
        end

        def onTransactionRedo(model)
          puts "onTransactionRedo #{model}"
        end
      end

      def onExplode(model)
        puts "onExplode #{model} #{model.selection.to_a}", model.edit_transform.inspect if TraceEvents
        model.selection.each do |c|
          if c.typename=='ComponentInstance' && c.XPSavedTransformation
            model.start_operation('Explode', true, false, true)
            puts "#{c} #{c.name}", "current:", c.transformation.inspect, "saved:", c.XPSavedTransformation.inspect if TraceEvents
            shift=model.edit_transform.inverse * c.transformation * c.XPSavedTransformation.inverse
            (0...c.XPCountFrames).each do |frame|
              puts "#{frame}: " + c.get_attribute(ATTR_DICT, ANIM_MATRIX_+frame.to_s).inspect if TraceEvents
              c.set_attribute(ATTR_DICT, ANIM_MATRIX_+frame.to_s, (shift * Geom::Transformation.new(c.get_attribute(ATTR_DICT, ANIM_MATRIX_+frame.to_s))).to_a)
            end
            c.XPSavedTransformation=c.transformation	# in case the user re-Groups this entity without changing selection
            model.commit_operation
          end
        end
      end

    end


    #
    # Monitor new Instances of Components and fix up any animations contained in the new Component Instance
    #
    class XPlaneAnimEntitiesObserver < Sketchup::EntitiesObserver

      def initialize(model)
        @model=model
        @model.active_entities.add_observer(self)
      end

      # This fails to fire when the new copy is inside a Component or Group. What a crock.
      def onElementAdded(entities, e)
        puts "onElementAdded #{entities} #{e}" if TraceEvents
        if e.typename=='ComponentInstance'
          # XPSavedTransformation holds the *new* location since we've already been selected before we're notified here!
          puts "#{e} #{e.name}", e.transformation.inspect if TraceEvents
          @model.start_operation('Shift', true, false, true)
          # So just do the fixup relative to frame 0 on the basis that this is probably better than nothing
          if e.get_attribute(ATTR_DICT, ANIM_MATRIX_+'0')
            shift=Geom::Transformation.translation(e.transformation.origin) * Geom::Transformation.translation(Geom::Transformation.new(e.get_attribute(ATTR_DICT, ANIM_MATRIX_+'0')).origin).inverse
            (0...e.XPCountFrames).each do |frame|
              puts "#{frame}: " + e.get_attribute(ATTR_DICT, ANIM_MATRIX_+frame.to_s).inspect if TraceEvents
              e.set_attribute(ATTR_DICT, ANIM_MATRIX_+frame.to_s, (shift * Geom::Transformation.new(e.get_attribute(ATTR_DICT, ANIM_MATRIX_+frame.to_s))).to_a)
            end
          end
          e.XPSavedTransformation=e.transformation	# in case the user re-Groups this entity without changing selection
          @model.commit_operation
        end
      end

      if TraceEvents
        def onElementModified(entities, entity)
          puts "onElementModified #{entities} #{entity}" if TraceEvents
        end

        def onElementRemoved(entities, entity)
          puts "onElementRemoved #{entities} #{entity}"
        end

        def onEraseEntities(entities, entity)
          puts "onEraseEntities #{entities}"
        end
      end

    end


    # Install Model observers
    XPlaneAxesAppObserver.new.onOpenModel(Sketchup.active_model)	# on[Open|New]Model not sent by SketchUp on initial model - see https://developers.google.com/sketchup/docs/ourdoc/appobserver#onOpenModel

  end
end
