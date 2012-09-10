def XPlaneToggleAttr(attr)
  ss = Sketchup.active_model.selection
  if ss.count>=1
    newval=1-ss.first.get_attribute(SU2XPlane::ATTR_DICT, attr, 0)
    ss.each do |ent|
      ent.set_attribute(SU2XPlane::ATTR_DICT, attr, newval) if ent.typename=="Face"
    end
  end
end

def XPlaneValidateAttr(attr)
  ss = Sketchup.active_model.selection
  return MF_GRAYED if ss.count==0 or ss.first.typename!="Face"
  val=ss.first.get_attribute(SU2XPlane::ATTR_DICT, attr, 0)
  # Gray out if multiple selected with different values
  ss.each do |ent|
    return MF_GRAYED if ent.typename!="Face"
    return MF_GRAYED|MF_CHECKED if ent.get_attribute(SU2XPlane::ATTR_DICT, attr, 0)!=val
  end
  if val!=0
    return MF_CHECKED
  else
    return MF_UNCHECKED
  end
end
