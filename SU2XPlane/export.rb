# -*- coding: utf-8 -*-
#
# X-Plane export
#
# Copyright (c) 2006-2013 Jonathan Harris
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#

class XPIndices < Array
  attr_accessor(:base)	# Offset in global table
end

class XPPrim

  include Comparable

  # Flags for export in order of priority low->high. Attributes represented by lower bits are flipped more frequently on output.
  HARD=1
  DECK=2
  # animation should come here
  SHINY=4
  ALPHA=8
  NDRAPED=16	# negated so ground polygons come first
  NPOLY=32	# ditto

  # Types
  TRIS='Tris'
  LIGHT='Light'

  attr_reader(:typename, :attrs)
  attr_accessor(:anim, :i)

  def initialize(typename, anim, attrs=NPOLY|NDRAPED)
    @typename=typename	# One of TRIS, LIGHT
    @anim=anim		# XPAnim context, or nil if top-level - i.e. not animated
    @attrs=attrs	# bitmask
    @i=XPIndices.new	# indices into the global vertex table for Tris. [freetext, vx, vy, vz] for Light
  end

  def <=>(other)
    # For sorting primitives in order of priority
    c = ((self.attrs&(NDRAPED|NPOLY|ALPHA|SHINY)) <=> (other.attrs&(NDRAPED|NPOLY|ALPHA|SHINY)))
    return c if c!=0
    if self.anim && other.anim
      c = ((self.anim) <=> (other.anim))
      return c if c!=0
    elsif self.anim || other.anim
      return -1 if !self.anim	# no animation precedes animation
      return 1 if !other.anim	# no animation precedes animation
    end
    c = ((self.attrs&(DECK|HARD)) <=> (other.attrs&(DECK|HARD)))
    return c if c!=0
    c = (self.typename <=> other.typename)
    return c
  end

end

class XPAnim

  include Comparable

  attr_reader(:parent, :cachekey, :transformation, :dataref, :v, :loop, :t, :rx, :ry, :rz, :hideshow, :label)

  def initialize(component, parent, trans)
    @parent=parent	# parent XPAnim, or nil if parent is top-level - i.e. not animated
    @cachekey=component.definition.object_id
    @transformation=trans*component.transformation	# transformation to be applied to sub-geometry
    @dataref=component.XPDataRef	# DataRef, w/ index if any
    @v=component.XPValues		# 0 or n keyframe dataref values. Note: stored as String
    @loop=component.XPLoop		# loop dataref value. Note: stored as String
    @t=component.XPTranslations(trans)	# translation, 0, 1 or n translations (0=just hide/show, 1=rotation w/ no translation)
    @rx=@ry=@rz=[]			# 0 or n rotation angles
    @hideshow=component.XPHideShow	# show/hide values [show/hide, dataref, from, to]
    @label=(component.name!='' ? component.name : "<#{component.definition.name}>")	# tag in output file

    @t=[@t[0]] if (@t.inject({}) { |h,v| h.store(v,true) && h }).length == 1	# if translation constant across keyframes reduce to one entry
    rot=component.XPRotations(trans)
    if (rot.inject({}) { |h,v| h.store(v,true) && h }).length <= 1
      # rotation constant across all keyframes - just use current rotation
      if @t.length > 1
        # strip out translation from children's transformation
        @transformation=trans * Geom::Transformation.translation(Geom::Point3d.new - component.transformation.origin) * component.transformation
      else
        # no animation of any kind
        @t=[]
        raise ArgumentError if @hideshow==[]	# and no Hide/Show either
      end
    else
      # we have rotation keyframes, so untranslate and unrotate to obtain children's transformation (i.e. just scale)
      currentangles=component.transformation.XPEuler()
      @transformation = Geom::Transformation.translation(Geom::Point3d.new - component.transformation.origin) * component.transformation
      if (rot.inject({}) { |h,v| h.store(v[0],true) && h }).length > 1
        # We have rotation about x axis, so unrotate about x
        @transformation = Geom::Transformation.rotation([0,0,0], [1,0,0], -currentangles[0]) * @transformation
        @rx = rot.map { |v| v[0] }
      end
      if (rot.inject({}) { |h,v| h.store(v[1],true) && h }).length > 1
        # We have rotation about y axis, so unrotate about y
        @transformation = Geom::Transformation.rotation([0,0,0], [0,1,0], -currentangles[1]) * @transformation
        @ry = rot.map { |v| v[1] }
      end
      if (rot.inject({}) { |h,v| h.store(v[2],true) && h }).length > 1
        # We have rotation about z axis, so unrotate about z
        @transformation = Geom::Transformation.rotation([0,0,0], [0,0,1], -currentangles[2]) * @transformation
        @rz = rot.map { |v| v[2] }
      end
      @transformation = trans * @transformation
    end
  end

  def <=>(other)
    # For sorting animations. We don't examine the animation contents - just ensure that parents come before their children.
    p=other.parent
    while p
      return -1 if p.object_id==self.object_id	# other is a child of self
      p=p.parent
    end
    p=self.parent
    while p
      return 1 if p.object_id==other.object_id	# self is a child of other
      p=p.parent
    end
    # no parent/child relationship ('though could be siblings, cousins, etc)
    return self.object_id<=>other.object_id	# use object_id to give a stable sort
  end

  def self.ins(anim)
    # Padding level in output file. Class method so can pass in nil anim.
    pad=''
    while anim do
      pad+="\t"
      anim=anim.parent
    end
    return pad
  end

end


# Accumulate vertices and indices into vt and idx
def XPlaneAccumPolys(entities, anim, trans, tw, vt, prims, primcache, notex)

  base=vt.length
  prim=nil	# keep adding to the same XPPrim until attributes change

  # Create transformation w/out translation for normals
  ntrans = Geom::Transformation.translation(Geom::Point3d.new - trans.origin) * trans

  # If determinant is negative (e.g. parent component is mirrored), tri indices need to be reversed.
  det = trans.determinant

  # If this is an animated component, store its geometry in case the component instance is used again.
  # If this is a Group or non-animated Component we're actually adding to the parent animated component.
  if anim
    primcache[anim.cachekey]=[] if !primcache.include?(anim.cachekey)
  end

  # Process Faces before Groups and ComponentInstances so that we can search Vertices added at this level (but not below) to detect dupes
  (entities.sort { |a,b| b.typename<=>a.typename }).each do |ent|

    next if ent.hidden? or not ent.layer.visible?

    case ent.typename

    when "ComponentInstance"
      begin
        newanim=XPAnim.new(ent, anim, trans)
        if primcache.include?(newanim.cachekey)
          # re-use existing definition's vertices, indices and attributes (but not its animation context).
          primcache[newanim.cachekey].each do |p|
            prim=p.clone()
            prim.anim=newanim
            prims << prim
          end
        else
          XPlaneAccumPolys(ent.definition.entities, newanim, newanim.transformation, tw, vt, prims, primcache, notex)
        end
      rescue ArgumentError
        # This component is not an animation
        XPlaneAccumPolys(ent.definition.entities, anim, trans*ent.transformation, tw, vt, prims, primcache, notex) unless ['Susan','Derrick'].include? ent.definition.name	# Silently skip figures
      end

    when "Group"
      XPlaneAccumPolys(ent.entities, anim, trans*ent.transformation, tw, vt, prims, primcache, notex)

    when "Text"
      light=ent.text[/\S*/]
      if ent.point && (SU2XPlane::LIGHTNAMED.include?(light) || SU2XPlane::LIGHTCUSTOM.include?(light))
        lightprim=XPPrim.new(XPPrim::LIGHT, anim)
        lightprim.i = [ent.text] + (trans*ent.point).to_a.map { |v| v.round(SU2XPlane::P_V) }
        prims << lightprim
        primcache[anim.cachekey].push(lightprim) if anim
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
      if anim
        # can't have poly_os or hard in animation
        attrs |= XPPrim::NPOLY|XPPrim::NDRAPED
      else
        attrs |= XPPrim::NPOLY   unless ent.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_POLY_NAME, 0)!=0
        attrs |= XPPrim::HARD    if     ent.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_HARD_NAME, 0)!=0
        attrs |= XPPrim::DECK    if     ent.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_DECK_NAME, 0)!=0
        attrs |= XPPrim::NDRAPED unless attrs&(XPPrim::NPOLY|XPPrim::DECK|XPPrim::HARD)==0	# Can't be draped if hard
      end
      if attrs & (XPPrim::NPOLY|XPPrim::NDRAPED) == (XPPrim::NPOLY|XPPrim::NDRAPED)
	# poly_os and/or draped implies ground level so no point in alpha
        attrs |= XPPrim::ALPHA if ent.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_ALPHA_NAME, 0)!=0
        attrs |= XPPrim::SHINY if ent.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_SHINY_NAME, 0)!=0
      end
      if !prim or prim.attrs!=attrs
        prim=XPPrim.new(XPPrim::TRIS, anim, attrs)
        prims << prim
        primcache[anim.cachekey].push(prim) if anim
      end

      mesh=ent.mesh(7)	# vertex, uvs & normal
      [true,false].each do |front|
        if front
          material=ent.material
        else
          material=ent.back_material
        end
        reverseidx=!(front^(det<0))

        if nomats or (material and material.alpha>0.0)
          if material and material.texture
            if not File.exists? material.texture.filename
              # Write embedded texture to filesystem (unless there's already a file of that name in the folder) and update material to use it
              newfile=File.dirname(Sketchup.active_model.path) + "/" + (material.texture.filename.split(/[\/\\:]+/)[-1])[0...-3] + "png"
              if (File.exists? newfile) || (tw.load(ent, front)!=0 && tw.write(ent, front, newfile)==0)
                theight = material.texture.height
                twidth  = material.texture.width
                material.texture = newfile
                material.texture.size = [twidth,theight]	# don't know why this should be required but it is
              end
            end
            tex=material.texture
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

          thisvt=[]	# Vertices in this face
          for i in (1..mesh.count_points)
            v=trans * mesh.point_at(i)
            if tex
              u=mesh.uv_at(i, front)
            else
              u=[0,0,1]
            end
            n=(ntrans * mesh.normal_at(i)).normalize
            n.reverse! if not front
            # round to export precision to increase chance of detecting dupes
            thisvt << [tex] + v.to_a.map { |j| j.round(SU2XPlane::P_V) } + n.to_a.map { |j| j.round(SU2XPlane::P_N) } + [(u.x/u.z-minu).round(SU2XPlane::P_UV), (u.y/u.z-minv).round(SU2XPlane::P_UV)]
          end

          for i in (1..mesh.count_polygons)
            thistri=[]	# indices in this face
            mesh.polygon_at(i).each do |index|
              if index>0
                v=thisvt[index-1]
              else
                v=thisvt[-index-1]
              end
              # Look for duplicate in Vertices already added at this level
              thisidx=vt.last(vt.length-base).rindex(v)
              if thisidx
                thisidx+=base
              else
                # Didn't find a duplicate vertex
                thisidx=vt.length
                vt << v
              end
              if reverseidx
                thistri.push(thisidx)
              else
                thistri.unshift(thisidx)
              end
            end
            prim.i.concat(thistri)
          end

        end

      end	# [true,false].each do |front|

    end		# case ent.typename

  end		# entities.each do |ent|

end

#-----------------------------------------------------------------------------

def XPlaneExport()

  model=Sketchup.active_model
  if model.path==''
    UI.messagebox XPL10n.t("Save this SketchUp model first.\n\nI don't know where to create the X-Plane object file\nbecause you have never saved this SketchUp model."), MB_OK, "X-Plane export"
    return
  else
    outpath=model.path[0...-3]+'obj'
  end
  if model.active_path!=nil
    UI.messagebox XPL10n.t("Close all open Components and Groups first.\n\nI can't export while you have Components and/or\nGroups open for editing."), MB_OK, "X-Plane export"
    return
  end

  vt=[]		# array of [tex, vx, vy, vz, nx, ny, nz, u, v]
  prims=[]	# arrays of XPPrim
  notex=[0,0]	# num not textured, num surfaces
  lights=[]	# array of [freetext, vx, vy, vz]
  begin
    XPlaneAccumPolys(model.entities, nil, Geom::Transformation.scaling(1.to_m, 1.to_m, 1.to_m), Sketchup.create_texture_writer, vt, prims, {}, notex)	# coords always returned in inches!
  rescue => e
    puts "Error: #{e.inspect}", e.backtrace	# Report to console
    UI.messagebox XPL10n.t('Internal error!') + "\n\n" + XPL10n.t("Saving your model, then quitting and restarting\nSketchUp might clear the problem."), MB_OK, 'X-Plane export'
    return
  end
  if prims.empty?
    UI.messagebox XPL10n.t('Nothing to export!'), MB_OK,"X-Plane export"
    return
  end

  # Sort to minimise state changes
  prims.sort!

  # Build global index list
  allidx=prims.inject([]) do |index, prim|
    if prim.typename==XPPrim::TRIS && !prim.i.base
      prim.i.base=index.length
      index+prim.i
    else
      index
    end
  end

  # find most popular texture
  tex=nil
  texcount={}
  vt.each do |v|
    if v[0]
      tex=v[0]
      if texcount.has_key?(tex)
        texcount[tex]+=1
      else
        texcount[tex]=1
      end
    end
  end
  multitex=(texcount.length>1)
  if multitex
    tex=texcount.index(texcount.values().sort()[-1])	# most popular
  end
  texfile=tex.filename.split(/[\/\\:]+/)[-1] if tex	# basename

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
    outfile.write("TEXTURE\t\t#{texfile}\n")
    if File.exists? "#{tex.filename[0..-5]}_LIT#{texfile[-4..-1]}"
      outfile.write("TEXTURE_LIT\t#{texfile[0..-5]}_LIT#{texfile[-4..-1]}\n")
    end
    prims.each do |prim|
      if prim.attrs&XPPrim::NDRAPED==0
        outfile.write("TEXTURE_DRAPED\t#{texfile}\n")
        break
      end
    end
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

  # Write commands. Batch up primitives that share state into a single TRIS statement
  current_attrs=XPPrim::NPOLY|XPPrim::NDRAPED	# X-Plane's default state
  current_anim=nil
  current_base=0
  current_count=0
  prims.each do |prim|
    if current_count>0 && (prim.attrs!=current_attrs || prim.anim!=current_anim)
      # Attribute change - flush TRIS
      outfile.write("#{XPAnim.ins(current_anim)}TRIS\t#{current_base} #{current_count}\n")
      current_base += current_count
      current_count = 0
    end

    ins=XPAnim.ins(current_anim)	# indent level for any attribute changes
    if current_anim == prim.anim
      newa=olda=[]
    else
      # close animations
      anim=current_anim
      olda=[]
      while anim do olda.unshift(anim); anim=anim.parent end
      anim=prim.anim
      newa=[]
      while anim do newa.unshift(anim); anim=anim.parent end
      # pop until we hit a parent common to old and new animations
      (olda.length-1).downto(0) do |i|
        if i>newa.length || olda[i]!=newa[i]
          ins=XPAnim.ins(olda[i].parent)
          outfile.write("#{ins}ANIM_end\n")
          olda.pop()
        else
          break
        end
      end
    end

    # In priority order
    if current_attrs&XPPrim::NPOLY==0 && prim.attrs&XPPrim::NPOLY!=0
      outfile.write("#{ins}ATTR_layer_group\tobjects 0\n#{ins}ATTR_poly_os\t0\n")
    elsif current_attrs&XPPrim::NPOLY!=0 && prim.attrs&XPPrim::NPOLY==0
      outfile.write("#{ins}ATTR_layer_group\tobjects -5\n#{ins}ATTR_poly_os\t2\n")
    end
    if current_attrs&XPPrim::NDRAPED==0 && prim.attrs&XPPrim::NDRAPED!=0
      outfile.write("#{ins}ATTR_no_draped\n")
    elsif current_attrs&XPPrim::NDRAPED!=0 && prim.attrs&XPPrim::NDRAPED==0
      outfile.write("#{ins}ATTR_draped\n")
    end
    if current_attrs&XPPrim::ALPHA==0 && prim.attrs&XPPrim::ALPHA!=0
      outfile.write("#{ins}####_alpha\n")
    elsif current_attrs&XPPrim::ALPHA!=0 && prim.attrs&XPPrim::ALPHA==0
      outfile.write("#{ins}####_no_alpha\n")
    end
    if current_attrs&XPPrim::SHINY==0 && prim.attrs&XPPrim::SHINY!=0
      outfile.write("#{ins}ATTR_shiny_rat\t1\n")
    elsif current_attrs&XPPrim::SHINY!=0 && prim.attrs&XPPrim::SHINY==0
      outfile.write("#{ins}ATTR_shiny_rat\t0\n")
    end
    if current_attrs&XPPrim::HARD==0 && prim.attrs&XPPrim::HARD!=0
      outfile.write("#{ins}ATTR_hard\n")
    elsif current_attrs&XPPrim::HARD!=0 && prim.attrs&XPPrim::HARD==0
      outfile.write("#{ins}ATTR_no_hard\n")
    end
    if current_attrs&XPPrim::DECK==0 && prim.attrs&XPPrim::DECK!=0
      outfile.write("#{ins}ATTR_hard_deck\n")
    elsif current_attrs&XPPrim::DECK!=0 && prim.attrs&XPPrim::DECK==0
      outfile.write("#{ins}ATTR_no_hard\n")
    end

    # Animation
    newa[(olda.length..-1)].each do |anim|
      outfile.write("#{XPAnim.ins(anim.parent)}ANIM_begin\n")
      ins=XPAnim.ins(anim)
      outfile.write("#{ins}# #{anim.label}\n")

      anim.hideshow.each do |hs, dataref, from, to|
        outfile.write("#{ins}ANIM_#{hs}\t#{from} #{to}\t#{dataref}\n")
      end

      if anim.t.length==1
        # not moving - save a potential accessor callback
        outfile.printf("#{ins}ANIM_trans\t%9.4f %9.4f %9.4f\t%9.4f %9.4f %9.4f\t0 0\tnone\n",
                       anim.t[0][0], anim.t[0][2], -anim.t[0][1], anim.t[0][0], anim.t[0][2], -anim.t[0][1])
      elsif anim.t.length!=0
        outfile.write("#{ins}ANIM_trans_begin\t#{anim.dataref}\n")

        0.upto(anim.t.length-1) do |i|
          outfile.printf("#{ins}\tANIM_trans_key\t\t#{anim.v[i]}\t%9.4f %9.4f %9.4f\n",
                         anim.t[i][0], anim.t[i][2], -anim.t[i][1])
        end
        outfile.write("#{ins}\tANIM_keyframe_loop\t#{anim.loop}\n") if anim.loop.to_f!=0.0
        outfile.write("#{ins}ANIM_trans_end\n")
      end

      [[anim.rx,[1,0,0]], [anim.ry,[0,1,0]], [anim.rz,[0,0,1]]].each do |r,axis|
        if r.length!=0
          outfile.printf("#{ins}ANIM_rotate_begin\t%d %d %d\t#{anim.dataref}\n",
                         axis[0], axis[2], -axis[1])

          0.upto(r.length-1) do |i|
            outfile.printf("#{ins}\tANIM_rotate_key\t\t#{anim.v[i]}\t%7.2f\n", r[i])
          end
          outfile.write("#{ins}\tANIM_keyframe_loop\t#{anim.loop}\n") if anim.loop.to_f!=0.0
          outfile.write("#{ins}ANIM_rotate_end\n")
        end
      end

    end

    # Process the primitive
    if prim.typename==XPPrim::LIGHT
      args=prim.i[0].split
      type=args.shift
      if SU2XPlane::LIGHTNAMED.include?(type)
        name=args.shift
        outfile.printf("#{ins}%s\t%s\t%9.4f %9.4f %9.4f\t%s\n", type, name, prim.i[1], prim.i[3], -prim.i[2], args.join(' '))
      else
        outfile.printf("#{ins}%s\t%9.4f %9.4f %9.4f\t%s\n", type, prim.i[1], prim.i[3], -prim.i[2], args.join(' '))
      end
    elsif current_count==0
      current_base  = prim.i.base
      current_count = prim.i.length
    elsif current_base+current_count != prim.i.base
      # Indices can get out of order when dealing with an animated component that is re-used. But a component
      # shouldn't have multiple allocations in the global table without a state change so this code shouldn't be called.
      outfile.write("#{XPAnim.ins(current_anim)}TRIS\t#{current_base} #{current_count}\n")
      current_base  = prim.i.base
      current_count = prim.i.length
    else
      # Normal case - batch up TRIS
      current_count += prim.i.length
    end

    current_attrs = prim.attrs
    current_anim  = prim.anim
  end

  # Flush last batch of TRIS and close any open animation
  outfile.write("#{XPAnim.ins(current_anim)}TRIS\t#{current_base} #{current_count}\n") if current_count>0
  anim=current_anim
  while anim do
    outfile.write("#{XPAnim.ins(anim.parent)}ANIM_end\n")
    anim=anim.parent
  end

  outfile.write("\n# Built with SketchUp #{Sketchup.version}. Exported with SketchUp2XPlane #{SU2XPlane::Version}.\n")
  outfile.close

  msg=XPL10n.t("Wrote %s triangles to") % (allidx.length/3) + "\n" + outpath + "\n"
  msg+="\n" + XPL10n.t('Warning: %s faces are untextured') % notex + '.' if notex
  msg+="\n" + XPL10n.t('Warning: You used multiple texture files; using file:') + "\n" + tex.filename if multitex
  msg+="\n" + XPL10n.t('Warning: Texture width is not a power of two') + '.' if tex and (tex.image_width & tex.image_width-1)!=0
  msg+="\n" + XPL10n.t('Warning: Texture height is not a power of two') + '.' if tex and (tex.image_height & tex.image_height-1)!=0
  if notex and not multitex and not model.materials["XPUntextured"]
    yesno=UI.messagebox msg+"\n" + XPL10n.t('Do you want to highlight the untextured faces?'), MB_YESNO,"X-Plane export"
    XPlaneHighlight() if yesno==6
  else
    UI.messagebox msg, MB_OK,"X-Plane export"
  end
end
