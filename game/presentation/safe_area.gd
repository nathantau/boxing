class_name SafeArea
## The part of the screen not covered by the notch / Dynamic Island / home indicator,
## in the viewport's canvas coordinates (what Controls and touch events use).


static func rect(viewport: Viewport) -> Rect2:
	var full := viewport.get_visible_rect()
	if not OS.has_feature("mobile"):
		return full
	var safe_px := Rect2(DisplayServer.get_display_safe_area())
	return (viewport.get_final_transform().affine_inverse() * safe_px).intersection(full)
