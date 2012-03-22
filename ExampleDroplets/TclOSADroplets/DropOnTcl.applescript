# Example droplet script for TclOSA
# Produces a .html file listing the files dropped
# Tells the default browser to display the result

set h_title "DroppedOnTcl"
set hdir [exec uuidgen];
set fname /tmp/$hdir/$h_title.html
if { ! [file exists $fname]} {
	file mkdir [file dirname $fname]
}

namespace eval tml {
	
	variable m_doclist
	variable m_meta "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">"
	variable m_body_open "\n<body>\n"
	variable m_body_close "\n</body>\n"
	variable m_tail "\n</html>\n"
	
	set tan "#EEDDCC"
	set dark_blue "#000088"
	
	variable m_style "<style type=\"text/css\">
	h1 {
		text-align: left;
		font-family:serif;
	}
	body {
		color:$dark_blue;
		background-color:$tan;
		font-family:serif;
		margin:12px;
	}
	table {
		width:540px;
		font-family:monospace;
		font-size:10px;
		border-spacing:1px;
		background-color:$dark_blue;
	}
	td {
		background-color:$tan;
		padding:9px 9px 9px 9px;
	}
	th {
		font-family:serif;
		font-weight:normal;
		background-color:$dark_blue;
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
</style>"
	
	proc print {theFile theDocID} {
		
		variable m_doclist
		variable m_body_open
		variable m_body_close
		variable m_tail
		
		array set elements $m_doclist($theDocID)
		puts $theFile $elements(head)$m_body_open$elements(body)$m_body_close$m_tail
	}
	
	proc new {theTitle} {
		
		variable m_doclist
		set id [clock clicks]
		set bstart ""
		
		set doc [list head [make_head $theTitle] body $bstart]
		set m_doclist($id) $doc
		append_tag $id h1 "" $theTitle
		
		return $id
	}
	
	proc make_head {theTitle} {
		
		variable m_meta
		variable m_style
		set charset "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\">"
		set desc "<meta name=\"description\" content=\"directory listing\">"
		
		return "$m_meta\n<html>\n<head>\n<title>$theTitle</title>\n$charset\n$desc\n$m_style\n</head>\n"
	}
	
	proc append_tag {theDocID theTag theAttributes theText} {
		
		variable m_doclist
		set attributes ""
		
		if {[string length $theAttributes] > 0} {
			set attributes " $theAttributes"
		}
		array set elements $m_doclist($theDocID)
		append elements(body) "\n<$theTag$attributes>$theText</$theTag>\n"
		set m_doclist($theDocID) [array get elements]
	}
	
	proc make_notice {theDocID {theAuthor ""} {theAuthorURL ""}} {
		
		variable m_doclist
		global env
		set year [clock format [clock seconds] -format %Y]
		set copysymbol [format %c 0xA9]
		
		if {[string length $theAuthor] == 0} {
			#set realname [exec /usr/bin/niutil -readprop . /users/$env(USER) realname]
			set realname [exec /usr/bin/dscl . -read /Users/$env(USER) RealName | tr -d \n | cut -d { } -f 2-];
		} else {
			set realname $theAuthor
		}
		
		if {[string length $theAuthorURL] == 0} {
			#set email [exec defaults read com.apple.mail | grep -w EmailAddresses | cut -d "\"" -f 2];
			#set url "$email"
			set url [exec $env(OSABRIDGE_SCRIPTS_FOLDER)/emadds.sh];
			
		} else {
			set url $theAuthorURL
		}
		
		array set elements $m_doclist($theDocID)
		append elements(body) "\n<h3>&sect;</h3>\n<p>\n<tt>For more information contact: <a href=\"mailto:$url\">$realname</a> &lt;$url&gt;</tt>\n</p>\n<h3>&sect;</h3>\n"
		append elements(body) "\n<!-- Copyright $copysymbol $year, $realname. All Rights Reserved -->\n"
		set m_doclist($theDocID) [array get elements]
	}
	
	proc append_file_list_table {theDocID theRowData theHeaderText} {
		
		variable m_doclist
		set table "\n<table>\n"
		set th "\n<th>$theHeaderText [clock format [clock seconds] -format "%Y.%m.%d %H:%M:%S"]</th>\n"
		set row_data ""
		
		foreach tr $theRowData {
			
			set label ""
			set fname $tr
			set img \"file://localhost/usr/share/httpd/icons/small/dir.gif\"
			
			if {[file exists $tr] == 1} {
				if {[string compare [file type $tr] "file"] == 0} {
					set label "([file size $tr] bytes)"
					set img \"file://localhost/usr/share/httpd/icons/small/generic.gif\"
				}
				if {[string compare $tr "/"] == 1} {
					set fname [file tail $tr]
				}
				set ignore [regsub -all -- " " $tr "%20" res]
				append row_data "\n<tr>\n<td>\n<img src=$img><a href=\"file://$tr\">$fname</a> $label\n</td>\n</tr>\n"
			} else {
				set img \"file://localhost/usr/share/httpd/icons/small/broken.png\"
				append row_data "\n<tr>\n<td>\n<img src=$img> $tr\n</td>\n</tr>\n"
			}
		}
		append table "$th$row_data\n</table>\n"
		array set elements $m_doclist($theDocID)
		append elements(body) $table
		set m_doclist($theDocID) [array get elements]
	}
}

if {$argc > 0} {
	set fargs {}
	foreach arg $argv {
		set ptype [file pathtype $arg]
		if {[string compare "absolute" $ptype] != 0 } {
			lappend fargs [file join [pwd] $arg]
		} else {
			lappend fargs $arg
		}
	}
	set doc_id [tml::new $h_title]
	tml::append_tag $doc_id p "style=\"color:purple;font-family:Comic Sans MS;font-size:13;\"" "TclOSA example: listing files dropped on an applet"
	tml::append_tag $doc_id h2 "" "File List:"
	tml::append_file_list_table $doc_id [lsort -dictionary $fargs] "Date:"
	tml::make_notice $doc_id
	set f [open $fname w]
	tml::print $f $doc_id
	close $f
	exec /usr/bin/open $fname
} else {
	set fargs {eee ddd ccc bbb aaa}
	set doc_id [tml::new $h_title]
	tml::append_tag $doc_id h2 "" "File List:"
	tml::append_file_list_table $doc_id [lsort -dictionary $fargs] "Date:"
	tml::make_notice $doc_id
	set f [open $fname w]
	tml::print $f $doc_id
	close $f
	exec /usr/bin/open $fname
}
