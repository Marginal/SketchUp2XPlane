VER=$(shell sed -nE 's/[[:space:]]+Version="([[:digit:]]+)(\.)([[:digit:]]+)"/\1\3/p' SU2XPlane.rb)

VPATH=examples:examples_DE

TARGETS=SketchUp2XPlane_$(VER).zip SketchUp2XPlane_$(VER).rbz SUanimation.zip SUlight.zip SUanimation_DE.zip

INSTALLDIR=/Library/Application\ Support/Google\ SketchUp\ 8/SketchUp/plugins

all:	$(TARGETS)

clean:
	rm -f $(TARGETS)

install:	$(TARGETS)
	rm -rf $(INSTALLDIR)/SU2XPlane
	unzip -o -d $(INSTALLDIR) SketchUp2XPlane_$(VER).zip

SketchUp2XPlane_$(VER).zip:	*-SU2XPlane*.html SU2XPlane.rb SU2XPlane/*.css SU2XPlane/*.html SU2XPlane/*.js SU2XPlane/*.rb SU2XPlane/*.txt
	rm -f $@
	zip -MM $@ $+

SketchUp2XPlane_$(VER).rbz:	SketchUp2XPlane_$(VER).zip
	cp -p $+ $@

SUanimation.zip:	A1_SeeSaw.skp A2_Radar.skp A3_Windsock.skp A4_Knobs.skp SeeSaw.png knobs.png Windsock.png
	rm -f $@
	zip -j -MM $@ $+

SUanimation_DE.zip:	A1_Wippe.skp examples_DE/A2_Radar.skp A3_Windsack.skp A4_Drehknopfen.skp SeeSaw.png knobs.png Windsock.png
	rm -f $@
	zip -j -MM $@ $+

SUlight.zip:	L1_named_light.skp L2_custom_light.skp gray.png
	rm -f $@
	zip -j -MM $@ $+
