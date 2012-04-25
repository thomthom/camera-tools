#-----------------------------------------------------------------------------
# Compatible: SketchUp 7 (PC)
#             (other versions untested)
#-----------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-----------------------------------------------------------------------------

require 'sketchup.rb'
require 'TT_Lib2/core.rb'

TT::Lib.compatible?('2.4.0', 'TT Camera Tools')

#-----------------------------------------------------------------------------

module TT::Plugins::CameraTools
  
  ### CONSTANTS ### --------------------------------------------------------
  
  VERSION = '0.3.1b'
  
  
  ### MENU & TOOLBARS ### --------------------------------------------------
  
  unless file_loaded?( File.basename(__FILE__) )
    m = TT.menu('Camera')
    m.add_separator
    m.add_item('Zoom Selected')     { self.zoom_selected }
    m.add_item('Roll Camera')       { self.roll }
    m.add_item('Set Fog Planes')    { self.set_fog_planes }
    m.add_separator
    m.add_item('View Camera')       { self.place_camera }
    m.add_item('View Fog Planes')   { self.place_fog_planes }
    m.add_separator
    m.add_item('Advanced')          { Sketchup.send_action(10624) }
  end
    
    
  def self.zoom_selected
    Sketchup.active_model.active_view.zoom(Sketchup.active_model.selection)
  end
  
  
  def self.roll_camera(angle)
    model = Sketchup.active_model
    view = model.active_view
    camera = view.camera
    
    vector = camera.direction
    t = Geom::Transformation.rotation(camera.eye, vector, angle.degrees)
    up = camera.up.transform(t)
    
    camera.set(camera.eye, camera.target, up)
  end
  
  
  def self.roll
    Sketchup.active_model.select_tool( CameraRollTool.new )
  end
  
  
  class CameraRollTool
  
    def initialize
      #@circle = TT::Geom3d.circle()
      
      @clr_line = Sketchup::Color.new(255,128,0)
      @clr_line.alpha = 192
      
      @clr_fill = Sketchup::Color.new(255,192,128)
      @clr_fill.alpha = 128
    end
    
    def activate
      update_ui()
      Sketchup.active_model.active_view.invalidate
    end
    
    def deactivate(view)
      view.invalidate
    end
    
    def resume(view)
      update_ui()
      view.invalidate
    end
    
    def update_ui
      Sketchup.vcb_label = 'Angle'
    end
    
    def enableVCB?
      return true
    end
    
    def onUserText(text, view)
      angle = TT::Locale.string_to_float( text )
      roll(view, angle.degrees)
    end
    
    def onLButtonDown(flags, x, y, view)
      @origin = Geom::Point3d.new(x,y,0)
      @up = view.camera.up
    end
    
    def onLButtonUp(flags, x, y, view)
      @origin = nil
      @mouse = nil
      view.invalidate
    end
    
    def onMouseMove(flags, x, y, view)
      if flags & MK_LBUTTON == MK_LBUTTON
        @mouse = Geom::Point3d.new(x,y,0)
        
        center = screen_center(view)
        v1 = center.vector_to( @origin )
        v2 = center.vector_to( @mouse )
        #angle = v1.angle_between( v2 )
        angle = signed_angle_between( v1, v2 )
        Sketchup.vcb_value = Sketchup.format_degrees( angle.radians )
        
        roll(view, angle)
        
        view.invalidate
      end
    end
    
    def draw(view)
      center = screen_center(view)
      # Rotation indicator
      if @origin && @mouse
        view.line_width = 1
        view.line_stipple = '-'
        view.drawing_color = 'black'
        # Axis - start
        view.draw2d( GL_LINES, center, @origin )
        # Axis - end
        view.draw2d( GL_LINES, center, @mouse )
        # Fill
        view.line_stipple = ''
        view.line_width = 2
        view.drawing_color = @clr_fill # [255,192,128]
        v1 = center.vector_to( @origin )
        v2 = center.vector_to( @mouse )
        #angle = v1.angle_between( v2 )
        angle = -signed_angle_between( v1, v2 )
        arc = TT::Geom3d.arc( center, v1, Z_AXIS, 100, 0, angle, 64 )
        arc << center
        view.draw2d( GL_POLYGON, arc )
      end
      # Circle
      @circle ||= center_circle(view)
      view.line_width = 2
      view.line_stipple = ''
      view.drawing_color = @clr_line # [255,128,0]
      view.draw2d( GL_LINE_LOOP, @circle )
      # Center
      pts = []
      pts << center.offset( X_AXIS.reverse, 5 )
      pts << center.offset( X_AXIS, 5 )
      pts << center.offset( Y_AXIS.reverse, 5 )
      pts << center.offset( Y_AXIS, 5 )
      view.draw2d( GL_LINES, pts )
    end
    
    def center_circle(view)
      center = screen_center(view)
      TT::Geom3d.circle(center, Z_AXIS, 100, 64)
    end
    
    def screen_center(view)
      x = view.vpwidth / 2.0
      y = view.vpheight / 2.0
      Geom::Point3d.new(x,y,0)
    end
    
    def full_angle_between(vector1, vector2)
      cross_vector = vector1 * vector2
      direction = (vector1 * vector2) % Z_AXIS
      angle = vector1.angle_between(vector2)
      angle = 360.degrees - angle if direction > 0.0
      return angle
    end
    
    def signed_angle_between(vector1, vector2)
      cross_vector = vector1 * vector2
      direction = (vector1 * vector2) % Z_AXIS
      angle = vector1.angle_between(vector2)
      angle = -angle if direction > 0.0
      return angle
    end
    
    def roll(view, angle)
      @up = view.camera.up if @up.nil?

      camera = view.camera
      t = Geom::Transformation.rotation( camera.eye, camera.direction, angle )
      up = @up.transform(t)
      camera.set( camera.eye, camera.target, up )
    end
  
  end # class CameraRollTool
  
  
  def self.set_fog_planes
    Sketchup.active_model.select_tool( SetFogTool.new )
  end
  
  class SetFogTool
    
    S_WAIT_FOR_FOG_START = 0
    S_WAIT_FOR_FOG_END = 1
    S_DONE = 2
    
    def activate
      reset()
      Sketchup.active_model.start_operation('Set Fog Planes')
    end
    
    def deactivate(view)
      if @state == S_DONE
        view.model.commit_operation
      else
        view.model.abort_operation
      end
      view.invalidate
    end
    
    def resume(view)
      view.invalidate
    end
    
    def onLButtonUp(flags, x, y, view)
      if @state == S_WAIT_FOR_FOG_START
        @state = S_WAIT_FOR_FOG_END
      else
        @state = S_DONE
        view.model.select_tool(nil)
      end
    end
    
    def onMouseMove(flags, x, y, view)
      @ip.pick(view,x,y)
      distance = view.camera.eye.distance( @ip.position )
      if @state == S_WAIT_FOR_FOG_START
        view.model.rendering_options['FogEndDist'] = distance
        #view.model.rendering_options['FogStartDist'] = distance
      else
        view.model.rendering_options['FogStartDist'] = distance
        #view.model.rendering_options['FogEndDist'] = distance
      end
      view.invalidate
    end
    
    def onCancel(reason, view)
      reset()
    end
    
    def reset
      @ip = Sketchup::InputPoint.new
      @state = S_WAIT_FOR_FOG_START
      Sketchup.active_model.rendering_options['FogStartDist'] = 0
    end
    
    def draw(view)
      @ip.draw(view) if @ip.valid?
    end
    
  end # class SetFogTool
  
  
  def self.place_fog_planes(camera = nil)
    model = Sketchup.active_model
    view = model.active_view
    ro = model.rendering_options
    
    camera = view.camera if camera.nil?
    
    TT::Model.start_operation('Place Fog Planes')
    
    self.place_camera(camera)
    
    puts "\nFog Info:"
    g = model.active_entities.add_group
    
    s = ro['FogStartDist']
    e = ro['FogEndDist']
    
    puts "> Start Distance: #{s.to_m}"
    puts "> End Distance: #{e.to_m}"
    
    ps = camera.eye.offset(camera.direction, s)
    pe = camera.eye.offset(camera.direction, e)
    
    plane = [ [-100.m,-100.m,0], [100.m,-100.m,0], [100.m,100.m,0], [-100.m,100.m,0] ]
    ts = Geom::Transformation.new(ps, camera.direction)
    te = Geom::Transformation.new(pe, camera.direction)
    
    plane_s = plane.map { |p| p.transform(ts) }
    plane_e = plane.map { |p| p.transform(te) }
    
    plane_s.each { |p| g.entities.add_face(plane_s) }
    plane_e.each { |p| g.entities.add_face(plane_e) }
    
    model.commit_operation
  end
  
  
  def self.place_camera(camera = nil)
    model = Sketchup.active_model
    view = model.active_view
    
    camera = view.camera if camera.nil?
    
    puts "\nCamera Info:"
    puts "> Aspect Ratio: #{camera.aspect_ratio}"
    puts "> Focal Length: #{camera.focal_length}"
    puts "> FOV: #{camera.fov}"
    #puts "Height: #{camera.height}"
    #puts "Width: #{camera.width}"
    #puts "Image Height: #{camera.image_height}"
    puts "> Image Width: #{camera.image_width}"
    
    TT::Model.start_operation('Place Camera')
    
    g = model.active_entities.add_group
    
    g.entities.add_cpoint(camera.eye)
    g.entities.add_cpoint(camera.target)
    g.entities.add_cline(camera.eye, camera.target)
    
    # (!) If View Aspect Ratio, then the camera zooms in by the view ratio.
    # Take into account this change.
    
    t = Geom::Transformation.rotation(camera.eye, camera.up, camera.fov.degrees / 2)
    
    ratio = view.vpwidth / view.vpheight.to_f
    fov_v = camera.fov * ratio
    
    ratio_inv = 1 / ratio
    
    target_lenght = camera.eye.distance(camera.target)
    
    puts "> Viewport: #{view.vpwidth}x#{view.vpheight}"
    puts "> Ratio: #{ratio}"
    puts "> Inverse Ratio: #{ratio_inv}"
    puts "> -"
    puts "> Target Length: #{target_lenght}"
    puts "> Target Length * Inverse Ratio: #{(target_lenght * ratio_inv).to_l}"
    puts "> -"
    puts "> Fov: #{camera.fov}"
    puts "> Fov Other: #{fov_v}"
    puts "> -"
    puts "> Focal Length V: #{camera.focal_length}"
    puts "> Focal Length H: #{camera.focal_length * ratio}"
    puts "> -"
    puts "> AOV: #{self.aov_horizontal(camera.focal_length)}"
    
    # Top and Bottom mid point
    p1 = camera.target.transform Geom::Transformation.rotation(camera.eye, camera.xaxis, camera.fov.degrees / 2)
    p2 = camera.target.transform Geom::Transformation.rotation(camera.eye, camera.xaxis, - camera.fov.degrees / 2)
    
    # Wrong
    p3 = camera.target.transform Geom::Transformation.rotation(camera.eye, camera.yaxis, fov_v.degrees / 2)
    p4 = camera.target.transform Geom::Transformation.rotation(camera.eye, camera.yaxis, - fov_v.degrees / 2)
    
    # Right
    puts "> -"
    plane = [camera.eye, camera.up]
    dist = p1.distance_to_plane(plane)
    offset_t = Geom::Transformation.scaling(dist * ratio)
    offset_v = camera.xaxis.transform(offset_t)
    
    puts "> Distance to Plane: #{dist.to_mm}"
    puts "> Vector: #{camera.xaxis}"
    puts "> Offset Vector: #{offset_v}"
    
    p5 = p1.offset(offset_v)
    p6 = p1.offset(offset_v.reverse)
    p7 = p2.offset(offset_v)
    p8 = p2.offset(offset_v.reverse)
    
    g.entities.add_cpoint(p5)
    g.entities.add_cpoint(p6)
    g.entities.add_cpoint(p7)
    g.entities.add_cpoint(p8)
    
    g.entities.add_cpoint(p1)
    g.entities.add_cpoint(p2)
    #g.entities.add_cpoint(p3)
    #g.entities.add_cpoint(p4)
    
    # Faces
    g.entities.add_face(camera.eye, p7, p5) # Right
    g.entities.add_face(camera.eye, p6, p8) # Left
    g.entities.add_face(camera.eye, p5, p6) # Top
    g.entities.add_face(camera.eye, p7, p8) # Bottom
    
    model.commit_operation
  end
  
  # http://en.wikipedia.org/wiki/Angle_of_view
  # Standard W/H: 35x24
  def self.aov_vertical(focal_length)
    aov = 2 * Math.atan( 24 / (2 * focal_length) )
  end
  
  def self.aov_horizontal(focal_length)
    aov = 2 * Math.atan( 35 / (2 * focal_length) )
  end
  
end # module

#-----------------------------------------------------------------------------
file_loaded( File.basename(__FILE__) )
#-----------------------------------------------------------------------------