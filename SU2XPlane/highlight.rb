def XPlaneHighlight()

  model=Sketchup.active_model
  materials=model.materials
  model.start_operation("Highlight Untextured", true)
  begin
    untextured=materials["XPUntextured"]
    if (not untextured) or (untextured.texture and untextured.texture.filename)
      untextured=materials.add("XPUntextured")
      untextured.color="Red"
    end
    untextured.alpha=1.0
    untextured.texture=nil

    reverse=materials["XPReverse"]
    if (not reverse) or (reverse.texture and reverse.texture.filename)
      reverse=materials.add("XPReverse")
      reverse.color="Magenta"
    end
    reverse.alpha=0
    reverse.texture=nil

    count=XPlaneHighlightFaces(model.entities, untextured, reverse)
    model.commit_operation
    UI.messagebox "All faces are textured", MB_OK,"X-Plane export" if count==0
  rescue
    model.abort_operation
  end

end


def XPlaneHighlightFaces(entities, untextured, reverse)

  count=0

  entities.each do |ent|

    case ent.typename

    when "ComponentInstance"
      count+=XPlaneHighlightFaces(ent.definition.entities, untextured, reverse)

    when "Group"
      count+=XPlaneHighlightFaces(ent.entities, untextured, reverse)

    when "Face"
      if not (ent.material and ent.material.texture and ent.material.texture.filename) and not (ent.back_material and ent.back_material.texture and ent.back_material.texture.filename)
	ent.material=untextured
	ent.back_material=reverse
	count+=1
      else
	ent.material=reverse if not (ent.material and ent.material.texture and ent.material.texture.filename)
	ent.back_material=reverse if not (ent.back_material and ent.back_material.texture and ent.back_material.texture.filename)
      end

    end
  end

  return count

end
