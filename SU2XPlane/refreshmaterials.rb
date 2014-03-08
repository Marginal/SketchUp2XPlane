#
# X-Plane refresh materials from texture file on disk, and consolidate
#
# Copyright (c) 2014 Jonathan Harris
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#

def XPlaneRefreshMaterials()

  model = Sketchup.active_model
  mymaterial = nil

  begin
    model.start_operation(XPL10n.t('Reload Textures'), true)

    usedmaterials = XPlaneMaterialsAccumulate(model.entities, Hash.new(0))
    n_faces = n_untextured = usedmaterials.delete(nil){|k|0}	# Ruby 1.8 returns nil not default_value if not found

    if usedmaterials.empty?
      mymaterial = nil
    else
      byuse = usedmaterials.invert
      n_faces += byuse.keys.inject { |sum,n| sum+n }
      mymaterial = byuse[byuse.keys.sort[-1]]	# most popular material

      # Refesh the texture in the most popular material first so that this is the one that writes to the filesystem if necessary
      newfile = XPlaneMaterialsRefreshOne(model, mymaterial)

      # Refresh the textures in other used materials
      basename = mymaterial.texture.filename.split(/[\/\\:]+/)[-1]
      usedmaterials.each_key do |material|
        if material!=mymaterial && material.texture && material.texture.filename
          if basename.casecmp(material.texture.filename.split(/[\/\\:]+/)[-1])==0
            # it uses the same texture as our material
            usedmaterials[mymaterial] += usedmaterials.delete(material){|k|0}
            if material.texture.height==mymaterial.texture.height && material.texture.width==mymaterial.texture.width && material.alpha==mymaterial.alpha
              # it's a duplicate of our material - eliminate it
              XPlaneMaterialsReplace(model, material, mymaterial)
              # model.materials.remove(material) - can't do this since might be in use elsewhere
            else
              # it is not a duplicate of our material - point to our texture
              theight = material.texture.height
              twidth  = material.texture.width
              material.color = nil
              material.texture = newfile
              material.texture.size = [twidth,theight]	# required to maintain UV mapping
            end
          else
            # it uses a different texture than our material - refresh it anyway
            XPlaneMaterialsRefreshOne(model, material)
          end
        end
      end

    end

    model.commit_operation

    thing = Struct.new(:material, :n_textures, :n_faces, :n_untextured)
    return thing.new(mymaterial, usedmaterials.length, n_faces, n_untextured)

  rescue => e
    puts "Error: #{e.inspect}", e.backtrace	# Report to console
    model.abort_operation
    return nil

  end

end


def XPlaneMaterialsAccumulate(entities, usedmaterials)

  entities.each do |ent|

    next if ent.hidden? || !ent.layer.visible?	# only interested in Materials in entities in active use

    case ent.typename

    when "ComponentInstance"
      # Instances can have a material which child Entities inherit, but children don't get UVs so we don't count it
      XPlaneMaterialsAccumulate(ent.definition.entities, usedmaterials)

    when "Group"
      XPlaneMaterialsAccumulate(ent.entities, usedmaterials)

    when "Face"
      n = ent.mesh(0).count_polygons	# complex faces get more weight
      if !ent.material && !ent.back_material
        usedmaterials[nil] += 1		# just count the whole face once
      else
        [ent.material, ent.back_material].each do |material|
          if material && material.alpha>0.0
            if material.texture
              usedmaterials[material] += n
            else
              usedmaterials[nil] += n
            end
          end
        end
      end

    end

  end

  return usedmaterials

end


# Refesh the texture in the material
def XPlaneMaterialsRefreshOne(model, material)

  if File.file? material.texture.filename
    newfile = material.texture.filename
  else
    raise "Save this SketchUp model first" if model.path==''
    newfile = File.dirname(Sketchup.active_model.path) + "/" + (material.texture.filename.split(/[\/\\:]+/)[-1])[0...-3] + "png"
    # Write embedded texture to filesystem (unless there's already a file of that name in the folder)
    if (!File.file? newfile)
      raise "Can't find Entity for #{newfile}" if !XPlaneMaterialsWrite(model, material, newfile)	# TextureWriter needs an Entity that uses the material, not the material itself
    end
  end
  theight = material.texture.height
  twidth  = material.texture.width
  material.color = nil
  material.texture = newfile
  material.texture.size = [twidth,theight]	# required to maintain UV mapping

  return newfile

end


# Find an entity in the model that uses this material, and write it out
def XPlaneMaterialsWrite(model, material, newfile)

  tw = Sketchup.create_texture_writer

  model.entities.each do |e|
    if ['Face', 'Group', 'ComponentInstance'].include?(e.typename)	# TextureWriter only operates on a limited set of Entities
      if e.material == material
        raise "Can't write #{newfile}" if tw.load(e, true)==0 || tw.write(e, true, newfile)!=0
        return true
      elsif e.respond_to?(:back_material) && e.back_material == material
        raise "Can't write #{newfile}" if tw.load(e, false)==0 || tw.write(e, false, newfile)!=0
        return true
      end
    end
  end

  if model.respond_to?(:definitions)
    model.definitions.each do |d|
      return true if XPlaneMaterialsWrite(d, material, newfile)
    end
  end

  return false

end


# Replace material in all entities in the model
def XPlaneMaterialsReplace(model, material, mymaterial)

  model.entities.each do |e|
    if e.respond_to?(:material) && e.material==material
      e.material = mymaterial
    end
    if e.respond_to?(:back_material) && e.back_material==material
      e.back_material = mymaterial
    end
  end

  if model.respond_to?(:definitions)
    model.definitions.each do |d|
      XPlaneMaterialsReplace(d, material, mymaterial)
    end
  end

  return false

end
