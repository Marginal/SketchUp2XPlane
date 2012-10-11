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

  def onDeleteModel(model)
    # This doesn't fire on closing the model, so currently worthless. Maybe it will work in the future.
    @parent.close()
  end

end


class XPlaneAnimation < Sketchup::EntityObserver

  @@dlgs={}	# map components to open dialogs

  def initialize(component)
    @component=component
    if @component.typename!='ComponentInstance' then fail end
    @lastaction=nil	# Record last change to the component for the purpose of merging Undo steps
    @myaction=false	# Record other changes made to the component so we don't merge those in to our Undo steps
    if Object::RUBY_PLATFORM =~ /darwin/i
      @dlg = UI::WebDialog.new("X-Plane Animation", true, "SU2XPA", 374, 500)
    else
      @dlg = UI::WebDialog.new("X-Plane Animation", true, "SU2XPA", 396, 640)
    end
    @@dlgs[@component]=@dlg
    @dlg.allow_actions_from_host("getfirebug.com")	# for debugging on Windows
    @dlg.set_file(Sketchup.find_support_file('SU2XPlane', 'Plugins') + "/anim.html")
    @dlg.add_action_callback("on_load") { |d,p| update_dialog }
    @dlg.add_action_callback("on_close") {|d,p| close }
    @dlg.add_action_callback("on_add_child") { |d,p| add_child }
    @dlg.add_action_callback("on_set_var") { |d,p| set_var(p) }
    @dlg.add_action_callback("on_set_transform") { |d,p| set_transform(p) }
    @dlg.add_action_callback("on_get_transform") { |d,p| get_transform(p) }
    @dlg.add_action_callback("on_insert_frame") { |d,p| insert_frame(p) }
    @dlg.add_action_callback("on_delete_frame") { |d,p| delete_frame(p) }
    @dlg.add_action_callback("on_insert_hideshow") { |d,p| insert_hideshow(p) }
    @dlg.add_action_callback("on_delete_hideshow") { |d,p| delete_hideshow(p) }
    @dlg.add_action_callback("on_preview") { |d,p| preview(p) }
    @component.add_observer(self)
    @modelobserver=XPlaneModelObserver.new(self)
    Sketchup.active_model.add_observer(@modelobserver)
    @dlg.set_on_close {
      begin @component.remove_observer(self) rescue TypeError end
      Sketchup.active_model.remove_observer(@modelobserver)
      @@dlgs.delete(@component)
    }
    @dlg.show
    @dlg.bring_to_front
  end

  def XPlaneAnimation.dlgs()
    return @@dlgs
  end

  def close()
    @dlg.close
  end

  def count_frames()
    # Recalculate frame count very time we need the value in case component has been modified elsewhere
    numframes=0
    while @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+numframes.to_s) != nil do numframes+=1 end
    return numframes
  end

  def count_hideshow()
    # Recalculate hideshow count very time we need the value in case component has been modified elsewhere
    numhs=0
    while @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_HS_+numhs.to_s+SU2XPlane::ANIM_HS_HIDESHOW) != nil do numhs+=1 end
    return numhs
  end

  def update_dialog()
    # Remaining initialization, deferred 'til DOM is ready via window.onload
    begin
      if @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_DATAREF)==nil
        # User has undone creation of animation attributes
        close()
        return
      end
    rescue TypeError
      # User has undone creation of animation component -> underlying @component object has been deleted.
      return	#  Ignore and wait for onEraseEntity
    end
    @dlg.execute_script("resetDialog('#{@component.name!='' ? @component.name : @component.definition.name}', '#{@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_DATAREF)}', '#{@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_INDEX)}')")

    numframes=count_frames()
    hasdeleter = numframes>2 ? "true" : "false"
    for frame in 0...numframes
      @dlg.execute_script("addFrameInserter(#{frame})")
      @dlg.execute_script("addKeyframe(#{frame}, '#{@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+frame.to_s)}', #{hasdeleter})")
    end
    @dlg.execute_script("addFrameInserter(#{numframes})")
    @dlg.execute_script("addLoop('#{@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_LOOP)}')")
    disable=!can_preview()
    @dlg.execute_script("document.getElementById('preview-slider').disabled=#{disable}")
    @dlg.execute_script("fdSlider."+(disable ? "disable" : "enable")+"('preview-slider')")

    hideshow=0
    while true
      prefix=SU2XPlane::ANIM_HS_+hideshow.to_s
      hs=@component.get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_HIDESHOW)
      if hs==nil then break end
      @dlg.execute_script("addHSInserter(#{hideshow})")
      @dlg.execute_script("addHideShow(#{hideshow}, '#{@component.get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_HIDESHOW)}', '#{@component.get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_DATAREF)}', '#{@component.get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_INDEX)}', '#{@component.get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_FROM)}', '#{@component.get_attribute(SU2XPlane::ATTR_DICT, prefix+SU2XPlane::ANIM_HS_TO)}')")
      hideshow+=1
    end
    @dlg.execute_script("addHSInserter(#{hideshow})")

    @dlg.execute_script("window.location='#top'")	# Force redisplay - required on Mac
    @lastaction=nil
  end

  def onChangeEntity(entity)	# from EntityObserver
    # destroy ourselves if the component instance that we are animating is deleted
    if @myaction
      # This change was caused by me
      @myaction=false
    else
      # This change was caused by other editing - don't merge later Undo steps with it
      @lastaction=nil
    end
  end

  def start_operation(op_name, action)
    # Merge this operation into last if performing same action again. If action==false don't merge even if it is the same action.
    Sketchup.active_model.start_operation(op_name, true, false, action==@lastaction)
    @lastaction = (action==false ? nil : action)
  end

  def commit_operation()
    @myaction=true	# This change was caused by me
    Sketchup.active_model.commit_operation
  end

  def onEraseEntity(entity)	# from EntityObserver
    # destroy ourselves if the component instance that we are animating is deleted
    close()
  end

  def set_var(p)
    start_operation('Animation value', "#{@component.object_id}/#{p}")	# merge into last if setting same var again
    @component.set_attribute(SU2XPlane::ATTR_DICT, p, @dlg.get_element_value(p).strip)
    commit_operation
    disable=!can_preview()
    @dlg.execute_script("document.getElementById('preview-slider').disabled=#{disable}")
    @dlg.execute_script("fdSlider."+(disable ? "disable" : "enable")+"('preview-slider')")
    @dlg.execute_script("document.getElementById('preview-value').innerHTML=''")	# reset preview display since may no longer be accurate
  end

  def set_transform(p)
    start_operation("Set Position", "#{@component.object_id}/"+SU2XPlane::ANIM_MATRIX_+p)	# merge into last if setting same transformation again
    model=Sketchup.active_model
    # X-Plane doesn't allow scaling, and SketchUp doesn't handle it in interpolation. So reset scale before saving transformation.
    #puts @component.transformation.to_a.join(' '), @component.transformation.origin, @component.transformation.xaxis, @component.transformation.yaxis, @component.transformation.zaxis
    t=@component.transformation.to_a
    @component.transformation=@component.transformation*Geom::Transformation.scaling(1/Math::sqrt(t[0]*t[0]+t[1]*t[1]+t[2]*t[2]), 1/Math::sqrt(t[4]*t[4]+t[5]*t[5]+t[6]*t[6]), 1/Math::sqrt(t[8]*t[8]+t[9]*t[9]+t[10]*t[10]))
    #puts @component.transformation.to_a.join(' '), @component.transformation.origin, @component.transformation.xaxis, @component.transformation.yaxis, @component.transformation.zaxis
    @component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+p, @component.transformation.to_a)
    commit_operation
  end

  def get_transform(p)
    start_operation('Preview Animation', "#{@component.object_id}/preview")	# treat same as preview for the sake of Undo
    model=Sketchup.active_model
    @component.transformation=@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+p)
    #puts "Keyframe #{p}", @component.transformation.to_a.join(' '), @component.transformation.origin, @component.transformation.xaxis, @component.transformation.yaxis, @component.transformation.zaxis
    commit_operation
    @dlg.execute_script("document.getElementById('preview-value').innerHTML='%.6g'" % @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+p))
  end

  def insert_frame(p)
    start_operation("Keyframe", false)
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
    # use current transformation for inserted frame
    model=Sketchup.active_model
    t=@component.transformation.to_a
    @component.transformation=@component.transformation*Geom::Transformation.scaling(1/Math::sqrt(t[0]*t[0]+t[1]*t[1]+t[2]*t[2]), 1/Math::sqrt(t[4]*t[4]+t[5]*t[5]+t[6]*t[6]), 1/Math::sqrt(t[8]*t[8]+t[9]*t[9]+t[10]*t[10]))
    @component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+newframe.to_s, @component.transformation.to_a)
    commit_operation
    update_dialog()
  end

  def delete_frame(p)
    start_operation("Erase Keyframe", false)
    oldframe=p.to_i
    numframes=count_frames()-1
    # shift everything down
    oldframe.upto(numframes-1) do |frame|
      @component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+frame.to_s,  @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+(frame+1).to_s))
      @component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s, @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+(frame+1).to_s))
    end
    @component.attribute_dictionary(SU2XPlane::ATTR_DICT).delete_key(SU2XPlane::ANIM_FRAME_+numframes.to_s)
    @component.attribute_dictionary(SU2XPlane::ATTR_DICT).delete_key(SU2XPlane::ANIM_MATRIX_+numframes.to_s)
    commit_operation
    update_dialog()
  end

  def insert_hideshow(p)
    start_operation("Hide/Show", false)
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
    commit_operation
    update_dialog()
  end

  def delete_hideshow(p)
    start_operation("Erase Hide/Show", false)
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
    @component.attribute_dictionary(SU2XPlane::ATTR_DICT).delete_key(prefix+SU2XPlane::ANIM_HS_HIDESHOW)
    @component.attribute_dictionary(SU2XPlane::ATTR_DICT).delete_key(prefix+SU2XPlane::ANIM_HS_DATAREF)
    @component.attribute_dictionary(SU2XPlane::ATTR_DICT).delete_key(prefix+SU2XPlane::ANIM_HS_INDEX)
    @component.attribute_dictionary(SU2XPlane::ATTR_DICT).delete_key(prefix+SU2XPlane::ANIM_HS_FROM)
    @component.attribute_dictionary(SU2XPlane::ATTR_DICT).delete_key(prefix+SU2XPlane::ANIM_HS_TO)
    commit_operation
    update_dialog()
  end

  def can_preview()
    # determine if previewable - i.e. dataref values are in order
    inorder=(@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_DATAREF) != '')
    frame=1
    while inorder
      val=@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+frame.to_s)
      if val==nil then break end
      if val.to_f < @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+(frame-1).to_s).to_f then inorder=false end
      frame+=1
    end
    loop=@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_LOOP)
    return inorder && frame>=2 && (loop=='' || loop.to_f>0.0)
  end

  def preview(p)
    if not can_preview() then return end
    start_operation('Preview Animation', "#{@component.object_id}/preview")	# merge into last if previewing again
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
    key_stop=0
    while true
      key=@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+(key_stop).to_s)
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
    val_start=@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+(key_start).to_s).to_f
    val_stop =@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+(key_stop).to_s).to_f
    interp= (val - val_start) / (val_stop - val_start)
    @component.transformation=
      Geom::Transformation.interpolate(@component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+key_start.to_s),
                                       @component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+key_stop.to_s),
                                       interp)
    #puts "Keyframe #{key_start+interp}", @component.transformation.to_a.join(' '), @component.transformation.origin, @component.transformation.xaxis, @component.transformation.yaxis, @component.transformation.zaxis
    commit_operation
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
    model.start_operation('Animate', true)
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
  
  if component.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_DATAREF)==nil
    # We have a pre-existing or new component. In either case set a minimal set of values.
    if !modified
      model.start_operation('Animate', true)
    end
    modified=true
    t=component.transformation.to_a
    component.transformation=component.transformation*Geom::Transformation.scaling(1/Math::sqrt(t[0]*t[0]+t[1]*t[1]+t[2]*t[2]), 1/Math::sqrt(t[4]*t[4]+t[5]*t[5]+t[6]*t[6]), 1/Math::sqrt(t[8]*t[8]+t[9]*t[9]+t[10]*t[10]))
    component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_DATAREF, '')
    component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_INDEX, '')
    component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+'0', '0.0')
    component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+'0', component.transformation.to_a)
    component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_FRAME_+'1', '1.0')
    component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+'1', component.transformation.to_a)
    component.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_LOOP, '')
  end

  if modified
    model.commit_operation
  end

  if XPlaneAnimation.dlgs.include?(component)
    # An animation dialog for this component already exists
    XPlaneAnimation.dlgs[component].bring_to_front
  else
    XPlaneAnimation.new(component)
  end

end