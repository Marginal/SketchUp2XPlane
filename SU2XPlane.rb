#------------------------------------------------------------------------
# X-Plane exporter for SketchUp
#
# Copyright (c) 2006 Jonathan Harris
# 
# Mail: <x-plane@marginal.org.uk>
# Web:  http://marginal.org.uk/x-planescenery/
#
# This software is licensed under a Creative Commons License
#   Attribution-ShareAlike 2.5:
#
#   You are free:
#     * to copy, distribute, display, and perform the work
#     * to make derivative works
#     * to make commercial use of the work
#   Under the following conditions:
#     * Attribution: You must give the original author credit.
#     * Share Alike: If you alter, transform, or build upon this work, you
#       may distribute the resulting work only under a license identical to
#       this one.
#   For any reuse or distribution, you must make clear to others the license
#   terms of this work.
#
# This is a human-readable summary of the Legal Code (the full license):
#   http://creativecommons.org/licenses/by-sa/2.5/legalcode
#
#
# 2006-11-27 v1.00
#  - First public version.
#

require 'sketchup.rb'

$XPlaneExportVersion="1.00"


def XPlaneAccumPolys(entities, trans, vt, idx)

  entities.each do |ent|

    case ent.typename

    when "ComponentInstance"
      XPlaneAccumPolys(ent.definition.entities, trans*ent.transformation, vt, idx)

    when "Group"
      XPlaneAccumPolys(ent.entities, trans*ent.transformation, vt, idx)

    when "Face"
      # if neither side has material then output both sides,
      # otherwise outout the side(s) with materials
      nomats = (not ent.material and not ent.back_material)

      # Create rotation-only transformation for normals
      narray=trans.to_a
      narray[12..16]=[0,0,0,1]
      ntrans = Geom::Transformation.new(narray)
      
      mesh=ent.mesh(7)

      [true,false].each do |front|
	if front
	  material=ent.material
	else
	  material=ent.back_material
	end
	
	if nomats or (material and material.alpha>0.0)
	  if material and material.texture
	    tex=material.texture.filename
	  else
	    tex=nil
	  end
	    
	  base=vt.length
	  for i in (1..mesh.count_points)
	    v=trans * mesh.point_at(i)
	    if material and material.texture
	      u=mesh.uv_at(i, front)
	    else
	      u=Geom::Point3d.new
	    end
	    n=(ntrans * mesh.normal_at(i)).normalize
	    if not front
	      n=n.reverse
	    end
	    vt << (([tex] + v.to_a + n.to_a) << u.x << u.y)
	  end
	    
	  for i in (1..mesh.count_polygons)
	    thistri=[]
	    mesh.polygon_at(i).each do |index|
	      if index>0
		thisidx=base+index-1
	      else
		thisidx=base-index-1
	      end
	      if front
		thistri.unshift(thisidx)
	      else
		thistri.push(thisidx)
	      end
	    end
	    idx.concat(thistri)
	  end

	end

      end
    end

  end
end

#-----------------------------------------------------------------------------

def XPlaneExport(ver)

  if Sketchup.active_model.path==""
    UI.messagebox "I don't know where to create the X-Plane object file because\nyou have never saved this SketchUp model.\n\nSave this SketchUp model first!", MB_OK, "X-Plane export"
    return
  end

  vt=[]
  idx=[]
  XPlaneAccumPolys(Sketchup.active_model.entities, Geom::Transformation.new(0.0254), vt, idx)	# coords always returned in inches!
  if idx.length==0
    UI.messagebox "Nothing to output!", MB_OK,"X-Plane export"
    return
  end
  
  # examine textures
  tex=nil
  notex=0
  badtex=false
  idx.each do |i|
    if vt[i][0]
      if not tex
	tex=vt[i][0]
      elsif tex!=vt[i][0]
	badtex=true
      end
    else
      notex+=1
    end
  end
  if tex
    tex=tex.split(/[\/\\:]+/)[-1]	# basename
  end

  if Sketchup.active_model.path==""
    outpath="Untitled.obj"
  else
    outpath=Sketchup.active_model.path[0...-3]+'obj'
  end

  if ver==7
    outfile=File.new(outpath, "w")
    outfile.write("I\n700\t// \nOBJ\t// \n\n")
    if tex
      outfile.write("#{tex[0..-5]}\t// Texture\n\n")
    else
      outfile.write("none\t\t// Texture\n\n")
    end

    # every 3 indices makes a triangle
    for i in (0...idx.length/3)
      outfile.write("tri\t\t// \n")
      for j in (i*3..i*3+2)
	v=vt[idx[j]]
	outfile.printf("%9.4f %9.4f %9.4f\t%7.4f %7.4f\n",
		       v[1], v[3], -v[2], v[7], v[8])
      end
      outfile.write("\n")
    end

    outfile.write("end\t\t// \n")
    outfile.write("\n// Built with SketchUp #{Sketchup.version}. Exported with SketchUp2XPlane #{$XPlaneExportVersion}.\n")
    outfile.close

  elsif ver==8
    outfile=File.new(outpath, "w")
    outfile.write("I\n800\nOBJ\n\n")
    if tex
      outfile.write("TEXTURE\t\t#{tex}\nTEXTURE_LIT\t#{tex[0..-5]}_LIT#{tex[-4..-1]}\n")
    else
      outfile.write("TEXTURE\t\n")	# X-Plane requires a TEXTURE statement
    end
    outfile.write("POINT_COUNTS\t#{vt.length} 0 0 #{idx.length}\n\n")

    vt.each do |v|
      outfile.printf("VT\t%9.4f %9.4f %9.4f\t%6.3f %6.3f %7.4f\t%7.4f %7.4f\n",
		     v[1], v[3], -v[2], v[4], v[6], -v[5], v[7], v[8])
    end
    outfile.write("\n")
    for i in (0...idx.length/10)
      outfile.write("IDX10\t")
      for j in (i*10...i*10+9)
	outfile.write("#{idx[j]} ")
      end
      outfile.write("#{idx[i*10+9]}\n")
    end
    for j in (idx.length-(idx.length%10)...idx.length)
      outfile.write("IDX\t#{idx[j]}\n")
    end

    outfile.write("\nTRIS\t0 #{idx.length}\n")
    outfile.write("\n# Built with SketchUp #{Sketchup.version}. Exported with SketchUp2XPlane #{$XPlaneExportVersion}.\n")
    outfile.close
  end

  msg="Wrote #{idx.length/3} triangles to #{outpath}.\n"
  if notex>0
    msg+="\nWarning: #{notex/3} of those triangles are untextured."
  end
  if badtex
    msg+="\nWarning: You used multiple texture files. Using file #{tex}."
  end
  UI.messagebox msg, MB_OK,"X-Plane export"

end

#-----------------------------------------------------------------------------

# Add some menu items to access this
if( not file_loaded?("SU2XPlane.rb") )
  UI.menu("File").add_item("Export X-Plane v7 Object") { XPlaneExport(7) }
  UI.menu("File").add_item("Export X-Plane v8 Object") { XPlaneExport(8) }
  help=Sketchup.find_support_file("SU2XPlane.html", "Plugins")
  if help
    UI.menu("Help").add_item("X-Plane") { UI.openURL("file://" + help) }
  end
end
file_loaded("SU2XPlane.rb")
