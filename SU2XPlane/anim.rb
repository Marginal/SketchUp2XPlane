#
# X-Plane animation UI
#
# Copyright (c) 2012-2013 Jonathan Harris
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#

#
# An X-Plane animation is represented by attaching an AttributeDictionary named SU2XPlane::ATTR_DICT to a component.
# (We use ComponentInstances rather than Groups because SketchUp by default doesn't display Group axes, and the axes' origin
#  is obviously important for rotation animations).
# A component can represent zero or one animation, and zero or multiple Hide/Show values.
# Animations that depend on multiple DataRefs can be represented by nested components.
#
# The AttributeDictionary contains a set of animation entries named:
# - SU2XPlane::ANIM_DATAREF - dataref, or '' if no animation
# - SU2XPlane::ANIM_INDEX - dataref index, or '' if not an array dataref
# - SU2XPlane::ANIM_FRAME_#, SU2XPlane::ANIM_MATRIX_# - dataref value and Geom::Transformation.to_a for each keyframe #
#
# The AttributeDictionary can also contain multiple entries representing Hide/Show. For each Hide/Show #:
# - SU2XPlane::ANIM_HS_#SU2XPlane::ANIM_HS_HIDESHOW - "hide" or "show"
# - SU2XPlane::ANIM_HS_#SU2XPlane::ANIM_HS_DATAREF  - dataref
# - SU2XPlane::ANIM_HS_#SU2XPlane::ANIM_HS_INDEX    - dataref index, or '' if not an array dataref
# - SU2XPlane::ANIM_HS_#SU2XPlane::ANIM_HS_FROM, SU2XPlane::ANIM_HS_#SU2XPlane::ANIM_HS_TO - from and to values
#
# Each animation component can have an associated WebDialog which displays and allows manipulation of the AttributeDictionary
# entries. The WebDialog is wrapped by an instance of the XPlaneAnimation class, implemented in this file.
# The WebDialog allows the user to store the component's current translation/rotation as a KeyFrame position in the component's
# AttributeDictionary as SU2XPlane::ANIM_MATRIX_#, and to preview the interpolation/extrapolation between KeyFrame positions.
#
# There is one complication: The component's transformation (ComponentInstance.transformation) is temporarily rewritten by
# SketchUp while the component (or component's parent or (grand)children) are "open" for editing (i.e. the component or its immediate
# parent is in Sketchup.active_model.active_path). (Presumably this seemed like a good idea to someone at the time).
# Storing or setting the component.transformation in this situation gives bogus results unless we adjust for this.
# See http://sketchucation.com/forums/viewtopic.php?f=323&p=263794 for a discussion.
# For children of the currently "open" component we can adjust for this by applying Sketchup.active_model.edit_transform.inverse
# to the child's transformation before storing it, and by applying Sketchup.active_model.edit_transform before setting the
# child's transformation.
# For the currently "open" component and its parents we could probably work up the Sketchup.active_model.active_path list to
# calculate the appropriate adjustment. But setting the open component's or its parents' transformations doesn't update the open
# component's edit bounding box in the SketchUp UI, so the open component and children can move out of their bounding box which
# looks weird.
#
# So we disable the WebDialog that allows the user to store and/or set component.transformation if the component or any of its
# children are "open" for editing in the SketchUp UI - i.e. if the the component is not a member or child of
# Sketchup.active_model.active_entities. Now we only need to apply Sketchup.active_model.edit_transform[.inverse] if the component
# is a direct child of the currently "open" component - i.e. the component is in Sketchup.active_model.active_entities.
#
# SketchUp displays everything outside of the currently "open" component as tinted green - both parents and unrelated component
# hierarchies. For consistency of UI we also disable the WebDialog for these unrelated components (even though it would be safe
# to store and/or set their component.transformation without causing edit bounding box weirdness).
#
#
# Undo:
#
# Some operations, notably setting animation values and using the preview slider, generate multiple SketchUp Undo steps.
# We want to merge these into a simple step to avoid making Undo unusable. We install an EntitiesObserver on each model
# to detect other changes to the model, so as to avoid merging Undo steps with those other changes.
#

if not defined? SU2XPlane
  UI.messagebox("X-Plane plugin installed incorrectly!\nDelete SketchUp's plugin folder, then re-install SketchUp and plugins.")
  exit
end

class Sketchup::Model
  attr_accessor(:XPDoneModelObservers)
  attr_accessor(:XPLastAction)		# Record last change to the component for the purpose of merging Undo steps
  attr_accessor(:XPLastActionRef)
end

class XPlaneAppObserver < Sketchup::AppObserver

  def initialize
    Sketchup.add_observer(self)
  end

  def onNewModel(model)
    onOpenModel(model)
  end

  def onOpenModel(model)
    # Hack! onOpenModel can be called multiple times if the user opens the model multiple times.
    # But we mustn't add multiple ToolsObservers otherwise we would erroneously apply the axes fix up multiple times.
    if !model.XPDoneModelObservers
      XPlaneEntitiesObserver.new(model)
      model.XPDoneModelObservers=true
    end
  end

end


#
# Monitor Entity changes to prevent merging of Undo steps with other edits.
# Would be more natural to use a ModelObserver to monitor transactions, but it's bugged - http://www.thomthom.net/software/sketchup/observers/#note_onTransaction
#
class XPlaneEntitiesObserver < Sketchup::EntitiesObserver

  def initialize(model)
    @model=model
    @model.active_entities.add_observer(self)
  end

  def onElementModified(entities, entity)
    puts "onElementModified #{entities} #{entity} #{@model.XPLastAction} #{@model.XPLastActionRef}" if SU2XPlane::TraceEvents
    if @model.XPLastActionRef
      # This event was caused by this script
      @model.XPLastActionRef=false
    else
      # This event was caused by other editing - don't merge later Undo steps with it
      @model.XPLastAction=nil
    end
  end

  if SU2XPlane::TraceEvents
    def onElementAdded(entities, entity)
      puts "onElementAdded #{entities} #{entity}"
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
XPlaneAppObserver.new.onOpenModel(Sketchup.active_model)	# on[Open|New]Model not sent by SketchUp on initial model - see https://developers.google.com/sketchup/docs/ourdoc/appobserver#onOpenModel


class XPlaneAnimationModelObserver < Sketchup::ModelObserver

  def initialize(model, parent)
    @model=model
    @parent=parent
    @model.add_observer(self)
  end

  def onTransactionUndo(model)
    puts "onTransactionUndo #{model} #{@parent}" if SU2XPlane::TraceEvents
    @model.XPLastAction=nil	# Don't merge subsequent operations with the operation that was previous to this undone operation
    # Don't know what's being undone, so just always update dialog
    @parent.update_dialog()
  end

  def onTransactionRedo(model)
    puts "onTransactionRedo #{model} #{@parent}" if SU2XPlane::TraceEvents
    # Don't know what's being redone, so just always update dialog
    @parent.update_dialog()
  end

  def onActivePathChanged(model)
    puts "onActivePathChanged #{model} #{@parent}" if SU2XPlane::TraceEvents
    @parent.update_dialog()
  end

  def onDeleteModel(model)
    puts "onDeleteModel #{model} #{@parent}" if SU2XPlane::TraceEvents
    # This doesn't fire on closing the model, so currently worthless. Maybe it will work in the future.
    @parent.close()
  end

  def onEraseAll(model)
    puts "onEraseAll #{model} #{@parent}" if SU2XPlane::TraceEvents
    # Currently only works on Windows.
    @parent.close()
  end

end


class XPlaneAnimation < Sketchup::EntityObserver

  # DataRef values are stored as Strings - need to convert decimal separator to user's locale for display
  DecimalSep=Sketchup.format_degrees(1.2).match(/\d(\D)\d/)[1]	# Hack! http://sketchucation.com/forums/viewtopic.php?f=180&t=28346&start=15#p246363

  @@instances={}	# map components to instances
  attr_reader(:dlg)

  def initialize(component, model)
    @component=component
    @model=model
    if @component.typename!='ComponentInstance' then fail end
    if Object::RUBY_PLATFORM =~ /darwin/i
      @dlg = UI::WebDialog.new(XPL10n.t('X-Plane Animation'), true, nil, 396, 402)
      @dlg.min_width = 396
    else
      @dlg = UI::WebDialog.new(XPL10n.t('X-Plane Animation'), true, nil, 450, 532)
      @dlg.min_width = 450
    end
    @@instances[@component]=self
    @dlg.allow_actions_from_host("getfirebug.com")	# for debugging on Windows
    @dlg.set_file(Sketchup.find_support_file('anim.html', 'Plugins/SU2XPlane/Resources'))
    @dlg.add_action_callback("on_load") { |d,p| update_dialog }
    @dlg.add_action_callback("on_close") {|d,p| close }
    @dlg.add_action_callback("on_erase") { |d,p| erase }
    @dlg.add_action_callback("on_set_var") { |d,p| set_var(p) }
    @dlg.add_action_callback("on_set_transform") { |d,p| set_transform(p) }
    @dlg.add_action_callback("on_get_transform") { |d,p| get_transform(p) }
    @dlg.add_action_callback("on_insert_frame") { |d,p| insert_frame(p) }
    @dlg.add_action_callback("on_delete_frame") { |d,p| delete_frame(p) }
    @dlg.add_action_callback("on_insert_hideshow") { |d,p| insert_hideshow(p) }
    @dlg.add_action_callback("on_delete_hideshow") { |d,p| delete_hideshow(p) }
    @dlg.add_action_callback("on_preview") { |d,p| preview(p) }
    @component.add_observer(self)
    @modelobserver=XPlaneAnimationModelObserver.new(@model, self)
    @dlg.set_on_close {	# Component or Model might be deleted, so use exception blocks
      begin @component.remove_observer(self) rescue TypeError end
      begin @model.remove_observer(@modelobserver) rescue TypeError end
      @@instances.delete(@component)
    }
    @dlg.show
    @dlg.bring_to_front
  end

  def XPlaneAnimation.instances()
    return @@instances
  end

  def close()
    @dlg.close
  end

  def included?(entities)
    # Is this component in entities, or in sub-entities
    return true if entities.include?(@component)
    entities.each do |e|
      if e.typename=='Group'
        return true if included?(e.entities)
      elsif e.typename=='ComponentInstance'
        return true if included?(e.definition.entities)
      end
    end
    return false
  end

  def count_frames()
    # Recalculate frame count very time we need the value in case component has been modified elsewhere
    return @component.XPCountFrames
  end

  def count_hideshow()
    # Recalculate hideshow count very time we need the value in case component has been modified elsewhere
    return @component.XPCountHideShow
  end

  def update_dialog()
    puts "update_dialog #{@component} #{dlg}" if SU2XPlane::TraceEvents
    # Remaining initialization, deferred 'til DOM is ready via window.onload
    begin
      return close() if !@model.valid? || @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_DATAREF)==nil	# User has closed the window on Mac, or undone creation of animation attributes
    rescue TypeError
      # User has undone creation of animation component -> underlying @component object has been deleted.
      return	#  Ignore and wait for onEraseEntity
    end
    if @component.name!=''
      title=@component.name
    elsif @component.respond_to?(:definition)
      title='&lt;'+@component.definition.name+'&gt;'
    else
      title='Group'
    end
    l10n_datarefval, l10n_position, l10n_preview, l10n_hideshow, l10n_erase = XPL10n.t('DataRef value'), XPL10n.t('Position'), XPL10n.t('Preview'), XPL10n.t('Hide / Show'), XPL10n.t('Erase')
    @dlg.execute_script("resetDialog('#{title}', '#{@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_DATAREF)}', '#{@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_INDEX)}', '#{l10n_datarefval}', '#{l10n_position}', '#{l10n_preview}', '#{l10n_hideshow}', '#{l10n_erase}', '#{DecimalSep}')")

    disable=((@model.active_path!=nil) and (!included?(@model.active_entities)))	# Can't manipulate transformation while subcomponents are being edited.

    numframes=count_frames()
    hasdeleter = numframes>2 ? "true" : "false"
    l10n_keyframe, l10n_set, l10n_recall = XPL10n.t('Keyframe'), XPL10n.t('Set'), XPL10n.t('Recall')
    for frame in 0...numframes
      @dlg.execute_script("addFrameInserter(#{frame})")
      @dlg.execute_script("addKeyframe(#{frame}, '#{@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+frame.to_s).tr('.',DecimalSep)}', #{hasdeleter}, '#{l10n_keyframe}', '#{l10n_set}', '#{l10n_recall}')")
    end
    @dlg.execute_script("addFrameInserter(#{numframes})")
    l10n_loop = XPL10n.t('Loop')
    @dlg.execute_script("addLoop('#{@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_LOOP).tr('.',DecimalSep)}', '#{l10n_loop}')")

    hideshow=0
    l10n_hide, l10n_show, l10n_when, l10n_to = XPL10n.t('Hide'), XPL10n.t('Show'), XPL10n.t('when'), XPL10n.t('to')
    while true
      prefix=SU2XPlane::ANIM_HS_+hideshow.to_s
      hs=@component.get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_HIDESHOW)
      if hs==nil then break end
      @dlg.execute_script("addHSInserter(#{hideshow})")
      @dlg.execute_script("addHideShow(#{hideshow}, '#{@component.get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_HIDESHOW)}', '#{@component.get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_DATAREF)}', '#{@component.get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_INDEX)}', '#{@component.get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_FROM).tr('.',DecimalSep)}', '#{@component.get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_TO).tr('.',DecimalSep)}', '#{l10n_hide}', '#{l10n_show}', '#{l10n_when}', '#{l10n_to}')")
      hideshow+=1
    end
    @dlg.execute_script("addHSInserter(#{hideshow})")

    @dlg.execute_script("document.getElementById('preview-value').innerHTML=''")	# reset preview display since may no longer be accurate
    @dlg.execute_script("disable(#{disable}, #{disable or !can_preview()})")
    @dlg.execute_script("window.location='#top'")	# Force redisplay - required on Mac
  end

  def merge_operation?(operation)
    # is the last operation performed by Sketchup the same as the one we're about to do? in which case we should merge
    puts "#{operation} #{@model.XPLastAction==operation}" if SU2XPlane::TraceEvents
    @model.XPLastActionRef=true
    if @model.XPLastAction==operation
      return true
    else
      @model.XPLastAction=operation
      return false
    end
  end

  def onEraseEntity(entity)	# from EntityObserver
    # destroy ourselves if the component instance that we are animating is deleted
    close()
  end

  def set_var(p)
    puts "set_var #{@component} #{p} #{@dlg.get_element_value(p)}" if SU2XPlane::TraceEvents
    return close() if !@model.valid?	# model was closed on Mac
    newval=@dlg.get_element_value(p).strip.tr(DecimalSep,'.')
    return if @component.get_attribute(SU2XPlane::ATTR_DICT, p)==newval	# can get spurious call when update_dialog is called - e.g. on Undo, which messes up Undo merging
    @model.start_operation(XPL10n.t('Animation value'), true, false, merge_operation?("#{@component.object_id}/#{p}"))	# merge into last if setting same var again
    @component.set_attribute(SU2XPlane::ATTR_DICT, p, newval)
    @model.commit_operation
    disable=!can_preview()
    @dlg.execute_script("document.getElementById('preview-slider').disabled=#{disable}")
    @dlg.execute_script("fdSlider."+(disable ? "disable" : "enable")+"('preview-slider')")
    @dlg.execute_script("document.getElementById('preview-value').innerHTML=''")	# reset preview display since may no longer be accurate
  end

  def set_transform(p)
    puts "set_transform #{@component} #{p} #{@component.transformation.inspect}" if SU2XPlane::TraceEvents
    return close() if !@model.valid?	# model was closed on Mac
    @model.start_operation(XPL10n.t('Set Position'), true, false, merge_operation?("#{@component.object_id}/"+SU2XPlane::ANIM_MATRIX_+p))	# merge into last if setting same transformation again
    trans = @model.active_entities.include?(@component) ? @model.edit_transform.inverse * @component.transformation : @component.transformation
    # X-Plane doesn't allow scaling, and SketchUp doesn't handle it in interpolation. So save transformation with identity (not current) scale
    trans *= Geom::Transformation.scaling(1/trans.xscale, 1/trans.yscale, 1/trans.zscale)
    @component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+p, trans.to_a)
    @model.commit_operation
  end

  def get_transform(p)
    puts "get_transform #{@component} #{p}" if SU2XPlane::TraceEvents
    return close() if !@model.valid?	# model was closed on Mac
    @model.start_operation(XPL10n.t('Preview Animation'), true, false, merge_operation?("#{@component.object_id}/preview"))	# treat same as preview for the sake of Undo
    trans = @model.active_entities.include?(@component) ? @model.edit_transform * @component.XPTransformation(p) : @component.XPTransformation(p)	# may not be unit scale if (grand)parent scaled
    @component.transformation = trans * Geom::Transformation.scaling(@component.transformation.xscale/trans.xscale, @component.transformation.yscale/trans.yscale, @component.transformation.zscale/trans.zscale)	# preserve scale
    @model.commit_operation
    if can_preview()
      @dlg.execute_script("document.getElementById('preview-value').innerHTML='#{('%.6g' % @component.XPGetValue(p).to_f).tr('.',DecimalSep)}'")
      loop=@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_LOOP).to_f
      if loop>0.0
        range_start, range_stop = 0.0, loop
      else
        range_start, range_stop = @component.XPGetValue(0).to_f, @component.XPGetValue(count_frames()-1).to_f
      end
      @dlg.execute_script("document.getElementById('preview-slider').value=#{(@component.XPGetValue(p).to_f-range_start)*200/(range_stop-range_start)}")
      @dlg.execute_script("fdSlider.updateSlider('preview-slider')")
    end
  end

  def insert_frame(p)
    puts "insert_frame #{@component} #{p}" if SU2XPlane::TraceEvents
    return close() if !@model.valid?	# model was closed on Mac
    @model.start_operation(XPL10n.t("Keyframe"), true)
    newframe=p.to_i
    numframes=count_frames()
    # shift everything up
    numframes.downto(newframe+1) do |frame|
      @component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+frame.to_s,  @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+(frame-1).to_s))
      @component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s, @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+(frame-1).to_s))
    end
    if newframe==numframes
      @component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+newframe.to_s, @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+(newframe-1).to_s))
    end
    trans = @model.active_entities.include?(@component) ? @model.edit_transform.inverse * @component.transformation : @component.transformation
    # X-Plane doesn't allow scaling, and SketchUp doesn't handle it in interpolation. So save transformation with identity (not current) scale
    trans *= Geom::Transformation.scaling(1/trans.xscale, 1/trans.yscale, 1/trans.zscale)
    @component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+newframe.to_s, trans.to_a)
    @model.commit_operation
    update_dialog()
  end

  def delete_frame(p)
    puts "delete_frame #{@component} #{p}" if SU2XPlane::TraceEvents
    return close() if !@model.valid?	# model was closed on Mac
    @model.start_operation(XPL10n.t('Erase Keyframe'), true)
    oldframe=p.to_i
    numframes=count_frames()-1
    # shift everything down
    oldframe.upto(numframes-1) do |frame|
      @component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+frame.to_s,  @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+(frame+1).to_s))
      @component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s, @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+(frame+1).to_s))
    end
    dict=@component.attribute_dictionary(SU2XPlane::ATTR_DICT)
    dict.delete_key(SU2XPlane::ANIM_FRAME_+numframes.to_s)
    dict.delete_key(SU2XPlane::ANIM_MATRIX_+numframes.to_s)
    @model.commit_operation
    update_dialog()
  end

  def insert_hideshow(p)
    puts "insert_hideshow #{@component} #{p}" if SU2XPlane::TraceEvents
    return close() if !@model.valid?	# model was closed on Mac
    @model.start_operation(XPL10n.t('Hide / Show'), true)
    newhs=p.to_i
    numhs=count_hideshow()
    # shift everything up
    numhs.downto(newhs+1) do |hs|
      prefix=SU2XPlane::ANIM_HS_+hs.to_s
      other=SU2XPlane::ANIM_HS_+(hs-1).to_s
      @component.set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_HIDESHOW, @component.get_attribute(SU2XPlane::ATTR_DICT, other+SU2XPlane::ANIM_HS_HIDESHOW))
      @component.set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_DATAREF,  @component.get_attribute(SU2XPlane::ATTR_DICT, other+SU2XPlane::ANIM_HS_DATAREF))
      @component.set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_INDEX,    @component.get_attribute(SU2XPlane::ATTR_DICT, other+SU2XPlane::ANIM_HS_INDEX))
      @component.set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_FROM,     @component.get_attribute(SU2XPlane::ATTR_DICT, other+SU2XPlane::ANIM_HS_FROM))
      @component.set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_TO,       @component.get_attribute(SU2XPlane::ATTR_DICT, other+SU2XPlane::ANIM_HS_TO))
    end
    prefix=SU2XPlane::ANIM_HS_+newhs.to_s
    @component.set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_HIDESHOW, newhs==0 ? SU2XPlane::ANIM_VAL_HIDE : SU2XPlane::ANIM_VAL_SHOW)
    @component.set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_DATAREF,  '')
    @component.set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_INDEX,    '')
    @component.set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_FROM,     '0.0')
    @component.set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_TO,       '1.0')
    @model.commit_operation
    update_dialog()
  end

  def delete_hideshow(p)
    puts "delete_hideshow #{@component} #{p}" if SU2XPlane::TraceEvents
    return close() if !@model.valid?	# model was closed on Mac
    @model.start_operation(XPL10n.t('Erase Hide / Show'), true)
    oldhs=p.to_i
    numhs=count_hideshow()-1
    # shift everything down
    oldhs.upto(numhs-1) do |hs|
      prefix=SU2XPlane::ANIM_HS_+hs.to_s
      other=SU2XPlane::ANIM_HS_+(hs+1).to_s
      @component.set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_HIDESHOW, @component.get_attribute(SU2XPlane::ATTR_DICT, other+SU2XPlane::ANIM_HS_HIDESHOW))
      @component.set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_DATAREF,  @component.get_attribute(SU2XPlane::ATTR_DICT, other+SU2XPlane::ANIM_HS_DATAREF))
      @component.set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_INDEX,    @component.get_attribute(SU2XPlane::ATTR_DICT, other+SU2XPlane::ANIM_HS_INDEX))
      @component.set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_FROM,     @component.get_attribute(SU2XPlane::ATTR_DICT, other+SU2XPlane::ANIM_HS_FROM))
      @component.set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_TO,       @component.get_attribute(SU2XPlane::ATTR_DICT, other+SU2XPlane::ANIM_HS_TO))
    end
    prefix=SU2XPlane::ANIM_HS_+numhs.to_s
    dict=@component.attribute_dictionary(SU2XPlane::ATTR_DICT)
    dict.delete_key(prefix+SU2XPlane::ANIM_HS_HIDESHOW)
    dict.delete_key(prefix+SU2XPlane::ANIM_HS_DATAREF)
    dict.delete_key(prefix+SU2XPlane::ANIM_HS_INDEX)
    dict.delete_key(prefix+SU2XPlane::ANIM_HS_FROM)
    dict.delete_key(prefix+SU2XPlane::ANIM_HS_TO)
    @model.commit_operation
    update_dialog()
  end

  def can_preview()
    inorder=(@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_DATAREF) != '')
    frame=1
    while inorder
      val=@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+frame.to_s)
      if val==nil then break end
      if val.to_f <= @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+(frame-1).to_s).to_f then inorder=false end
      frame+=1
    end
    loop=@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_LOOP)
    return inorder && frame>=2 && (loop=='' || loop.to_f>0.0)
  end

  def preview(p)
    return close() if !@model.valid?	# model was closed on Mac
    return if not can_preview()
    prop=p.to_f	# 0->1
    numframes=count_frames()
    loop=@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_LOOP).to_f
    if loop>0.0
      range_start=0.0
      range_stop=loop
    else
      range_start=@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+'0').to_f
      range_stop=@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+(numframes-1).to_s).to_f
    end
    val=range_start+(range_stop-range_start)*prop	# dataref value
    trans = @component.XPInterpolated(val)
    if merge_operation?("#{@component.object_id}/preview")
      # even if we merge this operation with previous it still uses up the Undo stack. So use move! which doesn't affect the Undo stack
      @component.move!(trans)
      @model.active_view.refresh	# move! doesn't cause redraw
    else
      @model.start_operation(XPL10n.t('Preview Animation'), true)
      @component.transformation = trans
      @model.commit_operation
    end
    @dlg.execute_script("document.getElementById('preview-value').innerHTML='#{('%.6g' % val).tr('.',DecimalSep)}'")
  end

  def erase()
    @model.start_operation(XPL10n.t('Erase Animation'), true)
    # Tempting to just do attribute_dictionaries.delete(SU2XPlane::ATTR_DICT), but that woudld erase other attributes like Alpha etc
    dict=@component.attribute_dictionary(SU2XPlane::ATTR_DICT)
    0.upto(count_frames()) do |frame|
      dict.delete_key(SU2XPlane::ANIM_FRAME_+frame.to_s)
      dict.delete_key(SU2XPlane::ANIM_MATRIX_+frame.to_s)
    end
    dict.delete_key(SU2XPlane::ANIM_DATAREF)
    dict.delete_key(SU2XPlane::ANIM_INDEX)

    0.upto(count_hideshow()) do |hs|
      prefix=SU2XPlane::ANIM_HS_+hs.to_s
      dict.delete_key(prefix+SU2XPlane::ANIM_HS_HIDESHOW)
      dict.delete_key(prefix+SU2XPlane::ANIM_HS_DATAREF)
      dict.delete_key(prefix+SU2XPlane::ANIM_HS_INDEX)
      dict.delete_key(prefix+SU2XPlane::ANIM_HS_FROM)
      dict.delete_key(prefix+SU2XPlane::ANIM_HS_TO)
    end
    close()
    @model.commit_operation
  end

end


def XPlaneMakeAnimation()
  modified=false
  model=Sketchup.active_model
  ss = model.selection
  if ss.empty?
    return
  elsif ss.count==1 and ss.first.typename=='ComponentInstance'
    component=ss.first
  else
    # Make a new component as the basis for animation
    model.start_operation(XPL10n.t('Animate'), true)
    modified=true
    if ss.count==1 and ss.first.typename=='Group'
      # Convert selected group
      name=ss.first.name
      component=ss.first.to_component
      component.name=name
    else
      # Make a new component out of whatever was selected
      component=model.active_entities.add_group(ss).to_component	# add_group is crashy but we should be OK since selection is subset of the active_model
    end
    component.definition.name=XPL10n.t('Component')+'#1'		# Otherwise has name Group#n. SketchUp will uniquify.
    model.selection.add(component)
  end
  
  if component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_DATAREF)==nil
    # We have a pre-existing or new component. In either case set a minimal set of values.
    if !modified
      model.start_operation(XPL10n.t('Animate'), true)
      modified=true
    end
    t=component.transformation.to_a
    trans=model.edit_transform.inverse * component.transformation * Geom::Transformation.scaling(1/Math::sqrt(t[0]*t[0]+t[1]*t[1]+t[2]*t[2]), 1/Math::sqrt(t[4]*t[4]+t[5]*t[5]+t[6]*t[6]), 1/Math::sqrt(t[8]*t[8]+t[9]*t[9]+t[10]*t[10]))
    component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_DATAREF, '')
    component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_INDEX, '')
    component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+'0', '0.0')
    component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+'0', trans.to_a)
    component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+'1', '1.0')
    component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+'1', trans.to_a)
    component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_LOOP, '')
  end

  if modified
    model.commit_operation
  end

  if XPlaneAnimation.instances.include?(component)
    # An animation dialog for this component already exists
    XPlaneAnimation.instances[component].update_dialog
    XPlaneAnimation.instances[component].dlg.bring_to_front
  else
    XPlaneAnimation.new(component, model)
  end

end


#
# Implement 1.9 round() functionality in 1.8
#
if Float.instance_method(:round).arity == 0
  class Float
    alias_method :oldround, :round
    def round(ndigits=0)
      factor = 10.0**ndigits
      if ndigits > 0
        return (self*factor).oldround / factor
      else
        return ((self*factor).oldround / factor).to_i	# return Integer if ndigits<=0
      end
    end
  end

  class Fixnum
    def round(ndigits=0)
      self.to_f.round(ndigits)
    end
  end
end


#
# Extend Transformation with accessors
#
class Geom::Transformation

  def XPEuler(forceme = false)
    # returns same as [rotx, roty, rotz], but returns Float radians not Integer degrees
    # http://www.soi.city.ac.uk/~sbbh653/publications/euler.pdf
    # http://sketchucation.com/forums/viewtopic.php?t=22639
    m = self.xaxis.to_a + self.yaxis.to_a + self.zaxis.to_a		# 3x3 rotation matrix, rescaled to identity
    if m[6].abs==1 && !forceme	# gimbal lock
      return nil		# don't know which of the two possible solutions to use
    elsif m[6] == -1
      rz = 0			# arbitrary
      ry = Math::PI/2
      rx = rz + Math.atan2(m[1],m[2])
    elsif m[6] == 1
      rz = 0			# arbitrary
      ry = -Math::PI/2
      rx = -rz + Math.atan2(-m[1],-m[2])
    else
      ry = -Math.asin(m[6])	# solution 1 in above pdf
      cry= Math.cos(ry)
      rx = Math.atan2(m[7]/cry, m[8]/cry)
      rz = Math.atan2(m[3]/cry, m[0]/cry)
    end
    return [-rx, -ry, -rz]	# X-Plane is CCW
  end

  if not Geom::Transformation.method_defined? :determinant
    def determinant
      t=self.to_a
      fail if t[3]!=0 or t[7]!=0 or t[11]!=0	# Assume transformation has no projection, so only need to calculate top left 3x3 portion
      t[0]*t[5]*t[10] - t[0]*t[6]*t[9] - t[1]*t[4]*t[10] + t[1]*t[6]*t[8] + t[2]*t[4]*t[9] - t[2]*t[5]*t[8]
    end
  end

  def inspect
    # pretty print, converting translation to m
    t=self.to_a
    return "[%10.6f %10.6f %10.6f %5.1f\n %10.6f %10.6f %10.6f %5.1f\n %10.6f %10.6f %10.6f %5.1f\n %10.6f %10.6f %10.6f %5.1f ]" % (t[0,12] + t[12,3].map { |d| d.to_m } + [t[15]])
  end

end


#
# Extend ComponentInstance with animation accessors.
# Logic is similar to XPlaneAnimation above, except return values are truncated to output precision etc
#
class Sketchup::ComponentInstance

  def XPDataRef
    # returns DataRef, w/ index if any
    dataref=get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_DATAREF)
    return nil if !dataref || dataref==''
    index=get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_INDEX)
    dataref = dataref+'['+index+']' if index and index!=''
    return dataref
  end

  def XPDataRef=(dataref)
    self.name=dataref.split('/').last
    index=dataref.index('[')
    if index
      set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_INDEX, dataref[(index+1...-1)])
      dataref=dataref[(0...index)]
    end
    set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_DATAREF, dataref)
  end

  def XPCountFrames
    numframes=0
    while get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+numframes.to_s) do numframes+=1 end
    return numframes
  end

  def XPTransformation(frame)
    return Geom::Transformation.new(get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s))
  end

  def XPValues
    return [] if !self.XPDataRef
    retval=[]
    (0...self.XPCountFrames).each do |frame|
      retval << get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+frame.to_s)
    end
    return retval
  end

  def XPGetValue(frame)
    get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+frame.to_s)
  end

  def XPSetValue(frame, value)
    set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+frame.to_s, value.to_s)
  end

  def XPLoop
    return '0' if !self.XPDataRef
    get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_LOOP)
  end

  def XPLoop=(loop)
    set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_LOOP, loop.to_s)
  end

  def XPRotations(trans=Geom::Transformation.new)
    # Returns Array of transformations converted to rotations about x, y, z axis
    # SketchUp returns squirrely transformations for rotations >= 180, so work out each rotation relative to previous
    numframes=self.XPCountFrames
    return [] if !self.XPDataRef || numframes==0
    lastval = (trans * XPTransformation(0)).XPEuler(true).map{ |a| a.radians }
    # p "0 #{lastval.map{|a|a.round(SU2XPlane::P_A)}.inspect}"
    retval = [lastval]
    (1...numframes).each do |frame|
      thistrans = trans * XPTransformation(frame-1).inverse * XPTransformation(frame)	# rotation since previous frame
      if thistrans.XPEuler
        thisval = thistrans.XPEuler.map{ |a| a.radians }
      elsif	# gimbal lock - need to interpolate if we can
        v = (trans * Geom::Transformation.interpolate(XPTransformation(frame-1), XPTransformation(frame), 0.5)).XPEuler
        if v
          thisval = v.map{ |a| a.radians * 2 }
        else
          thisval = thistrans.XPEuler(true).map{ |a| a.radians }
        end
      end
      lastval = lastval.zip(thisval).map{ |p| p[0] + (p[1]+180)%360 - 180 }	# cumulative with previous frame, no more than 180
      # p "#{frame} #{(trans*XPTransformation(frame)).XPEuler(true).map{|a|a.radians.round(SU2XPlane::P_A)}.inspect} #{thisval.map{|a|a.round(SU2XPlane::P_A)}.inspect} #{lastval.map{|a|a.round(SU2XPlane::P_A)}.inspect}"
      retval << lastval
    end
    # p retval.map { |r| r.map { |a| a.round(SU2XPlane::P_A) } }
    return retval.map { |r| r.map { |a| a.round(SU2XPlane::P_A) } }	# round at end to prevent comparision differences
  end

  def XPRotateFrame(frame, v, a)
    # Apply rotation, cumulative with any previously applied.
    # Use current transformation origin as centre of rotation if no existing animation for this frame.
    current = (get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s) ? Geom::Transformation.new(get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s)) : transformation)
    set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s, (Geom::Transformation.rotation(current.origin, v, a) * current).to_a)
  end

  def XPTranslations(trans=Geom::Transformation.new)
    return [] if !self.XPDataRef
    retval=[]
    (0...self.XPCountFrames).each do |frame|
      retval << (trans * Geom::Transformation.new(get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s))).origin.to_a.map { |v| v.round(SU2XPlane::P_V) }
    end
    return retval
  end

  def XPTranslateFrame(frame, v)
    # Assumes that no transformation exists for this frame (or can be overwritten).
    set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s, Geom::Transformation.translation(v).to_a)
  end

  def XPInterpolated(val)
    # Retun interpolated transformation for val. Assumes that component has at least two frames.
    model=Sketchup.active_model
    key_stop=0
    while true
      key=get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+(key_stop).to_s)
      if key==nil
        key_stop-=1	# extrapolate after
        break
      elsif key.to_f > val
        break
      end
      key_stop+=1
    end
    if key_stop==0 then key_stop=1 end	# extrapolate before
    key_start=key_stop-1
    val_start=get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+(key_start).to_s).to_f
    val_stop =get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+(key_stop).to_s).to_f
    interp= (val - val_start) / (val_stop - val_start)
    trans = (model.active_entities.include?(self) ? model.edit_transform : Geom::Transformation.new) *
      Geom::Transformation.interpolate(get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+key_start.to_s),
                                       get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+key_stop.to_s),
                                       interp)	# may not be unit scale if (grand)parent scaled
    trans *= Geom::Transformation.scaling(transformation.xscale/trans.xscale, transformation.yscale/trans.yscale, transformation.zscale/trans.zscale)	# preserve scale
    puts "preview #{val} #{interp}", trans.inspect if SU2XPlane::TraceEvents
    return trans
  end

  def XPCountHideShow()
    numhs=0
    while get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_HS_+numhs.to_s+SU2XPlane::ANIM_HS_HIDESHOW) do numhs+=1 end
    return numhs
  end

  def XPHideShow
    # returns Array of HideShow values ['hide'/'show', dataref, from, to]
    retval=[]
    numhs=0
    while true
      prefix=SU2XPlane::ANIM_HS_+numhs.to_s
      numhs+=1
      hs=get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_HIDESHOW)
      break if !hs
      dataref=get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_DATAREF)
      next if !dataref || dataref==''
      index=get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_INDEX)
      dataref+=('['+index+']') if index and index!=''
      retval << [hs, dataref, get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_FROM), get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_TO)]
    end
    return retval
  end

  def XPAddHideShow(hs, dataref, from, to)
    self.name = dataref.split('/').last if self.name.empty?
    numhs=0
    prefix=''
    while true
      prefix=SU2XPlane::ANIM_HS_+numhs.to_s
      break if !get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_HIDESHOW)
      numhs+=1
    end
    set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_HIDESHOW, hs)
    index=dataref.index('[')
    if index
      set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_INDEX, dataref[(index+1...-1)])
      dataref=dataref[(0...index)]
    end
    set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_DATAREF, dataref)
    set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_FROM, from.to_s)
    set_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_TO, to.to_s)
  end

end
