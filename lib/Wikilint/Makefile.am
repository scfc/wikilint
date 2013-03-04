SUBDIRS = DB

pmwikilint_DATA = Config.pm DB.pm
Config.pm: Config.pm.in
	sed -e 's#\@TOOL_PATH\@#$(tool_path)#g;' -e 's#\@STATIC_HTML_PATH\@#$(static_html_path)#g;' < $< > $@.tmp
	mv -f $@.tmp $@
CLEANFILES = Config.pm
