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

class XPlaneImporterError < StandardError
  attr_reader :message
  def initialize(message)
    @message = message
  end
end

class XPlaneImporter < Sketchup::Importer

  def description
    return XPL10n.t('X-Plane Object')+' (*.obj)'
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
    pibytwo=90.degrees
    smoothangle=35.degrees
    planarangle=0.00002	# normals at angles less than this considered coplanar

    return 2 if not file_path
    model=Sketchup.active_model

    begin
      file=File.new(file_path, 'r')
      line=file.readline.split(/\/\/|#/)[0].strip()
      if line.include? ?\r
        # Old Mac \r line endings
        linesep="\r"
        file.rewind
        line=file.readline(linesep).split(/\/\/|#/)[0].strip()
      else
        linesep="\n"
      end
      raise XPlaneImporterError, XPL10n.t('This is not a valid X-Plane file') if not ['A','I'].include?(line)
      line=file.readline(linesep).split(/\/\/|#/)[0].strip()
      if line.split()[0]=='2'
        raise XPlaneImporterError, XPL10n.t("Can't read X-Plane version %s files") % '6'
      elsif line!='800'
        raise XPlaneImporterError, XPL10n.t("Can't read X-Plane version %s files") % (line.to_i/100)
      elsif not file.readline(linesep).split(/\/\/|#/)[0].strip()=='OBJ'
        raise XPlaneImporterError, XPL10n.t('This is not a valid X-Plane file')
      end

      model.start_operation("#{XPL10n.t('Import')} #{File.basename(file_path)}", true)
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
        deck=false
        poly=false
        alpha=false
        shiny=false
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
          line=line.split(/\/\/|#/)[0].strip()
          next if line.empty?
          c=line.split()
          cmd=c.shift
          case cmd
          when 'TEXTURE'
            texture=line[7..-1].strip()
            if not texture.empty?
              orig_ext=File.extname(texture)
              texture=texture.tr(':\\','/')[(0...-orig_ext.length)]
              texdir=file_path.split(/\/|\\/)[0...-1]
              material=model.materials.add texture.split(/\/|\\/)[-1]
              [orig_ext,'.png'].each do |ext|	# also look for a PNG
                material.texture=texdir.join('/')+'/'+texture+ext
                if not material.texture
                  i=texdir.collect{|s| s.downcase}.index('custom objects')
                  material.texture=texdir[0...i].join('/')+'/custom object textures/'+texture+ext if i
                end
                break if material.texture
              end
              if not material.texture
                # lack of material crashes SketchUp somewhere
                model.abort_operation
                if File.file?(texdir.join('/')+'/'+texture+orig_ext) && orig_ext.casecmp('.dds')==0
                  raise XPlaneImporterError, XPL10n.t("Can't read DDS files. Convert %s to PNG format") % (texdir.join('/')+'/'+texture+orig_ext)
                else
                  raise XPlaneImporterError, XPL10n.t("Can't read texture file %s") % (texdir.join('/')+'/'+texture+orig_ext)
                end
                return 0	# Pretend we succeeded to suppress alert dialog
              else
                material.texture.size=10.m	# arbitrary
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
            while i<start+count
              thisvt=[vt[idx[i+2]].offset(anim_off.last), vt[idx[i+1]].offset(anim_off.last), vt[idx[i]].offset(anim_off.last)]
              begin
                face=entities.add_face thisvt
              rescue
                msg[XPL10n.t("Ignoring some geometry that couldn't be imported")]=true if !(thisvt[0]==thisvt[1] || thisvt[0]==thisvt[2] || thisvt[1]==thisvt[2])	# SketchUp doesn't like colocated vertices or colinear faces -> <ArgumentError: Points are not planar>
                i+=3	# next tri
                next
              end
              thisnm=[nm[idx[i+2]],nm[idx[i+1]],nm[idx[i]]]
              if material && (uv[idx[i+2]]!=[0.0,0.0,1.0] || uv[idx[i+1]]!=[0.0,0.0,1.0] || uv[idx[i]]!=[0.0,0.0,1.0])
                # SketchUp doesn't like colocated UVs - tolerance appears to be 0.0001
                thisuv=[uv[idx[i+2]]]
                thisuv << ((uv[idx[i+1]]!=uv[idx[i+2]]) ? uv[idx[i+1]] : uv[idx[i+1]]+Geom::Vector3d.new(1.0/1024,0,0))
                thisuv << ((uv[idx[i  ]]!=uv[idx[i+2]]) ? uv[idx[i  ]] : uv[idx[i  ]]+Geom::Vector3d.new(0,1.0/1024,0))
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
                  # SketchUp can't always compute texture layout -> <ArgumentError: Could not compute valid matrix from points>
                end
              end
              face.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_ALPHA_NAME,1) if alpha
              face.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_HARD_NAME, 1) if hard
              face.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_DECK_NAME, 1) if deck
              face.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_POLY_NAME, 1) if poly
              face.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_SHINY_NAME,1) if shiny

              # smooth & soften edges
              if thisnm[0]!=thisnm[1] || thisnm[0]!=thisnm[2] || thisnm[1]!=thisnm[2]
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
                if !edge.deleted? && edge.faces.length==2 && edge.faces[0].normal.angle_between(edge.faces[1].normal)<=planarangle	# same_direction? is too forgiving
                  if not material
                    edge.erase!
                    next
                  end
                  faces0=edge.faces[0]
                  faces1=edge.faces[1]
                  uv0=faces0.get_UVHelper(true, true, tw)
                  uv1=faces1.get_UVHelper(true, true, tw)
                  if uv0.get_front_UVQ(edge.start.position)==uv1.get_front_UVQ(edge.start.position) && uv0.get_front_UVQ(edge.end.position)==uv1.get_front_UVQ(edge.end.position) && faces0.back_material==faces1.back_material && (faces0.back_material==reverse || (uv0.get_back_UVQ(edge.start.position)==uv1.get_back_UVQ(edge.start.position) && uv0.get_back_UVQ(edge.end.position)==uv1.get_back_UVQ(edge.end.position)))
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

              i+=3	# next tri
            end

          when 'ATTR_LOD'
            if c[0].to_f>0.0
              msg[XPL10n.t('Ignoring lower level(s) of detail')]=true
              break
            end

          when 'ATTR_reset'
            cull=true
            hard=false
            deck=false
            poly=false
            alpha=false
            shiny=false
          when 'ATTR_cull'
            cull=true
          when 'ATTR_nocull', 'ATTR_no_cull'
            cull=false
          when 'ATTR_hard'
            hard=true
            deck=false
          when 'ATTR_hard_deck'
            hard=false
            deck=true
          when 'ATTR_no_hard'
            hard=false
            deck=false
          when 'ATTR_poly_os'
            poly=c[0].to_f > 0.0
          when 'ATTR_draped'
            poly=true
          when 'ATTR_no_draped'
            poly=false
          when '####_alpha'
            alpha=true
          when '####_no_alpha'
            alpha=false
          when 'ATTR_shiny_rat'
            shiny = c[0].to_f > 0.0

          when 'ANIM_begin'
            anim_context.push(entities.add_group.to_component)
            anim_context.last.definition.name=XPL10n.t('Component')+'#1'	# Otherwise has name Group#n. SketchUp will uniquify.
            anim_context.last.XPLoop=''				# may not be set below
            anim_off.push(anim_off.last.clone)			# inherit parent offset
            anim_t.push({})
            anim_r.push(Hash.new{|h,k|h[k]=[]})
            entities=anim_context.last.definition.entities	# To hold child geometry
          when 'ANIM_end'
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
                  anim_context.last.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frames[v].to_s, XPInterpolated(v).to_a)
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
            anim_context.last.transformation = Geom::Transformation.new(anim_context.last.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+'0')) if anim_context.last.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+'0')	# set current position to first keyframe position
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

          when 'TEXTURE_LIT', 'TEXTURE_NORMAL', 'TEXTURE_NORMAL_LIT', 'ATTR_no_blend', 'ATTR_shade_flat', 'ATTR_shade_smooth', 'ATTR_light_level_reset', 'ANIM_trans_end', 'ANIM_rotate_end'
            # suppress error message
          when 'POINT_COUNTS'
            tricount = c[3].to_i / 3
          when 'VLINE', 'LINES'
            msg[XPL10n.t('Ignoring old-style lines')]=true
          when 'VLIGHT', 'LIGHTS'
            msg[XPL10n.t('Ignoring old-style lights')]=true
          else
            if (SU2XPlane::LIGHTNAMED+SU2XPlane::LIGHTCUSTOM).include?(cmd)
              if SU2XPlane::LIGHTNAMED.include?(cmd)
                name=c.shift+' '
              else
                name=""
              end
              text=entities.add_text(cmd+' '+name+c[3..-1].join(' '), Geom::Point3d.new(c[0].to_f.m, -c[2].to_f.m, c[1].to_f.m))
              text.vector=Geom::Vector3d.new(0, 0, -5)	# arrow length & direction - arbitrary
              text.display_leader=true
            else
              msg[XPL10n.t('Ignoring command %s') % cmd]=true
            end
          end
        end
        model.commit_operation
        UI.messagebox(XPL10n.t("Imported %s triangles") % tricount + ".\n\n" + msg.keys.sort.join("\n"), MB_OK, 'X-Plane import')
        return 0	# Success

      rescue XPlaneImporterError => e
        model.abort_operation			# Otherwise SketchUp crashes on half-imported stuff
        UI.messagebox XPL10n.t("Can't import %s") % file_path.split(/\/|\\/)[-1] + ":\n#{e.message}.", MB_OK, 'X-Plane import'

      rescue => e
        puts "Error: #{e.inspect}", e.backtrace	# Report to console
        model.abort_operation			# Otherwise SketchUp crashes on half-imported stuff
        UI.messagebox XPL10n.t("Can't import %s") % file_path.split(/\/|\\/)[-1] + ":\n" + XPL10n.t('Internal error') + '.', MB_OK, 'X-Plane import'
      end

    rescue XPlaneImporterError => e
      UI.messagebox XPL10n.t("Can't import %s") % file_path.split(/\/|\\/)[-1] + ":\n#{e.message}.", MB_OK, 'X-Plane import'
    ensure
      file.close unless !file
    end

    return 0	# Pretend we succeeded to suppress alert dialog
  end
end
