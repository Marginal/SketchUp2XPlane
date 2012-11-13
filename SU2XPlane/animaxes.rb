#
# Monitor use of the "Change Axes" tool and fix up animations when the axes change
#

class Sketchup::Model
  attr_accessor(:XPDoneToolsObserver)
end

class Sketchup::ComponentInstance
  attr_accessor(:XPSavedTransformation)
end

class XPlaneAppObserver < Sketchup::AppObserver

  def initialize
    Sketchup.add_observer(self)
  end

  def onNewModel(model)
    XPlaneToolsObserver.new(model)
  end

  def onOpenModel(model)
    # Hack! onOpenModel can be called multiple times if the user opens the model multiple times.
    # But we mustn't add multiple ToolsObservers otherwise we would erroneously apply the axes fix up multiple times.
    if !model.XPDoneToolsObserver
      XPlaneToolsObserver.new(model)
      model.XPDoneToolsObserver=true
    end
  end

end


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
    puts "onActiveToolChanged #{tool_name} #{tool_id} #{@model.selection.to_a}" if SU2XPlane::TraceEvents
    if !@model.valid?		# this can't happen
      @model.tools.remove_observer(self)
    elsif tool_id==21126
      # Change Axes tool
      c=@model.selection.first	# can be nil if the user is changing global axes
      if c && c.typename=='ComponentInstance' && c.XPCountFrames>0
        @definition=c.definition
        @definition.instances.each { |c| c.XPSavedTransformation=c.transformation }
        @definition.entities.each do |c|
          if c.typename=='ComponentInstance' && c.XPCountFrames>0
            (0...c.XPCountFrames).each do |frame|
              c.XPSavedTransformation=c.transformation
            end
          end
        end
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
          c.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s, (shift * Geom::Transformation.new(c.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s))).to_a)
        end
      end
      # shift immediate childrens' stored keyframe positions too
      @definition.entities.each do |c|
        if c.typename=='ComponentInstance' && c.XPCountFrames>0
          shift=c.transformation * c.XPSavedTransformation.inverse
          (0...c.XPCountFrames).each do |frame|
            c.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s, (shift * Geom::Transformation.new(c.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s))).to_a)
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

  if SU2XPlane::TraceEvents
    def onToolStateChanged(tools, tool_name, tool_id, tool_state)
      puts "onToolStateChanged #{tool_name} #{tool_id} #{tool_state}"
    end
  end
end
