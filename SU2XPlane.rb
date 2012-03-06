#
# X-Plane importer/exporter for SketchUp
#
# Copyright (c) 2006,2007 Jonathan Harris
# 
# Mail: <x-plane@marginal.org.uk>
# Web:  http://marginal.org.uk/x-planescenery/
#
# This software is licensed under a Creative Commons
#   Attribution-Noncommercial-ShareAlike license:
#   http://creativecommons.org/licenses/by-nc-sa/3.0/
#

require 'sketchup.rb'
require 'extensions.rb'

$XPlaneExportVersion="1.41"

$tw = Sketchup.create_texture_writer

# X-Plane attributes
$ATTR_DICT="X-Plane"
$ATTR_HARD=1
$ATTR_HARD_NAME="poly"	# incorrect dictionary key not fixed for compatibility
$ATTR_POLY=2
$ATTR_POLY_NAME="hard"	# ditto
$ATTR_ALPHA=4
$ATTR_ALPHA_NAME="alpha"
$ATTR_SEQ=[
  $ATTR_POLY, $ATTR_POLY|$ATTR_HARD,
  $ATTR_POLY|$ATTR_ALPHA, $ATTR_POLY|$ATTR_ALPHA|$ATTR_HARD,
  0, $ATTR_HARD,
  $ATTR_ALPHA, $ATTR_ALPHA|$ATTR_HARD]

# Accumulate vertices and indices into vt and idx
def XPlaneAccumPolys(entities, trans, vt, idx, notex)

  # Vertices and Indices added at this level (but not below) - to detect dupes
  myvt=[]
  myidx=Array.new($ATTR_SEQ.length) {[]}

  entities.each do |ent|

    next if ent.hidden? or not ent.layer.visible?

    case ent.typename

    when "ComponentInstance"
      XPlaneAccumPolys(ent.definition.entities, trans*ent.transformation, vt, idx, notex) if ent.definition.name!="Susan"	# Silently skip Susan

    when "Group"
      XPlaneAccumPolys(ent.entities, trans*ent.transformation, vt, idx, notex)

    when "Face"
      # if neither side has material then output both sides,
      # otherwise outout the side(s) with materials
      nomats = (not ent.material and not ent.back_material)

      if not (ent.material and ent.material.texture and ent.material.texture.filename) and not (ent.back_material and ent.back_material.texture and ent.back_material.texture.filename)
	notex[0]+=1	# Only count once per surface (but still cylinders=24)
      end
      notex[1]+=1

      uvHelp = ent.get_UVHelper(true, true, $tw)
      attrs=0
      attrs|=$ATTR_POLY if ent.get_attribute($ATTR_DICT, $ATTR_POLY_NAME, 0)!=0
      attrs|=$ATTR_ALPHA if ent.get_attribute($ATTR_DICT, $ATTR_ALPHA_NAME, 0)!=0

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

	  attrs|=$ATTR_HARD if ent.get_attribute($ATTR_DICT, $ATTR_HARD_NAME, 0)!=0
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
  idx=Array.new($ATTR_SEQ.length) {[]} # arrays of indices
  notex=[0,0]	# num not textured, num surfaces
  XPlaneAccumPolys(Sketchup.active_model.entities, Geom::Transformation.new(0.0254), vt, idx, notex)	# coords always returned in inches!
  if idx.empty?
    UI.messagebox "Nothing to output!", MB_OK,"X-Plane export"
    return
  end

  allidx=[]
  $ATTR_SEQ.each do |attrs|
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
  $ATTR_SEQ.each do |attrs|
    next if idx[attrs].empty?
    if current_attrs&$ATTR_POLY==0 and attrs&$ATTR_POLY!=0
      outfile.write("ATTR_poly_os\t2\n")
    elsif current_attrs&$ATTR_POLY!=0 and attrs&$ATTR_POLY==0
      outfile.write("ATTR_poly_os\t0\n")
    end
    if current_attrs&$ATTR_HARD==0 and attrs&$ATTR_HARD!=0
      outfile.write("ATTR_hard\n")
    elsif current_attrs&$ATTR_HARD!=0 and attrs&$ATTR_HARD==0
      outfile.write("ATTR_no_hard\n")
    end
    outfile.write("TRIS\t#{current_base} #{idx[attrs].length}\n\n")
    current_attrs=attrs
    current_base+=idx[attrs].length
  end
  outfile.write("# Built with SketchUp #{Sketchup.version}. Exported with SketchUp2XPlane #{$XPlaneExportVersion}.\n")
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

#-----------------------------------------------------------------------------

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

#-----------------------------------------------------------------------------

def XPlaneToggleAttr(attr)
  ss = Sketchup.active_model.selection
  if ss.count>=1
    newval=1-ss.first.get_attribute($ATTR_DICT, attr, 0)
    ss.each do |ent|
      ent.set_attribute($ATTR_DICT, attr, newval) if ent.typename=="Face"
    end
  end
end

def XPlaneValidateAttr(attr)
  ss = Sketchup.active_model.selection
  return MF_GRAYED if ss.count==0 or ss.first.typename!="Face"
  val=ss.first.get_attribute($ATTR_DICT, attr, 0)
  # Gray out if multiple selected with different values
  ss.each do |ent|
    return MF_GRAYED if ent.typename!="Face"
    return MF_GRAYED|MF_CHECKED if ent.get_attribute($ATTR_DICT, attr, 0)!=val
  end
  if val!=0
    return MF_CHECKED
  else
    return MF_UNCHECKED
  end
end

#-----------------------------------------------------------------------------
class XPlaneImporter < Sketchup::Importer

  def description
    return "X-Plane Object (*.obj)"
  end

  def file_extension
    return "obj"
  end

  def id
    return "org.marginal.x-plane_obj"
  end

  def supports_options?
    return false
  end

  def load_file(file_path, status)
    return XPlaneImport(file_path)
  end

end

def XPlaneImport(name)
  m2i=1/0.0254	# SketchUp units are inches!
  pibytwo=Math::PI/2
  smoothangle=35*Math::PI/180
  planarangle=0.00002	# normals at angles less than this considered coplanar

  return 2 if not name
  begin
    file=File.new(name, 'r')
    line=file.readline.split(/\/\/|#/)[0].strip()
    if line.include? ?\r
      # Old Mac \r line endings
      linesep="\r"
      file.rewind
      line=file.readline(linesep).split(/\/\/|#/)[0].strip()
    else
      linesep="\n"
    end
    raise 'This is not a valid X-Plane file' if not ['A','I'].include?(line)
    line=file.readline(linesep).split(/\/\/|#/)[0].strip()
    if line.split()[0]=='2'
      raise "Can't read X-Plane version 6 files"
    elsif line!='800'
      raise "Can't read X-Plane version #{line.to_i/100} files"
    elsif not file.readline(linesep).split(/\/\/|#/)[0].strip()=='OBJ'
      raise 'This is not a valid X-Plane file'
    end

    model=Sketchup.active_model
    model.start_operation('Import '+File.basename(name), true)
    begin
      entities=model.active_entities	# Open component, else top level
      material=nil
      reverse=model.materials["XPReverse"]
      if (not reverse) or (reverse.texture and reverse.texture.filename)
	reverse=model.materials.add("XPReverse")
	reverse.color="Magenta"
      end
      reverse.alpha=0
      reverse.texture=nil
      tw = Sketchup.create_texture_writer
      cull=true
      hard=false
      poly=false
      vt=[]
      nm=[]
      uv=[]
      idx=[]
      msg=''
      llerr=false
      skiperr=false

      while true
	line=file.gets(linesep)
	break if not line
	line=line.split(/\/\/|#/)[0].strip()
	next if line.empty?
	c=line.split()
	cmd=c.shift
	case cmd
	when 'TEXTURE'
	  texture=line[7..-1].strip()
	  if not texture.empty?
	    texture=texture.tr(':\\','/')
	    texdir=name.split(/\/|\\/)[0...-1]
	    material=model.materials.add texture.split(/\/|\\/)[-1].split('.')[0]
	    material.texture=texdir.join('/')+'/'+texture
	    if not material.texture
	      i=texdir.collect{|s| s.downcase}.index('custom objects')
	      material.texture=texdir[0...i].join('/')+'/custom object textures/'+texture if i
	      if not material.texture
		# lack of material crashes SketchUp somewhere
		model.abort_operation
		UI.messagebox "Can't read texture file #{texture}", MB_OK, 'X-Plane import'
		return 1
	      end
	    end
	  end
	  material.texture.size=10*m2i if material	# arbitrary
	when 'VT'
	  vt << Geom::Point3d.new(c[0].to_f*m2i, -c[2].to_f*m2i, c[1].to_f*m2i)
	  nm << Geom::Vector3d.new(c[3].to_f, -c[5].to_f, c[4].to_f)
	  uv << Geom::Point3d.new(c[6].to_f, c[7].to_f, 1.0)
	when 'IDX'
	  idx << c[0].to_i
	when 'IDX10'
	  idx.concat(c.collect {|s| s.to_i})
	when 'TRIS'
	  start=c[0].to_i
	  count=c[1].to_i
	  i=start
	  while i<start+count
	    thisvt=[vt[idx[i+2]],vt[idx[i+1]],vt[idx[i]]]
	    begin
	      face=entities.add_face thisvt
	    rescue
	      skiperr=true if not (thisvt[0]==thisvt[1] or thisvt[0]==thisvt[2] or thisvt[1]==thisvt[2])	# SketchUp doesn't like colocated vertices
	      i+=3	# next tri
	      next
	    end
	    thisnm=[nm[idx[i+2]],nm[idx[i+1]],nm[idx[i]]]
	    smooth=(thisnm[0]!=thisnm[1] or thisnm[0]!=thisnm[2] or thisnm[1]!=thisnm[2])
	    if material and uv[idx[i+2]]!=[0.0,0.0,1.0] or uv[idx[i+1]]!=[0.0,0.0,1.0] or uv[idx[i]]!=[0.0,0.0,1.0]
	      # SketchUp doesn't like colocated UVs
	      thisuv=[uv[idx[i+2]]]
	      thisuv << ((uv[idx[i+1]]!=uv[idx[i+2]]) ? uv[idx[i+1]] : uv[idx[i+1]]+Geom::Vector3d.new(1.0/2048,0,0))
	      thisuv << ((uv[idx[i  ]]!=uv[idx[i+2]]) ? uv[idx[i  ]] : uv[idx[i  ]]+Geom::Vector3d.new(0,1.0/2048,0))
	      pts=[thisvt[0],thisuv[0],thisvt[1],thisuv[1],thisvt[2],thisuv[2]]
	      begin
		if face.material
		  # Face is back-to-back with existing face
		  face.position_material material, pts, false
		else
		  face.reverse! if face.normal.angle_between(thisnm[0]) > pibytwo
		  face.position_material material, pts, true
		  if cull
		    face.back_material=reverse
		  else
		    face.position_material material, pts, false
		  end
		end
	      rescue
		# SketchUp can't always compute texture layout
	      end
	    end
	    face.set_attribute($ATTR_DICT, $ATTR_HARD_NAME, 1) if hard
	    face.set_attribute($ATTR_DICT, $ATTR_POLY_NAME, 1) if poly

	    # smooth & soften edges
	    if smooth
	      face.edges.each do |edge|
		case edge.faces.length
		when 1
		  # ignore
		when 2
		  if edge.faces[0].normal.angle_between(edge.faces[1].normal)<=smoothangle
		    edge.smooth=true
		    edge.soft=true
		  end
		else
		  edge.smooth=false
		  edge.soft=false
		end
	      end
	    end

	    # remove coplanar edges
	    edges=face.edges	# face may get deleted
	    edges.each do |edge|
	      if !edge.deleted? and edge.faces.length==2 and edge.faces[0].normal.angle_between(edge.faces[1].normal)<=planarangle	# same_direction? is too forgiving
		if not material
		  edge.erase!
		  next
		end
		faces0=edge.faces[0]
		faces1=edge.faces[1]
		uv0=faces0.get_UVHelper(true, true, tw)
		uv1=faces1.get_UVHelper(true, true, tw)
		if uv0.get_front_UVQ(edge.start.position)==uv1.get_front_UVQ(edge.start.position) and uv0.get_front_UVQ(edge.end.position)==uv1.get_front_UVQ(edge.end.position) and faces0.back_material==faces1.back_material and (faces0.back_material==reverse or (uv0.get_back_UVQ(edge.start.position)==uv1.get_back_UVQ(edge.start.position) and uv0.get_back_UVQ(edge.end.position)==uv1.get_back_UVQ(edge.end.position)))
		  # Check that texture isn't mirrored about this edge
		  for v0 in faces0.vertices
		    if v0!=edge.start and v0!=edge.end
		      u0=uv0.get_front_UVQ(v0.position)
		      u0=Geom::Vector3d.new(u0.x/u0.z,u0.y/u0.z,1.0)
		      break
		    end
		  end
		  for v1 in faces1.vertices
		    if v1!=edge.start and v1!=edge.end
		      u1=uv1.get_front_UVQ(v1.position)
		      u1=Geom::Vector3d.new(u1.x/u1.z,u1.y/u1.z,1.0)
		      break
		    end
		  end
		  u2=uv0.get_front_UVQ(edge.start.position)
		  u2=Geom::Vector3d.new(u2.x/u2.z,u2.y/u2.z,1.0)
		  u3=uv0.get_front_UVQ(edge.end.position)
		  u3=Geom::Vector3d.new(u3.x/u3.z,u3.y/u3.z,1.0)
		  edge.erase! if (u2-u0).cross(u2-u3).z * (u2-u1).cross(u2-u3).z <= 0
		end
	      end
	    end

	    i+=3	# next tri
	  end

	when 'ATTR_LOD'
	  if c[0].to_f>0.0
	    msg+="Ignoring lower level(s) of detail.\n"
	    break
	  end
	when 'ATTR_cull'
	  cull=true
	when 'ATTR_nocull', 'ATTR_no_cull'
	  cull=false
	when 'ATTR_hard'
	  hard=true
	when 'ATTR_no_hard'
	  hard=false
	when 'ATTR_poly_os'
	  poly=c[0].to_f > 0.0
	when 'POINT_COUNTS', 'TEXTURE_LIT', 'ATTR_no_blend', 'ANIM_begin', 'ANIM_end', 'ATTR_shade_flat', 'ATTR_shade_smooth'
	  # suppress error message
	when 'VLINE', 'LINES', 'VLIGHT', 'LIGHTS', 'LIGHT_NAMED', 'LIGHT_CUSTOM'
	  msg+="Ignoring lights and/or lines.\n" if not llerr
	  llerr=true
	else
	  msg+="Ignoring command #{cmd}.\n"
	end
      end
      model.commit_operation
      msg="Ignoring some geometry that couldn't be imported.\n"+msg if skiperr
      UI.messagebox(msg, MB_OK, 'X-Plane import') if not msg.empty?
      return 0

    rescue
      model.abort_operation
      UI.messagebox "Can't import #{name.split(/\/|\\/)[-1]}:\nInternal error.", MB_OK, 'X-Plane import'
    end

  rescue
    UI.messagebox "Can't read #{name.split(/\/|\\/)[-1]}:\n#{$!}.", MB_OK, 'X-Plane import'
  ensure
    file.close unless file.nil?
  end

  return 1
end

#-----------------------------------------------------------------------------

# Add some menu items to access this

extension=SketchupExtension.new 'X-Plane Import/Export - SketchUp2XPlane', 'SU2XPlane.rb'
extension.description='Adds File->Import->X-Plane and File->Export X-Plane Object, Tools->Highlight Untextured, and items to the context menu to control X-Plane attributes.'
extension.version=$XPlaneExportVersion
extension.creator='Jonathan Harris'
extension.copyright='2007'
Sketchup.register_extension extension, true

if !file_loaded?("SU2XPlane.rb")
  Sketchup.register_importer(XPlaneImporter.new)
  UI.menu("File").add_item("Export X-Plane Object") { XPlaneExport() }
  UI.menu("Tools").add_item("Highlight Untextured") { XPlaneHighlight() }

  UI.add_context_menu_handler do |menu|
    #submenu = menu.add_submenu "X-Plane"
    menu.add_separator
    hard=menu.add_item("Hard")      { XPlaneToggleAttr  ($ATTR_HARD_NAME) }
    menu.set_validation_proc(hard)  { XPlaneValidateAttr($ATTR_HARD_NAME) }
    poly=menu.add_item("Ground")    { XPlaneToggleAttr  ($ATTR_POLY_NAME) }
    menu.set_validation_proc(poly)  { XPlaneValidateAttr($ATTR_POLY_NAME) }
    alpha=menu.add_item("Alpha")    { XPlaneToggleAttr  ($ATTR_ALPHA_NAME) }
    menu.set_validation_proc(alpha) { XPlaneValidateAttr($ATTR_ALPHA_NAME) }
  end

  help=Sketchup.find_support_file("SU2XPlane_"+Sketchup.get_locale.upcase.split('-')[0]+".html", "Plugins")
  if not help
    help=Sketchup.find_support_file("SU2XPlane.html", "Plugins")
  end
  if help
    UI.menu("Help").add_item("X-Plane") { UI.openURL("file://" + help) }
  end
  file_loaded("SU2XPlane.rb")
end

#Sketchup.send_action "showRubyPanel:"
