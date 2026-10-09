shader_type spatial;
render_mode unshaded, shadows_disabled;
// Original e_invisible_collidable effect: geometry remains physical, never visible.
void fragment(){discard;}
