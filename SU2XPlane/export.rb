# -*- coding: utf-8 -*-
#
# X-Plane export
#
# Copyright (c) 2006-2014 Jonathan Harris
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#

module Marginal
  module SU2XPlane

    class XPIndices < Array
      attr_accessor(:base)	# Offset in global table
    end

    class XPPrim

      include Comparable

      # Flags for export in order of priority low->high. Attributes represented by lower bits are flipped more frequently on output.
      HARD=1
      DECK=2
      SHINY=4
      # animation should come here
      ALPHA=8		# must be last for correctness
      NDRAPED=16	# negated so ground polygons come first (don't care about alpha for ground polygons)
      NPOLY=32		# ditto

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
        c = ((self.attrs&(NDRAPED|NPOLY|ALPHA)) <=> (other.attrs&(NDRAPED|NPOLY|ALPHA)))
        return c if c!=0
        if self.anim && other.anim
          c = (self.anim <=> other.anim)
          return c if c!=0
        elsif self.anim
          return 1	# no animation precedes animation
        elsif other.anim
          return -1	# no animation precedes animation
        end
        c = ((self.attrs&(SHINY|DECK|HARD)) <=> (other.attrs&(SHINY|DECK|HARD)))
        return c if c!=0
        c = (self.typename <=> other.typename)
        return c
      end

    end

    class XPAnim

      include Comparable

      attr_reader(:parent, :cachekey, :transformation, :dataref, :v, :loop, :idx, :t, :rx, :ry, :rz, :hideshow, :label)

      @@last_idx = 0

      def initialize(component, parent, trans)
        @parent=parent	# parent XPAnim, or nil if parent is top-level - i.e. not animated
        @cachekey=component.definition.object_id
        @transformation = trans * component.transformation
        @transformation = Geom::Transformation.scaling(@transformation.xscale, @transformation.yscale, @transformation.zscale)		# transformation to be applied to sub-geometry - just scale
        @dataref=component.XPDataRef	# DataRef, w/ index if any
        @v=component.XPValues		# 0 or n keyframe dataref values. Note: stored as String
        @loop=component.XPLoop		# loop dataref value. Note: stored as String
        @idx = (@@last_idx += 1)	# Sort index
        @t=component.XPTranslations(trans)	# 0, 1 or n set of translation coordinates (0=just hide/show, 1=rotation w/ no translation)
        @rx=@ry=@rz=[]			# 0, 1 or n rotation angles in degrees
        @hideshow=component.XPHideShow	# show/hide values [show/hide, dataref, from, to]
        @label=(component.name!='' ? component.name : "<#{component.definition.name}>")	# tag in output file

        # if translation constant across keyframes reduce to one entry
        @t=[@t[0]] if (@t.inject({}) { |h,v| h.store(v,true) && h }).length == 1

        if component.XPCountFrames>0 && !(0...component.XPCountFrames).inject(nil){|memo,frame| memo||(trans * component.XPTransformation(frame)).XPEuler}
          # rotation just about y axis - adjust to avoid gimbal lock
          trans = Geom::Transformation.rotation(Geom::Point3d.new(0,0,0), Geom::Vector3d.new(0,1,0), Math::PI/2) * trans
          @ry = [-90]
        end

        rot=component.XPRotations(trans)
        if (rot.inject({}) { |h,v| h.store(v,true) && h }).length <= 1
          # no keyframes, or rotation constant across all keyframes - just use current rotation
          rot = [(trans*component.transformation).XPEuler(true).map{ |a| a.radians.round(Marginal::SU2XPlane::P_A) }]
          if @t.length <= 1 && rot == [[0,0,0]]
            # no animation of any kind
            raise ArgumentError if @hideshow==[]	# no Hide/Show either - this is just a vanilla component
            @transformation = trans*component.transformation	# apply this component's transformation to sub-geometry
            @t=[]
            return
          end
          if @t.length <= 1
            # no keyframes, or translation constant across all keyframes - just use current translation
            @t=[(trans*component.transformation).origin.to_a.map { |v| v.round(Marginal::SU2XPlane::P_V) }]
          end
          @rz = [rot[0][2]]
          @ry = [rot[0][1]]
          @rx = [rot[0][0]]
        else
          # we have rotation keyframes
          if (rot.inject({}) { |h,v| h.store(v[2],true) && h }).length > 1
            @rz = rot.map { |v| v[2] }
          elsif rot[0][2]!=0
            @rz = [rot[0][2]]	# rotation is constant
          end
          if (rot.inject({}) { |h,v| h.store(v[1],true) && h }).length > 1
            @ry = rot.map { |v| v[1] }
          elsif rot[0][1]!=0
            @ry = [rot[0][1]]	# rotation is constant
          end
          if (rot.inject({}) { |h,v| h.store(v[0],true) && h }).length > 1
            @rx = rot.map { |v| v[0] }
          elsif rot[0][0]!=0
            @rx = [rot[0][0]]	# rotation is constant
          end
        end
      end

      # For sorting animations. We create animations by depth-first traversal through the hierarchy, which
      # happens to also be fine for writing to the OBJ file.
      def <=>(other)
        return self.idx <=> other.idx
      end

      def self.last_idx
        @@last_idx
      end

      def self.last_idx=(x)
        @@last_idx = x
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
    def self.XPlaneAccumPolys(entities, anim, trans, tw, vt, prims, primcache, usedmaterials)

      start = Time.now
      vtlookup = {}	# indices of vertices added at this level
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

      # filter out invisible
      entities = entities.reject { |ent| ent.hidden? || !ent.layer.visible? }

      # Process in roughly same order as output so indices are output in order - so ComponentInstances last

      entities.grep(Sketchup::Text).each do |ent|
        light=ent.text[/\S*/]
        if ent.point && (SU2XPlane::LIGHTNAMED.include?(light) || SU2XPlane::LIGHTCUSTOM.include?(light))
          lightprim=XPPrim.new(XPPrim::LIGHT, anim)
          lightprim.i = [ent.text] + (trans*ent.point).to_a.map { |v| v.round(SU2XPlane::P_V) }
          prims << lightprim
          primcache[anim.cachekey].push(lightprim) if anim
        end
      end

      entities.grep(Sketchup::Face).each do |ent|
        # if neither side has material then output both sides,
        # otherwise outout the side(s) with materials
        nomats = (not ent.material and not ent.back_material)

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
        n_polys = mesh.count_polygons
        usedmaterials[nil] += n_polys if nomats	# count one side only

        [true,false].each do |front|
          if front
            material=ent.material
          else
            material=ent.back_material
          end
          reverseidx=!(front^(det<0))

          if nomats or (material and material.alpha>0.0)
            if material and material.texture
              usedmaterials[material] += n_polys
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
              usedmaterials[nil] += n_polys if not nomats
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
              thisvt << v.to_a.map { |j| j.round(SU2XPlane::P_V) } + n.to_a.map { |j| j.round(SU2XPlane::P_N) } + [(u.x/u.z-minu).round(SU2XPlane::P_UV), (u.y/u.z-minv).round(SU2XPlane::P_UV)]
            end

            for i in (1..mesh.count_polygons)
              thistri=[]	# indices in this face
              mesh.polygon_at(i).each do |index|
                v = thisvt[(index>0 ? index : -index) - 1]
                # Look for duplicate in Vertices already added at this level
                thisidx = vtlookup[v]
                if !thisidx
                  # Didn't find a duplicate vertex
                  vtlookup[v] = thisidx = vt.length
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
      end	# entities.grep(Sketchup::Face).each do |ent|

      entities.grep(Sketchup::Group).each do |ent|
        XPlaneAccumPolys(ent.entities, anim, trans*ent.transformation, tw, vt, prims, primcache, usedmaterials)
      end

      # output Components in same order as listed in Outliner window
      entities.grep(Sketchup::ComponentInstance).sort{ |a,b| "#{a.name} <#{a.definition.name}>" <=> "#{b.name} <#{b.definition.name}>" }.each do |ent|
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
            XPlaneAccumPolys(ent.definition.entities, newanim, newanim.transformation, tw, vt, prims, primcache, usedmaterials)
          end
        rescue ArgumentError
          # This component is not an animation
          XPlaneAccumPolys(ent.definition.entities, anim, trans*ent.transformation, tw, vt, prims, primcache, usedmaterials) unless ['Susan','Derrick','Sang','Nancy'].include? ent.definition.name	# Silently skip figures
        end
      end

      p "#{Time.now - start}s in XPlaneAccumPolys" if Benchmark
    end

    #-----------------------------------------------------------------------------

    def self.XPlaneExport()

      model=Sketchup.active_model
      if model.path=='' || !model.path
        UI.messagebox L10N.t("Save this SketchUp model first.\n\nI don't know where to create the X-Plane object file\nbecause you have never saved this SketchUp model."), MB_OK, "X-Plane export"
        return
      end
      if model.path.split(/[\/\\:]+/)[-1].unpack('C*').inject(false) { |memo,c| memo || c<32 || c>=128 }
        UI.messagebox L10N.t("Object name must only use ASCII characters.\n\nPlease re-save this SketchUp model with a new file name that does not contain accented letters, or non-Western characters."), MB_OK, "X-Plane export"
        return
      end
      if model.active_path!=nil
        UI.messagebox L10N.t("Close all open Components and Groups first.\n\nI can't export while you have Components and/or\nGroups open for editing."), MB_OK, "X-Plane export"
        return
      end
      begin
        XPlaneDoExport()
      rescue => e
        puts "Error: #{e.inspect}", e.backtrace	# Report to console
        UI.messagebox L10N.t('Internal error!') + "\n\n" + L10N.t("Saving your model, then quitting and restarting\nSketchUp might clear the problem."), MB_OK, 'X-Plane export'
        return
      end

    end


    def self.XPlaneDoExport()

      start = Time.now
      time = Time.now
      model=Sketchup.active_model
      outpath=model.path[0...-3]+'obj'
      tw = Sketchup.create_texture_writer
      vt=[]		# array of [vx, vy, vz, nx, ny, nz, u, v]
      prims=[]	# arrays of XPPrim
      usedmaterials = Hash.new(0)
      XPAnim.last_idx = 0
      XPlaneAccumPolys(model.entities, nil, Geom::Transformation.scaling(1.to_m, 1.to_m, 1.to_m), tw, vt, prims, {}, usedmaterials)	# coords always returned in inches!
      if prims.empty?
        UI.messagebox L10N.t('Nothing to export!'), MB_OK,"X-Plane export"
        return
      end
      p "#{Time.now - time}s to accumulate" if Benchmark
      time = Time.now

      # Determine most used material
      sep = File::ALT_SEPARATOR || File::SEPARATOR
      n_faces = n_untextured = usedmaterials.delete(nil){|k|0}	# Ruby 1.8 returns nil not default_value if not found
      if usedmaterials.empty?
        mymaterial = nil
        n_textures = 0
      else
        byuse = usedmaterials.invert
        n_faces += byuse.keys.inject { |sum,n| sum+n }
        mymaterial = byuse[byuse.keys.sort[-1]]	# most popular material

        # Write out the texture in the most popular material first if missing
        basename = mymaterial.texture.filename.split(/[\/\\:]+/)[-1]
        if !File.file? mymaterial.texture.filename
          newfile = File.dirname(model.path) + sep + basename.split(/\.([^.]*)$/)[0] + ".png"
          XPlaneMaterialsWrite(model, tw, mymaterial, newfile) if !File.file? newfile	# TextureWriter needs an Entity that uses the material, not the material itself
        end

        # Write out missing textures in remaining materials
        usedmaterials.each_key do |material|
          if material!=mymaterial && material.texture && material.texture.filename
            if basename.casecmp(material.texture.filename.split(/[\/\\:]+/)[-1])==0
              # it uses the same texture as our material
              usedmaterials[mymaterial] += usedmaterials.delete(material){|k|0}
            elsif !File.file? material.texture.filename
              # it uses a different texture than our material - write it anyway
              newfile = File.dirname(model.path) + sep + material.texture.filename.split(/[\/\\:]+/)[-1].split(/\.([^.]*)$/)[0] + ".png"
              XPlaneMaterialsWrite(model, tw, material, newfile) if !File.file? newfile	# TextureWriter needs an Entity that uses the material, not the material itself
            end
          end
        end

        if basename.unpack('C*').inject(false) { |memo,c| memo || c<=32 || c>=128 }
          UI.messagebox L10N.t("Texture file name must only use ASCII characters.\n\nPlease re-name the file \"#{basename}\" with a file name that does not contain spaces, accented letters, or non-Western characters."), MB_OK, "X-Plane export"
          return
        end

        n_textures = usedmaterials.length
      end
      p "#{Time.now - time}s to write materials" if Benchmark
      time = Time.now

      # Sort to minimise state changes
      prims.sort!
      p "#{Time.now - time}s to sort primitives" if Benchmark
      time = Time.now

      # Build global index list
      allidx=prims.inject([]) do |index, prim|
        if prim.typename==XPPrim::TRIS && !prim.i.base
          prim.i.base=index.length
          index+prim.i
        else
          index
        end
      end
      p "#{Time.now - time}s to build index list" if Benchmark
      time = Time.now

      tex = mymaterial && mymaterial.texture
      texfile = tex && tex.filename.split(/[\/\\:]+/)[-1]	# basename
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
        outfile.printf("VT\t%9.4f %9.4f %9.4f\t%6.3f %6.3f %6.3f\t%7.4f %7.4f\n", v[0], v[2], -v[1], v[3], v[5], -v[4], v[6], v[7])
      end
      outfile.write("\n")
      for i in (0...allidx.length/10)
        outfile.write("IDX10\t#{allidx[i*10..i*10+9].join(' ')}\n")
      end
      for i in (allidx.length-(allidx.length%10)...allidx.length)
        outfile.write("IDX\t#{allidx[i]}\n")
      end
      outfile.write("\n")
      p "#{Time.now - time}s to write indices" if Benchmark
      time = Time.now

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
            outfile.printf("#{ins}ANIM_trans\t%9.4f %9.4f %9.4f\t%9.4f %9.4f %9.4f\t0 0\tnone\n", anim.t[0][0], anim.t[0][2], -anim.t[0][1], anim.t[0][0], anim.t[0][2], -anim.t[0][1])
          elsif anim.t.length!=0
            outfile.write("#{ins}ANIM_trans_begin\t#{anim.dataref}\n")
            0.upto(anim.t.length-1) do |i|
              outfile.printf("#{ins}\tANIM_trans_key\t\t#{anim.v[i]}\t%9.4f %9.4f %9.4f\n", anim.t[i][0], anim.t[i][2], -anim.t[i][1])
            end
            outfile.write("#{ins}\tANIM_keyframe_loop\t#{anim.loop}\n") if anim.loop.to_f!=0.0
            outfile.write("#{ins}ANIM_trans_end\n")
          end

          [[anim.rx,[1,0,0]], [anim.ry,[0,1,0]], [anim.rz,[0,0,1]]].each do |r,axis|
            if r.length==1
              outfile.printf("#{ins}ANIM_rotate\t\t%d %d %d\t%7.2f %7.2f\t0 0\tnone\n", axis[0], axis[2], -axis[1], r[0], r[0])
            elsif r.length!=0
              outfile.printf("#{ins}ANIM_rotate_begin\t%d %d %d\t#{anim.dataref}\n", axis[0], axis[2], -axis[1])
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
      p "#{Time.now - time}s to write commands" if Benchmark
      p "#{Time.now - start}s total" if Benchmark

      msg=L10N.t("Wrote %s triangles to") % (allidx.length/3) + "\n" + outpath + "\n"
      msg+="\n" + L10N.t('Warning: You used multiple texture files; using file:') + "\n" + (File.file? tex.filename and tex.filename + "\n" + L10N.t('from material') + ' "' + mymaterial.display_name + '".' or File.dirname(model.path) + sep + texfile) + "\n" if  n_textures>1
      msg+="\n" + L10N.t('Warning: Texture width is not a power of two') + ".\n" if tex and (tex.image_width & tex.image_width-1)!=0
      msg+="\n" + L10N.t('Warning: Texture height is not a power of two') + ".\n" if tex and (tex.image_height & tex.image_height-1)!=0
      msg+="\n" + (mymaterial and (L10N.t('Warning: %s faces are untextured') % n_untextured) or L10N.t('Warning: All faces are untextured')) + ".\n" if n_untextured>0
      if n_untextured>0 && n_textures<=1 && !model.materials["XPUntextured"]
        yesno=UI.messagebox msg + L10N.t('Do you want to highlight the untextured faces?'), MB_YESNO,"X-Plane export"
        XPlaneHighlight() if yesno==6
      else
        UI.messagebox msg, MB_OK,"X-Plane export"
      end
    end

  end
end
