VER=$(shell sed -nE 's/[[:space:]]+Version="([[:digit:]]+)(\.)([[:digit:]]+)"/\1\3/p' SU2XPlane.rb)
PROJECT=SU2XPlane

VPATH=examples:examples_DE

TARGETS=SketchUp2XPlane_$(VER).rbz SUanimation.zip SUlight.zip SUanimation_DE.zip

INSTALLDIRS = \
	/Library/Application\ Support/Google\ SketchUp\ 8 \
	~/Library/Application\ Support/SketchUp\ 2013 \
	~/Library/Application\ Support/SketchUp\ 2014 \
	~/Library/Application\ Support/SketchUp\ 2015 \
	~/Library/Application\ Support/SketchUp\ 2016

all:	$(TARGETS)

clean:
	rm -f $(TARGETS)

install:	$(TARGETS)
	for INSTALLDIR in $(INSTALLDIRS); do \
		if [ -d "$${INSTALLDIR}/SketchUp/Plugins" ]; then \
			rm -rf "$${INSTALLDIR}/SketchUp/Plugins/$(PROJECT)" ; \
			unzip -o -d "$${INSTALLDIR}/SketchUp/Plugins" SketchUp2XPlane_$(VER).rbz ; \
		fi; \
	done

SketchUp2XPlane_$(VER).rbz:	$(PROJECT).rb $(PROJECT)/*.rb $(PROJECT)/Resources/*.html $(PROJECT)/Resources/*.js $(PROJECT)/Resources/*.css $(PROJECT)/Resources/??/*.html $(PROJECT)/Resources/??/*.strings
	rm -f $@
	zip -MM $@ $+

SUanimation.zip:	A1_SeeSaw.skp A2_Radar.skp A3_Windsock.skp A4_Knobs.skp SeeSaw.png knobs.png Windsock.png
	rm -f $@
	zip -j -MM $@ $+

SUanimation_DE.zip:	A1_Wippe.skp examples_DE/A2_Radar.skp A3_Windsack.skp A4_Drehknopfen.skp SeeSaw.png knobs.png Windsock.png
	rm -f $@
	zip -j -MM $@ $+

SUlight.zip:	L1_named_light.skp L2_custom_light.skp gray.png
	rm -f $@
	zip -j -MM $@ $+
