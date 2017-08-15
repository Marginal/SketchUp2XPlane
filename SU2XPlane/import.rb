#
# X-Plane import
#
# Copyright (c) 2006-2013 Jonathan Harris
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#

require File.join(File.dirname(__FILE__), 'L10N.rb')

module Marginal
  module SU2XPlane

    PIBYTWO = 90.degrees
    SMOOTHANGLE = 35.degrees
    PLANARANGLE = 0.00002	# Faces with normals at angles less than this considered coplanar

    class XPlaneImporterError < StandardError
      attr_reader :message
      def initialize(message)
        @message = message
      end
    end

    class XPlaneImporter < Sketchup::Importer

      def initialize
        @tw = Sketchup.create_texture_writer
      end

      def description
        return L10N.t('X-Plane Object')+' (*.obj)'
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

        return 2 if not file_path
        model=Sketchup.active_model

        begin
          file=File.new(file_path, 'r')
          enc = String.new.respond_to?(:force_encoding)
          line = (enc ? file.readline.force_encoding(Encoding::ASCII_8BIT) : file.readline).split(/\/\/|#/)[0].strip()
          if line.include? ?\r
            # Old Mac \r line endings
            linesep="\r"
            file.rewind
            line = (enc ? file.readline(linesep).force_encoding(Encoding::ASCII_8BIT) : file.readline(linesep)).split(/\/\/|#/)[0].strip()
          else
            linesep="\n"
          end
          raise XPlaneImporterError, L10N.t('This is not a valid X-Plane file') if not ['A','I'].include?(line)
          line = (enc ? file.readline(linesep).force_encoding(Encoding::ASCII_8BIT) : file.readline(linesep)).split(/\/\/|#/)[0].strip()
          if line.split()[0]=='2'
            raise XPlaneImporterError, L10N.t("Can't read X-Plane version %s files") % '6'
          elsif line!='800'
            raise XPlaneImporterError, L10N.t("Can't read X-Plane version %s files") % (line.to_i/100)
          elsif not (enc ? file.readline(linesep).force_encoding(Encoding::ASCII_8BIT) : file.readline(linesep)).split(/\/\/|#/)[0].strip()=='OBJ'
            raise XPlaneImporterError, L10N.t('This is not a valid X-Plane file')
          end

          # Adding and/or texturing a triangle face can fail if points/UVs are co-located or co-linear (within
          # SketchUp's tolerances).
          # So under Sketchup<=2013 we put an exception handler round each individual new face and each texture
          # positioning on a face, which is slow but robust.
          # However, SketchUp 2014 (14.0.4900) doesn't handle exceptions cleanly (it behaves as if it does an
          # abort_operation) so instead we use Entities.add_faces_from_mesh which doesn't generate exceptions on
          # poor UVs, and is also slightly faster. (PolygonMesh.set_uv is new in SketchUp 2014, so can't use this
          # technique in older versions).
          @mesh = Geom::PolygonMesh.new
          usepolygonmesh = @mesh.respond_to?('set_uv')

          model.start_operation("#{L10N.t('Import')} #{File.basename(file_path)}", true)
          begin
            nullUV = Geom::Point3d.new([0,0,1])
            entities=model.active_entities	# Open component, else top level
            @material = nil
            @reverse = model.materials["XPReverse"]
            if (not @reverse) or (@reverse.texture and @reverse.texture.filename)
              @reverse = model.materials.add("XPReverse")
              @reverse.color = "Magenta"
            end
            @reverse.alpha = 0
            @reverse.texture = nil
            @cull = true
            @invisible = false
            @hard = false
            @deck = false
            @poly = false
            @alpha = true
            @shiny = false
            vt=[]
            nm=[]
            uv=[]
            idx=[]
            msg={}
            # Animation context
            anim_context=[]			# Stack of animation ComponentInstances
            anim_off=[Geom::Vector3d.new]	# stack of compensating offsets for children of animations
            anim_axes=Geom::Vector3d.new
            anim_t=[]			# Stack of translations {value => Point3d}
            anim_r=[]			# Stack of rotations    {value => [[Vector3d, angle]]}

            while true
              line=file.gets(linesep)
              break if not line
              if line[0..10]=='####_alpha'
                add_collected_faces(entities)
                @alpha = true
                next
              elsif line[0,13]=='####_no_alpha'
                add_collected_faces(entities)
                @alpha = false
                next
              end
              line = enc ? line.force_encoding(Encoding::ASCII_8BIT).split(/\/\/|#/)[0].strip() : line.split(/\/\/|#/)[0].strip()
              next if line.empty?
              c=line.split()
              cmd=c.shift
              case cmd
              when 'TEXTURE'
                texture=line[7..-1].strip()
                if not texture.empty?
                  orig_ext=File.extname(texture)
                  texture = texture.tr(':\\','/').chomp(orig_ext)	# unixify, minus extension
                  texdir = File.dirname(file_path)
                  @material = model.materials.add(File.basename(texture))
                  [orig_ext,'.png'].each do |ext|	# also look for a PNG
                    @material.texture = File.join(texdir, texture+ext)
                    @material.texture = File.join(texdir, texture.sub(/custom objects/i, 'custom object textures') + ext) if not @material.texture	# v7 style
                    break if @material.texture
                  end
                  if not @material.texture
                    # lack of material texture crashes SketchUp somewhere
                    model.abort_operation
                    if File.file?(File.join(texdir, texture+orig_ext)) && orig_ext.casecmp('.dds')==0
                      raise XPlaneImporterError, L10N.t("Can't read DDS files. Convert %s to PNG format") % File.join(texdir, texture+orig_ext)
                    else
                      raise XPlaneImporterError, L10N.t("Can't read texture file %s") % File.join(texdir, texture+orig_ext)
                    end
                    return 0	# Pretend we succeeded to suppress alert dialog
                  else
                    @material.texture.size = 10.m	# arbitrary
                  end
                end
              when 'VT'
                vt << Geom::Point3d.new(c[0].to_f.m, -c[2].to_f.m, c[1].to_f.m)
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

                if usepolygonmesh

                  while i<start+count
                    if vt[idx[i]].on_line?([vt[idx[i+1]], vt[idx[i+2]]]) || vt[idx[i+1]].on_line?([vt[idx[i+2]], vt[idx[i]]]) || vt[idx[i+2]].on_line?([vt[idx[i]], vt[idx[i+1]]])	# degenerate
                      i+=3	# next tri
                      next
                    end
                    pts = []
                    j = i+2
                    while j>=i
                      p = @mesh.add_point(vt[idx[j]].offset(anim_off.last))
                      if p==@mesh.count_points	# new point (1-based indexing)
                        @mesh.set_uv(p, uv[idx[j]], true)	# just do the front face - add_faces_from_mesh handles back-to-back Faces correctly
                        pts << p
                      elsif @mesh.uv_at(p, true).to_a == uv[idx[j]].to_a	# existing point with same UV
                        pts << p
                      else	# UV discontinuity - commit outstanding triangles and redo
                        add_collected_faces(entities)
                        break
                      end
                      j-=1
                    end
                    if j<i
                      @mesh.add_polygon(pts)
                      i+=3	# next tri
                    else
                      # had UV discontinuity - redo this triangle
                    end
                  end

                else	# !usepolygonmesh

                  while i<start+count
                    thisvt = [vt[idx[i+2]].offset(anim_off.last), vt[idx[i+1]].offset(anim_off.last), vt[idx[i]].offset(anim_off.last)]
                    thisnm = [nm[idx[i+2]],nm[idx[i+1]],nm[idx[i]]]
                    thisuv = [uv[idx[i+2]],uv[idx[i+1]],uv[idx[i]]]
                    i += 3
                    next if thisvt[0].on_line?([thisvt[1], thisvt[2]]) || thisvt[1].on_line?([thisvt[2], thisvt[0]]) || thisvt[2].on_line?([thisvt[0], thisvt[1]])	# co-located / co-linear => degenerate
                    begin
                      face=entities.add_face thisvt
                    rescue ArgumentError => e
                      p "Error: #{e.inspect}", thisvt, e.backtrace[0]	# Report to console
                      msg[L10N.t("Ignoring some geometry that couldn't be imported")]=true
                      next	# next tri
                    end

                    if @material && (thisuv[0]!=nullUV || thisuv[1]!=nullUV || thisuv[2]!=nullUV)
                      pts = [thisvt[0],thisuv[0], thisvt[1],thisuv[1], thisvt[2],thisuv[2]]
                      begin
                        if face.material
                          # Face is back-to-back with existing face
                          face.back_material = @material
                          face.position_material(@material, pts, false)
                        else
                          face.reverse! if thisvt[0].z==0 && thisvt[1].z==0 && thisvt[2].z==0 && face.normal.angle_between(thisnm[0]) > PIBYTWO	# special handling for ground plane
                          face.material = @material
                          face.position_material(@material, pts, true)
                          if @cull
                            face.back_material = @reverse
                          else
                            face.back_material = @material
                            face.position_material(@material, pts, false)
                          end
                        end
                      rescue ArgumentError => e
                        # SketchUp can't always compute texture layout -> <ArgumentError: Could not compute valid matrix from points>
                        # p "Error: #{e.inspect}", pts, e.backtrace[0]	# Report to console
                        next if !face.valid?	# SketchUp sometimes decides that it no longer needs the face
                      end
                    end
                    face.set_attribute(ATTR_DICT, ATTR_ALPHA_NAME,1) if @alpha
                    face.set_attribute(ATTR_DICT, ATTR_INVISIBLE_NAME, 1) if @invisible
                    face.set_attribute(ATTR_DICT, ATTR_HARD_NAME, 1) if @hard
                    face.set_attribute(ATTR_DICT, ATTR_DECK_NAME, 1) if @deck
                    face.set_attribute(ATTR_DICT, ATTR_POLY_NAME, 1) if @poly
                    face.set_attribute(ATTR_DICT, ATTR_SHINY_NAME,1) if @shiny
                  end

                end		# usepolygonmesh

              when 'ATTR_LOD'
                if c[0].to_f>0.0
                  msg[L10N.t('Ignoring lower level(s) of detail')]=true
                  break
                end

              when 'ATTR_reset'
                add_collected_faces(entities)	# commit any outstanding triangles before we change state
                @cull = true
                @invisible = false
                @hard = false
                @deck = false
                @poly = false
                @alpha = true
                @shiny = false
              when 'ATTR_cull'
                add_collected_faces(entities)
                @cull = true
              when 'ATTR_nocull', 'ATTR_no_cull'
                add_collected_faces(entities)
                @cull = false
              when 'ATTR_draw_disable'
                add_collected_faces(entities)
                @invisible = true
              when 'ATTR_draw_enable'
                add_collected_faces(entities)
                @invisible = false
              when 'ATTR_hard'
                add_collected_faces(entities)
                @hard = true
                @deck = false
              when 'ATTR_hard_deck'
                add_collected_faces(entities)
                @hard = false
                @deck = true
              when 'ATTR_no_hard'
                add_collected_faces(entities)
                @hard = false
                @deck = false
              when 'ATTR_poly_os'
                add_collected_faces(entities)
                @poly = c[0].to_f > 0.0
              when 'ATTR_draped'
                add_collected_faces(entities)
                @poly = true
              when 'ATTR_no_draped'
                add_collected_faces(entities)
                @poly = false
              when 'ATTR_shiny_rat', 'GLOBAL_specular'
                add_collected_faces(entities)
                @shiny = c[0].to_f > 0.0
              when 'ATTR_blend', 'ATTR_shadow_blend', 'GLOBAL_shadow_blend'
                add_collected_faces(entities)
                @alpha = true
              when 'ATTR_no_blend'
                add_collected_faces(entities)
                @alpha = false

              when 'ANIM_begin'
                add_collected_faces(entities)	# commit any outstanding triangles before we change to new context
                anim_context.push(entities.add_group.to_component)
                anim_context.last.definition.name=L10N.t('Component')+'#1'	# Otherwise has name Group#n. SketchUp will uniquify.
                anim_context.last.XPLoop=''				# may not be set below
                anim_off.push(anim_off.last.clone)			# inherit parent offset
                anim_t.push({})
                anim_r.push(Hash.new{|h,k|h[k]=[]})
                entities=anim_context.last.definition.entities	# To hold child geometry

              when 'ANIM_end'
                # we won't visit this Component again so commit any outstanding triangles and soften
                add_collected_faces(entities)
                soften_edges(entities)

                # Values may be specified out of sequence (eg by 3dsMax plugin) and number of translation and rotation
                # keyframes may not match, so sort frames and interpolate any missing keyframe info
                t = anim_t.pop
                r = anim_r.pop
                # What frames do we have?
                frames = {}
                frame = 0
                keys = (t.keys + r.keys).uniq.sort
                keys.each do |v|
                  frames[v] = frame
                  frame += 1
                end
                # Add translations, and interpolated translations for any missing frames
                if not t.empty?
                  t.each do |v,tt|
                    anim_context.last.XPTranslateFrame(frames[v], tt)
                    anim_context.last.XPSetValue(frames[v], v)
                  end
                  keys.each do |v|
                    if not t.has_key?(v)
                      anim_context.last.set_attribute(ATTR_DICT, ANIM_MATRIX_+frames[v].to_s, XPInterpolated(v).to_a)
                      anim_context.last.XPSetValue(frames[v], v)
                    end
                  end
                end
                # Add rotations, and derive any missing frames (can't just interpolate because missing frames will have translations).
                if not r.empty?
                  rkeys = r.keys.sort
                  keys.each_index do |frame|
                    v = keys[frame]
                    if r.has_key? v
                      r[v].each { |rot| anim_context.last.XPRotateFrame(frame, rot[0], rot[1]) }
                    else
                      if frame==0
                        val_start, val_stop = rkeys[0..1]	# extrapolate before
                      elsif frame==keys.length-1
                        val_start, val_stop = rkeys[-2..-1]	# extrapolate after
                      else
                        val_stop = rkeys[-1]
                        rkeys.each { |val_stop| break if val_stop > v }
                        val_start  = rkeys[rkeys.index(val_stop)-1]
                      end
                      interp = (v - val_start) / (val_stop - val_start)
                      r[val_start].each_index do |i|
                        a_start,a_stop = r[val_start][i][1], r[val_stop][i][1]
                        anim_context.last.XPRotateFrame(frame, r[val_start][i][0], a_start + interp * (a_stop - a_start))
                      end
                    end
                    anim_context.last.XPSetValue(frame, v)
                  end
                end
                anim_context.last.transformation = Geom::Transformation.new(anim_context.last.get_attribute(ATTR_DICT, ANIM_MATRIX_+'0')) if anim_context.last.get_attribute(ATTR_DICT, ANIM_MATRIX_+'0')	# set current position to first keyframe position
                anim_context.pop
                anim_off.pop
                entities=(anim_context.empty? ? model.active_entities : anim_context.last.definition.entities)
              when 'ANIM_trans'
                if [c[0].to_f, c[1].to_f, c[2].to_f] == [c[3].to_f, c[4].to_f, c[5].to_f]
                  # special form for just shifting rotation origin
                  if anim_context.last.transformation.origin==[0,0,0]
                    anim_context.last.transformation=Geom::Transformation.translation(Geom::Point3d.new(c[0].to_f.m, -c[2].to_f.m, c[1].to_f.m).offset(anim_off.last))
                    anim_off[-1]=Geom::Vector3d.new	# We've applied this offset
                  else
                    # Deal with AC3D plugin which shifts origin back - we don't want to shift the component origin back since then the
                    # origin would not be at centre of rotation, and could end up far away from the child geometry
                    anim_off[-1] = Geom::Vector3d.new(c[0].to_f.m, -c[2].to_f.m, c[1].to_f.m)
                  end
                else
                  # v8-style translation
                  anim_context.last.XPDataRef=c[8]
                  anim_t.last[c[6].to_f] = Geom::Point3d.new(c[0].to_f.m, -c[2].to_f.m, c[1].to_f.m).offset(anim_off.last)
                  anim_t.last[c[7].to_f] = Geom::Point3d.new(c[3].to_f.m, -c[5].to_f.m, c[4].to_f.m).offset(anim_off.last)
                  anim_off[-1]=Geom::Vector3d.new	# We've applied this offset
                end
              when 'ANIM_trans_begin'
                anim_context.last.XPDataRef=c[0]
              when 'ANIM_trans_key'
                anim_t.last[c[0].to_f] = Geom::Point3d.new(c[1].to_f.m, -c[3].to_f.m, c[2].to_f.m).offset(anim_off.last)
              when 'ANIM_trans_end'
                anim_off[-1]=Geom::Vector3d.new	# We've applied this offset
              when 'ANIM_rotate'
                if c[3].to_f==c[4].to_f || c[5].to_f==c[6].to_f
                  # 3dsMax exporter does this to rotate component
                  anim_context.last.transformation = Geom::Transformation.rotation(anim_context.last.transformation.origin, Geom::Vector3d.new(c[0].to_f, -c[2].to_f, c[1].to_f), c[3].to_f.degrees) * anim_context.last.transformation
                else
                  anim_axes=Geom::Vector3d.new(c[0].to_f, -c[2].to_f, c[1].to_f)
                  anim_r.last[c[5].to_f].push([anim_axes, c[3].to_f.degrees])
                  anim_r.last[c[6].to_f].push([anim_axes, c[4].to_f.degrees])
                  anim_context.last.XPDataRef=c[7]
                end
              when 'ANIM_rotate_begin'
                anim_axes=Geom::Vector3d.new(c[0].to_f, -c[2].to_f, c[1].to_f)
                anim_context.last.XPDataRef=c[3]
              when 'ANIM_rotate_key'
                anim_r.last[c[0].to_f].push([anim_axes, c[1].to_f.degrees])
              when 'ANIM_keyframe_loop'
                anim_context.last.XPLoop=c[0].to_f
              when 'ANIM_hide', 'ANIM_show'
                anim_context.last.XPAddHideShow(cmd[5..-1], c[2], c[0].to_f, c[1].to_f)

              when 'TEXTURE_LIT', 'TEXTURE_NORMAL', 'TEXTURE_NORMAL_LIT', 'GLOBAL_no_blend', 'ATTR_shade_flat', 'ATTR_shade_smooth', 'ATTR_light_level_reset', 'ANIM_trans_end', 'ANIM_rotate_end', 'IF', 'ENDIF'
                # suppress error message
              when 'POINT_COUNTS'
                tricount = c[3].to_i / 3
              when 'VLINE', 'LINES'
                msg[L10N.t('Ignoring old-style lines')]=true
              when 'VLIGHT', 'LIGHTS'
                msg[L10N.t('Ignoring old-style lights')]=true
              else
                if (LIGHTNAMED+LIGHTCUSTOM).include?(cmd)
                  if LIGHTNAMED.include?(cmd)
                    name=c.shift+' '
                  else
                    name=""
                  end
                  text=entities.add_text(cmd+' '+name+c[3..-1].join(' '), Geom::Point3d.new(c[0].to_f.m, -c[2].to_f.m, c[1].to_f.m))
                  text.vector=Geom::Vector3d.new(0, 0, -5)	# arrow length & direction - arbitrary
                  text.display_leader=true
                else
                  msg[L10N.t('Ignoring command %s') % cmd]=true
                end
              end
            end

            # Commit any outstanding triangles in top-level context and soften
            add_collected_faces(entities)
            soften_edges(entities)

            model.commit_operation
            UI.messagebox(L10N.t("Imported %s triangles") % tricount + ".\n\n" + msg.keys.sort.join("\n"), MB_OK, 'X-Plane import')
            return 0	# Success

          rescue XPlaneImporterError => e
            model.abort_operation			# Otherwise SketchUp crashes on half-imported stuff
            UI.messagebox L10N.t("Can't import %s") % file_path.split(/\/|\\/)[-1] + ":\n#{e.message}.", MB_OK, 'X-Plane import'

          rescue => e
            puts "Error: #{e.inspect}", e.backtrace	# Report to console
            model.abort_operation			# Otherwise SketchUp crashes on half-imported stuff
            UI.messagebox L10N.t("Can't import %s") % file_path.split(/\/|\\/)[-1] + ":\n" + L10N.t('Internal error') + '.', MB_OK, 'X-Plane import'
          end

        rescue XPlaneImporterError => e
          UI.messagebox L10N.t("Can't import %s") % file_path.split(/\/|\\/)[-1] + ":\n#{e.message}.", MB_OK, 'X-Plane import'
        ensure
          file.close unless !file
        end

        return 0	# Pretend we succeeded to suppress alert dialog
      end


      # Commit any outstanding triangles
      def add_collected_faces(entities)
        return if @mesh.count_points==0
        if @alpha || @hard || @deck ||@poly || @shiny
          oldfaces = entities.grep(Sketchup::Face)
          entities.add_faces_from_mesh(@mesh, Geom::PolygonMesh::NO_SMOOTH_OR_HIDE, @material, @cull ? @reverse : @material)
          @mesh = Geom::PolygonMesh.new
          (entities.grep(Sketchup::Face) - oldfaces).each do |face|
            face.set_attribute(ATTR_DICT, ATTR_ALPHA_NAME,1) if @alpha
            face.set_attribute(ATTR_DICT, ATTR_HARD_NAME, 1) if @hard
            face.set_attribute(ATTR_DICT, ATTR_DECK_NAME, 1) if @deck
            face.set_attribute(ATTR_DICT, ATTR_POLY_NAME, 1) if @poly
            face.set_attribute(ATTR_DICT, ATTR_SHINY_NAME,1) if @shiny
          end
        else
          # common case of default state
          entities.add_faces_from_mesh(@mesh, Geom::PolygonMesh::NO_SMOOTH_OR_HIDE, @material, @cull ? @reverse : @material)
          @mesh = Geom::PolygonMesh.new
        end
      end


      def soften_edges(entities)
        # http://www.thomthom.net/thoughts/2012/06/soft-vs-smooth-vs-hidden-edges/
        for edge in entities.grep(Sketchup::Edge) do

          next if !edge.valid? || edge.faces.length!=2

          # smooth & soften edges
          if edge.faces[0].normal.angle_between(edge.faces[1].normal)<=SMOOTHANGLE
            edge.smooth=true
            edge.soft=true
          end

          # remove coplanar edges
          next if edge.faces[0].normal.angle_between(edge.faces[1].normal)>PLANARANGLE	# same_direction? is too forgiving

          faces0 = edge.faces[0]
          faces1 = edge.faces[1]
          if not faces0.material
            edge.erase!
            next
          end

          uv0=faces0.get_UVHelper(true, true, @tw)
          uv1=faces1.get_UVHelper(true, true, @tw)
          next if !(faces0.back_material==faces1.back_material &&
                    uv0.get_front_UVQ(edge.start.position)== uv1.get_front_UVQ(edge.start.position) &&
                    uv0.get_front_UVQ(edge.end.position)  == uv1.get_front_UVQ(edge.end.position) &&
                    uv0.get_back_UVQ(edge.start.position) == uv1.get_back_UVQ(edge.start.position) &&
                    uv0.get_back_UVQ(edge.end.position)   == uv1.get_back_UVQ(edge.end.position))

          # Check that texture isn't mirrored about this edge
          for v0 in faces0.vertices
            if v0!=edge.start && v0!=edge.end
              u0=uv0.get_front_UVQ(v0.position)
              u0=Geom::Vector3d.new(u0.x/u0.z,u0.y/u0.z,1.0)
              break
            end
          end
          for v1 in faces1.vertices
            if v1!=edge.start && v1!=edge.end
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

  end
end
