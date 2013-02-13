def XPlaneToggleAttr(attr)
  newval = (XPlaneValidateAttr(attr)!=MF_CHECKED)
  if newval
    Sketchup.active_model.selection.each do |ent|
      ent.set_attribute(SU2XPlane::ATTR_DICT, attr, 1) if ent.typename=="Face"	# 1 for backwards compatibility
    end
  else
    Sketchup.active_model.selection.each do |ent|
      ent.delete_attribute(SU2XPlane::ATTR_DICT, attr) if ent.typename=="Face"
    end
  end
end

# Return MF_GRAYED if any Components/Groups selected (but ignore Edges)
# Can't do anything useful/reasonable if only some faces have this attribute (used to return MF_GRAYED|MF_CHECKED),
# so return MF_CHECKED if *all* selected Faces have this attribute, otherwise MF_UNCHECKED.
def XPlaneValidateAttr(attr)
  ss = Sketchup.active_model.selection
  return MF_GRAYED if ss.empty?
  ss.each do |ent|
    next if ent.typename=="Edge"
    return MF_GRAYED if ent.typename!="Face"
    return MF_UNCHECKED if ent.get_attribute(SU2XPlane::ATTR_DICT, attr, 0)==0
  end
  return MF_CHECKED
end
