#!/usr/bin/perl -w

# Try to extract the content of a MIME message as plain or RTF text

# This code can be used under the same terms as Perl itself. It comes
# with absolutely NO WARRANTY. Use at your own risk.

# Andreas Amann, 2002-2007
# http://homepage.mac.com/aamann/

# since we use some modules not installed in OSX per default, we have them packaged within the app
# -> add the local path to the include path
use lib 'Perl';

use MIME::Parser;
use HTML::Parser 3.00 ();
use Getopt::Std;
use Text::Wrap;
use MacOSX::File::Info;
use MacOSX::File::Copy;
use Encode qw(encode decode);

use vars qw($wd $enc $e $quoteString $attDest);
my %inside;
my %options=();
$quoteLevel = 0;
$fontSize = 11;
$skipAnchor = 1;
@lastFontSize = (11);
@recoveredFiles = ();
$quoteString = '';
$newlineChar = '';
$rtf_paragraph_start = "\\pard";
$rtf_paragraph_end = "\\pardeftab560\\ql\\qnatural \\uc0\n\n";

getopts("rhw:a:f:",\%options);
die "usage: ExtractText [options] -f filename\n
Available options:
-h            complete headers
              (otherwise only From, Subject, Date, To, Cc, and Bcc will be used)
-w <num>      wrap long lines after <num> characters
-r            use RTF instead of plain text for result
-a <location> save attachments to folder <location>\n\n" unless defined $options{f};
if ( $options{w} ) {
	$Text::Wrap::columns = $options{w};
	$Text::Wrap::huge = 'overflow';
}
if ( $options{a} ) {
	$attDest = $options{a};
}
if ( $options{r} ) {
	$newlineChar = "\\\n";
}
else {
	$newlineChar = "\n";
}

#Setup the MIME parser
my $mime_parser = new MIME::Parser;
$mime_parser->ignore_errors(1);
$mime_parser->extract_uuencode(1);
$mime_parser->output_dir("/tmp/MailScripts");	# so we don't litter the file system in case something goes wrongÉ

# Setup the HTML parser
my $html_parser = HTML::Parser->new
(
 api_version => 3,
 handlers	=>
 [
	 start => [\&tag, "tagname, '+1',tag,attr"],
	 end   => [\&tag, "tagname, '-1',tag,attr"],
	 text  => [\&text, "dtext" ],
	 ],
 marked_sections => 1
 ) or die "Can't create HTML parser\n";

$html_parser->ignore_elements(qw(title style)); # some clients seem to add the subject as the title -> ignore it
# since we convert to plain text, we don't care about styles either

# Setup the text/enriched parser - we use a slightly simpler HTML parser for thatÉ
my $richtext_parser = HTML::Parser->new
(
 api_version => 3,
 handlers	=>
 [
	 start => [\&tag, "tagname, '+1',tag,attr"],
	 end   => [\&tag, "tagname, '-1',tag,attr"],
	 text  => [\&richtext, "dtext" ],
	 ],
 marked_sections => 1
 ) or die "Can't create richtext parser\n";

$richtext_parser->ignore_elements(qw(param)); # since we don't care about the tags, we also can ignore their parameters

# we know that we wrote UTF-16 so we'd better tell Perl about this :-)
open(my $input,'<:encoding(UTF-16)',$options{f});
# now pass the message through the MIME parserÉ
eval { $e = $mime_parser->parse($input); };
# Éand close the input file
close($input);
my $error = ($@ || $mime_parser->last_error);
if ($error)
{
	# Get rid of the temp filesÉ
	$mime_parser->filer->purge;
	# Éand pass on the error
	die "Error parsing the message: $error\n";
}
# remove duplicates caused by multipart/alternative
$e = &analyze($e);

# Setup the decoder based on the header informationÉ
setup_decoder($e->head);
# Éprint the initial paragraph informationÉ
if ( $options{r} ) {
	print $rtf_paragraph_start, $rtf_paragraph_end, "\\shading10000\\cfpat7\\fs22\\cb7 "; # TextEdit uses the \cb, Word uses \shading & \cfpat
	$fontSize = 11;
	@lastFontSize = (11);
}
# Éprint the headers as neededÉ
if ( $options{h} ) {
	use utf8;
	@lines = split(/\n/, decode('MIME-Header',$e->head->as_string));
	if ( $options{r} ) {
		foreach $line (@lines) {
			if ( $options{w} ) {
				$line = wrap( '', "\t", $line );
			}
			$line =~ s/\n/\\\n/g;
			if ( $line =~ m/^([^\s]+\:)(.*)/ ) {
				if ( $1 =~ /subject/i ) {
					print_header("Subject");
				}
				else {
					print_utf16("\\f0\\b\\fs22 \\cf2 " . $1 . "\n\\f1\\b0 \\cf3 " . $2 . "\\\n\n");
				}
			}
			elsif ( $line =~ m/^$/ ) { # end of header
				print_utf16($line . "\\cb1 \\\n\n");
			}
			else {
				print_utf16($line . "\\\n\n");
			}
		}
	}
	else {
		foreach $line (@lines) {
			if ( $options{w} ) {
				$line = wrap( '', "\t", $line );
			}
			print_utf16($line . "\n");
		}
	}
}
else {
	print_header("From");
	print_header("Date");
	print_header("To");
	print_header("Cc");
	print_header("Bcc");
	print_header("Subject");
}
# Éfinish the headerÉ
if ( $options{r} ) {
	print "\\cb1", $rtf_paragraph_start, $rtf_paragraph_end. " \\\n";
}
else {
	print_utf16("\n");
}
# Éand process each of the parts
decode_entities($e);

# all done -> delete temp files
$mime_parser->filer->purge;

####################################

# tag handler for both, HTML and rich text processing - produce something rather close to the HTML version
sub tag
{
	my($tagname, $num, $tag, $attr) = @_;
	my $skip = 0;
	my $quotelevelchange = 0;
	$inside{$tagname} += $num;
	if ( $tag eq "br" || $tag eq "div" || $tag eq "p" || $tag eq "/tr" ) {
		if ( $options{r} && $skipAnchor == 0 ) {
			# deal with missing </a> tags to prevent invalid RTF
			$skipAnchor = 1;
			print "}}" . get_paragraph_color();
		}
		print_utf16($newlineChar); # start a new line
	}
	elsif ( $tag eq "li" ) {
		if ( $options{r} && $skipAnchor == 0 ) {
			# deal with missing </a> tags to prevent invalid RTF
			$skipAnchor = 1;
			print "}}" . get_paragraph_color();
		}
		print_utf16($newlineChar . "\x{2022} ");
	}
	elsif ( $tagname eq "td" ) {
		if ( $options{r} && $skipAnchor == 0 ) {
			# deal with missing </a> tags to prevent invalid RTF
			$skipAnchor = 1;
			print "}}" . get_paragraph_color();
		}
		print_utf16(" "); # add space for table cell separation
	}
	elsif ( $tag eq "blockquote" || $tag eq "excerpt" ) {
		print_utf16($newlineChar); # start a new line
			$quotelevelchange = 1;
		$quoteLevel += 1;
		if ( $quoteString eq "" ) {
			$quoteString = "> ";
		}
		else {
			$quoteString = ">" . $quoteString;
		}
	}
	elsif ( $tag eq "/blockquote" || $tag eq "/excerpt" ) {
		print_utf16($newlineChar); # start a new line
			$quotelevelchange = 1;
		$quoteLevel -= 1;
		if ( $quoteString eq "> " ) {
			$quoteString = "";
		}
		else {
			$quoteString = substr($quoteString, 1);
		}
	}
	elsif ( $tag eq "/p" ) {
		print_utf16($newlineChar . $newlineChar); # start a new paragraph (i.e., insert empty line)
	}
	elsif ( $tag eq "hr" ) {
		print_utf16($newlineChar . "----------" . $newlineChar); # create a dummy <HR>
	}
	elsif ( $tag eq "a" ) {
		unless ( exists $attr->{href} ) {
			$skipAnchor = 1;
			return;
		}
		$skipAnchor = 0;
		if ( $options{r} ) {
			print_utf16("{\\field{\\*\\fldinst{HYPERLINK \"$attr->{href}\"}}{\\fldrslt \\cf6 ");
		}
		else {
			print_utf16("<$attr->{href}> "); # insert the link location
		}
	}
	elsif ( $tag eq "/a" && $options{r} && $skipAnchor == 0 ) {
		print "}}" . get_paragraph_color();
		$skipAnchor = 1;
	}
	elsif ( ( $tag eq "b" || $tag eq "bold" ) && $options{r} ) {
		print "\n\\b ";
	}
	elsif ( ( $tag eq "/b" || $tag eq "/bold" ) && $options{r} ) {
		print "\n\\b0 ";
	}
	elsif ( ( $tag eq "u" || $tag eq "underline" ) && $options{r} ) {
		print "\n\\ul ";
	}
	elsif ( ( $tag eq "/u" || $tag eq "/underline" ) && $options{r} ) {
		print "\n\\ul0 ";
	}
	elsif ( ( $tag eq "i" || $tag eq "italic" ) && $options{r} ) {
		print "\n\\i ";
	}
	elsif ( ( $tag eq "/i" || $tag eq "/italic" ) && $options{r} ) {
		print "\n\\i0 ";
	}
	elsif ( ( $tag eq "sup" ) && $options{r} ) {
		print "\n{\\super ";
	}
	elsif ( ( $tag eq "/sup" ) && $options{r} ) {
		print "}";
	}
	elsif ( ( $tag eq "sub" ) && $options{r} ) {
		print "\n{\\sub ";
	}
	elsif ( ( $tag eq "/sub" ) && $options{r} ) {
		print "}";
	}
	elsif ( $tag eq "img" ) {
		if ( $options{a} && $attr->{src} =~ m/^cid:/i ) {
			if ( $options{r} ) {
				$imgName = substr($mime_parser->filer->find_unused_path($attDest,substr($attr->{src},4)),length($attDest)+1);
				print_utf16($newlineChar . "{{\\NeXTGraphic " . $imgName . " \\width0 \\height0}\x{AC}}");
			}
		}
		else
		{
			if ( $options{r} ) {
				print_utf16("\\fs20");
			}
			if ( exists $attr->{alt} && $attr->{alt} ne "" ) {
				print_utf16("[Image '$attr->{alt}']"); # insert IMG placeholder with title ("alt")
			}
			else {
				print_utf16("[Image]"); # insert IMG placeholder
			}
			if ( $options{r} ) {
				print_utf16("\\fs" . 2 * $fontSize);
			}
		}
	}
	elsif ( ( $tag eq "smaller" || $tag eq "/bigger" )  && $options{r} ) {
		$fontSize -= 1;
		print "\\fs", 2 * $fontSize, " ";
	}
	elsif ( ( $tag eq "/smaller" || $tag eq "bigger" )  && $options{r} ){
		$fontSize += 1;
		print "\\fs", 2 * $fontSize, " ";
	}
	elsif ( $tag eq "font"  && $options{r} ) {
		if ( ! $attr->{size} ) {
			push(@lastFontSize, $fontSize);
			return;
		}
		if ( $attr->{size} =~ m/[0-9]+p(t|x)/i ) {
			push (@lastFontSize, $fontSize);
			$fontSize = $attr->{size};
			$fontSize =~ m/[0-9]+/i; 
		}
		elsif ( $attr->{size} =~ m/[0-9]+em/i ) {
			push(@lastFontSize, $fontSize);
			$fontSize = $attr->{size};
			$fontSize =~ m/[0-9]+/i; 
			$fontSize = int($fontSize * 11);
		}
		elsif ( $attr->{size} =~ m/[0-9]+/i ) {
			push(@lastFontSize, $fontSize);
			$fontSize = $attr->{size};
			$fontSize =~ m/[0-9]+/i; 
			$fontSize = int($fontSize + 8);
		}
		else {
			return;
		}
		print "\\fs", 2 * $fontSize, " ";
	}
	elsif ( $tag eq "/font"  && $options{r} ) {
		return unless $#lastFontSize > 1;
		$fontSize = pop(@lastFontSize);
		print "\\fs", 2 * $fontSize, " ";
	}
	else {
		$skip = 1;
	}
	if ( $skip == 0 && $inside{blockquote} && ! $options{r} ) {
		print_utf16($quoteString);
	}
	if ( $skip == 0 && $quotelevelchange == 1 && $options{r} ) {
		start_rtf_paragraph();
	}
}

# text handler for the text extracted from the HTML source
sub text
{
	# we don't need anything within a script tag
	return if $inside{script};
	# we apparently don't need a character decoder hereÉ
	$_ = $_[0];
	# if we have more than one newline, add an additional one so that we preserve empty lines even while removing the initial newline
	s/^\n(\n+)/\n\n$1/g;
	# remove leading newlineÉ (which would have been inserted if we had a tag as the last thing in the line before)
	s/^\n//g;
	# Éand add a space at the end unless we have an empty line
	s/(.)\n$/$1 /g;
	# replace all multiple white-space with a single space (HTML does so)
	s/\s+/ /g;
	# if the -w flag was supplied, wrap long lines as requested
	if ( $options{w} ) {
		if ( $options{r} ) {
			$_ = wrap( '', '', $_ ); 
		}
		else {
			$_ = wrap( '', $quoteString, $_ ); 
		}
	}
	# change newlines to RTF way and escape "{" and "}"É
	if ( $options{r} ) {
		s/([{}\\\n])/\\$1/g;
	}
	# print the text after all processing
	print_utf16($_);
}

# text handler for the text extracted from the rich text source
sub richtext
{
	# pass through the character decoder
	$_ = decode($enc,$wd->decode($_[0]));
	# text/enriched quotes "<" as "<<", we replaced this so we can catch itÉ
	s/___ExtractText___lt___/</g;
	# if we have more than one newline, add an additional one so that we preserve empty lines even while removing the initial newline
	s/^\n(\n+)/\n\n$1/g;
	# remove leading newlineÉ (which would have been inserted if we had a tag as the last thing in the line before)
	s/^\n$/ /g;
	s/^\n//g;
	# Éand add a space at the end unless we have a real newline
	s/([^\n])\n$/$1 /g;
	# replace single newlines with spaces
	s/([^\n])\n([^\n])/$1 $2/g;
	# remove the additional newline from "real" newlines
	s/\n(\n+)/$1/g;
	# change newlines to RTF way and escape "{" and "}"É
	if ( $options{r} ) {
		s/([{}\\\n])/\\$1/g;
	}
	# activate links
	if ( $options{r} ) {
		$_ = activate_links($_);
	}
	# if the -w flag was supplied, wrap long lines as requested
	if ( $options{w} ) {
		if ( $options{r} ) {
			$_ = wrap( '', '', $_ ); 
		}
		else {
			$_ = wrap( '', $quoteString, $_ ); 
		}
	}
	# print the text after all processing
	print_utf16($_);
}

# set up decoder based on header information for the current MIME entity
sub setup_decoder
{
	my $head = shift;
	if ( $head->get('Content-Type') && $head->get('Content-Type') =~ m!charset=\"?([^\";]+)! ) {
		$enc = uc $1;
		# fix an encoding the WordDecoder does not recognize
		if ( $enc =~ m/MACINTOSH/ ) { $enc = 'MACROMAN' };
		$wd = supported MIME::WordDecoder $enc;
	}
	$enc = "ISO-8859-1" unless $enc;
	$wd = supported MIME::WordDecoder "ISO-8859-1" unless $wd;
}

# decode each of the MIME entities we care about
sub decode_entities
{
	my $ent = shift;
	if ( my @parts = $ent->parts ) {
		decode_entities($_) for @parts;
	}
	elsif ( my $body = $ent->bodyhandle ) {
		my $type = $ent->head->mime_type;
		setup_decoder($ent->head);
		if ( $type =~ /text\/plain/i 
			 &&  ( !$ent->head->mime_attr("content-disposition")
				   || ( $ent->head->mime_attr("content-disposition") && $ent->head->mime_attr("content-disposition") !~ /attachment/i ) ) ) 
		{	# dump the content directly (after passing through the WordDecoder)
			my $textpart = decode($enc,$wd->decode($body->as_string));
			@lines = split(/\n/, $textpart);
			foreach $line (@lines) {
				if ( $options{r} ) {
					$line =~ s/([{}\\])/\\$1/g;
					if ( $line =~ m/^(>[> ]+|>+$)/ ) {
						$tmpStr = $line;
						$tmpStr =~ s/(^[> ]*)(.*)/$1/g;
						$tmpStr =~ s/ //g;
						$line =~ s/(^[> ]*)(.*)/$2/g;
						if ( $quoteLevel != length($tmpStr) ) {
							$quoteLevel = length($tmpStr);
							start_rtf_paragraph();
						}
					}
					elsif ( $quoteLevel != 0 ) {
						$quoteLevel = 0;
						start_rtf_paragraph();
					}
					$line = activate_links($line);
					if ( $options{w} ) {
						$line = wrap('','',$line);
					}
					$line =~ s/\n/\\\n/g;
					print_utf16($line . "\\");
				}
				else {
					if ( $options{w} ) {
						if ( $line =~ m/^(>[> ]+)/ ) {
							$line = wrap('',$1,$line);
						}
						else {
							$line = wrap('','',$line);
						}
					}
					print_utf16($line);
				}
				print_utf16("\n");
			}
		}
		elsif ( $type =~ /text\/html/i 
				&&  ( !$ent->head->mime_attr("content-disposition")
					  || ( $ent->head->mime_attr("content-disposition") && $ent->head->mime_attr("content-disposition") !~ /attachment/i ) ) ) 
		{
			$html_parser->parse($body->as_string); # pass the content on to the HTML parser which creates the output
		}
		elsif ( $type =~ /text\/enriched/i 
				&&  ( !$ent->head->mime_attr("content-disposition")
					  || ( $ent->head->mime_attr("content-disposition") && $ent->head->mime_attr("content-disposition") !~ /attachment/i ) ) ) 
		{
			$theRichPartContent = $body->as_string;
			# make sure we don't confuse the parser with "<" which are escaped as "<<"
			$theRichPartContent =~ s/<</___ExtractText___lt___/g;
			$richtext_parser->parse($theRichPartContent); # pass the content on to the richtext parser which creates the output
		}
		elsif ( $type =~ /application\/applefile/i ) {
			# nothing here in order not to get duplicate attachment listings for files with resource and data fork
		}
		else {
			if ( my $filename = decode('MIME-Header',$wd->decode($ent->head->recommended_filename())) ) {
				if ( $options{a} ) {
					$theTempFile = File::Spec->catfile($mime_parser->filer->output_dir(),$filename);
					# see whether we already processed a file by that name:
					$fileFound = grep($theTempFile,@recoveredFiles);
					if ( ( ! $fileFound && ! -e $theTempFile ) || $fileFound ) {
						# we have to figure out what name the file was stored underÉ
						$theTempFile = $mime_parser->filer->output_path($ent->head);
						if ($theTempFile =~ /^(.*)-([0-9]+)(\..*)/ ) {
							if ( $2 eq "1" ) {
								$theTempFile = $1.$3;
							}
							else {
								$i = 1;
								while ( $i < $2 ) {
									$theTempFile = $1."-".$i.$3;
									$fileFound = grep($theTempFile,@recoveredFiles);
									if ( ! $fileFound && -e $theTempFile ) { $i = $2 }
									$i++;
								}
							}
						}
						else {
							$theTempFile =~ m/^(.*)-([0-9]+)/;
							if ( $2 eq "1" ) {
								$theTempFile = $1;
							}
							else {
								$i = 1;
								while ( $i < $2 ) {
									$theTempFile = $1."-".$i;
									$fileFound = grep($theTempFile,@recoveredFiles);
									if ( ! $fileFound && -e $theTempFile ) { $i = $2 }
									$i++;
								}
							}
						}
					}
					# copy the file to the destination directory, making sure that we don't overwrite files with the same name in the destination directory
					if ( $ent->head->get("content-id") ) {
						$theFile = $ent->head->get("content-id");
						$theFile =~ s/[<>]//g;
						chomp($theFile);
						$theFile = substr($mime_parser->filer->find_unused_path($attDest,$theFile),length($attDest)+1);
					}
					else {
						$theFile = substr($mime_parser->filer->find_unused_path($attDest,encode("UTF-8", decode('MIME-Header',$wd->decode($filename)))),length($attDest) + 1);
					}
					$macType = "\0\0\0\0";
					$macCreator = "\0\0\0\0";
					$unixMode = "0644";
					$contentTypeHeader = $ent->head->get("content-type");
					if ( $contentTypeHeader =~ m/x-mac-type/i ) {
						$macType = $contentTypeHeader;
						$macType =~ s/(.*)x-mac-type=([a-fA-F0-9]+)(.*)/$2/si;
						$macType =~ s/([a-fA-F0-9]{2})/chr(hex $1)/eg;
					}
					else { # set from the content-type header - this helps to have them display properly within the RTF file
						if ( $type =~ m/^text\//i ) { $macType = "TEXT"; } 
						elsif ( $type =~ m/^image\/gif/i ) { $macType = "GIFf"; } 
						elsif ( $type =~ m/^image\/jpeg/i ) { $macType = "JPEG"; } 
						elsif ( $type =~ m/^image\/tiff/i ) { $macType = "TIFF"; } 
						elsif ( $type =~ m/^application\/pdf/i ) { $macType = "PDF "; } 
						elsif ( $type =~ m/^video\/mpeg/i ) { $macType = "MPEG"; } 
					}
					if ( $contentTypeHeader =~ m/x-mac-creator/i ) {
						$macCreator = $contentTypeHeader;
						$macCreator =~ s/(.*)x-mac-creator=([a-fA-F0-9]+)(.*)/$2/si;
						$macCreator =~ s/([a-fA-F0-9]{2})/chr(hex $1)/eg;
					}
					if ( $contentTypeHeader =~ m/x-unix-mode/i ) {
						$unixMode = $contentTypeHeader;
						$unixMode =~ s/(.*)x-unix-mode=([0-9]+)(.*)/$2/si;
					}
					# properly quote "'" the way the shell likes it
					$theTempFile =~ s/\'/'\\''/g;
					$attDest =~ s/\'/'\\''/g;
					$theFile =~ s/\'/'\\''/g;
					# make sure we don't lose the whole message just because we screwed up something with the attachments:
					if ( -e $theTempFile ) {
						# add the file to the list of processed files so we don't get duplicates
						push(@recoveredFiles,$theTempFile);
						# copy the file from the temp directory to the target directory - this preserves resource forks and file meta data
						system( qq|ditto -rsrc '$theTempFile' '$attDest/$theFile'| );
						# adjust the permissions on the attachment in its new location
						system( qq|chmod $unixMode '$attDest/$theFile'| );
						# re-do the quoting we did for the shell so Perl is happyÉ
						$attDest =~ s/'\\''/\'/g;
						$theFile =~ s/'\\''/\'/g;
						# and set Mac file and creator
						$finfo = MacOSX::File::Info->get($attDest.'/'.$theFile);
						$finfo->type($macType);
						$finfo->creator($macCreator);
						if ( $contentTypeHeader =~ m/x-mac-hide-extension=yes;/i ) { $finfo->flags( -hiddenx => 1 ); }
						$finfo->set;
						if ( $options{r} && !$ent->head->get("content-id") ) {
							print_utf16($newlineChar . "{{\\NeXTGraphic " . $theFile . " \\width0 \\height0}\x{AC}}");
						}
					}
				}
				else {
				# add attachment placeholder with original filename
					print_utf16($newlineChar . "[Attachment '" . decode('MIME-Header',$wd->decode($filename)) . "']");
				}
			}
			else {
				print_utf16($newlineChar . "[Unhandled part of type $type]");	# don't know how to deal with this -> add unspecified placeholder
			}
		}
	}
}

# get rid of MIME entities we don't care about before processing
sub analyze
{
	my($body,$i)=(@_,0);
	my($parts)=$body->{ME_Parts};
	# Reduce multipart/alternative
	if ( $body->mime_type =~ /multipart\/alternative/i ) {
		$i=-1;
		if ( $options{r} ) {
			$i++ until ( $$parts[$i]->mime_type =~ /text\/(html|enriched)/i || $i==$#{$parts} ); # try to find the most advanced version we can handle
				if ( $$parts[$i]->mime_type =~ /text\/(plain|html|enriched)/i ) {
					@$parts = @$parts[$i];
				}
		}
		else {
			$i++ until ( $$parts[$i]->mime_type =~ /text\/plain/i || $i==$#{$parts} );
			if ( $$parts[$i]->mime_type =~ /text\/plain/i ) {
				@$parts = @$parts[$i];
			}
		}
	}
	else {
		# Kill superfluous junk:
		# - text/x-vcard
		# - application/pgp-signature
		# - application/x-pkcs7-signature and application/pkcs7-signature
		# - application/ms-tnef
		# Recursion on multipart
		while ( $i <= $#{$parts} ) {
			if ( $$parts[$i]->mime_type =~ /(text\/x-vcard|application\/(?:(?:pgp|(?:x-)?pkcs7)-signature|ms-tnef))/i ) {
				splice(@$parts,$i,1);
			}
			elsif ( $$parts[$i]->mime_type =~ /^multipart\//i ) {
				$$parts[$i] = &analyze($$parts[$i]);
				$i++;
			}
			else {
				$i++;
			}
		}
	}
	$body->{ME_Parts} = $parts;

	if ( $body->mime_type =~ m/^multipart\/related/i && $body->head->mime_attr("content-type.type") && $body->head->mime_attr("content-type.type") =~ m/multipart\/alternative/i ) {
		$body->head->mime_attr("content-type.type" => "text/plain");
	}
	$body->make_singlepart if $body->parts == 1;
	return $body;
}

sub print_utf16
{
	if ( $options{r}) {
		$_ = shift;
		# properly convert 8bit charactersÉ
		s/([\x80-\xFF])/sprintf("\\'%02x",ord($1))/eg;
		# Éas well as Unicode characters into RTF format
		s/([\x{100}-\x{7FFF}])/sprintf("\\u%i",ord($1))/eg;
		s/([\x{8000}-\x{FFFF}])/sprintf("\\u%i",ord($1)-0x10000)/eg;
		# make sure we don't lose spaces after Unicode chars
		s/(\\u[\-0-9]+ )/$1 /g;
	}
	else {
		$_ = encode("UTF-16BE",shift);
	}
	print;
}

sub print_header
{
	my $the_header = shift;
	use utf8;
	if ( $e->head->get($the_header) || $the_header =~ /subject/i ) {
		# figure out the encoding used in RFC-2047 encoded headers
		eval { $header_content = decode('MIME-Header',$e->head->get_all($the_header)); };
		# if we encountered an unknown encoding, default to ISO-8859-1 (at least we get somethingÉ)
		if ( $@ ) {
			if ( $@ =~ /Unknown encoding \"([^\"]*)\"/ ) {
				my $tmp_header = $e->head->get_all($the_header);
				$tmp_header =~ s/$1/ISO-8859-1/g;
				$header_content = decode('MIME-Header',$tmp_header);
			}
		}
		if ( $options{w} ) {
			$header_content = wrap( '', "\t", $header_content );
		}
		if ( $options{r} ) {
			chomp($header_content);
			$header_content =~ s/([{}\\\n])/\\$1/g;
			if ( $the_header =~ /subject/i ) {
				print_utf16("\\f0\\b\\cf2 " . $the_header . ": \n \\cf3 " . $header_content . "\\\n\n\\f1\\b0 ");
			}
			else {
				print_utf16("\\f0\\b\\cf2 " . $the_header . ": \n\\f1\\b0 \\cf3 " . $header_content . "\\\n\n");
			}
		}
		else {
			print_utf16($the_header . ": " . $header_content);
		}
	}
}

sub start_rtf_paragraph
{
	print $rtf_paragraph_start;
	if ( $quoteLevel != 0 ) {
		print "\\li", 200 * $quoteLevel;
	}
	print $rtf_paragraph_end;
	print get_paragraph_color();
}

sub get_paragraph_color
{
	if ( $quoteLevel != 0 ) {
		my $colorlevel = $quoteLevel % 3;
		if ( $colorlevel == 0 ) { return "\\cf4 "; }
		elsif ( $colorlevel == 1 ) { return "\\cf6 "; }
		else { return "\\cf5 "; }
	}
	else { return "\\cf3 "; }
}

sub activate_links
{
	# when exporting to RTF, make URIs and email addresses clickable
	my $line = shift;
	if ( $line =~ m/((?:f|ht)tps?:\/\/)([^>\s]+)/ ) {
		# links (ftp, http, https)
		my $theColor = get_paragraph_color();
		$line =~ s/((?:f|ht)tps?:\/\/)([^>\s]+\w)/\{\\field\{\\*\\fldinst\{HYPERLINK \"$1$2\"\}\}\{\\fldrslt \\cf6 $1$2\}\}$theColor/g;
	}
	if ( $line =~ m/(.*\s)?(\w+[-\w\.]*)\@(\w[-\w]*\.[-\w\.]+(?:\w|\z))/ ) {
		# try to make email addresses and mailto: links active as well
		my $theColor = get_paragraph_color();
		$line =~ s/(.*\s)?(mailto\:)?(\w+[-\w\.]*)\@(\w[-\w]*\.[-\w\.]+(?:\w|\z))/$1\{\\field\{\\*\\fldinst\{HYPERLINK \"mailto:$3\@$4\"\}\}\{\\fldrslt \\cf6 $2$3\@$4\}\}$theColor/g;
	}
	return $line;
}

# ExtractText.pl
