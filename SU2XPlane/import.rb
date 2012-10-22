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
    m2i=1/0.0254	# SketchUp units are inches!
    pibytwo=Math::PI/2
    smoothangle=35*Math::PI/180
    planarangle=0.00002	# normals at angles less than this considered coplanar

    return 2 if not file_path
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
      model.start_operation('Import '+File.basename(file_path), true)
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
                UI.messagebox "Import failed.\nCan't read texture file #{texture+orig_ext}", MB_OK, 'X-Plane import'
                return 0	# Pretend we succeeded to suppress alert dialog
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
              face.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_HARD_NAME, 1) if hard
              face.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ATTR_POLY_NAME, 1) if poly

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
          when 'VLINE', 'LINES', 'VLIGHT', 'LIGHTS'
            msg+="Ignoring old-style lights and/or lines.\n" if not llerr
            llerr=true
          else
            if (SU2XPlane::LIGHTNAMED+SU2XPlane::LIGHTCUSTOM).include?(cmd)
              if SU2XPlane::LIGHTNAMED.include?(cmd)
                name=c.shift+' '
              else
                name=""
              end
              text=entities.add_text(cmd+' '+name+c[3..-1].join(' '), Geom::Point3d.new(c[0].to_f*m2i, -c[2].to_f*m2i, c[1].to_f*m2i))
              text.vector=Geom::Vector3d.new(0, 0, 5)	# arrow length & direction - arbitrary
              text.display_leader=true
            else
              msg+="Ignoring command #{cmd}.\n"
            end
          end
        end
        model.commit_operation
        msg="Ignoring some geometry that couldn't be imported.\n"+msg if skiperr
        UI.messagebox(msg, MB_OK, 'X-Plane import') if not msg.empty?
        return 0	# Success

      rescue
        model.abort_operation
        UI.messagebox "Can't import #{file_path.split(/\/|\\/)[-1]}:\nInternal error.", MB_OK, 'X-Plane import'
      end

    rescue
      UI.messagebox "Can't read #{file_path.split(/\/|\\/)[-1]}:\n#{$!}.", MB_OK, 'X-Plane import'
    ensure
      file.close unless !file
    end

    return 0	# Pretend we succeeded to suppress alert dialog
  end
end
