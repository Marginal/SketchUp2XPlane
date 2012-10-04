class XPlaneModelObserver < Sketchup::ModelObserver

  def initialize(parent)
    @parent=parent
  end

  def onTransactionUndo(model)	# from ModelObserver
    # Don't know what's being undone, so just always update dialog
    @parent.update_dialog()
  end

  def onTransactionRedo(model)	# from ModelObserver
    # Don't know what's being redone, so just always update dialog
    @parent.update_dialog()
  end

end

class XPlaneAnimation < Sketchup::EntityObserver

  def initialize(component)
    @component=component
    if @component.typename!='ComponentInstance' then fail end
    @lastsetvar=nil
    if Object::RUBY_PLATFORM =~ /darwin/i
      @dlg = UI::WebDialog.new("X-Plane Animation", true, "SU2XPA", 374, 600)
    else
      @dlg = UI::WebDialog.new("X-Plane Animation", true, "SU2XPA", 400, 650)
    end
    @dlg.allow_actions_from_host("getfirebug.com")	# for debugging on Windows
    @dlg.allow_actions_from_host("www.frequency-decoder.com")	# for debugging on Windows
    @dlg.set_file(Sketchup.find_support_file('SU2XPlane', 'Plugins') + "/anim.html")
    @dlg.add_action_callback("on_load") { |d,p| update_dialog }
    @dlg.add_action_callback("on_close") {|d,p| @dlg.close }
    @dlg.add_action_callback("on_set_var") { |d,p| set_var(p) }
    @dlg.add_action_callback("on_set_position") { |d,p| set_position(p) }
    @dlg.add_action_callback("on_insert_frame") { |d,p| insert_frame(p) }
    @dlg.add_action_callback("on_delete_frame") { |d,p| delete_frame(p) }
    @dlg.add_action_callback("on_preview") { |d,p| preview(p) }
    @component.add_observer(self)
    @modelobserver=XPlaneModelObserver.new(self)
    Sketchup.active_model.add_observer(@modelobserver)
    @dlg.set_on_close { @component.remove_observer(self); Sketchup.active_model.remove_observer(@modelobserver) }
    @dlg.show
    @dlg.bring_to_front
  end

  def count_frames()
    # Recalculate frame count very time we need the value in case component has been modified elsewhere
    numframes=0
    while @component.get_attribute(SU2XPlane::DYNAMIC_DICT, "frame#{numframes}") != nil do numframes+=1 end
    return numframes
  end

  def update_dialog()
    # Remaining initialization, deferred 'til DOM is ready via window.onload
    @lastsetvar=nil
    if @component.name!=""
      @dlg.execute_script("document.getElementById('title').innerHTML='#{@component.name}'")
    else
      @dlg.execute_script("document.getElementById('title').innerHTML='#{@component.definition.name}'")
    end
    @dlg.execute_script("document.form.dataref.value='#{@component.get_attribute(SU2XPlane::DYNAMIC_DICT, "dataref")}'")
    @dlg.execute_script("document.form.dataref_index.value='#{@component.get_attribute(SU2XPlane::DYNAMIC_DICT, "dataref_index")}'")

    @dlg.execute_script("resetKeyframes()")
    numframes=count_frames()
    hasdeleter = numframes>2 ? "true" : "false"
    val=0
    valsinorder=true
    for keyframe in 0...numframes
      newval=@component.get_attribute(SU2XPlane::DYNAMIC_DICT, 'frame'+keyframe.to_s).to_f
      if keyframe>0
        valsinorder=valsinorder and newval>=val
      end
      val=newval
      @dlg.execute_script("addInserter(#{keyframe})")
      @dlg.execute_script("addKeyframe(#{keyframe}, \"#{val}\", #{hasdeleter})")
    end
    @dlg.execute_script("addInserter(#{numframes})")
    @dlg.execute_script("addLoop(\"#{@component.get_attribute(SU2XPlane::DYNAMIC_DICT, 'loop', '')}\")")
    disable=!can_preview()
    @dlg.execute_script("document.getElementById('preview-slider').disabled=#{disable}")
    @dlg.execute_script("fdSlider."+(disable ? "disable" : "enable")+"('preview-slider')")

    @dlg.execute_script("window.location='#top'")	# Force redisplay - required on Mac
  end

  def onEraseEntity(entity)	# from EntityObserver
    # destroy ourselves if the component instance that we are animating is deleted
    @dlg.close
  end

  def set_var(p)
    setvar=@component.definition.name+'/'+p
    model=Sketchup.active_model
    model.start_operation('DataRef value', true, false, setvar==@lastsetvar)	# merge into last if setting same var again
    @component.set_attribute SU2XPlane::DYNAMIC_DICT, p, @dlg.get_element_value(p).strip
    model.commit_operation
    @lastsetvar=setvar
    disable=!can_preview()
    @dlg.execute_script("document.getElementById('preview-slider').disabled=#{disable}")
    @dlg.execute_script("fdSlider."+(disable ? "disable" : "enable")+"('preview-slider')")
    @dlg.execute_script("document.getElementById('preview-value').innerHTML=''")	# reset preview display since may no longer be accurate
  end

  def set_position(p)
    model=Sketchup.active_model
    model.start_operation("Keyframe #{p} position", true)
    @component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_ANIM_TRANS+p, @component.transformation.to_a)
    model.commit_operation
    @lastsetvar=nil
  end

  def insert_frame(p)
    model=Sketchup.active_model
    model.start_operation("Insert Keyframe #{p}", true)
    newframe=p.to_i
    numframes=count_frames()
    # shift everything up
    numframes.downto(newframe+1) do |frame|
      @component.set_attribute SU2XPlane::DYNAMIC_DICT, "frame#{frame}", @component.get_attribute(SU2XPlane::DYNAMIC_DICT, "frame#{frame-1}")
      @component.set_attribute SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_ANIM_TRANS+frame.to_s, @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_ANIM_TRANS+(frame-1).to_s)
    end
    # use current transformation for inserted frame
    @component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_ANIM_TRANS+newframe.to_s, @component.transformation.to_a)
    # add dynamic blurb for last frame
    @component.set_attribute SU2XPlane::DYNAMIC_DICT, "frame#{numframes}", 1.0
    @component.set_attribute SU2XPlane::DYNAMIC_DICT, "_frame#{numframes}_access", 'TEXTBOX'
    @component.set_attribute SU2XPlane::DYNAMIC_DICT, "_frame#{numframes}_formlabel", "Value at Keyframe ##{numframes}"
    @component.set_attribute SU2XPlane::DYNAMIC_DICT, "_frame#{numframes}_label", "Frame#{numframes}"
    @component.set_attribute SU2XPlane::DYNAMIC_DICT, "_frame#{numframes}_units", 'FLOAT'
    model.commit_operation
    update_dialog()
  end

  def delete_frame(p)
    model=Sketchup.active_model
    model.start_operation("Delete Keyframe #{p}", true)
    oldframe=p.to_i
    numframes=count_frames()-1
    # shift everything down
    oldframe.upto(numframes-1) do |frame|
      @component.set_attribute SU2XPlane::DYNAMIC_DICT, "frame#{frame}", @component.get_attribute(SU2XPlane::DYNAMIC_DICT, "frame#{frame+1}")
      @component.set_attribute SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_ANIM_TRANS+frame.to_s, @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_ANIM_TRANS+(frame+1).to_s)
    end
    Sketchup.active_model.selection.first.attribute_dictionary(SU2XPlane::ATTR_DICT).delete_key(SU2XPlane::ATTR_ANIM_TRANS+numframes.to_s)
    Sketchup.active_model.selection.first.attribute_dictionary(SU2XPlane::DYNAMIC_DICT).delete_key("frame#{numframes}")
    Sketchup.active_model.selection.first.attribute_dictionary(SU2XPlane::DYNAMIC_DICT).delete_key("_frame#{numframes}_access")
    Sketchup.active_model.selection.first.attribute_dictionary(SU2XPlane::DYNAMIC_DICT).delete_key("_frame#{numframes}_formlabel")
    Sketchup.active_model.selection.first.attribute_dictionary(SU2XPlane::DYNAMIC_DICT).delete_key("_frame#{numframes}_label")
    Sketchup.active_model.selection.first.attribute_dictionary(SU2XPlane::DYNAMIC_DICT).delete_key("_frame#{numframes}_units")
    model.commit_operation
    update_dialog()
  end

  def can_preview()
    # determine if previewable - i.e. dataref values are in order
    inorder=true
    frame=1
    while true
      val=@component.get_attribute(SU2XPlane::DYNAMIC_DICT, "frame#{frame}")
      if val==nil then break end
      if val.to_f < @component.get_attribute(SU2XPlane::DYNAMIC_DICT, "frame#{frame-1}").to_f
        inorder=false
        break
      end
      frame+=1
    end
    loop=@component.get_attribute(SU2XPlane::DYNAMIC_DICT, 'loop')
    return inorder && frame>=2 && (loop=='' || loop.to_f>0.0)
  end

  def preview(p)
    if not can_preview() then return end
    setvar=@component.definition.name+'/transformation'
    model=Sketchup.active_model
    model.start_operation('Preview Animation', true, false, setvar==@lastsetvar)	# merge into last if previewing again
    prop=p.to_f	# 0->1
    numframes=count_frames()
    loop=@component.get_attribute(SU2XPlane::DYNAMIC_DICT, 'loop').to_f
    if loop>0.0
      range_start=0.0
      range_stop=loop
    else
      range_start=@component.get_attribute(SU2XPlane::DYNAMIC_DICT, 'frame0').to_f
      range_stop=@component.get_attribute(SU2XPlane::DYNAMIC_DICT, "frame#{numframes-1}").to_f
    end
    val=range_start+(range_stop-range_start)*prop	# dataref value
    key_stop=0
    while true
      key=@component.get_attribute(SU2XPlane::DYNAMIC_DICT, "frame#{key_stop}")
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
    val_start=@component.get_attribute(SU2XPlane::DYNAMIC_DICT, "frame#{key_start}").to_f
    val_stop =@component.get_attribute(SU2XPlane::DYNAMIC_DICT, "frame#{key_stop}").to_f
    interp= (val - val_start) / (val_stop - val_start)
    @component.transformation=
      Geom::Transformation.interpolate(@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_ANIM_TRANS+key_start.to_s),
                                       @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_ANIM_TRANS+key_stop.to_s),
                                       interp)
    model.commit_operation
    @lastsetvar=setvar
    @dlg.execute_script("document.getElementById('preview-value').innerHTML='%.6g'" % val)
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
    model.start_operation('Create X-Plane Animation', true)
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
    component.definition.name='Animation'	# Otherwise has name Group#n
  end
  
  if component.get_attribute(SU2XPlane::DYNAMIC_DICT, 'summary')!='X-Plane Animation'
    # We have a pre-existing or new component. In either case set a minimal set of values.
    if !modified
      model.start_operation('Create X-Plane Animation', true)
    end
    modified=true

    component.set_attribute SU2XPlane::DYNAMIC_DICT, 'summary', 'X-Plane Animation'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, 'description', 'You can make this component (and any children) animate in X-Plane according to the value of one of the simulator DataRefs of type "int", "float" or "double" listed <a href="http://www.xsquawkbox.net/xpsdk/docs/DataRefs.html">here</a>.<br>DataRefs listed with "[<i>n</i>]" after their type are arrays; you will need to also supply an Index value for these.'

    component.set_attribute SU2XPlane::DYNAMIC_DICT, 'dataref', 'none'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_dataref_access', 'TEXTBOX'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_dataref_formlabel', 'DataRef Name'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_dataref_label', 'DataRef'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_dataref_units', 'STRING'

    component.set_attribute SU2XPlane::DYNAMIC_DICT, 'dataref_index', ''
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_dataref_index_access', 'TEXTBOX'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_dataref_index_formlabel', 'DataRef Index'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_dataref_index_label', 'DataRefIndex'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_dataref_index_units', 'INTEGER'

    component.set_attribute SU2XPlane::DYNAMIC_DICT, 'frame0', '0.0'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_frame0_access', 'TEXTBOX'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_frame0_formlabel', 'Value at Keyframe #0'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_frame0_label', 'Frame0'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_frame0_units', 'FLOAT'
    component.set_attribute SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_ANIM_TRANS+'0', component.transformation.to_a

    component.set_attribute SU2XPlane::DYNAMIC_DICT, 'frame1', '1.0'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_frame1_access', 'TEXTBOX'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_frame1_formlabel', 'Value at Keyframe #1'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_frame1_label', 'Frame1'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_frame1_units', 'FLOAT'
    component.set_attribute SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_ANIM_TRANS+'1', component.transformation.to_a

    component.set_attribute SU2XPlane::DYNAMIC_DICT, 'loop', ''
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_loop_access', 'TEXTBOX'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_loop_formlabel', 'Loop divisor'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_loop_label', 'Loop'
    component.set_attribute SU2XPlane::DYNAMIC_DICT, '_loop_units', 'FLOAT'
  end

  if modified
    model.commit_operation
  end

  XPlaneAnimation.new(component)

end
