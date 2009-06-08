install: all
	rm -Rf ~/lib ~/public_html/cgi-bin ~/public_html/wikilint
	cp -R cgi-bin wikilint ~/public_html/
	cp -R lib ~/

all: lib/langdata/de/disambs.db lib/langdata/de/redirs.db

lib/langdata/de/disambs.txt:
	mysql -e "SELECT REPLACE(page_title, '_', ' ') FROM categorylinks JOIN page ON cl_from = page_id WHERE cl_to = 'Begriffsklärung' AND page_namespace = 0 UNION SELECT REPLACE(p2.page_title, '_', ' ') FROM categorylinks JOIN page AS p1 ON cl_from = p1.page_id JOIN redirect ON rd_namespace = p1.page_namespace AND rd_title = p1.page_title JOIN page AS p2 ON rd_from = p2.page_id WHERE cl_to = 'Begriffsklärung';" dewiki_p | tail -n +2 | sort > lib/langdata/de/disambs.txt

lib/langdata/de/disambs.db: make-disambs lib/langdata/de/disambs.txt
	./make-disambs lib/langdata/de/disambs.txt lib/langdata/de/disambs.db

lib/langdata/de/redirs.txt:
	mysql -e "SELECT REPLACE(page_title, '_', ' '), REPLACE(rd_title, '_', ' ') FROM page JOIN redirect ON page_id = rd_from WHERE page_namespace = 0 AND rd_namespace = 0;" dewiki_p | tail -n +2 | sort > lib/langdata/de/redirs.txt

lib/langdata/de/redirs.db: make-redirs lib/langdata/de/redirs.txt
	./make-redirs lib/langdata/de/redirs.txt lib/langdata/de/redirs.db

test: all
	perl -Icgi-bin -MTest::Harness -we 'runtests (<t/*.t>);'
