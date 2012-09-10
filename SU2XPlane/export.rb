# Accumulate vertices and indices into vt and idx
def XPlaneAccumPolys(entities, trans, tw, vt, idx, notex, lights)

  # Vertices and Indices added at this level (but not below) - to detect dupes
  myvt=[]
  myidx=Array.new(SU2XPlane::ATTR_SEQ.length) {[]}

  entities.each do |ent|

    next if ent.hidden? or not ent.layer.visible?

    case ent.typename

    when "ComponentInstance"
      XPlaneAccumPolys(ent.definition.entities, trans*ent.transformation, tw, vt, idx, notex, lights) if ent.definition.name!="Susan"	# Silently skip Susan

    when "Group"
      XPlaneAccumPolys(ent.entities, trans*ent.transformation, tw, vt, idx, notex, lights)

    when "Text"
      light=ent.text[/\S*/]
      if SU2XPlane::LIGHTNAMED.include?(light) or SU2XPlane::LIGHTCUSTOM.include?(light)
        v=trans * ent.point
        lights << ([ent.text] + v.to_a.collect{|j| (j*10000).round/10000.0})
      end

    when "Face"
      # if neither side has material then output both sides,
      # otherwise outout the side(s) with materials
      nomats = (not ent.material and not ent.back_material)

      if not (ent.material and ent.material.texture and ent.material.texture.filename) and not (ent.back_material and ent.back_material.texture and ent.back_material.texture.filename)
	notex[0]+=1	# Only count once per surface (but still cylinders=24)
      end
      notex[1]+=1

      uvHelp = ent.get_UVHelper(true, true, tw)
      attrs=0
      attrs|=SU2XPlane::ATTR_POLY if ent.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_POLY_NAME, 0)!=0
      attrs|=SU2XPlane::ATTR_ALPHA if ent.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_ALPHA_NAME, 0)!=0

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
            if not File.exists? tex
              # Write embedded texture to filesystem, and update material to use it
              newtex=File.dirname(Sketchup.active_model.path) + "/" + (tex.split(/[\/\\:]+/)[-1])[0...-3] + "png"
              if tw.load(ent, front)!=0 and tw.write(ent, front, newtex)==0
                theight = material.texture.height
                twidth  = material.texture.width
                material.texture = newtex
                material.texture.size = [twidth,theight]	# don't know why this should be required but it is
                tex=newtex
              end
            end
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

	  attrs|=SU2XPlane::ATTR_HARD if ent.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_HARD_NAME, 0)!=0
	  thisvt=[]	# Vertices in this face
	  for i in (1..mesh.count_points)
	    v=trans * mesh.point_at(i)
	    if tex
	      u=mesh.uv_at(i, front)
	    else
	      u=[0,0,1]
	    end
	    n=(ntrans * mesh.normal_at(i)).normalize
	    n=n.reverse if not front
	    # round to export precision to increase chance of detecting dupes
	    thisvt << (([tex] + v.to_a.collect{|j| (j*10000).round/10000.0} + n.to_a.collect{|j| (j*1000).round/1000.0}) << ((u.x/u.z-minu)*10000).round/10000.0 << ((u.y/u.z-minv)*10000).round/10000.0)
	  end

	  for i in (1..mesh.count_polygons)
	    thistri=[]	# indices in this face
	    mesh.polygon_at(i).each do |index|
	      if index>0
		v=thisvt[index-1]
	      else
		v=thisvt[-index-1]
	      end
	      # Look for duplicate vertex
	      thisidx=myvt.rindex(v)
	      if not thisidx
		# Didn't find a duplicate vertex
		thisidx=myvt.length
		myvt << v
	      end
	      if front
		thistri.unshift(thisidx)
	      else
		thistri.push(thisidx)
	      end
	    end
	    if not thistri.empty?
              myidx[attrs].concat(thistri)
	    end
	  end

	end

      end	# [true,false].each do |front|

    end		# case ent.typename

  end		# entities.each do |ent|

  # Add new vertices and fix up and add new indices
  base=vt.length
  vt.concat(myvt)
  for attrs in (0...myidx.length)
    myidx[attrs].collect!{|j| j+base}
    idx[attrs].concat(myidx[attrs])
  end

end

#-----------------------------------------------------------------------------

def XPlaneExport()

  if Sketchup.active_model.path==""
    UI.messagebox "Save this SketchUp model first.\n\nI don't know where to create the X-Plane object file\nbecause you have never saved this SketchUp model.", MB_OK, "X-Plane export"
    outpath="Untitled.obj"
    return
  else
    outpath=Sketchup.active_model.path[0...-3]+'obj'
  end

  vt=[]		# array of [tex, vx, vy, vz, nx, ny, nz, u, v]
  idx=Array.new(SU2XPlane::ATTR_SEQ.length) {[]} # arrays of indices
  notex=[0,0]	# num not textured, num surfaces
  lights=[]	# array of [freetext, vx, vy, vz]
  XPlaneAccumPolys(Sketchup.active_model.entities, Geom::Transformation.new(0.0254), Sketchup.create_texture_writer, vt, idx, notex, lights)	# coords always returned in inches!
  if idx.empty?
    UI.messagebox "Nothing to output!", MB_OK,"X-Plane export"
    return
  end

  allidx=[]
  SU2XPlane::ATTR_SEQ.each do |attrs|
    allidx.concat(idx[attrs])
  end

  # examine textures
  tex=nil
  badtex=false
  allidx.each do |i|
    if vt[i][0]
      if not tex
        tex=vt[i][0]
      elsif tex!=vt[i][0]
        badtex=true
      end
    end
  end
  tex=tex.split(/[\/\\:]+/)[-1] if tex	# basename

  if notex[0]==0
    notex=false
  elsif notex[0]==notex[1]
    notex="All"
  else
    notex=notex[0]
  end

  outfile=File.new(outpath, "w")
  outfile.write("I\n800\nOBJ\n\n")
  if tex
    outfile.write("TEXTURE\t\t#{tex}\nTEXTURE_LIT\t#{tex[0..-5]}_LIT#{tex[-4..-1]}\n")
  else
    outfile.write("TEXTURE\t\n")	# X-Plane requires a TEXTURE statement
  end
  outfile.write("POINT_COUNTS\t#{vt.length} 0 0 #{allidx.length}\n\n")

  vt.each do |v|
    outfile.printf("VT\t%9.4f %9.4f %9.4f\t%6.3f %6.3f %6.3f\t%7.4f %7.4f\n",
                   v[1], v[3], -v[2], v[4], v[6], -v[5], v[7], v[8])
  end
  outfile.write("\n")
  for i in (0...allidx.length/10)
    outfile.write("IDX10\t#{allidx[i*10..i*10+9].join(' ')}\n")
  end
  for i in (allidx.length-(allidx.length%10)...allidx.length)
    outfile.write("IDX\t#{allidx[i]}\n")
  end
  outfile.write("\n")

  current_attrs=0
  current_base=0
  SU2XPlane::ATTR_SEQ.each do |attrs|
    next if idx[attrs].empty?
    if current_attrs&SU2XPlane::ATTR_POLY==0 and attrs&SU2XPlane::ATTR_POLY!=0
      outfile.write("ATTR_poly_os\t2\n")
    elsif current_attrs&SU2XPlane::ATTR_POLY!=0 and attrs&SU2XPlane::ATTR_POLY==0
      outfile.write("ATTR_poly_os\t0\n")
    end
    if current_attrs&SU2XPlane::ATTR_HARD==0 and attrs&SU2XPlane::ATTR_HARD!=0
      outfile.write("ATTR_hard\n")
    elsif current_attrs&SU2XPlane::ATTR_HARD!=0 and attrs&SU2XPlane::ATTR_HARD==0
      outfile.write("ATTR_no_hard\n")
    end
    outfile.write("TRIS\t#{current_base} #{idx[attrs].length}\n\n")
    current_attrs=attrs
    current_base+=idx[attrs].length
  end
  lights.each do |v|
    args=v[0].split
    type=args.shift
    if SU2XPlane::LIGHTNAMED.include?(type)
      name=args.shift
      outfile.printf("%s\t%s\t%9.4f %9.4f %9.4f\t%s\n", type, name, v[1], v[3], -v[2], args.join(' '))
    else
      outfile.printf("%s\t%9.4f %9.4f %9.4f\t%s\n", type, v[1], v[3], -v[2], args.join(' '))
    end
  end
  outfile.write("\n# Built with SketchUp #{Sketchup.version}. Exported with SketchUp2XPlane #{SU2XPlane::Version}.\n")
  outfile.close

  msg="Wrote #{allidx.length/3} triangles to #{outpath}.\n"
  msg+="\nWarning: #{notex} faces are untextured." if notex
  msg+="\nWarning: You used multiple texture files. Using file #{tex}." if badtex
  if notex and not badtex and not Sketchup.active_model.materials["XPUntextured"]
    yesno=UI.messagebox msg+"\nDo you want to highlight the untexured faces?", MB_YESNO,"X-Plane export"
    XPlaneHighlight() if yesno==6
  else
    UI.messagebox msg, MB_OK,"X-Plane export"
  end
end
