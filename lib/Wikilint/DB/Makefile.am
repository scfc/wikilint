pmwikilintdb_DATA = Language.pm
Language.pm: Language.pm.in
	sed -e 's#\@PKGLANGDATADIR\@#$(pkglangdatadir)#g;' < $< > $@.tmp
	mv -f $@.tmp $@
CLEANFILES = Language.pm
