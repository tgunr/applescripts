@m_title = "DroppedOnRuby"
@h_cell_metric = "\"3\""
@m_date = Time.now.strftime("%b %e, %Y")
@m_year = Time.now.strftime("%Y")
@m_user = `id -un`.chop
@m_home = `echo $HOME`.chop
@tempf = `uuidgen`.chop
@m_outfile = "/tmp/#@tempf/tmp.html"

@dark_blue = "#000088"
@tan = "#EEDDCC"
@m_css = "<style type=\"text/css\">
	h1 {
		text-align: left;
		font-family:serif;
	}
	body {
		color:#@dark_blue;
		background-color:#@tan;
		font-family:serif;
		margin:12px;
	}
	table {
		width:540px;
		font-family:monospace;
		font-size:10px;
		border-spacing:1px;
		background-color:#@dark_blue;
	}
	td {
		background-color:#@tan;
		padding:9px 9px 9px 9px;
	}
	th {
		font-family:serif;
		font-weight:normal;
		background-color:#@dark_blue;
		font-size:13px;
		color:white;
		text-align:left;
		background-image:url( \"file://localhost/usr/share/httpd/icons/small/rainbow.png\" );
	}
	tt {
		font-family:monospace;
		text-size:10px;
	}
	img {
		padding:0px 9px 0px 0px;
	}
</style>
"
system( "mkdir -p /tmp/#@tempf" )
html = open( "#@m_outfile", "w" )
html.print "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">
<html>
<head>
<title>#@m_title</title>
<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\">
<meta name=\"description\" content=\"directory listing\">
#@m_css
</head>
<body>
<h1>#@m_title</h1>
<p style=\"color:purple;font-family:Comic Sans MS;font-size:13;\">RubyOSA example: listing files dropped on an applet</p>
<h2>File List:</h2>

<table>
<th>File List: #@m_date</th>
"
while filename = ARGV.shift
	html.puts "\n<tr>\n<td>\n"
	img = "<img src=\"file://localhost/usr/share/httpd/icons/small/broken.png\">"
	if test( ?f, filename ) then
		img = "<img src=\"file://localhost/usr/share/httpd/icons/small/generic.gif\">"
	end
	if test( ?d, filename ) then
		img = "<img src=\"file://localhost/usr/share/httpd/icons/small/dir.gif\">"
	end
	fname = filename;
	if filename != "/" then
		fname = File.basename(filename);
	end
	html.puts img
	html.puts "<a href =\"file://" + filename + "\">" + fname + "</a>"
	html.puts "</td>\n</tr>\n"
end

#author = `/usr/bin/niutil -readprop . /users/#@m_user realname`.chop
author = `/usr/bin/dscl . -read /Users/#@m_user RealName | tr -d '\n' | cut -d ' ' -f 2-`.chop
#email = `defaults read com.apple.mail | grep -w EmailAddresses | cut -d '"' -f 2`.chop
email = `#{ENV['OSABRIDGE_SCRIPTS_FOLDER']}/emadds.sh`.chop
html.print "
</table>

<h3>&sect;</h3>
<tt>For more information contact: <a href=\"mailto:" + email + "\">" + author + "</a> &lt;" + email + "&gt;</tt>
<h3>&sect;</h3>
<!-- Copyright c " + @m_year + ", " + author + ". All Rights Reserved -->
</body>
</html>"

html.close

system( "/usr/bin/open 'file://#@m_outfile'" )
