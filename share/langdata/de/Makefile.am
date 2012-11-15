pkglangdatade_DATA = cache.db fill_words.txt abbreviations.txt avoid_words.txt typos.txt

disambs.txt:
	mysql -BNe "SELECT REPLACE(page_title, '_', ' ') FROM categorylinks JOIN page ON cl_from = page_id WHERE cl_to = 'Begriffsklärung' AND page_namespace = 0 UNION SELECT REPLACE(p2.page_title, '_', ' ') FROM categorylinks JOIN page AS p1 ON cl_from = p1.page_id JOIN redirect ON rd_namespace = p1.page_namespace AND rd_title = p1.page_title JOIN page AS p2 ON rd_from = p2.page_id WHERE cl_to = 'Begriffsklärung' UNION SELECT CONCAT('#', UNIX_TIMESTAMP()) ORDER BY 1;" -h dewiki-p.rrdb.toolserver.org dewiki_p > $@.tmp
	mv -f $@.tmp $@

redirs.txt:
	mysql -BNe "SELECT REPLACE(page_title, '_', ' '), REPLACE(rd_title, '_', ' ') FROM page JOIN redirect ON page_id = rd_from WHERE page_namespace = 0 AND rd_namespace = 0 UNION SELECT '#', UNIX_TIMESTAMP() ORDER BY 1, 2;" -h dewiki-p.rrdb.toolserver.org dewiki_p > $@.tmp
	mv -f $@.tmp $@

cache.db: disambs.txt redirs.txt
	rm -f $@.tmp
	{ echo 'CREATE TABLE DisambiguationPages (Title VARCHAR(255) PRIMARY KEY);';                          \
	  echo 'CREATE TABLE Redirects (FromTitle VARCHAR(255) PRIMARY KEY, ToTitle VARCHAR(255) NOT NULL);'; \
	  echo 'CREATE INDEX Redirects_ToTitle_Index ON Redirects (ToTitle);';                                \
	  echo '.mode tabs';                                                                                  \
	  echo '.import disambs.txt DisambiguationPages';                                                     \
	  echo '.import redirs.txt Redirects';                                                                \
	} | sqlite3 $@.tmp
	mv -f $@.tmp $@

CLEANFILES = cache.db
