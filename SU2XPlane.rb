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
# 2006-11-30 v1.03
#  - Add Tools->Highlight Untextured.
#
# 2006-11-30 v1.04
#  - Remove duplicate vertices in OBJv8.
#
# 2006-11-30 v1.05
#  - Create quads in OBJv7.
#
# 2006-11-03 v1.07
#  - Fix for weirdly scaled UVs (typically made with "Fixed Pins" unchecked).
#

require 'sketchup.rb'

$XPlaneExportVersion="1.07"

$tw = Sketchup.create_texture_writer


def XPlaneAccumPolys(entities, trans, ver, vt, idx, notex)

  # Vertices and Indices added at this level- to detect dupes
  myvt=[]
  myidx=[]

  entities.each do |ent|

    case ent.typename

    when "ComponentInstance"
      XPlaneAccumPolys(ent.definition.entities, trans*ent.transformation, ver, vt, idx, notex)

    when "Group"
      XPlaneAccumPolys(ent.entities, trans*ent.transformation, ver, vt, idx, notex)

    when "Face"
      # if neither side has material then output both sides,
      # otherwise outout the side(s) with materials
      nomats = (not ent.material and not ent.back_material)

      if not (ent.material and ent.material.texture and ent.material.texture.filename) and not (ent.back_material and ent.back_material.texture and ent.back_material.texture.filename)
	notex[0]+=1	# Only count once per surface (but still cylinders=24)
      end
      notex[1]+=1

      uvHelp = ent.get_UVHelper(true, true, $tw)

      # Create transformation w/out translation for normals
      narray=trans.to_a
      narray[12..16]=[0,0,0,1]
      ntrans = Geom::Transformation.new(narray)

      mesh=ent.mesh(7)	# vertex, uvs & normal 
      [true,false].each do |front|
	if front
	  material=ent.material
	else
	  material=ent.back_material
	end
	
	if nomats or (material and material.alpha>0.0)
	  if material and material.texture
	    tex=material.texture.filename
	    # Get minimum uv co-oords
	    us=[]
	    vs=[]
	    ent.outer_loop.vertices.each do |vertex|
	      if front
		u=uvHelp.get_front_UVQ(vertex.position).to_a
	      else
		u=uvHelp.get_back_UVQ(vertex.position).to_a
	      end
	      us << (u.x/u.z).floor
	      vs << (u.y/u.z).floor
	    end
	    minu=us.min
	    minv=vs.min
	  else
	    tex=nil
	    minu=minv=0
	  end

	  if ver==7 and ent.loops.length==1 and ent.outer_loop.vertices.length==4
	    # simple quad
	    if front
	      idx << (Array.new(4) {|i| vt.length+3-i})
	    else
	      idx << (Array.new(4) {|i| vt.length+i})
	    end
	    ent.outer_loop.vertices.each do |vertex|
	      if tex
		if front
		  u=uvHelp.get_front_UVQ(vertex.position).to_a
		else
		  u=uvHelp.get_back_UVQ(vertex.position).to_a
		end
	      else
		u=[0,0,1]
	      end
	      vt << ([tex] + (trans*vertex.position).to_a + [0, 0, 0, u.x/u.z-minu, u.y/u.z-minv])
	    end
	    next
	  end

	  thisvt=[]	# Vertices in this face
	  for i in (1..mesh.count_points)
	    v=trans * mesh.point_at(i)
	    if tex
	      u=mesh.uv_at(i, front)
	    else
	      u=[0,0,1]
	    end
	    n=(ntrans * mesh.normal_at(i)).normalize
	    if not front
	      n=n.reverse
	    end
	    thisvt << (([tex] + v.to_a + n.to_a) << u.x/u.z-minu << u.y/u.z-minv)
	  end
	    
	  for i in (1..mesh.count_polygons)
	    thistri=[]	# indices in this face
	    mesh.polygon_at(i).each do |index|
	      if index>0
		v=thisvt[index-1]
	      else
		v=thisvt[-index-1]
	      end
	      if ver==7
		thisidx=vt.length
		vt << v
	      else
		# Look for duplicate vertex
		thisidx=myvt.rindex(v)
		if not thisidx
		  # Didn't find a duplicate vertex
		  thisidx=myvt.length
		  myvt << v
		end
	      end
	      if front
		thistri.unshift(thisidx)
	      else
		thistri.push(thisidx)
	      end
	    end
	    if ver==7
	      idx << thistri
	    else
	      myidx.concat(thistri)
	    end
	  end

	end

      end
    end

  end

  # Add new vertices and indices
  if ver==8
    base=vt.length
    myidx.collect!{|i| i+base}
    vt.concat(myvt)
    idx.concat(myidx)
  end

end

#-----------------------------------------------------------------------------

def XPlaneExport(ver)

  if Sketchup.active_model.path==""
    UI.messagebox "Save this SketchUp model first.\n\nI don't know where to create the X-Plane object file because\nyou have never saved this SketchUp model.", MB_OK, "X-Plane export"
    outpath="Untitled.obj"
    return
  else
    outpath=Sketchup.active_model.path[0...-3]+'obj'
  end

  vt=[]		# array of [tex, vx, vy, vz, nx, ny, nz, u, v]
  idx=[]	# v8: flat array of indices. v7: array of 3 or 4 length arrays
  notex=[0,0]	# num not textured, num surfaces
  XPlaneAccumPolys(Sketchup.active_model.entities, Geom::Transformation.new(0.0254), ver, vt, idx, notex)	# coords always returned in inches!
  if idx.length==0
    UI.messagebox "Nothing to output!", MB_OK,"X-Plane export"
    return
  end
  
  # examine textures
  tex=nil
  badtex=false
  idx.each do |i|
    if ver==7
      if vt[i[0]][0]
	if not tex
	  tex=vt[i[0]][0]
	elsif tex!=vt[i[0]][0]
	  badtex=true
	end
      end
    elsif ver==8
      if vt[i][0]
	if not tex
	  tex=vt[i][0]
	elsif tex!=vt[i][0]
	  badtex=true
	end
      end
    end
  end
  if tex
    tex=tex.split(/[\/\\:]+/)[-1]	# basename
  end

  if notex[0]==0
    notex=false
  elsif notex[0]==notex[1]
    notex="All"
  else
    notex=notex[0]
  end

  if ver==7
    outfile=File.new(outpath, "w")
    outfile.write("I\n700\t// \nOBJ\t// \n\n")
    if tex
      outfile.write("#{tex[0..-5]}\t// Texture\n\n")
    else
      outfile.write("none\t\t// Texture\n\n")
    end

    [3,4].each do |sides|
      idx.each do |poly|
	if poly.length!=sides
	  next
	end
	if sides==4
	  outfile.write("quad\t\t// \n")
	else
	  outfile.write("tri\t\t// \n")
	end
	poly.each do |i|
	  v=vt[i]
	  outfile.printf("%9.4f %9.4f %9.4f\t%7.4f %7.4f\n",
			 v[1], v[3], -v[2], v[7], v[8])
	end
	outfile.write("\n")
      end
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
      outfile.printf("VT\t%9.4f %9.4f %9.4f\t%6.3f %6.3f %6.3f\t%7.4f %7.4f\n",
		     v[1], v[3], -v[2], v[4], v[6], -v[5], v[7], v[8])
    end
    outfile.write("\n")
    for i in (0...idx.length/10)
      outfile.write("IDX10\t#{idx[i*10..i*10+9].join(' ')}\n")
    end
    for i in (idx.length-(idx.length%10)...idx.length)
      outfile.write("IDX\t#{idx[i]}\n")
    end

    outfile.write("\nTRIS\t0 #{idx.length}\n")
    outfile.write("\n# Built with SketchUp #{Sketchup.version}. Exported with SketchUp2XPlane #{$XPlaneExportVersion}.\n")
    outfile.close
  end

  if ver==7
    msg="Wrote #{idx.length} polygons to #{outpath}.\n"
  elsif ver==8
    msg="Wrote #{idx.length/3} triangles to #{outpath}.\n"
  end
  if notex
    msg+="\nWarning: #{notex} surfaces are untextured."
  end
  if badtex
    msg+="\nWarning: You used multiple texture files. Using file #{tex}."
  end
  if notex and not badtex and not Sketchup.active_model.materials["XPUntextured"]
    yesno=UI.messagebox msg+"\nDo you want to highlight the untexured surfaces?", MB_YESNO,"X-Plane export"
    if yesno==6
      XPlaneHighlight()
    end
  else
    UI.messagebox msg, MB_OK,"X-Plane export"
  end
end

#-----------------------------------------------------------------------------

def XPlaneHighlight()

  model=Sketchup.active_model
  materials=model.materials
  model.start_operation("Highlight Untextured")
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
    if count==0
      UI.messagebox "All surfaces are textured", MB_OK,"X-Plane export"
    end
  rescue
    model.abort_operation
  end

end

#-----------------------------------------------------------------------------

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
	if not (ent.material and ent.material.texture and ent.material.texture.filename)
	  ent.material=reverse
	end
	if not (ent.back_material and ent.back_material.texture and ent.back_material.texture.filename)
	  ent.back_material=reverse
	end
      end

    end
  end

  return count

end

#-----------------------------------------------------------------------------

# Add some menu items to access this
if( not file_loaded?("SU2XPlane.rb") )
  UI.menu("File").add_item("Export X-Plane v7 Object") { XPlaneExport(7) }
  UI.menu("File").add_item("Export X-Plane v8 Object") { XPlaneExport(8) }
  UI.menu("Tools").add_item("Highlight Untextured") { XPlaneHighlight() }
  help=Sketchup.find_support_file("SU2XPlane.html", "Plugins")
  if help
    UI.menu("Help").add_item("X-Plane") { UI.openURL("file://" + help) }
  end
end
file_loaded("SU2XPlane.rb")
