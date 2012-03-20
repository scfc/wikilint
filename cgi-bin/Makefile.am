cgibin_DATA = test.html
cgibin_SCRIPTS = wikilint
wikilint: wikilint.in
	sed -e 's#\@PMDIR\@#$(pmdir)#g;' < $< > $@.tmp
	chmod +x $@.tmp
	mv -f $@.tmp $@
CLEANFILES = wikilint
